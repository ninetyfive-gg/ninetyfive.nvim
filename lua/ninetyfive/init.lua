local main = require("ninetyfive.main")
local config = require("ninetyfive.config")
local log = require("ninetyfive.util.log")
local state = require("ninetyfive.state")
local Communication = require("ninetyfive.communication")
local CommunicationAutocmds = require("ninetyfive.communication_autocmds")
local Completion = require("ninetyfive.completion")
local suggestion = require("ninetyfive.suggestion")
local websocket = require("ninetyfive.websocket")

local communication = Communication.new()
local autocmds = CommunicationAutocmds.new({ communication = communication })

-- Register callback to resync buffers after websocket reconnection
websocket.on_reconnect(function()
    communication:resync_all_buffers()
end)

math.randomseed(os.time())

local Ninetyfive = {}

local function get_plugin_root()
    local runtime = vim.api.nvim_get_runtime_file("lua/ninetyfive/init.lua", false)[1] or ""
    return vim.fn.fnamemodify(runtime, ":h:h:h")
end

local function has_dist_directory()
    local plugin_root = get_plugin_root()
    if plugin_root == "" then
        return true
    end
    local dist_dir = plugin_root .. "/dist"
    return vim.fn.isdirectory(dist_dir) == 1
end

local function shutdown_connection()
    autocmds:clear()
    communication:shutdown()
end

local function setup_connection(server, user_id, api_key)
    shutdown_connection()

    communication:configure({
        server_uri = server,
        user_id = user_id,
        api_key = api_key,
    })

    local dist_available = has_dist_directory()
    communication:configure({
        preferred = dist_available and "websocket" or "sse",
        allow_fallback = dist_available,
    })

    local ok, mode = communication:connect()
    if ok then
        autocmds:setup_autocommands()
        return true, mode
    end

    if not dist_available then
        log.notify(
            "transport",
            vim.log.levels.ERROR,
            true,
            "Failed to enable SSE fallback despite missing dist directory"
        )
    else
        log.notify(
            "transport",
            vim.log.levels.ERROR,
            true,
            string.format("Failed to establish Ninetyfive transport (%s)", tostring(mode))
        )
    end

    return false
end

