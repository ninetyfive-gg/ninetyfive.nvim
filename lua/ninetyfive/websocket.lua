local log = require("ninetyfive.util.log")
local Queue = require("ninetyfive.queue")
local suggestion = require("ninetyfive.suggestion")
local git = require("ninetyfive.git")

local Websocket = {}

-- Variable to store aggregated ghost text
local completion = ""
local request_id = ""
local completion_queue = Queue.New()

-- Function to send a message to the websocket
function Websocket.send_message(message)
    -- Check if the global table exists
    if not _G.Ninetyfive then
        log.debug("websocket", "Global Ninetyfive table not initialized")
        return false
    end

    -- Check if websocket job exists and is valid
    if not (_G.Ninetyfive.websocket_job and _G.Ninetyfive.websocket_job > 0) then
        log.debug("websocket", "Websocket connection not established")
        return false
    end

    local ok, result = pcall(function()
        return vim.fn.chansend(_G.Ninetyfive.websocket_job, message .. "\n")
    end)

    -- Handle any errors that occurred
    if not ok then
        log.debug("websocket", "Error sending message: " .. tostring(result))
        return false
    end

    -- Check if the send was successful
    if result == 0 then
        log.debug("websocket", "Failed to send message to websocket")
        return false
    end

    log.debug("websocket", "Sent message to websocket: " .. message)
    return true
end

local function set_workspace()
    local head = git:get_head()
    local cwd = vim.fn.getcwd()
    local repo = "unknown"
    local repo_match = string.match(cwd, "/([^/]+)$")
    if repo_match then
        repo = repo_match
    end

    if head ~= nil then
        local set_workspace = vim.json.encode({
            type = "set-workspace",
            commitHash = head.hash,
            path = cwd,
            name = repo .. "/" .. head.branch,
        })

        print("-> [set-workspace]", set_workspace)

        if not Websocket.send_message(set_workspace) then
            log.debug("websocket", "Failed to set-workspace")
        end
    else
        local empty_workspace = vim.json.encode({
            type = "set-workspace",
        })

        print("-> [set-workspace] empty")

        if not Websocket.send_message(empty_workspace) then
            log.debug("websocket", "Failed to empty set-workspace")
        end
    end
end

local function request_completion(args)
    local ok, err = pcall(function()
        -- Check that we're connected
        if
            not (_G.Ninetyfive and _G.Ninetyfive.websocket_job and _G.Ninetyfive.websocket_job > 0)
        then
            log.debug("websocket", "Skipping delta-completion-request - websocket not connected")
            return
        end

        local bufnr = args.buf
        local cursor = vim.api.nvim_win_get_cursor(0)
        local line = cursor[1] - 1 -- Lua uses 0-based indexing for lines
        local col = cursor[2] -- Column is 0-based

        -- Get buffer content from start to cursor position
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line + 1, false)
        -- Adjust the last line to only include content up to the cursor
        if #lines > 0 then
            lines[#lines] = string.sub(lines[#lines], 1, col)
        end
        local content_to_cursor = table.concat(lines, "\n")

        -- Get byte position (length of content in bytes)
        local pos = #content_to_cursor

        -- Repo is the cwd? Is this generally correct with how people use neovim?
        local cwd = vim.fn.getcwd()
        local repo = "unknown"
        local repo_match = string.match(cwd, "/([^/]+)$")
        if repo_match then
            repo = repo_match
        end

        -- Generate a request ID
        request_id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))

        -- Clear the aggregated ghost text when sending a new completion request
        completion = ""

        local message = vim.json.encode({
            type = "delta-completion-request",
            requestId = request_id,
            repo = repo,
            pos = pos,
        })

        print("-> [delta-completion-request]", request_id, repo, pos)

        if not Websocket.send_message(message) then
            log.debug("websocket", "Failed to send delta-completion-request message")
        end

        Queue.clear(completion_queue)
    end)

    if not ok then
        log.debug("websocket", "Error in CursorMovedI callback: " .. tostring(err))
    end

    -- Also clear any suggestions that were showing
    suggestion.clear()
end

-- Function to set up autocommands related to websocket functionality
function Websocket.setup_autocommands()
    -- Create an autogroup for Ninetyfive
    -- https://www.youtube.com/watch?v=F6GNPOXpfwU
    local ninetyfive_augroup = vim.api.nvim_create_augroup("Ninetyfive", { clear = true })

    -- Make accept_completion available globally
    _G.accept_ninetyfive_completion = function()
        suggestion.accept()
        completion = ""
        request_id = ""
        return "" -- This is important for expr mappings to not insert anything
    end

    -- Set up the Tab key mapping
    vim.api.nvim_set_keymap(
        "i",
        "<Tab>",
        "<Cmd>lua _G.accept_ninetyfive_completion()<CR>",
        { noremap = true, silent = true }
    )

    -- Autocommand for cursor movement in insert mode
    -- CursorMovedI does not seem to trigger when you type in insert mode!!
    vim.api.nvim_create_autocmd({ "CursorMovedI" }, {
        pattern = "*",
        group = ninetyfive_augroup,
        callback = function(args)
            print("CursorMovedI")
            if request_id == "" and Queue.length(completion_queue) == 0 then
                request_completion(args)
                return
            end

            -- TODO should we suggest here?
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChangedI" }, {
        pattern = "*",
        group = ninetyfive_augroup,
        callback = function(args)
            -- TODO here we should check if we need to send a delta
            print("TextChangedI")

            -- Clear old ones
            suggestion.clear()

            -- Check if there's an active completion?
            if request_id == "" and Queue.length(completion_queue) == 0 then
                request_completion(args)
                return
            end
        end,
    })

    -- Autocommand for new buffer creation
    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
        pattern = "*",
        group = ninetyfive_augroup,
        callback = function(args)
            local ok, err = pcall(function()
                -- Check that we're connected
                if
                    not (
                        _G.Ninetyfive
                        and _G.Ninetyfive.websocket_job
                        and _G.Ninetyfive.websocket_job > 0
                    )
                then
                    log.debug("websocket", "Skipping buffer message - websocket not connected")
                    return
                end

                -- TODO Is this the right way? This would be per buffer so may trigger more commit/blob requests?
                set_workspace()

                local bufnr = args.buf
                local bufname = vim.api.nvim_buf_get_name(bufnr)
                local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

                local message = vim.json.encode({
                    type = "file-content",
                    path = bufname,
                    text = content,
                })

                print("-> [file-content]", bufname)

                if not Websocket.send_message(message) then
                    log.debug("websocket", "Failed to send file-content message")
                end
            end)

            if not ok then
                log.debug("websocket", "Error in BufReadPost callback: " .. tostring(err))
            end
        end,
    })
