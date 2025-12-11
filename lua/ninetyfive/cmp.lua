local log = require("ninetyfive.util.log")
local Completion = require("ninetyfive.completion")
local util = require("ninetyfive.util")

vim.g.ninetyfive_cmp_enabled = true

local Source = {}
Source.__index = Source

local function label_text(text)
    if not text or text == "" then
        return ""
    end

    text = text:gsub("^%s*", "")

    if #text <= 40 then
        return text
    end

    local short_prefix = string.sub(text, 1, 20)
    local short_suffix = string.sub(text, #text - 15, #text)
    return string.format("%s ... %s", short_prefix, short_suffix)
end

local function completion_result(items, is_incomplete)
    return {
        items = items or {},
        isIncomplete = is_incomplete or false,
    }
end

local function completion_text(chunks)
    if type(chunks) ~= "table" then
        return ""
    end

    local parts = {}
    for i = 1, #chunks do
        local item = chunks[i]
        if item == vim.NIL then
            break
        end
        parts[#parts + 1] = tostring(item)
    end

    return table.concat(parts)
end

function Source.new(opts)
    local self = setmetatable({}, Source)
    self.opts = opts or {}
    return self
end

function Source:get_trigger_characters()
    return { "*" }
end

function Source:get_keyword_pattern()
    return "."
end

function Source:is_available()
    return vim ~= nil and vim.fn ~= nil and vim.g.ninetyfive_cmp_enabled ~= false
end

function Source:_prepare_context(params)
    params = params or {}
    local bufnr = params.context and params.context.bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_line = cursor[1] - 1
    local cursor_col = cursor[2]
    local line_text = vim.api.nvim_buf_get_lines(bufnr, cursor_line, cursor_line + 1, false)[1]
        or ""
    local before_cursor = line_text:sub(1, cursor_col)
    local cursor_prefix = util.get_cursor_prefix(bufnr, cursor)

    return {
        bufnr = bufnr,
        cursor_line = cursor_line,
        cursor_col = cursor_col,
        cursor_prefix = cursor_prefix,
        line_text = line_text,
        before_cursor = before_cursor,
        filetype = vim.bo[bufnr].filetype,
    }
end

function Source:_build_items(context, text)
    text = text or context.result_text or ""
    if text == "" then
        return {}
    end

    local has_newline = text:find("\n", 1, true) ~= nil
    local first_line = text:match("([^\n]*)") or text
    local lsp_util = vim.lsp.util
    local encoding = "utf-8"
    local ok_start, start_character = pcall(
        lsp_util.character_offset,
        context.bufnr,
        context.cursor_line,
        context.cursor_col,
        encoding
    )
    if not ok_start then
        log.debug("cmp", "failed to compute start character offset: %s", tostring(start_character))
        return {}
    end

    local end_character = start_character
    if not has_newline then
        local ok_end, computed = pcall(
            lsp_util.character_offset,
            context.bufnr,
            context.cursor_line,
            #context.line_text,
            encoding
        )
        if not ok_end then
            log.debug("cmp", "failed to compute end character offset: %s", tostring(computed))
            return {}
        end
        end_character = computed
    end

    local range = {
        start = { line = context.cursor_line, character = start_character },
        ["end"] = { line = context.cursor_line, character = end_character },
    }

    local documentation =
        string.format("```%s\n%s\n```", context.filetype or "", context.before_cursor .. text)

    local item = {
        label = label_text(first_line),
        kind = 1,
        score = 100,
        insertTextFormat = has_newline and 2 or 1,
        textEdit = {
            newText = text,
            insert = range,
            replace = range,
        },
        documentation = {
            kind = "markdown",
            value = documentation,
        },
        dup = 0,
    }

    return { item }
end

function Source:_matching_completion(context)
    local completion = Completion.get()
    if not completion then
        return nil
    end

    if completion.buffer and completion.buffer ~= context.bufnr then
        return nil
    end

    if completion.prefix and context.cursor_prefix and completion.prefix ~= context.cursor_prefix then
        return nil
    end

    return completion
end

function Source:complete(params, callback)
    if not self:is_available() then
        callback(completion_result({}, false))
        return
    end

    self:abort()
    local context = self:_prepare_context(params)
    if not context then
        callback(completion_result({}, false))
        return
    end

    local completion = self:_matching_completion(context)
    if not completion then
        callback(completion_result({}, false))
        return
    end

    local text = completion_text(completion.completion)
    if text == "" then
        callback(completion_result({}, false))
        return
    end

    context.result_text = text
    callback(completion_result(self:_build_items(context, text), false))
end

function Source:abort()
end

function Source:resolve(completion_item, callback)
    callback(completion_item)
end

function Source:execute(completion_item, callback)
    callback(completion_item)
end

return Source
