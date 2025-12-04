local suggestion = require("ninetyfive.suggestion")
local Completion = require("ninetyfive.completion")

local CompletionState = {}

function CompletionState.has_active()
    if not current_completion or not current_completion.completion then
        return false
    end

    for _, item in ipairs(current_completion.completion) do
        if item.v and tostring(item.v):match("%S") then
            return true
        end
    end

    return false
end

function CompletionState.reset_completion()
    current_completion = nil
    buffer = nil
end

function CompletionState.get_completion_chunks()
    if current_completion == nil then
        return nil
    end
    return current_completion.completion
end

function CompletionState.reject()
    suggestion.clear()
end

function CompletionState.clear_suggestion()
    suggestion.clear()
end

return CompletionState
