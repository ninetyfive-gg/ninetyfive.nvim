local log = require("ninetyfive.util.log")
local websocket = require("ninetyfive.websocket")
local sse = require("ninetyfive.sse")
local completion_state = require("ninetyfive.completion_state")

local Transport = {}

local mode = nil

local function get_plugin_root()
    local runtime = vim.api.nvim_get_runtime_file("lua/ninetyfive/init.lua", false)[1] or ""
    return vim.fn.fnamemodify(runtime, ":h:h:h")
end

local function enable_websocket(server_uri, user_id, api_key)
    local ok = websocket.setup_connection(server_uri, user_id, api_key)
    if ok then
        mode = "websocket"
        return true
    end

    return false
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

    if enable_websocket(server_uri, user_id, api_key) then
        Transport.setup_autocommands()
        return true, mode
    end

    log.debug("transport", "websocket setup failed, attempting SSE fallback")

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
    return completion_state.has_active()
end

function Transport.clear()
    completion_state.clear()
end

function Transport.accept()
    completion_state.accept()
end

function Transport.accept_edit()
    completion_state.accept_edit()
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
