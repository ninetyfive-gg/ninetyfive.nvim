local M = {}

---@class DiffEdit
---@field type "ghost" | "delete" | "match"
---@field offset number Position in buffer (0-indexed from cursor)
---@field text string The text content

---@class DiffResult
---@field edits DiffEdit[]

---Greedy matching algorithm for calculating diff between completion and buffer.
---
---For each character in buffer, finds its next occurrence in completion.
---Gaps in completion become ghost text edits. Matched characters are preserved.
---
---@param completion string The completion text (first line only)
---@param buffer string The text after cursor on current line
---@param is_complete boolean If true, mark leftover buffer for deletion
---@return DiffResult
function M.calculate_diff(completion, buffer, is_complete)
    local edits = {}

    -- Empty buffer: entire completion is ghost text
    if buffer == "" then
        if completion ~= "" then
            table.insert(edits, { type = "ghost", offset = 0, text = completion })
        end
        return { edits = edits }
    end

    -- Empty completion: mark buffer for deletion if complete
    if completion == "" then
        if is_complete then
            table.insert(edits, { type = "delete", offset = 0, text = buffer })
        end
        return { edits = edits }
    end

    local i = 1 -- index in completion (1-based for Lua)
    local j = 1 -- index in buffer (1-based for Lua)
    local comp_len = #completion
    local buf_len = #buffer

    while i <= comp_len and j <= buf_len do
        -- Find next occurrence of buffer[j] in completion[i..]
        local buf_char = buffer:sub(j, j)
        local k = completion:find(buf_char, i, true) -- plain search

        if k then
            if k > i then
                -- There's a gap - add ghost text at current buffer position
                table.insert(edits, {
                    type = "ghost",
                    offset = j - 1, -- 0-indexed
                    text = completion:sub(i, k - 1),
                })
            end
            -- Record the match
            table.insert(edits, {
                type = "match",
                offset = j - 1, -- 0-indexed
                text = buf_char,
            })
            i = k + 1
            j = j + 1
        else
            -- No match found, stop matching
            break
        end
    end

    -- Leftover completion text becomes ghost text at end of matched buffer
    if i <= comp_len then
        table.insert(edits, {
            type = "ghost",
            offset = j - 1, -- 0-indexed
            text = completion:sub(i),
        })
    end

    -- Leftover buffer text - only mark for deletion after flush
    if j <= buf_len then
        if is_complete then
            table.insert(edits, {
                type = "delete",
                offset = j - 1, -- 0-indexed
                text = buffer:sub(j),
            })
        end
        -- During streaming, leftover buffer is left as-is (no edit)
    end

    return { edits = edits }
end

---Merge consecutive edits of the same type at the same effective position.
---This simplifies the edit list for rendering.
---@param edits DiffEdit[]
---@return DiffEdit[]
function M.merge_edits(edits)
    if #edits == 0 then
        return edits
    end

    local merged = {}
    local current = nil

    for _, edit in ipairs(edits) do
        if current == nil then
            current = { type = edit.type, offset = edit.offset, text = edit.text }
        elseif current.type == edit.type and current.type ~= "match" then
            -- Merge consecutive ghost or delete edits
            current.text = current.text .. edit.text
        else
            table.insert(merged, current)
            current = { type = edit.type, offset = edit.offset, text = edit.text }
        end
    end

    if current then
        table.insert(merged, current)
    end

    return merged
end

---Get only ghost text edits, merged together.
---@param result DiffResult
---@return string The combined ghost text
function M.get_ghost_text(result)
    local parts = {}
    for _, edit in ipairs(result.edits) do
        if edit.type == "ghost" then
            table.insert(parts, edit.text)
        end
    end
    return table.concat(parts)
end

---Check if the diff result has any delete markers.
---@param result DiffResult
---@return boolean
function M.has_deletions(result)
    for _, edit in ipairs(result.edits) do
        if edit.type == "delete" then
            return true
        end
    end
    return false
end

return M
