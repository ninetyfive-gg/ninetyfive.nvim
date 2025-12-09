local M = {}

---Compute the minimal delta between old_text and new_text.
---Returns start (byte offset), end (byte offset in old text), and the new text to insert.
---@param old_text string
---@param new_text string
---@return number start byte offset where change begins
---@return number end_pos byte offset in old_text where change ends
---@return string insert_text the text to insert at start
function M.compute_delta(old_text, new_text)
    -- Find common prefix
    local i = 1
    while i <= #old_text and i <= #new_text and old_text:sub(i, i) == new_text:sub(i, i) do
        i = i + 1
    end
    local prefix_len = i - 1

    -- Find common suffix (but don't overlap with prefix)
    local j = 0
    while j < #old_text - prefix_len and j < #new_text - prefix_len
          and old_text:sub(#old_text - j, #old_text - j) == new_text:sub(#new_text - j, #new_text - j) do
        j = j + 1
    end

    local start = prefix_len
    local end_pos = #old_text - j
    local insert_text = new_text:sub(prefix_len + 1, #new_text - j)

    return start, end_pos, insert_text
end

return M
