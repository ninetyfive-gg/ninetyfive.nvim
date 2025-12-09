local log = require("ninetyfive.util.log")
local state = require("ninetyfive.state")
local ignored_filetypes = require("ninetyfive.ignored_filetypes")
local suggestion = require("ninetyfive.suggestion")
local Completion = require("ninetyfive.completion")
local Communication = require("ninetyfive.communication")
local util = require("ninetyfive.util")

local CommunicationAutocmds = {}
CommunicationAutocmds.__index = CommunicationAutocmds

local function print_table(completion)
    for i = 1, #completion do
        local item = completion[i]
        if item == vim.NIL then -- Stop at first nil
            break
        end
    end
    return
end

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

local function consume_chars(array, count)
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

function CommunicationAutocmds:reconcile(args, event)
    local bufnr = args.buf
    if should_ignore_buffer(bufnr) then
        return
    end

    local completion = Completion.get()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_prefix = util.get_cursor_prefix(bufnr, cursor)
    local is_accepting = vim.b[bufnr].ninetyfive_accepting == true
    local event_is_move = event == "move"
    local event_is_edit = event == "edit"

    local function completion_ready()
        return completion and completion.prefix and completion.completion
    end

    local should_request_completion = not completion_ready()

    local function clear_completion_state()
        suggestion.clear()
        Completion.clear()
        completion = nil
        should_request_completion = true
    end

    local function consume_current_completion(opts)
        if not completion or not completion.prefix or not completion.completion then
            return false
        end

        if #current_prefix < #completion.prefix then
            clear_completion_state()
            return false
        end

        local inserted_text = current_prefix:sub(#completion.prefix + 1)
        if inserted_text == "" then
            return false
        end

        local completion_text = completion_as_text(completion.completion)
        if completion_text:sub(1, #inserted_text) ~= inserted_text then
            if opts and opts.clear_on_mismatch then
                clear_completion_state()
            end
            return false
        end

        local accepted_length = #inserted_text
        local consumed_entire_completion = accepted_length >= #completion_text
        local new_completion

        if opts and opts.strategy == "trim" then
            new_completion = trim_completion_chunks(completion.completion, accepted_length)
        else
            local consume_count = accepted_length
            if opts and opts.consume_extra_when_complete and consumed_entire_completion then
                consume_count = consume_count + 1
            end

            new_completion = consume_chars(completion.completion, consume_count)
            if opts and opts.append_newline_when_complete and #new_completion > 0 and consumed_entire_completion then
                table.insert(new_completion, 1, "\n")
            end
        end

        completion.completion = new_completion
        completion.prefix = current_prefix
        completion.last_accepted = ""
        suggestion.clear()
        local has_remaining = #new_completion > 0
        if has_remaining then
            suggestion.show(new_completion)
        else
            clear_completion_state()
        end

        return true, has_remaining
    end

    if is_accepting and event_is_move then
        should_request_completion = not completion_ready() or #completion.completion == 0
        vim.b[bufnr].ninetyfive_accepting = false
    elseif is_accepting and event_is_edit then
        local consumed, has_remaining = consume_current_completion({ strategy = "trim", clear_on_mismatch = true })
        if consumed then
            should_request_completion = not has_remaining
        end
    elseif (event_is_edit or event_is_move) and completion_ready() then
        local consumed, has_remaining = consume_current_completion({
            consume_extra_when_complete = true,
            append_newline_when_complete = true,
            clear_on_mismatch = true,
        })
        if consumed then
            should_request_completion = not has_remaining
        end
    end

    if event_is_move then
        vim.b[bufnr].ninetyfive_accepting = false
    end

    if should_request_completion then
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
            self:reconcile(args, "move")
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChangedI" }, {
        pattern = "*",
        group = group,
        callback = function(args)
            self:reconcile(args, "edit")
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

            vim.b[bufnr].ninetyfive_accepting = false

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
