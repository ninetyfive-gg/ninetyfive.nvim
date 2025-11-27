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

local function reset_http_module()
    child.lua([[
        package.loaded["ninetyfive.http"] = nil
        _G.http = require("ninetyfive.http")
    ]])
end

T["falls back to curl shell when libcurl disabled"] = function()
    reset_http_module()

    child.lua([[
        local original_system = vim.system
        local original_exec = vim.fn.executable

        http.using_libcurl = false

        vim.fn.executable = function(bin)
            if bin == "curl" then
                return 1
            end
            return original_exec(bin)
        end

        vim.system = function(cmd, opts, callback)
            -- Simulate async callback
            vim.schedule(function()
                callback({ code = 0, stdout = "pong\n201", stderr = "" })
            end)
        end

        _G.result = nil
        http.post_json("http://example", { "h:1" }, "payload", function(ok, status, body)
            _G.result = { ok = ok, status = status, body = body }
        end)

        -- Wait for async completion
        vim.wait(1000, function()
            return _G.result ~= nil
        end)

        -- restore
        vim.system = original_system
        vim.fn.executable = original_exec
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(result.ok, true)
    MiniTest.expect.equality(result.status, 201)
    MiniTest.expect.equality(result.body, "pong")
end

T["returns error when curl missing"] = function()
    reset_http_module()

    child.lua([[
        local original_exec = vim.fn.executable

        http.using_libcurl = false

        vim.fn.executable = function()
            return 0
        end

        _G.result = nil
        http.post_json("http://example", {}, "payload", function(ok, status, body)
            _G.result = { ok = ok, status = status, body = body }
        end)

        vim.wait(1000, function()
            return _G.result ~= nil
        end)

        vim.fn.executable = original_exec
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(result.ok, false)
    MiniTest.expect.equality(result.status, nil)
end

T["returns error on unparsable curl status"] = function()
    reset_http_module()

    child.lua([[
        local original_system = vim.system
        local original_exec = vim.fn.executable

        http.using_libcurl = false

        vim.fn.executable = function()
            return 1
        end

        vim.system = function(cmd, opts, callback)
            vim.schedule(function()
                callback({ code = 0, stdout = "bad-output", stderr = "" })
            end)
        end

        _G.result = nil
        http.post_json("http://example", {}, "payload", function(ok, status, body)
            _G.result = { ok = ok, status = status, body = body }
        end)

        vim.wait(1000, function()
            return _G.result ~= nil
        end)

        vim.system = original_system
        vim.fn.executable = original_exec
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(result.ok, false)
    MiniTest.expect.equality(result.status, nil)
end

T["libcurl flag reflects availability"] = function()
    reset_http_module()
    local has_libcurl = eval_lua("http.libcurl_available()")
    MiniTest.expect.equality(type(has_libcurl), "boolean")
end

T["makes real HTTP request with libcurl without crashing"] = function()
    reset_http_module()

    -- Skip if libcurl is not available
    local has_libcurl = eval_lua("http.libcurl_available()")
    if not has_libcurl then
        MiniTest.skip("libcurl not available")
        return
    end

    -- Make multiple real HTTP requests to trigger potential GC issues.
    -- The main goal is to catch segfaults from improper FFI string handling.
    -- If the child process crashes, eval_lua will fail with "Invalid channel".
    -- We tolerate server errors (5xx) since httpbin.org can be flaky.
    child.lua([[
        local results = {}
        local completed = 0
        local total = 3

        for i = 1, total do
            -- Create some garbage to encourage GC
            for j = 1, 100 do
                local _ = string.rep("x", 1000)
            end
            collectgarbage("collect")

            http.post_json(
                "https://httpbin.org/post",
                { "Content-Type: application/json" },
                vim.json.encode({ test = "data", iteration = i }),
                function(ok, status, body)
                    table.insert(results, { ok = ok, status = status, has_body = body ~= nil and #body > 0 })
                    completed = completed + 1
                end
            )
        end

        -- Wait for all requests to complete
        vim.wait(30000, function()
            return completed >= total
        end)

        _G.results = results
    ]])

    local results = eval_lua("_G.results")
    -- If we got here, the child process didn't crash (which is the main test).
    -- Verify requests completed - allow server errors (5xx) due to httpbin flakiness
    for i, result in ipairs(results) do
        -- ok=true means libcurl completed without crashing
        MiniTest.expect.equality(result.ok, true, "Request " .. i .. " should complete without crashing")
        -- Accept any valid HTTP status (2xx, 4xx, 5xx) - we just care it didn't segfault
        MiniTest.expect.equality(type(result.status), "number", "Request " .. i .. " should return a status code")
    end
end

return T
