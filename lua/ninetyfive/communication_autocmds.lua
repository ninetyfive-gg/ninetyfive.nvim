local log = require("ninetyfive.util.log")
local state = require("ninetyfive.state")
local ignored_filetypes = require("ninetyfive.ignored_filetypes")
local suggestion = require("ninetyfive.suggestion")
local Completion = require("ninetyfive.completion")
local Communication = require("ninetyfive.communication")
local util = require("ninetyfive.util")

local CommunicationAutocmds = {}
CommunicationAutocmds.__index = CommunicationAutocmds

local function should_ignore_buffer(bufnr)
    local filetype = vim.bo[bufnr].filetype
    if vim.tbl_contains(ignored_filetypes, filetype) then
        return true
    end

    if not state:get_enabled() then
        return true
    end

    return false
end

local function completion_as_text(chunks)
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

local function trim_completion_chunks(chunks, remove_count)
    log.debug("autocmds", "trim_completion_chunks: remove_count=%d, chunks=%d", remove_count, #chunks)
    log.debug("autocmds", "trim_completion_chunks: before=%q", completion_as_text(chunks))

    local remaining = remove_count
    local trimmed = {}

    for idx, segment in ipairs(chunks) do
        if segment == vim.NIL then
            for rest = idx, #chunks do
                trimmed[#trimmed + 1] = chunks[rest]
            end
            break
        end

        if remaining >= #segment then
            remaining = remaining - #segment
        else
            local leftover = segment:sub(remaining + 1)
            trimmed[#trimmed + 1] = leftover
            remaining = 0
            for rest = idx + 1, #chunks do
                trimmed[#trimmed + 1] = chunks[rest]
            end
            break
        end
    end

    log.debug("autocmds", "trim_completion_chunks: after=%q", completion_as_text(trimmed))
    return trimmed
end

local function handle_existing_completion(current_prefix)
    local current_completion = Completion.get()
    if
        not current_completion
        or not current_completion.prefix
        or not current_completion.completion
    then
        return false
    end

    local inserted_text = current_prefix:sub(#current_completion.prefix + 1)
    if inserted_text == "" then
        return false
    end

    local completion_text = completion_as_text(current_completion.completion)

    log.debug("autocmds", "handle_existing_completion:")
    log.debug("autocmds", "  current_prefix=%q", current_prefix)
    log.debug("autocmds", "  stored_prefix=%q", current_completion.prefix)
    log.debug("autocmds", "  inserted_text=%q", inserted_text)
    log.debug("autocmds", "  completion_text=%q", completion_text)

    if completion_text:sub(1, #inserted_text) == inserted_text then
        log.debug("autocmds", "  -> prefix match, trimming %d chars", #inserted_text)
        local new_completion = trim_completion_chunks(current_completion.completion, #inserted_text)
        current_completion.completion = new_completion
        current_completion.prefix = current_prefix
        suggestion.clear()
        suggestion.show(new_completion)
        return true
    end

    -- What was previously accepted
    if inserted_text == current_completion.last_accepted then
        log.debug("autocmds", "  -> matches last_accepted")
        current_completion.prefix = current_completion.prefix .. current_completion.last_accepted
        current_completion.last_accepted = ""
        return true
    end

    log.debug("autocmds", "  -> no match")
    return false
end

function CommunicationAutocmds.new(opts)
    opts = opts or {}
    local communication
    if opts.communication then
        communication = opts.communication
    else
        communication = Communication.new(opts.communication_opts or {})
    end

    local instance = setmetatable({
        communication = communication,
        group_name = opts.group_name or "Ninetyfive",
        group_id = nil,
    }, CommunicationAutocmds)

    return instance
end

function CommunicationAutocmds:clear()
    if self.group_id then
        pcall(vim.api.nvim_del_augroup_by_id, self.group_id)
        self.group_id = nil
    end
end

function CommunicationAutocmds:setup_autocommands()
    self:clear()

    self.group_id = vim.api.nvim_create_augroup(self.group_name, { clear = true })
    local group = self.group_id

    vim.api.nvim_create_autocmd({ "CursorMovedI" }, {
        pattern = "*",
        group = group,
        callback = function(args)
            local bufnr = args.buf
            if vim.b[bufnr].ninetyfive_accepting then
                return
            end

            if should_ignore_buffer(bufnr) then
                return
            end

            local cursor = vim.api.nvim_win_get_cursor(0)
            local current_prefix = util.get_cursor_prefix(bufnr, cursor)

            -- Check if cursor moved but completion is still valid (user typed matching chars)
            if handle_existing_completion(current_prefix) then
                return
            end

            Completion.clear()
            suggestion.clear()

            -- Request new completion at cursor position
            vim.schedule(function()
                local ok, err = self.communication:request_completion({
                    bufnr = bufnr,
                    buf = bufnr,
                    cursor = cursor,
                })
                if not ok and err then
                    log.debug("autocmds", "request_completion failed: %s", tostring(err))
                end
            end)
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChangedI" }, {
        pattern = "*",
        group = group,
        callback = function(args)
            local bufnr = args.buf
            if should_ignore_buffer(bufnr) then
                return
            end

            -- if vim.b[bufnr].ninetyfive_accepting then
            --     return
            -- end

            local cursor = vim.api.nvim_win_get_cursor(0)
            local current_prefix = util.get_cursor_prefix(bufnr, cursor)

            if handle_existing_completion(current_prefix) then
                return
            end

            suggestion.clear()
            Completion.clear()

            vim.schedule(function()
                local ok, err = self.communication:request_completion({
                    bufnr = bufnr,
                    buf = bufnr,
                    cursor = cursor,
                })
                if not ok and err then
                    log.debug("autocmds", "request_completion failed: %s", tostring(err))
                end
            end)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
        pattern = "*",
        group = group,
        callback = function(args)
            local bufnr = args.buf
            if should_ignore_buffer(bufnr) then
                return
            end

            if self.communication:is_websocket() then
                self.communication:set_workspace({ bufnr = bufnr })
                self.communication:send_file_content({ bufnr = bufnr })
            end
        end,
    })

    vim.api.nvim_create_autocmd("InsertLeave", {
        group = group,
        callback = function(args)
            suggestion.clear()
            Completion.clear()
            vim.b[args.buf].ninetyfive_accepting = false
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            self.communication:shutdown()
        end,
        desc = "[ninetyfive] Close Ninetyfive connection on exit",
    })
end

return CommunicationAutocmds
