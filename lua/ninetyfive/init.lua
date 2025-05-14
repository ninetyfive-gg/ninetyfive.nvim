local main = require("ninetyfive.main")
local config = require("ninetyfive.config")
local log = require("ninetyfive.util.log")
local state = require("ninetyfive.state")
local websocket = require("ninetyfive.websocket")
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

local function get_or_create_user_id()
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
        if ok and data and data.user_id then
            return data.user_id
        end
    end

    user_data.user_id = generate_user_id()
    local json_str = vim.json.encode(user_data)
    vim.fn.writefile({ json_str }, user_data_file)

    return user_data.user_id
end

--- Toggle the plugin by calling the `enable`/`disable` methods respectively.
function Ninetyfive.toggle()
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    -- Check if the plugin is currently disabled
    local was_disabled = not state:get_enabled()

    main.toggle("public_api_toggle")

    -- If the plugin was disabled and is now enabled, set up autocommands and websocket
    if was_disabled and state:get_enabled() then
        local server = _G.Ninetyfive.config.server
        log.debug("toggle", "Setting up autocommands and websocket after toggle")
        websocket.setup_autocommands()
        local user_id = get_or_create_user_id()
        websocket.setup_connection(server, user_id)
    end
end

--- Initializes the plugin, sets event listeners and internal state.
function Ninetyfive.enable(scope)
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    local server = _G.Ninetyfive.config.server

    -- Set up autocommands when plugin is enabled
    websocket.setup_autocommands()

    local user_id = get_or_create_user_id()
    -- Set up websocket connection
    websocket.setup_connection(server, user_id)

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
        local user_id = get_or_create_user_id()
        -- Set up autocommands when plugin is enabled
        websocket.setup_autocommands()

        local server = _G.Ninetyfive.config.server
        -- Set up websocket connection
        websocket.setup_connection(server, user_id)
    end
end

--- sets Ninetyfive with the provided API Key
---
---@param api_key string: the api key you want to use.
function Ninetyfive.setApiKey(api_key)
    log.debug("init.lua", "Set api key called!!!!")
end

function Ninetyfive.accept()
    websocket.accept()
end

function Ninetyfive.accept_edit(edit)
    websocket.accept_edit()
end

function Ninetyfive.reject()
    websocket.reject()
end

_G.Ninetyfive = Ninetyfive

return _G.Ninetyfive
