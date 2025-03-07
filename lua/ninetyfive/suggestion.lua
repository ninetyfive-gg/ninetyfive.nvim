local suggestion = {}
local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")

local completion_id = ""

suggestion.show = function(message)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local col = cursor[2]

    -- Clear any existing extmarks in the buffer
    vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_ns, 0, -1)

    local virt_lines = {}
    print("[suggestion.show] message:", message)
    for _, l in ipairs(vim.fn.split(message, "\n")) do
        table.insert(virt_lines, { { l, "Comment" } })
    end
    local first_line = table.remove(virt_lines, 1)

    -- Set the ghost text using an extmark
    -- https://neovim.io/doc/user/api.html#nvim_buf_set_extmark()
    completion_id = vim.api.nvim_buf_set_extmark(bufnr, ninetyfive_ns, line, col, {
        right_gravity = true,
        virt_text = first_line,
        virt_text_pos = "inline",
        virt_lines = virt_lines,
        hl_mode = "combine",
        ephemeral = false,
    })
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

        print("accepted completion", extmark_text)

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
        if string.find(extmark_text, "\n") then
            -- Split the ghost text by newlines
            local lines = {}
            for s in string.gmatch(extmark_text, "[^\n]+") do
                table.insert(lines, s)
            end

            -- Insert the first line at the cursor position
            if #lines > 0 then
                vim.api.nvim_buf_set_text(bufnr, line, col, line, col, { lines[1] })
            end

            -- Insert the rest of the lines as new lines
            if #lines > 1 then
                local new_lines = {}
                for i = 2, #lines do
                    table.insert(new_lines, lines[i])
                end
                vim.api.nvim_buf_set_lines(bufnr, line + 1, line + 1, false, new_lines)
            end
        else
            -- No newlines, just insert the text
            vim.api.nvim_buf_set_text(bufnr, line, col, line, col, { extmark_text })
        end

        completion_id = ""
    end
end

suggestion.clear = function()
    local buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(buffer, ninetyfive_ns, 0, -1)
end

return suggestion