end

-- See: https://github.com/neovim/neovim/blob/master/test/testutil.lua#L390
local function pick_binary()
    local uname = vim.uv.os_uname()
    local sysname = uname.sysname:lower()
    local arch = uname.machine

    -- Missing some
    local binaries = {
        darwin = {
            x86_64 = "/websocat.x86_64-apple-darwin",
            default = "/websocat.aarch64-apple-darwin",
        },
        linux = "/websocat.x86_64-unknown-linux-musl",
        freebsd = "/websocat.x86_64-unknown-freebsd",
        windows = "/websocat.x86_64-pc-windows-gnu.exe",
    }

    if binaries[sysname] then
        if type(binaries[sysname]) == "table" then
            return binaries[sysname][arch] or binaries[sysname].default
        end
        return binaries[sysname]
    end

    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
        return binaries.windows
    end

    return ""
end

-- Function to set up websocket connection
function Websocket.setup_connection(server_uri)
    log.debug("websocket", "Setting up websocket connection")

    -- Store the job ID for the websocket connection
    if _G.Ninetyfive.websocket_job then
        -- Kill existing connection if there is one
        vim.fn.jobstop(_G.Ninetyfive.websocket_job)
        _G.Ninetyfive.websocket_job = nil
    end

    -- Path to the websocat binary (relative to the plugin directory)
    -- Get the plugin's root directory in a way that works regardless of where Neovim is opened
    local plugin_root = vim.fn.fnamemodify(
        vim.api.nvim_get_runtime_file("lua/ninetyfive/init.lua", false)[1] or "",
        ":h:h:h"
    )
    local websocat_path = plugin_root .. pick_binary()
    log.debug("websocket", "Using websocat at: " .. websocat_path)

    -- Make sure the binary is executable, this likely doesnt work everywhere, should we just commit them
    -- on the right "mode"?
    vim.fn.system("chmod +x " .. vim.fn.shellescape(websocat_path))

    _G.Ninetyfive.websocket_job = vim.fn.jobstart({
        websocat_path,
        server_uri,
    }, {
        on_stdout = function(_, data, _)
            if data and #data > 0 then
                local message = table.concat(data, "\n")
                if message ~= "" then
                    local ok, parsed = pcall(vim.json.decode, message)
                    if ok and parsed then
                        if parsed.type then
                            if parsed.type == "subscription-info" then
                                print("<- [subscription-info]", parsed)
                            elseif parsed.type == "get-commit" then
                                print("<- [get-commit]")
                                local commit = git:get_commit(parsed.commitHash)

                                local send_commit = vim.json.encode({
                                    type = "commit",
                                    commitHash = parsed.commitHash,
                                    commit = commit,
                                })

                                print("-> [commit]", send_commit)

                                if not Websocket.send_message(send_commit) then
                                    log.debug("websocket", "Failed to send commit")
                                end
                            elseif parsed.type == "get-blob" then
                                print("<- [get-blob]")
                            end
                        else
                            if parsed.v and parsed.r == request_id then
                                print("<- [completion-response]")
                                if parsed.v == vim.NIL then
                                    Queue.append(completion_queue, completion, true)
                                else
                                    completion = completion .. tostring(parsed.v)
                                    if
                                        Queue.length(completion_queue) == 0
                                        and string.find(parsed.v, "\n")
                                    then
                                        local new_line_idx = completion:match(".*\n()") or -1

                                        if new_line_idx == 1 then
                                            return
                                        end

                                        local line = completion:sub(1, new_line_idx - 1)
                                        Queue.append(completion_queue, line, false)
                                        completion = string.sub(completion, 1, new_line_idx)
                                    end
                                end

                                -- We could have a suggestion here, try to show it
                                local current_completion = Queue.pop(completion_queue)
                                if current_completion ~= nil then
                                    suggestion.show(current_completion.completion)
                                end
                            end
                        end
                    end
                end
            end
        end,
        on_stderr = function(_, data, _)
            if data and #data > 0 then
                local message = table.concat(data, "\n")
                if message ~= "" then
                    log.debug("websocket", "Failed to connect")
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            log.debug("websocket", "Websocket connection closed with exit code: " .. exit_code)
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    if _G.Ninetyfive.websocket_job <= 0 then
        log.notify("websocket", vim.log.levels.ERROR, true, "Failed to start websocat process")
        return false
    end

    log.debug("websocket", "Started websocat process with job ID: " .. _G.Ninetyfive.websocket_job)

    vim.notify("Ninetyfive websocket connection established.", vim.log.levels.INFO)
    return true
end

function Websocket.get_completion()
    return completion
end

function Websocket.reset_completion()
    completion = ""
end

return Websocket
