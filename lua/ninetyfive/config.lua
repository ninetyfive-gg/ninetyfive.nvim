local log = require("ninetyfive.util.log")
local transport = require("ninetyfive.transport")

local Ninetyfive = {}

--- Ninetyfive configuration with its default values.
---
---@type table
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
Ninetyfive.options = {
    -- Prints useful logs about what event are triggered, and reasons actions are executed.
    debug = false,
    -- When `true`, enables the plugin on NeoVim startup
    enable_on_startup = true,
    -- Update server URI, mostly for debugging
    server = "wss://api.ninetyfive.gg",
    mappings = {
        -- When `true`, creates all the mappings set
        enabled = true,
        -- Sets a global mapping to accept a suggestion
        accept = "<Tab>",
        accept_edit = "<C-g>",
        -- Sets a global mapping to reject a suggestion
        reject = "<C-w>",
    },

    indexing = {
        -- Possible values: "ask" | "on" | "off"
        mode = "ask",
        -- Whether to cache the user's answer in /tmp per project
        cache_consent = true,
    },
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

--- Registers the plugin mappings if the option is enabled.
---
---@param options table The mappins provided by the user.
---@param mappings table A key value map of the mapping name and its command.
---
---@private
local function register_mappings(options, mappings)
    if not options.enabled then
        return
    end

    for name, command in pairs(mappings) do
        if not options[name] then
            return
        end

        assert(type(options[name]) == "string", string.format("`%s` must be a string", name))

        local key = options[name]
        local opts = { noremap = true, silent = true }

        -- conditional tab behavior, ensure we don't completely hijack the tab key.
        if name == "accept" then
            opts.expr = true
            vim.keymap.set("i", key, function()
                if transport.has_active and transport.has_active() then
                    return "<Cmd>NinetyFiveAccept<CR>"
                else
                    return vim.fn.pumvisible() == 1 and "<C-n>" or "<Tab>"
                end
            end, opts)
        else
            vim.keymap.set({ "n", "i" }, key, command, opts)
        end
    end
end

--- Define your ninetyfive setup.
---
---@param options table Module config table. See |Ninetyfive.options|.
---
---@usage `require("ninetyfive").setup()` (add `{}` with your |Ninetyfive.options| table)
function Ninetyfive.setup(options)
    Ninetyfive.options = Ninetyfive.defaults(options or {})

    log.warn_deprecation(Ninetyfive.options)

    register_mappings(Ninetyfive.options.mappings, {
        accept = "<Cmd>NinetyFiveAccept<CR>",
        accept_edit = "<Cmd>NinetyFiveAcceptEdit<CR>",
        reject = "<Cmd>NinetyFiveReject<CR>",
    })

    return Ninetyfive.options
end

return Ninetyfive
