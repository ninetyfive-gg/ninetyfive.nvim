local suggestion = {}
local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")
local Completion = require("ninetyfive.completion")

local completion_id = ""
local completion_bufnr = nil

local log = require("ninetyfive.util.log")
local lsp_util = vim.lsp.util

suggestion.show = function(completion)
    -- build text up to the next flush
    local parts = {}
    -- print("show")
    if type(completion) == "table" then
        for i = 1, #completion do
            local item = completion[i]
            if item == vim.NIL then -- Stop at first nil
                break
            end
            table.insert(parts, tostring(item))
            -- print(tostring(item))
        end
    end

    local text = table.concat(parts)

    local bufnr = vim.api.nvim_get_current_buf()
    -- Clear any existing extmarks in the buffer
    if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_del_extmark(bufnr, ninetyfive_ns, 1)
    end
    local virt_lines = {}
    for _, l in ipairs(vim.fn.split(text, "\n", true)) do
        table.insert(virt_lines, { { l, "Comment" } })
    end
    local first_line = table.remove(virt_lines, 1) or { { "", "Comment" } }

    completion_id = vim.api.nvim_buf_set_extmark(
        bufnr,
        ninetyfive_ns,
        vim.fn.line(".") - 1,
        vim.fn.col(".") - 1,
        {
            id = 1,
            -- right_gravity = true,
            virt_text = first_line,
            -- virt_text_pos = vim.fn.has("nvim-0.10") == 1 and "inline" or "overlay",
            virt_lines = virt_lines,
            virt_text_win_col = vim.fn.virtcol(".") - 1,
            hl_mode = "combine",
            ephemeral = false,
        }
    )
    completion_bufnr = bufnr
end

function suggestion.get_current_extmark_position(bufnr)
    bufnr = bufnr or completion_bufnr

    if completion_id == "" or not bufnr or bufnr == 0 then
        return nil
    end

    local mark =
        vim.api.nvim_buf_get_extmark_by_id(bufnr, ninetyfive_ns, completion_id, { details = false })
    if not mark or #mark < 2 then
        return nil
    end

    return { row = mark[1], col = mark[2] }
end

