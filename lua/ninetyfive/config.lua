local log = require("ninetyfive.util.log")

local Ninetyfive = {}

--- Ninetyfive configuration with its default values.
---
---@type table
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
Ninetyfive.options = {
    -- Prints useful logs about what event are triggered, and reasons actions are executed.
    debug = false,
}

---@private
local defaults = vim.deepcopy(Ninetyfive.options)

--- Defaults Ninetyfive options by merging user provided options with the default plugin values.
---
---@param options table Module config table. See |Ninetyfive.options|.
---
---@private
function Ninetyfive.defaults(options)
    Ninetyfive.options = vim.deepcopy(vim.tbl_deep_extend("keep", options or {}, defaults or {}))

    -- let your user know that they provided a wrong value, this is reported when your plugin is executed.
    assert(
        type(Ninetyfive.options.debug) == "boolean",
        "`debug` must be a boolean (`true` or `false`)."
    )

    return Ninetyfive.options
end

--- Define your ninetyfive setup.
---
---@param options table Module config table. See |Ninetyfive.options|.
---
---@usage `require("ninetyfive").setup()` (add `{}` with your |Ninetyfive.options| table)
function Ninetyfive.setup(options)
    Ninetyfive.options = Ninetyfive.defaults(options or {})

    log.warn_deprecation(Ninetyfive.options)

    return Ninetyfive.options
end

return Ninetyfive
