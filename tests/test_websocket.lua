local websocket = require("ninetyfive.websocket")
local eq = MiniTest.expect.equality

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

        eq(result, false)
    end)
end)
