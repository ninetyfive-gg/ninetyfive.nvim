local log = require("ninetyfive.util.log")
local Completion = require("ninetyfive.completion")
local git = require("ninetyfive.git")
local suggestion = require("ninetyfive.suggestion")
local state = require("ninetyfive.state")
local ignored_filetypes = require("ninetyfive.ignored_filetypes")
local plugin_version = require("ninetyfive.version")
local util = require("ninetyfive.util")

local Websocket = {}

-- Reconnection settings
local reconnect_attempts = 0
local max_reconnect_attempts = 300
local reconnect_delay = 1000

local home = vim.fn.expand("~")
local cache_path = home .. "/.ninetyfive/consent.json"
vim.fn.mkdir(home .. "/.ninetyfive", "p")

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
        -- log.debug("websocket", "Error sending message: " .. tostring(result))
        return false
    end

    -- Check if the send was successful
    if result == 0 then
        -- log.debug("websocket", "Failed to send message to websocket")
        return false
    end

    -- log.debug("websocket", "Sent message to websocket")
    return true
end

local function get_indexing_consent(callback)
    local mode = _G.Ninetyfive.config.indexing.mode or "ask"
    local use_cache = _G.Ninetyfive.config.indexing.cache_consent ~= false

    -- check the config and short circuit
    if mode == "on" then
        callback(true)
        return
    elseif mode == "off" then
        callback(false)
        return
    end

    if #vim.api.nvim_list_uis() == 0 then
        callback(false)
        return
    end

    -- if caching is enabled, check it first
    if use_cache then
        local f = io.open(cache_path, "r")
        if f then
            local data = f:read("*a")
            f:close()
            local ok, parsed = pcall(vim.json.decode, data)
            if ok and parsed and parsed.consent ~= nil then
                callback(parsed.consent)
                return
            end
        end
    end

    vim.ui.select({ "Allow", "Deny" }, {
        prompt = "This extension can index your workspace to provide better completions. Would you like to allow this?",
    }, function(choice)
        if not choice then
            return
        end
        local consent = (choice == "Allow")

        -- persist it to our cache
        if use_cache then
            local ok, out = pcall(vim.json.encode, { consent = consent })
            if ok then
                local wf = io.open(cache_path, "w")
                if wf then
                    wf:write(out)
                    wf:close()
                end
            end
        end

        callback(consent)
    end)
end

-- See: https://github.com/neovim/neovim/blob/master/test/testutil.lua#L390
local function pick_binary()
    local uv = vim.uv or vim.loop -- `vim.uv` is only available after 0.10
    local uname = uv.os_uname()
    local sysname = uname.sysname:lower()
    local arch = uname.machine

    local binaries = {
        darwin = {
            x86_64 = "/dist/go-ws-proxy-darwin-amd64",
            default = "/dist/go-ws-proxy-darwin-arm64",
        },
        linux = {
            x86_64 = "/dist/go-ws-proxy-linux-amd64",
            default = "/dist/go-ws-proxy-linux-arm64",
        },
        windows = {
            x86_64 = "/dist/go-ws-proxy-windows-amd64.exe",
            default = "/dist/go-ws-proxy-windows-arm64.exe",
        },
    }

    if binaries[sysname] then
        if type(binaries[sysname]) == "table" then
            return binaries[sysname][arch] or binaries[sysname].default
        end
        return binaries[sysname]
    end

    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 or sysname:lower():find("windows") then
        return binaries.windows[arch] or binaries.windows.default or ""
    end

    return ""
end

function Websocket.shutdown()
    if _G.Ninetyfive.websocket_job then
        log.debug("websocket", "Shutting down websocket process")
        vim.fn.jobstop(_G.Ninetyfive.websocket_job)
        _G.Ninetyfive.websocket_job = nil
    end
end

