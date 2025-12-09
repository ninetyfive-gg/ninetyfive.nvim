local suggestion = {}
local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")
local ninetyfive_delete_ns = vim.api.nvim_create_namespace("ninetyfive_delete_ns")
local Completion = require("ninetyfive.completion")
local highlighting = require("ninetyfive.highlighting")
local diff = require("ninetyfive.diff")

local completion_id = ""
local completion_bufnr = nil

local log = require("ninetyfive.util.log")
local lsp_util = vim.lsp.util

-- Highlight group for text to be deleted (red + strikethrough)
local function setup_delete_highlight()
    vim.api.nvim_set_hl(0, "NinetyFiveDelete", {
        strikethrough = true,
        fg = "#ff6666",
        bg = "#3d1f1f",
    })
end

suggestion.show = function(completion)
    if vim.fn.mode() ~= "i" then
        -- Do not show a suggestion if not in insert mode!
        return
    end

    -- build text up to the next flush
    local parts = {}
    local is_complete = false
    if type(completion) == "table" then
        log.debug("suggestion", "show() - completion array has %d items", #completion)
        for i = 1, #completion do
            local item = completion[i]
            if item == vim.NIL then -- Stop at first nil (flush marker)
                log.debug("suggestion", "show() - found flush at index %d", i)
                is_complete = true
                break
            end
            log.debug("suggestion", "show() - chunk[%d]: %q", i, tostring(item))
            table.insert(parts, tostring(item))
        end
    end

    local text = table.concat(parts)
    log.debug("suggestion", "show() - full text: %q (len=%d)", text, #text)

    local bufnr = vim.api.nvim_get_current_buf()
    -- Clear any existing extmarks in the buffer
    if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_del_extmark(bufnr, ninetyfive_ns, 1)
        vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_delete_ns, 0, -1)
    end

    local cursor_line = vim.fn.line(".") - 1
    local cursor_col = vim.fn.col(".") - 1

    -- Split completion into first line and remaining lines
    local lines = vim.split(text, "\n", { plain = true })
    local first_line_text = lines[1] or ""
    local remaining_lines = {}
    for i = 2, #lines do
        table.insert(remaining_lines, lines[i])
    end

    -- Get text after cursor on current line (the "buffer" for diff)
    local current_line = vim.api.nvim_buf_get_lines(bufnr, cursor_line, cursor_line + 1, false)[1] or ""
    local buffer_after_cursor = current_line:sub(cursor_col + 1)

    log.debug("suggestion", "show() - cursor_line=%d, cursor_col=%d", cursor_line, cursor_col)
    log.debug("suggestion", "show() - current_line=%q", current_line)
    log.debug("suggestion", "show() - first_line_text=%q", first_line_text)
    log.debug("suggestion", "show() - buffer_after_cursor=%q", buffer_after_cursor)
    log.debug("suggestion", "show() - is_complete=%s", tostring(is_complete))

    -- Calculate diff between first line of completion and buffer
    local diff_result = diff.calculate_diff(first_line_text, buffer_after_cursor, is_complete)

    log.debug("suggestion", "show() - diff returned %d edits", #diff_result.edits)

    -- Count ghost edits to detect fragmented diffs
    local ghost_count = 0
    for _, edit in ipairs(diff_result.edits) do
        if edit.type == "ghost" then
            ghost_count = ghost_count + 1
        end
    end

    -- Build virtual text for first line based on diff
    local first_line_virt_text = {}

    -- If diff is too fragmented (more than 2 ghost segments), fall back to simple rendering
    -- This happens when greedy matching produces many small interspersed edits
    local use_simple_rendering = ghost_count > 2

    if use_simple_rendering then
        log.debug("suggestion", "show() - using simple rendering (ghost_count=%d)", ghost_count)
        -- Simple rendering: show full completion as ghost text
        local highlighted = highlighting.highlight_completion(first_line_text, bufnr)
        if highlighted[1] then
            for _, segment in ipairs(highlighted[1]) do
                table.insert(first_line_virt_text, segment)
            end
        end
        -- Mark entire buffer after cursor for deletion if complete
        if is_complete and buffer_after_cursor ~= "" then
            setup_delete_highlight()
            vim.api.nvim_buf_add_highlight(
                bufnr,
                ninetyfive_delete_ns,
                "NinetyFiveDelete",
                cursor_line,
                cursor_col,
                cursor_col + #buffer_after_cursor
            )
            log.debug("suggestion", "show() - simple: marking buffer for deletion: col %d-%d",
                cursor_col, cursor_col + #buffer_after_cursor)
        end
    else
        -- Use diff-based rendering for clean diffs
        for idx, edit in ipairs(diff_result.edits) do
            log.debug("suggestion", "show() - processing edit[%d]: type=%s, offset=%d, text=%q",
                idx, edit.type, edit.offset, edit.text)
            if edit.type == "ghost" then
                -- Get highlighted segments for this ghost text
                local highlighted = highlighting.highlight_completion(edit.text, bufnr)
                if highlighted[1] then
                    for _, segment in ipairs(highlighted[1]) do
                        table.insert(first_line_virt_text, segment)
                    end
                end
                log.debug("suggestion", "show() - added ghost text to virt_text")
            elseif edit.type == "delete" and is_complete then
                -- Add delete highlight to existing buffer text
                setup_delete_highlight()
                local delete_start_col = cursor_col + edit.offset
                local delete_end_col = delete_start_col + #edit.text
                log.debug("suggestion", "show() - adding delete highlight: col %d-%d",
                    delete_start_col, delete_end_col)
                vim.api.nvim_buf_add_highlight(
                    bufnr,
                    ninetyfive_delete_ns,
                    "NinetyFiveDelete",
                    cursor_line,
                    delete_start_col,
                    delete_end_col
                )
            end
            -- "match" type: text already in buffer, no virtual text needed
        end
    end

    log.debug("suggestion", "show() - first_line_virt_text has %d segments", #first_line_virt_text)

    -- If no ghost text edits, use empty virtual text
    if #first_line_virt_text == 0 then
        first_line_virt_text = { { "", "NinetyFiveGhost" } }
        log.debug("suggestion", "show() - no ghost edits, using empty virt_text")
    end

    -- Get highlighted virtual lines for remaining lines
    local virt_lines = {}
    if #remaining_lines > 0 then
        local remaining_text = table.concat(remaining_lines, "\n")
        virt_lines = highlighting.highlight_completion(remaining_text, bufnr)
    end

    -- Use inline positioning (Neovim 0.10+) to push text right, fall back to overlay
    local has_inline = vim.fn.has("nvim-0.10") == 1
    local extmark_opts = {
        id = 1,
        virt_text = first_line_virt_text,
        virt_lines = virt_lines,
        hl_mode = "combine",
        ephemeral = false,
    }

    if has_inline then
        extmark_opts.virt_text_pos = "inline"
    else
        extmark_opts.virt_text_win_col = vim.fn.virtcol(".") - 1
    end

    completion_id = vim.api.nvim_buf_set_extmark(
        bufnr,
        ninetyfive_ns,
        cursor_line,
        cursor_col,
        extmark_opts
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
    if not applied then
        return
    end

    current_completion.last_accepted = accepted_text
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
        vim.api.nvim_buf_clear_namespace(buffer, ninetyfive_delete_ns, 0, -1)
    end
    completion_id = ""
    completion_bufnr = nil
end

return suggestion
