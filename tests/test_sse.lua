local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        post_once = child.stop,
    },
})

local function eval_lua(code)
    return child.lua_get(code)
end

T["start_request always uses stdin for curl data"] = function()
    child.lua([[
        -- Initialize the global Ninetyfive object
        _G.Ninetyfive = { config = { debug = false } }

        -- Capture jobstart calls to inspect the command and options
        local captured_cmd = nil
        local captured_opts = nil

        local original_jobstart = vim.fn.jobstart
        vim.fn.jobstart = function(cmd, opts)
            captured_cmd = cmd
            -- Only capture the stdin option, not the callbacks which can't be serialized
            captured_opts = { stdin = opts.stdin }
            -- Return a fake job id without actually starting the job
            return 1
        end

        -- Mock chansend and chanclose to prevent errors
        local original_chansend = vim.fn.chansend
        local original_chanclose = vim.fn.chanclose
        vim.fn.chansend = function() return 1 end
        vim.fn.chanclose = function() return 0 end

        -- Load SSE module and set up minimal state
        local sse = require("ninetyfive.sse")
        sse.setup({ server_uri = "http://test.example.com", user_id = "test" })

        -- Create a test payload - simulate a large file content
        local large_content = string.rep("x", 100000)  -- 100KB payload
        local payload = {
            user_id = "test",
            id = "test_id",
            repo = "test_repo",
            filepath = "test.lua",
            content = large_content,
            cursor = 50000,
        }

        -- Call the internal start_request function by triggering request_completion
        -- We need to access it indirectly since start_request is local
        -- Instead, we'll directly test by encoding and calling jobstart patterns

        -- Encode the payload to simulate what start_request does
        local encoded = vim.json.encode(payload)

        -- Verify encoded payload is large enough to cause issues on command line
        _G.payload_size = #encoded

        -- Now trigger a completion request to capture the curl command
        -- First set up the completion state module
        local Completion = require("ninetyfive.completion")
        Completion.clear()

        -- Create a buffer for the request
        vim.cmd("new")
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(large_content, "\n"))
        vim.cmd("startinsert")

        -- Request completion (this will call start_request internally)
        sse.request_completion({ buf = bufnr })

        vim.wait(100, function()
            return captured_cmd ~= nil
        end)

        _G.captured_cmd = captured_cmd
        _G.captured_opts = captured_opts

        -- Restore originals
        vim.fn.jobstart = original_jobstart
        vim.fn.chansend = original_chansend
        vim.fn.chanclose = original_chanclose
    ]])

    -- Verify the payload size is large enough to demonstrate the fix
    local payload_size = eval_lua("_G.payload_size")
    MiniTest.expect.equality(payload_size > 50000, true, "Payload should be large")

    -- Verify the curl command was captured
    local cmd = eval_lua("_G.captured_cmd")
    MiniTest.expect.equality(type(cmd), "table", "Command should be a table")

    -- Check that --data-binary @- is in the command (stdin mode)
    local has_data_binary = false
    local has_stdin_marker = false
    local has_inline_data = false

    for i, arg in ipairs(cmd) do
        if arg == "--data-binary" then
            has_data_binary = true
            if cmd[i + 1] == "@-" then
                has_stdin_marker = true
            end
        end
        -- Make sure we're NOT using inline --data with the payload
        if arg == "--data" and cmd[i + 1] and #cmd[i + 1] > 1000 then
            has_inline_data = true
        end
    end

    MiniTest.expect.equality(has_data_binary, true, "Command should use --data-binary")
    MiniTest.expect.equality(has_stdin_marker, true, "Command should use @- for stdin")
    MiniTest.expect.equality(has_inline_data, false, "Command should NOT have inline data")

    -- Verify stdin pipe is enabled in job options
    local opts = eval_lua("_G.captured_opts")
    MiniTest.expect.equality(opts.stdin, "pipe", "Job options should have stdin=pipe")
end

T["start_request sends body via chansend"] = function()
    child.lua([[
        -- Initialize the global Ninetyfive object
        _G.Ninetyfive = { config = { debug = false } }

        local chansend_called = false
        local chanclose_called = false
        local sent_data = nil

        local original_jobstart = vim.fn.jobstart
        vim.fn.jobstart = function(cmd, opts)
            return 1  -- Return fake job id
        end

        local original_chansend = vim.fn.chansend
        vim.fn.chansend = function(job_id, data)
            chansend_called = true
            sent_data = data
            return 1
        end

        local original_chanclose = vim.fn.chanclose
        vim.fn.chanclose = function(job_id, stream)
            if stream == "stdin" then
                chanclose_called = true
            end
            return 0
        end

        local sse = require("ninetyfive.sse")
        sse.setup({ server_uri = "http://test.example.com", user_id = "test" })

        local Completion = require("ninetyfive.completion")
        Completion.clear()

        vim.cmd("new")
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test content" })
        vim.cmd("startinsert")

        sse.request_completion({ buf = bufnr })

        vim.wait(100, function()
            return chansend_called
        end)

        _G.chansend_called = chansend_called
        _G.chanclose_called = chanclose_called
        _G.sent_data_type = type(sent_data)

        vim.fn.jobstart = original_jobstart
        vim.fn.chansend = original_chansend
        vim.fn.chanclose = original_chanclose
    ]])

    -- Verify chansend was called to send the body
    local chansend_called = eval_lua("_G.chansend_called")
    MiniTest.expect.equality(chansend_called, true, "chansend should be called")

    -- Verify chanclose was called to close stdin
    local chanclose_called = eval_lua("_G.chanclose_called")
    MiniTest.expect.equality(chanclose_called, true, "chanclose should be called for stdin")

    -- Verify data was sent
    local sent_data_type = eval_lua("_G.sent_data_type")
    MiniTest.expect.equality(sent_data_type, "string", "Sent data should be a string")
end

return T
