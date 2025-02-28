local main = require("ninetyfive.main")
local config = require("ninetyfive.config")
local log = require("ninetyfive.util.log")

local Ninetyfive = {}

local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")

local function set_ghost_text(bufnr, line, col)
    -- Clear any existing extmarks in the buffer
    vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_ns, 0, -1)
  
    -- Set the ghost text using an extmark
    -- https://neovim.io/doc/user/api.html#nvim_buf_set_extmark()
    vim.api.nvim_buf_set_extmark(bufnr, ninetyfive_ns, line, col, {
      virt_text = {{"hello world", "Comment"}}, -- "Comment" is the highlight group
      virt_text_pos = "eol", -- Display the text at the end of the line
      hl_mode = "combine", -- Combine with existing highlights
    })
  end
  
  -- Function to set up autocommands
  local function setup_autocommands()
    log.debug("some.scope", "set_autocommands")
    vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
      pattern = "*",
      callback = function(args)
        local bufnr = args.buf
        local cursor = vim.api.nvim_win_get_cursor(0)
        local line = cursor[1] - 1 -- Lua uses 0-based indexing for lines
        local col = cursor[2] -- Column is 0-based
  
        -- Set the ghost text at the current cursor position
        set_ghost_text(bufnr, line, col)
      end,
    })
  end

--- Toggle the plugin by calling the `enable`/`disable` methods respectively.
function Ninetyfive.toggle()
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    main.toggle("public_api_toggle")
end

--- Initializes the plugin, sets event listeners and internal state.
function Ninetyfive.enable(scope)
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    main.toggle(scope or "public_api_enable")
end

--- Disables the plugin, clear highlight groups and autocmds, closes side buffers and resets the internal state.
function Ninetyfive.disable()
    main.toggle("public_api_disable")
end

-- setup Ninetyfive options and merge them with user provided ones.
function Ninetyfive.setup(opts)
    _G.Ninetyfive.config = config.setup(opts)
end

--- sets Ninetyfive with the provided API Key
---
---@param apiKey: the api key you want to use.
function Ninetyfive.setApiKey(apiKey)
    log.debug("some.scope", "Set api key called!!!!")
    setup_autocommands()
end

_G.Ninetyfive = Ninetyfive

return _G.Ninetyfive
