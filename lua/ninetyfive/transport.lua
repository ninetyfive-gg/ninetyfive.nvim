local log = require("ninetyfive.util.log")
local websocket = require("ninetyfive.websocket")
local sse = require("ninetyfive.sse")
local completion_state = require("ninetyfive.completion_state")
local Completion = require("ninetyfive.completion")
local suggestion = require("ninetyfive.suggestion")

local Transport = {}

local mode = nil

local function get_plugin_root()
    local runtime = vim.api.nvim_get_runtime_file("lua/ninetyfive/init.lua", false)[1] or ""
    return vim.fn.fnamemodify(runtime, ":h:h:h")
end

local function enable_websocket(server_uri, user_id, api_key)
    local ok, err = websocket.setup_connection(server_uri, user_id, api_key)
    if ok then
        mode = "websocket"
        return true
    end

    return false, err
end

local function enable_sse(server_uri, user_id, api_key)
    local ok = sse.setup({
        server_uri = server_uri,
        user_id = user_id,
        api_key = api_key,
    })

    if ok then
        mode = "sse"
        return true
    end

    return false
end

function Transport.current_mode()
    return mode
end

function Transport.is_sse()
    return mode == "sse"
end

function Transport.shutdown()
    sse.shutdown()
    websocket.shutdown()
    mode = nil
end

function Transport.setup_connection(server_uri, user_id, api_key)
    Transport.shutdown()

    local plugin_root = get_plugin_root()
    if plugin_root ~= "" then
        local dist_dir = plugin_root .. "/dist"
        local has_dist = vim.fn.isdirectory(dist_dir) == 1

        if not has_dist then
            if enable_sse(server_uri, user_id, api_key) then
                log.debug("transport", "dist directory missing, using SSE transport")
                Transport.setup_autocommands()
                return true, mode
            end

            log.notify(
                "transport",
                vim.log.levels.ERROR,
                true,
                "Failed to enable SSE fallback despite missing dist directory"
            )
            return false
        end
    end

    local ws_ok, ws_err = enable_websocket(server_uri, user_id, api_key)
    if ws_ok then
        Transport.setup_autocommands()
        return true, mode
    end

    local fallback_reason
    if ws_err == "missing_binary" then
        fallback_reason = "Websocket proxy binary not available"
    else
        fallback_reason = "Websocket setup failed"
    end

    log.debug("transport", fallback_reason .. ", trying to use SSE")

    if enable_sse(server_uri, user_id, api_key) then
        Transport.setup_autocommands()
        return true, mode
    end

    return false
end

function Transport.setup_autocommands()
    if mode == "sse" then
        sse.setup_autocommands()
    elseif mode == "websocket" then
        websocket.setup_autocommands()
    end
end

function Transport.has_active()
    local completion = Completion.get()
    return completion and #completion.completion > 0
end

function Transport.clear()
    completion_state.clear()
end

function Transport.accept()
    suggestion.accept()
end

function Transport.reject()
    completion_state.reject()
end

function Transport.get_completion()
    return completion_state.get_completion_chunks()
end

function Transport.reset_completion()
    completion_state.reset_completion()
end

return Transport
