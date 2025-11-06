-- List of buffers that we don't want to show suggestions in as it may break
-- or make it weird
local ignored_filetypes = {
    "oil", -- https://github.com/stevearc/oil.nvim
    "fff_input", -- https://github.com/dmtrKovalenko/fff.nvim
    "grug-far", -- https://github.com/MagicDuck/grug-far.nvim
    "TelescopePrompt", -- https://github.com/nvim-telescope/telescope.nvim
    "DressingInput", -- https://github.com/stevearc/dressing.nvim
    "snacks_input", -- https://github.com/folke/snacks.nvim
}

return ignored_filetypes
