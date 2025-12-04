local suggestion = {}
local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")
local ninetyfive_edit_ns = vim.api.nvim_create_namespace("ninetyfive_edit_ns")
local ninetyfive_hint_ns = vim.api.nvim_create_namespace("ninetyfive_hint_ns")

local completion_id = ""

local log = require("ninetyfive.util.log")

local function get_pos_from_index(buf, index)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
    local char_count = 0

    for line_num, line in ipairs(lines) do
        local line_len = #line -- No need to add 1 for newline
        if char_count + line_len >= index then
            local col = math.min(index - char_count, line_len) -- Clamp to valid range
            return line_num - 1, col -- Convert to 0-based
        end
        char_count = char_count + line_len + 1 -- +1 for newline
    end

    return #lines - 1, 0 -- Fallback to last line start
end

suggestion.showInsertSuggestion = function(start_pos, end_pos, message)
    local buf = vim.api.nvim_get_current_buf()
    local start_line, start_col = get_pos_from_index(buf, start_pos)

    vim.api.nvim_buf_clear_namespace(buf, ninetyfive_edit_ns, 0, -1)

    message = message:gsub("\n+$", "")
    local message_lines = vim.fn.split(message, "\n")

    local virt_lines = {}
    for _, line in ipairs(message_lines) do
        if line ~= "" then
            table.insert(virt_lines, { { line, "DiffAdd" } })
        end
    end

    if #virt_lines > 0 then
        vim.api.nvim_buf_set_extmark(buf, ninetyfive_edit_ns, start_line, start_col, {
            virt_lines = virt_lines,
            virt_lines_above = true,
            hl_mode = "combine",
            ephemeral = false,
        })
    end
end

suggestion.showDeleteSuggestion = function(edit)
    local buf = vim.api.nvim_get_current_buf()
    local start_line, start_col = get_pos_from_index(buf, edit.start)
    local end_line, end_col = get_pos_from_index(buf, edit["end"])

    -- Clear previous highlights in the namespace
    vim.api.nvim_buf_clear_namespace(buf, ninetyfive_edit_ns, 0, -1)

    -- Create a custom highlight group with red background for deletion
    vim.cmd([[
        highlight NinetyfiveDelete guibg=#ff5555 guifg=white ctermbg=red ctermfg=white
    ]])

    -- Highlight the region to be deleted with red background
    if start_line == end_line then
        -- Single line deletion
        vim.api.nvim_buf_add_highlight(
            buf,
            ninetyfive_edit_ns,
            "NinetyfiveDelete",
            start_line,
            start_col,
            end_col
        )
    else
        -- Multi-line deletion
        -- Highlight first line from start_col to end
        local first_line_text = vim.api.nvim_buf_get_lines(buf, start_line, start_line + 1, false)[1]
            or ""
        vim.api.nvim_buf_add_highlight(
            buf,
            ninetyfive_edit_ns,
            "NinetyfiveDelete",
            start_line,
            start_col,
            #first_line_text
        )

        -- Highlight middle lines completely
        for line = start_line + 1, end_line - 1 do
            local line_text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
            vim.api.nvim_buf_add_highlight(
                buf,
                ninetyfive_edit_ns,
                "NinetyfiveDelete",
                line,
                0,
                #line_text
            )
        end

        -- Highlight last line from start to end_col
        if start_line < end_line then
            vim.api.nvim_buf_add_highlight(
                buf,
                ninetyfive_edit_ns,
                "NinetyfiveDelete",
                end_line,
                0,
                end_col
            )
        end
    end
end

