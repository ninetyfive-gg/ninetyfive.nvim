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
      virt_text_pos = "overlay", -- Display the text at the end of the line
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

    -- Store the job ID for the websocket connection
    if _G.Ninetyfive.websocket_job then
        -- Kill existing connection if there is one
        vim.fn.jobstop(_G.Ninetyfive.websocket_job)
        _G.Ninetyfive.websocket_job = nil
    end

    -- Path to the websocat binary (relative to the plugin directory)
    local websocat_path = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand('<sfile>:p')), ':h:h:h') .. '/websocat.x86_64-unknown-linux-musl'
    
    -- Make sure the binary is executable
    vim.fn.system('chmod +x ' .. vim.fn.shellescape(websocat_path))
    
    -- Create a buffer for websocket messages if it doesn't exist
    if not _G.Ninetyfive.websocket_buffer or not vim.api.nvim_buf_is_valid(_G.Ninetyfive.websocket_buffer) then
        _G.Ninetyfive.websocket_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(_G.Ninetyfive.websocket_buffer, "NinetyfiveWebsocket")
    end
    
    -- Clear the buffer
    vim.api.nvim_buf_set_lines(_G.Ninetyfive.websocket_buffer, 0, -1, false, {})
    
    -- Add header to the buffer
    vim.api.nvim_buf_set_lines(_G.Ninetyfive.websocket_buffer, 0, -1, false, {
        "Ninetyfive Websocket Connection",
        "Connected to: wss://api.ninetyfive.gg",
        "-------------------------------------------",
        ""
    })
    
    -- Function to append messages to the buffer
    local function append_to_buffer(message)
        local lines = {}
        for line in message:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end
        
        local line_count = vim.api.nvim_buf_line_count(_G.Ninetyfive.websocket_buffer)
        vim.api.nvim_buf_set_lines(_G.Ninetyfive.websocket_buffer, line_count, line_count, false, lines)
        
        -- Log the message as well
        log.debug("websocket", message)
    end
    
    -- Start the websocat process
    _G.Ninetyfive.websocket_job = vim.fn.jobstart({
        websocat_path,
        "wss://api.ninetyfive.gg"
    }, {
        on_stdout = function(_, data, _)
            if data and #data > 0 then
                local message = table.concat(data, "\n")
                if message ~= "" then
                    append_to_buffer("Received: " .. message)
                end
            end
        end,
        on_stderr = function(_, data, _)
            if data and #data > 0 then
                local message = table.concat(data, "\n")
                if message ~= "" then
                    append_to_buffer("Error: " .. message)
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            append_to_buffer("Websocket connection closed with exit code: " .. exit_code)
        end,
        stdout_buffered = false,
        stderr_buffered = false
    })
    
    if _G.Ninetyfive.websocket_job <= 0 then
        log.error("websocket", "Failed to start websocat process")
        return
    end
    
    log.debug("websocket", "Started websocat process with job ID: " .. _G.Ninetyfive.websocket_job)
    
    -- Add command to show the websocket buffer
    vim.api.nvim_create_user_command("NinetyfiveWebsocket", function()
        -- Check if buffer exists and is valid
        if _G.Ninetyfive.websocket_buffer and vim.api.nvim_buf_is_valid(_G.Ninetyfive.websocket_buffer) then
            -- Get current window
            local win = vim.api.nvim_get_current_win()
            -- Set the buffer in the current window
            vim.api.nvim_win_set_buf(win, _G.Ninetyfive.websocket_buffer)
        else
            vim.notify("Websocket buffer not available", vim.log.levels.ERROR)
        end
    end, {})
    
    vim.notify("Ninetyfive websocket connection established. Use :NinetyfiveWebsocket to view messages.", vim.log.levels.INFO)
end

_G.Ninetyfive = Ninetyfive

return _G.Ninetyfive
