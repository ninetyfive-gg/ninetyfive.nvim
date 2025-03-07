local websocket = require("ninetyfive.websocket")
local Helpers = dofile("tests/helpers.lua")

-- Ensure the global table exists
_G.Ninetyfive = _G.Ninetyfive or {}

describe("websocket", function()
  before_each(function()
    -- Make sure the global table exists before accessing its properties
    _G.Ninetyfive = _G.Ninetyfive or {}
    _G.Ninetyfive.websocket_job = nil
    
    -- Check if reset_completion function exists before calling it
    if websocket.reset_completion then
      websocket.reset_completion()
    end
  end)

  it("should return false when sending message without connection", function()
    -- Don't connect: websocket.setup_connection("wss://echo.websocket.org")
    local result = websocket.send_message("1")
    
    Helpers.expect.match_bool(result, false)
  end)

end)
