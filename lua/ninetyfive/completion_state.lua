local suggestion = require("ninetyfive.suggestion")

local CompletionState = {}

local current_completion = nil
local buffer = nil
local active_text = nil

function CompletionState.get_current_completion()
    return current_completion
end

function CompletionState.set_current_completion(value)
    current_completion = value
end

function CompletionState.get_buffer()
    return buffer
end

function CompletionState.set_buffer(bufnr)
    buffer = bufnr
end

function CompletionState.get_active_text()
    return active_text
end

function CompletionState.set_active_text(text)
    active_text = text
end

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

function CompletionState.clear()
    current_completion = nil
    buffer = nil
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

function CompletionState.accept()
    if
        current_completion ~= nil
        and #current_completion.completion > 0
        and buffer == vim.api.nvim_get_current_buf()
    then
        local bufnr = vim.api.nvim_get_current_buf()
        vim.b[bufnr].ninetyfive_accepting = true

        local built = {}
        for _, item in ipairs(current_completion.completion) do
            if item.v and item.v ~= vim.NIL then
                table.insert(built, tostring(item.v))
            end
        end
        local accepted_text = table.concat(built)

        suggestion.accept(current_completion)
        current_completion:consume(#accepted_text)

        local edit = current_completion:next_edit()

        if not edit then
            return
        end

        suggestion.showEditDescription(current_completion)

        current_completion.is_active = true

        if edit.text == "" then
            suggestion.showDeleteSuggestion(edit)
        elseif edit.start == edit["end"] then
            suggestion.showInsertSuggestion(edit.start, edit["end"], edit.text)
        else
            suggestion.showUpdateSuggestion(edit.start, edit["end"], edit.text)
        end

        current_completion.edit_index = current_completion.edit_index + 1
    end
end

function CompletionState.reject()
    suggestion.clear()
end

function CompletionState.clear_suggestion()
    suggestion.clear()
end

return CompletionState
