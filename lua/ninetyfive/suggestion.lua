local log = require("ninetyfive.util.log")

local suggestion = {}
local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")
local ninetyfive_edit_ns = vim.api.nvim_create_namespace("ninetyfive_edit_ns")
local ninetyfive_hint_ns = vim.api.nvim_create_namespace("ninetyfive_hint_ns")

local completion_id = ""

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
    local end_line, end_col = get_pos_from_index(buf, end_pos)

    -- Clear previous highlights in the namespace
    vim.api.nvim_buf_clear_namespace(buf, ninetyfive_edit_ns, 0, -1)

    -- Then overlay the message text on top of the range
    local message_lines = vim.fn.split(message, "\n")
    local num_lines = end_line - start_line + 1

    -- Handle the case where message has more or fewer lines than the range
    local lines_to_show = math.min(#message_lines, num_lines)

    for i = 1, lines_to_show do
        local line_text = message_lines[i]
        local current_line = start_line + i - 1
        local current_col = 0

        -- For the first line, use start_col
        if i == 1 then
            current_col = start_col
        end

        -- Create an extmark for each line with overlay text
        vim.api.nvim_buf_set_extmark(buf, ninetyfive_edit_ns, current_line, current_col, {
            virt_text = { { line_text, "DiffAdd" } },
            virt_text_pos = "overlay",
            hl_mode = "replace",
            ephemeral = false,
        })
    end
end

suggestion.showDeleteSuggestion = function(start_pos, end_pos, message)
    local buf = vim.api.nvim_get_current_buf()
    local start_line, start_col = get_pos_from_index(buf, start_pos)
    local end_line, end_col = get_pos_from_index(buf, end_pos)

    -- Clear previous highlights in the namespace
    vim.api.nvim_buf_clear_namespace(buf, ninetyfive_edit_ns, 0, -1)

    -- Then overlay the message text on top of the range
    local message_lines = vim.fn.split(message, "\n")
    local num_lines = end_line - start_line + 1

    -- Handle the case where message has more or fewer lines than the range
    local lines_to_show = math.min(#message_lines, num_lines)

    for i = 1, lines_to_show do
        local line_text = message_lines[i]
        local current_line = start_line + i - 1
        local current_col = 0

        -- For the first line, use start_col
        if i == 1 then
            current_col = start_col
        end

        -- For the LAST line, append the tail (if it exists)
        if i == #message_lines and i == lines_to_show and current_line == end_line then
            local end_line_text = vim.api.nvim_buf_get_lines(buf, end_line, end_line + 1, false)[1]
                or ""
            local tail = end_line_text:sub(end_col + 1)
            if tail ~= "" then
                line_text = line_text .. tail -- Append tail to the last error line
            end
        end

        -- Create an extmark for each line with overlay text
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

suggestion.show = function(message)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local col = cursor[2]

    -- Clear any existing extmarks in the buffer
    vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_ns, 0, -1)

    local virt_lines = {}
    for _, l in ipairs(vim.fn.split(message, "\n")) do
        table.insert(virt_lines, { { l, "Comment" } })
    end
    local first_line = table.remove(virt_lines, 1)

    -- Set the ghost text using an extmark
    -- https://neovim.io/doc/user/api.html#nvim_buf_set_extmark()
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

suggestion.accept = function()
    if completion_id == "" then
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    -- Retrieve the extmark and get the suggestion from it
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

        -- Add the rest of the lines from virt_lines
        if details.virt_lines then
            for _, virt_line in ipairs(details.virt_lines) do
                extmark_text = extmark_text .. "\n"
                for _, part in ipairs(virt_line) do
                    extmark_text = extmark_text .. part[1]
                end
            end
        end

        -- Remove the suggestion
        vim.api.nvim_buf_del_extmark(bufnr, ninetyfive_ns, completion_id)

        -- Inserting the completion has to be done line by line
        local new_line, new_col = line, col

        if string.find(extmark_text, "\n") then
            -- Split the ghost text by newlines
            local lines = {}
            for s in string.gmatch(extmark_text, "[^\n]+") do
                table.insert(lines, s)
            end

            -- Insert the first line at the cursor position
            if #lines > 0 then
                vim.api.nvim_buf_set_text(bufnr, line, col, line, col, { lines[1] })
                new_col = col + #lines[1]
            end

            -- Insert the rest of the lines as new lines
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
            -- No newlines, just insert the text
            vim.api.nvim_buf_set_text(bufnr, line, col, line, col, { extmark_text })
            new_col = col + #extmark_text
        end

        -- Move cursor to the end of inserted text
        vim.api.nvim_win_set_cursor(0, { new_line + 1, new_col })

        -- Switch back to insert mode
        vim.cmd("startinsert!")

        completion_id = ""
    end
end

suggestion.clear = function()
    local buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(buffer, ninetyfive_ns, 0, -1)
end

return suggestion
