local lualine_require = require("lualine_require")
local M = lualine_require.require("lualine.component"):extend()
local highlight = require("lualine.highlight")

local default_options = {
    short = false,
    show_colors = true,
    colors = {
        disconnected = "#e06c75",
        unpaid = "#e5c07b",
    },
}

function M:init(options)
    M.super.init(self, options)
    self.options = vim.tbl_deep_extend("force", default_options, self.options or {})

    if self.options.show_colors then
        self.highlight_groups = {
            disconnected = highlight.create_component_highlight_group(
                { bg = self.options.colors.disconnected, fg = "#ffffff" },
                "disconnected",
                self.options
            ),
            unpaid = highlight.create_component_highlight_group(
                { bg = self.options.colors.unpaid, fg = "#ffffff" },
                "unpaid",
                self.options
            ),
        }
    end
end

function M:update_status()
    local ok, websocket = pcall(require, "ninetyfive.websocket")
    if not ok then
        return ""
    end

    local connected = websocket.is_connected()
    local sub_info = websocket.get_subscription_info()

    local status_text
    local hl_group

    if not connected then
        status_text = self.options.short and "95" or "NinetyFive Disconnected"
        hl_group = self.highlight_groups and self.highlight_groups.disconnected
    elseif sub_info and sub_info.name then
        status_text = self.options.short and "95" or sub_info.name
        if not sub_info.is_paid then
            hl_group = self.highlight_groups and self.highlight_groups.unpaid
        end
    else
        status_text = self.options.short and "95" or "NinetyFive"
        hl_group = self.highlight_groups and self.highlight_groups.unpaid
    end

    if hl_group then
        return highlight.component_format_highlight(hl_group) .. status_text
    end
    return status_text
end

return M