local function generate_user_id()
    local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    local result = {}
    for i = 1, 10 do
        local rand = math.random(1, #chars)
        table.insert(result, chars:sub(rand, rand))
    end
    return table.concat(result)
end

local function get_user_data()
    local data_dir = vim.fn.stdpath("data")
    local ninetyfive_dir = data_dir .. "/ninetyfive"
    local user_data_file = ninetyfive_dir .. "/user_data.json" -- use a json file in case we need to store more stuff later

    if vim.fn.isdirectory(ninetyfive_dir) == 0 then
        vim.fn.mkdir(ninetyfive_dir, "p")
    end

    local user_data = {}

    if vim.fn.filereadable(user_data_file) == 1 then
        local content = table.concat(vim.fn.readfile(user_data_file), "\n")
        local ok, data = pcall(vim.json.decode, content)
        if ok and data then
            user_data = data
        end
    end

    if not user_data.user_id then
        user_data.user_id = generate_user_id()
        local json_str = vim.json.encode(user_data)
        vim.fn.writefile({ json_str }, user_data_file)
    end

    return user_data
end

--- Toggle the plugin by calling the `enable`/`disable` methods respectively.
function Ninetyfive.toggle()
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    -- Check if the plugin is currently disabled
    local was_disabled = not state:get_enabled()

    main.toggle("public_api_toggle")

    -- If the plugin was disabled and is now enabled, establish transport connection
    if was_disabled and state:get_enabled() then
        local server = _G.Ninetyfive.config.server
        log.debug("toggle", "Setting up transport after toggle")
        local user_data = get_user_data()
        setup_connection(server, user_data.user_id, user_data.api_key)
    else
        shutdown_connection()
        suggestion.clear()
        Completion.clear()
    end
end

--- Initializes the plugin, sets event listeners and internal state.
function Ninetyfive.enable(scope)
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    local server = _G.Ninetyfive.config.server

    -- Set up autocommands when plugin is enabled
    local user_data = get_user_data()
    setup_connection(server, user_data.user_id, user_data.api_key)

    main.toggle(scope or "public_api_enable")
end

--- Disables the plugin, clear highlight groups and autocmds, closes side buffers and resets the internal state.
function Ninetyfive.disable()
    main.toggle("public_api_disable")
end

-- setup Ninetyfive options and merge them with user provided ones.
function Ninetyfive.setup(opts)
    _G.Ninetyfive.config = config.setup(opts)

    if _G.Ninetyfive.config and _G.Ninetyfive.config.enable_on_startup then
        -- We make sure we enable, since the default value for 'state' is disabled
        main.enable("public_api_enable")
        local user_data = get_user_data()
        -- Set up autocommands when plugin is enabled
        local server = _G.Ninetyfive.config.server
        setup_connection(server, user_data.user_id, user_data.api_key)
    end
end

--- sets Ninetyfive with the provided API Key
---
---@param api_key string: the api key you want to use.
function Ninetyfive.setApiKey(api_key)
    log.debug("init.lua", "Setting API key")

    local data_dir = vim.fn.stdpath("data")
    local ninetyfive_dir = data_dir .. "/ninetyfive"
    local user_data_file = ninetyfive_dir .. "/user_data.json"

    if vim.fn.isdirectory(ninetyfive_dir) == 0 then
        vim.fn.mkdir(ninetyfive_dir, "p")
    end

    local user_data = {}

    if vim.fn.filereadable(user_data_file) == 1 then
        local content = table.concat(vim.fn.readfile(user_data_file), "\n")
        local ok, data = pcall(vim.json.decode, content)
        if ok and data then
            user_data = data
        end
    end

    user_data.api_key = api_key

    -- Write to the file
    local json_str = vim.json.encode(user_data)
    vim.fn.writefile({ json_str }, user_data_file)

    -- We probably want to reconnect
    if _G.Ninetyfive and _G.Ninetyfive.config and _G.Ninetyfive.config.server then
        local server = _G.Ninetyfive.config.server
        local user_data = get_user_data()

        setup_connection(server, user_data.user_id, user_data.api_key)
    end
end

function Ninetyfive.accept()
    suggestion.accept()
end

function Ninetyfive.accept_word()
    suggestion.accept_word()
end

function Ninetyfive.accept_line()
    suggestion.accept_line()
end

function Ninetyfive.reject()
    local completion = Completion.get()
    local request_id = completion and completion.request_id or nil

    Completion.clear()
    suggestion.clear()

    if not request_id or not communication:is_websocket() then
        return
    end

    vim.schedule(function()
        if not websocket.is_connected() then
            return
        end

        local payload = {
            type = "reject-completion",
            requestId = request_id,
        }
        local ok, message = pcall(vim.json.encode, payload)
        if not ok then
            log.debug("init", "failed to encode reject-completion payload: %s", tostring(message))
            return
        end

        if not websocket.send_message(message) then
            log.debug("init", "failed to send reject-completion message")
        end
    end)
end

--- Returns the current status text for display (e.g., in lualine)
--- Returns subscription name if connected, "NinetyFive Disconnected" otherwise
---@return string
function Ninetyfive.get_status()
    if not websocket.is_connected() then
        return "NinetyFive Disconnected"
    end

    local sub_info = websocket.get_subscription_info()
    if sub_info and sub_info.name then
        return sub_info.name
    end

    return "NinetyFive"
end

--- Returns the color for the current status (for lualine)
--- Returns nil for paid users (use default), red for disconnected, yellow for unpaid
---@return table|nil
function Ninetyfive.get_status_color()
    if not websocket.is_connected() then
        return { fg = "#e06c75" } -- red for disconnected
    end

    local sub_info = websocket.get_subscription_info()
    if sub_info and sub_info.is_paid then
        return nil -- no color override for paid users
    end

    return { fg = "#e5c07b" } -- yellow for unpaid/unknown
end

_G.Ninetyfive = Ninetyfive

return _G.Ninetyfive
