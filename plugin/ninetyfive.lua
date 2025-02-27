-- You can use this loaded variable to enable conditional parts of your plugin.
if _G.NinetyfiveLoaded then
    return
end

_G.NinetyfiveLoaded = true

-- Useful if you want your plugin to be compatible with older (<0.7) neovim versions
if vim.fn.has("nvim-0.7") == 0 then
    vim.cmd("command! Ninetyfive lua require('ninetyfive').toggle()")
else
    vim.api.nvim_create_user_command("Ninetyfive", function()
        require("ninetyfive").toggle()
    end, {})
end
