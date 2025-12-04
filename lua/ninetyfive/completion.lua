local Completion = {}
Completion.__index = Completion

-- Global single completion instance
local current_completion = nil

-- Create or replace the global completion
function Completion.new(request_id)
    local self = setmetatable({}, Completion)
    self.request_id = request_id
    self.completion = {}
    self.is_closed = false
    self.is_active = false
    self.buffer = nil
    self.active_text = nil
    self.prefix = ""
    self.last_accepted = ""

    -- Set as the global completion
    current_completion = self

    return self
end

-- Get the current global completion
function Completion.get()
    return current_completion
end

-- Clear the global completion
function Completion.clear()
    print("whos clearing")
    current_completion = nil
end

-- Check if a completion exists
function Completion.exists()
    return current_completion ~= nil
end

return Completion
