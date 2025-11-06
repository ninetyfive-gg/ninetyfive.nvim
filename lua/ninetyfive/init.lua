local main = require("ninetyfive.main")
local config = require("ninetyfive.config")
local log = require("ninetyfive.util.log")
local state = require("ninetyfive.state")
local transport = require("ninetyfive.transport")
local completion_state = require("ninetyfive.completion_state")

math.randomseed(os.time())

local Ninetyfive = {}

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
        transport.setup_connection(server, user_data.user_id, user_data.api_key)
    else
        transport.shutdown()
        completion_state.clear()
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
    transport.setup_connection(server, user_data.user_id, user_data.api_key)

    main.toggle(scope or "public_api_enable")
end

--- Disables the plugin, clear highlight groups and autocmds, closes side buffers and resets the internal state.
function Ninetyfive.disable()
    main.toggle("public_api_disable")
end

-- setup Ninetyfive options and merge them with user provided ones.
function Ninetyfive.setup(opts)
    _G.Ninetyfive.config = config.setup(opts)

    if _G.Ninetyfive.config.enable_on_startup then
        -- We make sure we enable, since the default value for 'state' is disabled
        main.enable("public_api_enable")
        local user_data = get_user_data()
        -- Set up autocommands when plugin is enabled
        local server = _G.Ninetyfive.config.server
        transport.setup_connection(server, user_data.user_id, user_data.api_key)
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

        transport.setup_connection(server, user_data.user_id, user_data.api_key)
    end
end

function Ninetyfive.accept()
    transport.accept()
end

function Ninetyfive.accept_edit(edit)
    transport.accept_edit()
end

function Ninetyfive.reject()
    transport.reject()
end

_G.Ninetyfive = Ninetyfive

return _G.Ninetyfive