-- Function to set up websocket connection
function Websocket.setup_connection(server_uri, user_id, api_key)
    log.debug("websocket", "Setting up websocket connection")

    Websocket.shutdown()

    local uname = vim.loop.os_uname()
    local sysname = uname and uname.sysname or ""

    local plugin_root = vim.fn.fnamemodify(
        vim.api.nvim_get_runtime_file("lua/ninetyfive/init.lua", false)[1] or "",
        ":h:h:h"
    )
    local binary_suffix = pick_binary()
    local binary_path = plugin_root .. binary_suffix

    if
        (vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 or sysname:lower():find("windows"))
        and vim.fn.filereadable(binary_path) ~= 1
    then
        local exe_path = binary_path .. ".exe"
        if vim.fn.filereadable(exe_path) == 1 then
            binary_path = exe_path
        end
    end

    if
        binary_suffix == ""
        or vim.fn.filereadable(binary_path) ~= 1
        or vim.fn.executable(binary_path) ~= 1
    then
        log.notify(
            "websocket",
            vim.log.levels.ERROR,
            true,
            "Websocket proxy binary not available; attempting SSE fallback"
        )
        return false, "missing_binary"
    end

    local base_url = server_uri:gsub("^ws://", "http://"):gsub("^wss://", "https://")
    local git_endpoint_base = base_url:gsub("/ws$", "")

    get_indexing_consent(function(allowed)
        if not allowed then
            log.debug("websocket", "Indexing consent not granted, skipping git sync")
            return
        end

        if api_key and api_key ~= "" then
            log.debug(
                "websocket",
                "indexing consent allowed and api key exists, syncing repository data..."
            )

            vim.defer_fn(function()
                vim.schedule(function()
                    local ok, err = pcall(function()
                        local git_endpoint = git_endpoint_base .. "/datasets"

                        git.sync_current_repo(api_key, git_endpoint, 50) -- limit to 50 commits for now

                        log.debug("websocket", "Git repository sync completed")
                    end)

                    if not ok then
                        log.notify(
                            "websocket",
                            vim.log.levels.ERROR,
                            true,
                            "Failed to sync git repository: " .. tostring(err)
                        )
                    end
                end)
            end, 2000)
        else
            log.debug("websocket", "No API key provided, skipping git sync")
        end
    end)

    -- Build the websocket URI with query parameters
    local ws_uri = server_uri
        .. "?user_id="
        .. user_id
        .. "&editor=neovim"
        .. "&version="
        .. tostring(plugin_version)

    if api_key and api_key ~= "" then
        ws_uri = ws_uri .. "&api_key=" .. api_key
    end

    _G.Ninetyfive.websocket_job = vim.fn.jobstart({
        binary_path,
        ws_uri,
    }, {
        on_stdout = function(_, data, _)
            if not data then
                return
            end

            for _, line in ipairs(data) do
                if line ~= "" then
                    log.debug("websocket", "Got message line from websocket: ", line)

                    local ok, parsed = pcall(vim.json.decode, line)
                    if not ok or type(parsed) ~= "table" then
                        log.debug("websocket", "Failed to parse JSON line: ", line)
                        goto continue
                    end

                    local msg_type = parsed.type

                    if msg_type == "subscription-info" then
                        log.debug("messages", "<- [subscription-info]", parsed)
                    elseif msg_type == "get-commit" then
                        local commit = git.get_commit(parsed.commitHash)
                        if commit then
                            local send_commit = vim.json.encode({
                                type = "commit",
                                commitHash = parsed.commitHash,
                                commit = commit,
                            })
                            if not Websocket.send_message(send_commit) then
                                log.debug("websocket", "Failed to send commit")
                            end
                        end
                    elseif msg_type == "get-blob" then
                        local blob = git.get_blob(parsed.commitHash, parsed.path)
                        if blob then
                            local send_blob = vim.json.encode({
                                type = "blob",
                                commitHash = parsed.commitHash,
                                objectHash = parsed.objectHash,
                                path = parsed.path,
                                blobBytes = blob.blob,
                                diffBytes = blob.diff,
                            })
                            log.debug("messages", "-> [blob]", send_blob)
                            if not Websocket.send_message(send_blob) then
                                log.debug("websocket", "Failed to send blob")
                            end
                        end
                    else
                        local c = Completion.get()
                        if c then
                            if c.request_id ~= parsed.r then
                                return
                            end

                            if parsed.v and parsed.v ~= vim.NIL and parsed ~= nil then
                                table.insert(c.completion, parsed.v)
                                c.is_active = true
                            end

                            if parsed.flush == true or parsed["end"] == true then
                                table.insert(c.completion, vim.NIL)
                                if parsed["end"] == true then
                                    c.is_active = false
                                end
                            end

                            suggestion.show(c.completion)
                        end
                    end
                end
                ::continue::
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
            -- 143 = SIGTERM (normal shutdown), 0 = normal exit
            if exit_code ~= 0 and exit_code ~= 143 then
                log.notify(
                    "websocket",
                    vim.log.levels.WARN,
                    true,
                    "websocket job exiting with code: " .. tostring(exit_code)
                )
            else
                log.debug("websocket", "websocket job exiting with code: " .. tostring(exit_code))
            end
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    if _G.Ninetyfive.websocket_job <= 0 then
        log.notify("websocket", vim.log.levels.ERROR, true, "Failed to start process")
        return false
    end

    log.debug("websocket", "Started process with job ID: " .. _G.Ninetyfive.websocket_job)

    return true
end

function Websocket.get_completion()
    local c = Completion.get()
    if c == nil then
        return ""
    end

    return c.completion
end

return Websocket
