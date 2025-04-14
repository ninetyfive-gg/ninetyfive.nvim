local log = require("ninetyfive.util.log")

local Completion = {}
Completion.__index = Completion

-- Create a new Completion instance
function Completion.new(request_id)
    local self = setmetatable({}, Completion)
    self.request_id = request_id
    self.completion = ""
    self.consumed = 0
    self.is_closed = false
    self.edits = {}
    self.edit_description = ""
    self.edit_index = 0

    self.isJumpEdit = false
    self.isInlineEdit = false
    self.isJumpHint = false
    self.isActive = false
    self.hint = ""
    self.buffer = nil
    self.offset = 0
    self.jumpDestLine = 0
    self.jumpDestCol = 0
    return self
end

function Completion:consume(n)
    if n > #self.completion then
        log.debug("edit_state", "Illegal state: trying to mark flush beyond completion length")
        return
    end
    self.consumed = n
end

function Completion:close()
    self.is_closed = true
    if vim.trim(self.completion) == "" then
        -- Handle a single newline as an edge case, we ignore the completion and directly go to edits
        self.consumed = #self.completion
    end
end

function Completion:next_edit()
    if self.is_closed and self.consumed == #self.completion and self.edit_index < #self.edits then
        return self.edits[self.edit_index + 1]
    end
end

return Completion
