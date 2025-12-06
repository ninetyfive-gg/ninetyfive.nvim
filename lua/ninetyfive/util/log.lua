local log = {}

local longest_scope = 15

--- prints only if debug is true.
---
---@param scope string: the scope from where this function is called.
---@param str string: the formatted string.
---@param ... any: the arguments of the formatted string.
---@private
function log.debug(scope, str, ...)
    return log.notify(scope, vim.log.levels.DEBUG, false, str, ...)
end

--- prints only if debug is true.
---
---@param scope string: the scope from where this function is called.
---@param level string: the log level of vim.notify.
---@param verbose boolean: when false, only prints when config.debug is true.
---@param str string: the formatted string.
---@param ... any: the arguments of the formatted string.
---@private
function log.notify(scope, level, verbose, str, ...)
    if not verbose and _G.Ninetyfive.config ~= nil and not _G.Ninetyfive.config.debug then
        return
    end

    if string.len(scope) > longest_scope then
        longest_scope = string.len(scope)
    end

    for i = longest_scope, string.len(scope), -1 do
        if i < string.len(scope) then
            scope = string.format("%s ", scope)
        else
            scope = string.format("%s", scope)
        end
    end

    local formatted_message
    local has_args = select(1, ...) ~= nil

    if has_args and string.find(str, "%%") then
        -- If str contains format specifiers and we have args, use string.format
        formatted_message = string.format(str, ...)
    elseif has_args then
        -- If str doesn't have format specifiers but we have args, concatenate them
        formatted_message = str

        -- Convert each argument to string and concatenate
        local args = { ... }
        for i, arg in ipairs(args) do
            if type(arg) == "table" then
                formatted_message = formatted_message .. " " .. vim.inspect(arg)
            else
                formatted_message = formatted_message .. " " .. tostring(arg)
            end
        end
    else
        -- If no args, just use str as is
        formatted_message = str
    end

    vim.schedule(function()
        vim.notify(
            string.format("[ninetyfive.nvim@%s] %s", scope, formatted_message),
            level,
            { title = "ninetyfive.nvim" }
        )
    end)
end

--- analyzes the user provided `setup` parameters and sends a message if they use a deprecated option, then gives the new option to use.
---
---@param options table: the options provided by the user.
---@private
function log.warn_deprecation(options)
    local uses_deprecated_option = false
    local notice = "is now deprecated, use `%s` instead."
    local root_deprecated = {
        foo = "bar",
        bar = "baz",
    }

    for name, warning in pairs(root_deprecated) do
        if options[name] ~= nil then
            uses_deprecated_option = true
            log.notify(
                "deprecated_options",
                vim.log.levels.WARN,
                true,
                string.format("`%s` %s", name, string.format(notice, warning))
            )
        end
    end

    if uses_deprecated_option then
        log.notify(
            "deprecated_options",
            vim.log.levels.WARN,
            true,
            "sorry to bother you with the breaking changes :("
        )
        log.notify(
            "deprecated_options",
            vim.log.levels.WARN,
            true,
            "use `:h Ninetyfive.options` to read more."
        )
    end
end

return log