local function collect_completion_text(completion)
    if type(completion) ~= "table" then
        return ""
    end

    local parts = {}
    for i = 1, #completion do
        local item = completion[i]
        if item == vim.NIL then
            break
        end
        parts[#parts + 1] = tostring(item)
    end

    return table.concat(parts)
end

local function extract_extmark_text(details)
    if type(details) ~= "table" then
        return ""
    end

    local parts = {}

    if details.virt_text then
        for _, part in ipairs(details.virt_text) do
            parts[#parts + 1] = part[1]
        end
    end

    if details.virt_lines then
        for _, virt_line in ipairs(details.virt_lines) do
            parts[#parts + 1] = "\n"
            for _, part in ipairs(virt_line) do
                parts[#parts + 1] = part[1]
            end
        end
    end

    return table.concat(parts)
end

local function apply_completion_text(bufnr, line, col, text)
    if text == "" then
        return false
    end

    local has_newline = string.find(text, "\n", 1, true) ~= nil
    local end_line = line
    local end_col = col

    if not has_newline then
        local first_line = text
        local line_break = string.find(text, "\n", 1, true)
        if line_break then
            first_line = string.sub(text, 1, line_break - 1)
        end

        local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
        local virt_width = vim.fn.strdisplaywidth(first_line)
        end_col = math.min(#line_text, col + virt_width)
    end

    local offset_encoding = "utf-8"
    local start_character = lsp_util.character_offset(bufnr, line, col, offset_encoding)
    local end_character = lsp_util.character_offset(bufnr, end_line, end_col, offset_encoding)

    local ok, err = pcall(lsp_util.apply_text_edits, {
        {
            range = {
                start = { line = line, character = start_character },
                ["end"] = { line = end_line, character = end_character },
            },
            newText = text,
        },
    }, bufnr, offset_encoding)

    if not ok then
        log.error("Failed to apply suggestion: " .. tostring(err))
        vim.b[bufnr].ninetyfive_accepting = false
        return false
    end

    local lines = vim.split(text, "\n", { plain = true, trimempty = false })
    local new_line = line
    local new_col = col

    if #lines > 0 then
        if #lines > 1 then
            new_line = line + #lines - 1
            new_col = #lines[#lines]
        else
            new_col = col + #lines[1]
        end
    end

    vim.api.nvim_win_set_cursor(0, { new_line + 1, new_col })
    return true
end

local function accept_with_selector(selector)
    local current_completion = Completion.get()
    if
        current_completion == nil
        or #current_completion.completion == 0
        or current_completion.buffer ~= vim.api.nvim_get_current_buf()
    then
        return
    end

    if completion_id == "" then
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    vim.b[bufnr].ninetyfive_accepting = true

    local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ninetyfive_ns, 1, { details = true })
    if not extmark or #extmark == 0 then
        vim.b[bufnr].ninetyfive_accepting = false
        return
    end

    local completion_text = collect_completion_text(current_completion.completion)
    if completion_text == "" then
        vim.b[bufnr].ninetyfive_accepting = false
        return
    end

    local details = extmark[3]
    local display_text = extract_extmark_text(details)
    if display_text == "" then
        display_text = completion_text
    end

    local accepted_text = selector(display_text, completion_text)
    if not accepted_text or accepted_text == "" then
        vim.b[bufnr].ninetyfive_accepting = false
        return
    end

    vim.api.nvim_buf_del_extmark(bufnr, ninetyfive_ns, 1)

    local line, col = extmark[1], extmark[2]
    vim.b[bufnr].ninetyfive_accepting = true
    local applied = apply_completion_text(bufnr, line, col, accepted_text)
    -- vim.b[bufnr].ninetyfive_accepting = false
    if not applied then
        return
    end

    current_completion.last_accepted = accepted_text

    -- local accepted_length = #accepted_text
    -- local consumed_entire_completion = accepted_length >= #completion_text
    -- local consume_count = consumed_entire_completion and (accepted_length + 1) or accepted_length

    -- local updated_completion = consumeChars(current_completion.completion, consume_count)
    -- current_completion.completion = updated_completion

    -- if #updated_completion > 0 then
    --     if consumed_entire_completion then
    --         table.insert(updated_completion, 1, "\n")
    --     end
    --     vim.b[bufnr].ninetyfive_accepting = true
    --     suggestion.show(updated_completion)
    -- else
    --     vim.b[bufnr].ninetyfive_accepting = false
    --     completion_id = ""
    --     completion_bufnr = nil
    -- end
end

local function select_next_word(text)
    if text == "" then
        return ""
    end

    local newline_idx = string.find(text, "\n", 1, true)
    local limit = newline_idx and (newline_idx - 1) or #text
    if limit <= 0 then
        return ""
    end

    local idx = 1
    while idx <= limit and string.match(text:sub(idx, idx), "%s") do
        idx = idx + 1
    end

    if idx > limit then
        return string.sub(text, 1, limit)
    end

    local word_end = idx
    while word_end <= limit and not string.match(text:sub(word_end, word_end), "%s") do
        word_end = word_end + 1
    end

    while word_end <= limit and string.match(text:sub(word_end, word_end), "%s") do
        word_end = word_end + 1
    end

    return string.sub(text, 1, word_end - 1)
end

local function select_line(text)
    if text == "" then
        return ""
    end

    local newline_idx = string.find(text, "\n", 1, true)
    if newline_idx then
        return string.sub(text, 1, newline_idx)
    end

    return text
end

local function select_completion_text(_, completion_text)
    return completion_text or ""
end

suggestion.accept = function()
    accept_with_selector(select_completion_text)
end

suggestion.accept_word = function()
    accept_with_selector(select_next_word)
end

suggestion.accept_line = function()
    accept_with_selector(select_line)
end

suggestion.clear = function()
    local buffer = vim.api.nvim_get_current_buf()
    if buffer ~= nil and vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_del_extmark(buffer, ninetyfive_ns, 1)
    end
    completion_id = ""
    completion_bufnr = nil
end

return suggestion
