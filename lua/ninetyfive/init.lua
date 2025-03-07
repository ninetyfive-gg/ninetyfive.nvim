local main = require("ninetyfive.main")
local config = require("ninetyfive.config")
local log = require("ninetyfive.util.log")
local state = require("ninetyfive.state")
local websocket = require("ninetyfive.websocket")

local Ninetyfive = {}

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
        log.debug("toggle", "Setting up autocommands and websocket after toggle")
        websocket.setup_autocommands()
        websocket.setup_connection("wss://api.ninetyfive.gg")
    end
end

--- Initializes the plugin, sets event listeners and internal state.
function Ninetyfive.enable(scope)
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    log.debug("init", "about to set up our stuff")
    
    -- Set up autocommands when plugin is enabled
    websocket.setup_autocommands()
    
    -- Set up websocket connection
    websocket.setup_connection("wss://api.ninetyfive.gg")
      
    main.toggle(scope or "public_api_enable")
end

--- Disables the plugin, clear highlight groups and autocmds, closes side buffers and resets the internal state.
function Ninetyfive.disable()
    main.toggle("public_api_disable")
end

-- setup Ninetyfive options and merge them with user provided ones.
function Ninetyfive.setup(opts)
    _G.Ninetyfive.config = config.setup(opts)
end

--- sets Ninetyfive with the provided API Key
---
---@param apiKey: the api key you want to use.
function Ninetyfive.setApiKey(apiKey)
    log.debug("some.scope", "Set api key called!!!!")
end

_G.Ninetyfive = Ninetyfive

return _G.Ninetyfive