suggestion.showUpdateSuggestion = function(start_pos, end_pos, message)
    local buf = vim.api.nvim_get_current_buf()
    local start_line, start_col = get_pos_from_index(buf, start_pos)
    local end_line, end_col = get_pos_from_index(buf, end_pos)

    vim.api.nvim_buf_clear_namespace(buf, ninetyfive_edit_ns, 0, -1)

    local message_lines = vim.fn.split(message, "\n")
    local num_lines = end_line - start_line + 1

    local lines_to_show = math.min(#message_lines, num_lines)

    for i = 1, lines_to_show do
        local line_text = message_lines[i]
        local current_line = start_line + i - 1
        local current_col = 0

        if i == 1 then
            current_col = start_col
        end

        if i == #message_lines and i == lines_to_show and current_line == end_line then
            local end_line_text = vim.api.nvim_buf_get_lines(buf, end_line, end_line + 1, false)[1]
                or ""
            local tail = end_line_text:sub(end_col + 1)
            if tail ~= "" then
                line_text = line_text .. tail
            end
        end

        vim.api.nvim_buf_set_extmark(buf, ninetyfive_edit_ns, current_line, current_col, {
            virt_text = { { line_text, "DiffChange" } },
            virt_text_pos = "overlay",
            hl_mode = "replace",
            ephemeral = false,
        })
    end
end

suggestion.showEditDescription = function(completion)
    if not completion then
        log.debug("suggestion", "no active completion")
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()

    -- Clear previous hints
    vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_hint_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_edit_ns, 0, -1)

    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local col = cursor[2]

    -- Show a hint about the edit
    vim.api.nvim_buf_set_extmark(bufnr, ninetyfive_hint_ns, line, col, {
        right_gravity = true,
        virt_text = { { " ⇘ " .. completion.edit_description, "DiagnosticHint" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
        ephemeral = false,
    })
end

suggestion.show = function(completion)
    -- build text up to the next flush
    local parts = {}
    if type(completion) == "table" then
        for _, item in ipairs(completion) do
            if item.v and item.v ~= vim.NIL then
                table.insert(parts, tostring(item.v))
            end
            if item.flush then
                break
            end
        end
    elseif type(completion) == "string" then
        parts = { completion }
    end

    local text = table.concat(parts)

    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local col = cursor[2]

    local current_line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
    local rest_of_line = current_line_text:sub(col + 1)

    local completion_lines = vim.fn.split(text, "\n", true)

    -- find if any suffix matches the start of rest_of_line
    if #completion_lines > 0 and #rest_of_line > 0 then
        local first_line = completion_lines[1]
        for i = 1, #first_line do
            local suffix = first_line:sub(i)
            if rest_of_line:sub(1, #suffix) == suffix then
                -- keep only the part before the matching suffix
                completion_lines[1] = first_line:sub(1, i - 1)
                break
            end
        end
    end

    -- Clear any existing extmarks in the buffer
    vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_ns, 0, -1)

    -- check if there's anything left to show
    local has_content = false
    for _, l in ipairs(completion_lines) do
        if #l > 0 then
            has_content = true
            break
        end
    end

    if not has_content then
        return
    end

    local virt_lines = {}
    for _, l in ipairs(completion_lines) do
        table.insert(virt_lines, { { l, "Comment" } })
    end
    local first_line = table.remove(virt_lines, 1) or { { "", "Comment" } }

    completion_id = vim.api.nvim_buf_set_extmark(bufnr, ninetyfive_ns, line, col, {
        right_gravity = true,
        virt_text = first_line,
        virt_text_pos = vim.fn.has("nvim-0.10") == 1 and "inline" or "overlay",
        virt_lines = virt_lines,
        hl_mode = "combine",
        ephemeral = false,
    })
end

suggestion.accept_edit = function(current_completion)
    local bufnr = vim.api.nvim_get_current_buf()
    local edit_index = current_completion.edit_index - 1

    if edit_index < 0 then
        return
    end

    local edit = current_completion.edits[edit_index]

    if not edit then
        return
    end

    local start_row, start_col = get_pos_from_index(bufnr, edit.start)
    local end_row, end_col = get_pos_from_index(bufnr, edit["end"])

    vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_hint_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_edit_ns, 0, -1)

    local edit_text = edit.text
    if string.find(edit_text, "\n") then
        local lines = {}
        for s in string.gmatch(edit_text, "[^\n]+") do
            table.insert(lines, s)
        end

        -- TODO does this ever override some text from the last line after the edit???

        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
    else
        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, { edit_text })
    end
end

suggestion.accept = function(current_completion)
    if completion_id == "" then
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local extmark =
        vim.api.nvim_buf_get_extmark_by_id(bufnr, ninetyfive_ns, completion_id, { details = true })

    if extmark and #extmark > 0 then
        local line, col = extmark[1], extmark[2]
        local details = extmark[3]

        local extmark_text = ""

        if details.virt_text then
            for _, part in ipairs(details.virt_text) do
                extmark_text = extmark_text .. part[1]
            end
        end

        if details.virt_lines then
            for _, virt_line in ipairs(details.virt_lines) do
                extmark_text = extmark_text .. "\n"
                for _, part in ipairs(virt_line) do
                    extmark_text = extmark_text .. part[1]
                end
            end
        end

        vim.api.nvim_buf_del_extmark(bufnr, ninetyfive_ns, completion_id)

        local new_line, new_col = line, col

        if string.find(extmark_text, "\n") then
            local lines = vim.split(extmark_text, "\n", { plain = true, trimempty = false })

            if #lines > 0 then
                vim.api.nvim_buf_set_text(bufnr, line, col, line, col, { lines[1] })
                new_col = col + #lines[1]
            end

            if #lines > 1 then
                local new_lines = {}
                for i = 2, #lines do
                    table.insert(new_lines, lines[i])
                end

                vim.api.nvim_buf_set_lines(bufnr, line + 1, line + 1, false, new_lines)
                new_line = line + #lines - 1
                new_col = #lines[#lines]
            end
        else
            -- just insert the text, don't replace anything
            vim.api.nvim_buf_set_text(bufnr, line, col, line, col, { extmark_text })
            new_col = col + #extmark_text
        end

        vim.api.nvim_win_set_cursor(0, { new_line + 1, new_col })

        local current_line_text = vim.api.nvim_buf_get_lines(bufnr, new_line, new_line + 1, false)[1] or ""
        local rest_of_line = current_line_text:sub(new_col + 1)
        local is_mid_line = #vim.trim(rest_of_line) > 0

        if is_mid_line then
            -- defer this reset to the next tick so that TextChangedI doesn't render mid line again...
            -- this works, trust me.
            vim.schedule(function()
                vim.b[bufnr].ninetyfive_accepting = false
            end)
            completion_id = ""
            return
        end

        -- after accept, slice the original array
        local has_remaining = false
        if current_completion and type(current_completion.completion) == "table" then
            local arr = current_completion.completion
            local flush_idx = nil

            for i, item in ipairs(arr) do
                if item.flush == true then
                    flush_idx = i
                    break
                end
            end

            if flush_idx then
                local old_len = #arr
                local new_len = old_len - flush_idx

                for i = 1, new_len do
                    arr[i] = arr[i + flush_idx]
                end

                for i = old_len, new_len + 1, -1 do
                    arr[i] = nil
                end

                if #arr > 0 then
                    has_remaining = true
                end
            else
                for i = #arr, 1, -1 do
                    arr[i] = nil
                end
            end
        end

        if has_remaining then
            vim.defer_fn(function()
                suggestion.show(current_completion.completion)
            end, 10)
        else
            vim.b[bufnr].ninetyfive_accepting = false
            completion_id = ""
        end
    end
end

suggestion.clear = function()
    local buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(buffer, ninetyfive_ns, 0, -1)
end

return suggestion
