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
    end, { desc = "Toggles the plugin." })

    vim.api.nvim_create_user_command("NinetyfiveAccept", function()
        require("ninetyfive").accept()
    end, { desc = "Accepts a suggestion." })

    vim.api.nvim_create_user_command("NinetyfiveAcceptEdit", function()
        require("ninetyfive").accept_edit()
    end, { desc = "Accepts an edit." })

    vim.api.nvim_create_user_command("NinetyfiveReject", function()
        require("ninetyfive").reject()
    end, { desc = "Rejects a suggestion." })

    vim.api.nvim_create_user_command("NinetyfiveKey", function()
        local api_key = vim.fn.input("Enter API Key: ")
        if api_key and api_key ~= "" then
            require("ninetyfive").setApiKey(api_key)
            vim.notify("API key has been set", vim.log.levels.INFO)
        else
            vim.notify("API key not set (empty input)", vim.log.levels.WARN)
        end
    end, { desc = "Sets the API Key." })
end
