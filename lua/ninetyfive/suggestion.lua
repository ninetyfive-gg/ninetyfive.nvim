local suggestion = {}
local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")
local Completion = require("ninetyfive.completion")

local completion_id = ""
local completion_bufnr = nil

local log = require("ninetyfive.util.log")

suggestion.show = function(completion)
    -- build text up to the next flush
    local parts = {}
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
    ) -- :h api-extended-marks
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

local function consumeChars(array, count)
    local remaining = count

    while remaining > 0 and #array > 0 do
        local chunk = table.remove(array, 1)

        if chunk == vim.NIL then
            -- Continue to next iteration, nil is already removed
        elseif #chunk <= remaining then
            -- Consume the entire chunk
            remaining = remaining - #chunk
        else
            -- Consume part of the chunk and put the rest back
            table.insert(array, 1, string.sub(chunk, remaining + 1))
            remaining = 0
        end
    end

    -- Remove any leading nils to expose the next chunk
    while #array > 0 and array[1] == nil do
        table.remove(array, 1)
    end

    return array
end

suggestion.accept = function()
    local current_completion = Completion.get()
    if
        current_completion ~= nil
        and #current_completion.completion > 0
        and current_completion.buffer == vim.api.nvim_get_current_buf()
    then
        if completion_id == "" then
            return
        end

        local bufnr = vim.api.nvim_get_current_buf()
        vim.b[bufnr].ninetyfive_accepting = true
        -- Retrieve the extmark and get the suggestion from it
        local extmark =
            vim.api.nvim_buf_get_extmark_by_id(bufnr, ninetyfive_ns, 1, { details = true })

        local completion_text = ""
        for i = 1, #current_completion.completion do
            local item = current_completion.completion[i]
            if item == vim.NIL then -- Stop at first nil
                break
            end
            completion_text = completion_text .. tostring(item)
        end

        current_completion.last_accepted = completion_text

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
            vim.api.nvim_buf_del_extmark(bufnr, ninetyfive_ns, 1)

            local new_line, new_col = line, col

            if string.find(extmark_text, "\n") then
                local lines = vim.split(extmark_text, "\n", { plain = true, trimempty = false })

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
                local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
                local virt_width = 0
                if details.virt_text then
                    for _, part in ipairs(details.virt_text) do
                        virt_width = virt_width + vim.fn.strdisplaywidth(part[1])
                    end
                end

                local end_col = math.min(#line_text, col + virt_width)

                vim.api.nvim_buf_set_text(bufnr, line, col, line, end_col, { extmark_text })
                new_col = col + #extmark_text
            end

            vim.api.nvim_win_set_cursor(0, { new_line + 1, new_col })

            -- count how many we accept
            local count = 0
            if type(current_completion.completion) == "table" then
                for i = 1, #current_completion.completion do
                    local item = current_completion.completion[i]
                    if item == vim.NIL then
                        count = count + 1 -- we want to consume the nil
                        break
                    end
                    count = count + #item
                end
            end

            local updated_completion = consumeChars(current_completion.completion, count)

            local c = Completion.get()
            c.completion = updated_completion
            if #updated_completion > 0 then
                table.insert(updated_completion, 1, "\n") -- idk if this is the right place...
                vim.b[bufnr].ninetyfive_accepting = true
                suggestion.show(updated_completion)
            else
                vim.b[bufnr].ninetyfive_accepting = false
                completion_id = ""
                completion_bufnr = nil
            end
        end
    end
end

suggestion.clear = function()
    local buffer = vim.api.nvim_get_current_buf()
    print("clear " .. buffer)
    if buffer ~= nil and vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_del_extmark(buffer, ninetyfive_ns, 1)
    end
    completion_id = ""
    completion_bufnr = nil
end

return suggestion
