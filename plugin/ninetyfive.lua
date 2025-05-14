local uv = vim.uv or vim.loop
local os_uname = uv.os_uname().sysname

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

    vim.api.nvim_create_user_command("NinetyfivePurchase", function()
        local url = "https://ninetyfive.gg/api/payment"
        local cmd
        if os_uname == "Linux" then
            local candidates = { "xdg-open", "gvfs-open", "gnome-open", "wslview" }
            for _, candidate_cmd in ipairs(candidates) do
                if vim.fn.executable(candidate_cmd) == 1 then
                    cmd = candidate_cmd
                    break
                end
            end
        elseif vim.loop.os_uname().sysname == "Darwin" then
            cmd = "open"
        elseif vim.loop.os_uname().sysname == "Windows" then
            cmd = "start"
        end

        if cmd then
            vim.fn.jobstart({ cmd, url }, { detach = true })
        else
            vim.notify(
                "Make sure one of these tools is installed xdg-open, gvfs-open, gnome-open, wslview, open (MacOS) or start (Windows)",
                vim.log.levels.WARN
            )
        end
    end, { desc = "Open the purchase site on your browser" })
end
