local log = require("ninetyfive.util.log")

local Completion = {}
Completion.__index = Completion

-- Create a new Completion instance
function Completion.new(request_id)
    local self = setmetatable({}, Completion)
    self.request_id = request_id
    self.completion = {}
    self.consumed = 0
    self.is_closed = false
    self.edits = {}
    self.edit_description = ""
    self.edit_index = 1

    self.is_active = false
    return self
end

function Completion:consume(n)
    local total = self:length()
    if n > total then
        log.debug("edit_state", "Illegal state: trying to mark flush beyond completion length")
        return
    end
    self.consumed = n
end

function Completion:get_text()
    local parts = {}

    if type(self.completion) == "table" then
        for _, item in ipairs(self.completion) do
            if type(item) == "table" then
                if item.v and item.v ~= vim.NIL then
                    table.insert(parts, tostring(item.v))
                end
            elseif type(item) == "string" then
                table.insert(parts, item)
            end
        end
    elseif type(self.completion) == "string" then
        table.insert(parts, self.completion)
    end

    return table.concat(parts)
end

function Completion:length()
    local text = self:get_text()
    return #text
end

function Completion:close()
    self.is_closed = true
    local text = self:get_text()

    if vim.trim(text) == "" then
        -- Handle a single newline as an edge case, we ignore the completion and directly go to edits
        self.consumed = #text
    end
end

function Completion:next_edit()
    if self.is_closed and self.consumed >= self:length() and self.edit_index <= #self.edits then
        return self.edits[self.edit_index]
    end
end

return Completion
