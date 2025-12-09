local util = {}

function util.get_cursor_prefix(bufnr, cursor)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return ""
    end

    local prefix = vim.api.nvim_buf_get_text(bufnr, 0, 0, cursor[1] - 1, cursor[2], {})
    local text = table.concat(prefix, "\n")
    return text
end

return util
