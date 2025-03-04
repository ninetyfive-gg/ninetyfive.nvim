local main = require("ninetyfive.main")
local config = require("ninetyfive.config")
local log = require("ninetyfive.util.log")
local state = require("ninetyfive.state")

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
  
  -- Function to send a message to the websocket
  local function send_websocket_message(message)
    -- Check if the global table exists
    if not _G.Ninetyfive then
      log.debug("websocket", "Global Ninetyfive table not initialized")
      return false
    end
    
    -- Check if websocket job exists and is valid
    if not (_G.Ninetyfive.websocket_job and _G.Ninetyfive.websocket_job > 0) then
      log.debug("websocket", "Websocket connection not established")
      return false
    end
    
    -- Use pcall to safely attempt to send the message
    local ok, result = pcall(function()
      return vim.fn.chansend(_G.Ninetyfive.websocket_job, message .. "\n")
    end)
    
    -- Handle any errors that occurred
    if not ok then
      log.debug("websocket", "Error sending message: " .. tostring(result))
      return false
    end
    
    -- Check if the send was successful
    if result == 0 then
      log.debug("websocket", "Failed to send message to websocket")
      return false
    end
    
    -- Log success
    log.debug("websocket", "Sent message to websocket: " .. message)
    
    -- Also append to the buffer if it exists
    if _G.Ninetyfive.websocket_buffer and vim.api.nvim_buf_is_valid(_G.Ninetyfive.websocket_buffer) then
      local line_count = vim.api.nvim_buf_line_count(_G.Ninetyfive.websocket_buffer)
      vim.api.nvim_buf_set_lines(_G.Ninetyfive.websocket_buffer, line_count, line_count, false, {"Sent: " .. message})
    end
    
    return true
  end

  -- Function to set up autocommands
  local function setup_autocommands()
    log.debug("some.scope", "set_autocommands")
    
    -- Create an autogroup for Ninetyfive
    local ninetyfive_augroup = vim.api.nvim_create_augroup("Ninetyfive", { clear = true })
    
    -- Autocommand for cursor movement and text changes
    vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
      pattern = "*",
      group = ninetyfive_augroup,
      callback = function(args)
        -- Use pcall to handle any errors in the callback
        local ok, err = pcall(function()
          local bufnr = args.buf
          local cursor = vim.api.nvim_win_get_cursor(0)
          local line = cursor[1] - 1 -- Lua uses 0-based indexing for lines
          local col = cursor[2] -- Column is 0-based
    
          -- Set the ghost text at the current cursor position
          set_ghost_text(bufnr, line, col)
        end)
        
        -- Log any errors that occurred
        if not ok then
          log.debug("ghost_text", "Error in TextChanged/TextChangedI callback: " .. tostring(err))
        end
      end,
    })
    
    -- Autocommand for cursor movement in insert mode
    vim.api.nvim_create_autocmd({"CursorMovedI"}, {
      pattern = "*",
      group = ninetyfive_augroup,
      callback = function(args)
        -- Use pcall to handle any errors in the callback
        local ok, err = pcall(function()
          -- Check that we're connected
          if not (_G.Ninetyfive and _G.Ninetyfive.websocket_job and _G.Ninetyfive.websocket_job > 0) then
            log.debug("websocket", "Skipping delta-completion-request - websocket not connected")
            return
          end
          
          local bufnr = args.buf
          local cursor = vim.api.nvim_win_get_cursor(0)
          local line = cursor[1] - 1 -- Lua uses 0-based indexing for lines
          local col = cursor[2] -- Column is 0-based
          
          -- Get buffer content from start to cursor position
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line + 1, false)
          -- Adjust the last line to only include content up to the cursor
          if #lines > 0 then
            lines[#lines] = string.sub(lines[#lines], 1, col)
          end
          local content_to_cursor = table.concat(lines, '\n')
          
          -- Get byte position (length of content in bytes)
          local pos = #content_to_cursor
          
          -- Get repo name from buffer path
          local bufpath = vim.api.nvim_buf_get_name(bufnr)
          local repo = "unknown"
          -- Extract repo name from path if possible
          local repo_match = string.match(bufpath, "/([^/]+)/[^/]+$")
          if repo_match then
            repo = repo_match
          end
          
          -- Generate a request ID
          local requestId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
          
          -- Create delta-completion-request message
          local message = vim.json.encode({
            type = "delta-completion-request",
            requestId = requestId,
            repo = repo,
            pos = pos
          })
          
          -- Send the message to the websocket and check result
          if not send_websocket_message(message) then
            log.debug("websocket", "Failed to send delta-completion-request message")
          end
        end)
        
        -- Log any errors that occurred
        if not ok then
          log.debug("websocket", "Error in CursorMovedI callback: " .. tostring(err))
        end
      end,
    })
    
    -- Autocommand for new buffer creation
    vim.api.nvim_create_autocmd({"BufReadPost"}, {
      pattern = "*",
      group = ninetyfive_augroup,
      callback = function(args)
        -- Use pcall to handle any errors in the callback
        local ok, err = pcall(function()
          -- Check that we're connected
          if not (_G.Ninetyfive and _G.Ninetyfive.websocket_job and _G.Ninetyfive.websocket_job > 0) then
            log.debug("websocket", "Skipping buffer message - websocket not connected")
            return
          end
          
          local bufnr = args.buf
          local bufname = vim.api.nvim_buf_get_name(bufnr)
          local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
          
          -- Create our file-content msg
          local message = vim.json.encode({
            type = "file-content",
            path = bufname,
            text = content
          })
          
          -- Send the message to the websocket and check result
          if not send_websocket_message(message) then
            log.debug("websocket", "Failed to send file-content message")
          end
        end)
        
        -- Log any errors that occurred
        if not ok then
          log.debug("websocket", "Error in BufReadPost callback: " .. tostring(err))
        end
      end,
    })
  end
  
  -- Function to set up websocket connection
  local function setup_websocket_connection()
    log.debug("websocket", "Setting up websocket connection")
    
    -- Store the job ID for the websocket connection
    if _G.Ninetyfive.websocket_job then
      -- Kill existing connection if there is one
      vim.fn.jobstop(_G.Ninetyfive.websocket_job)
      _G.Ninetyfive.websocket_job = nil
    end

    -- Path to the websocat binary (relative to the plugin directory)
    -- Get the plugin's root directory in a way that works regardless of where Neovim is opened
    local plugin_root = vim.fn.fnamemodify(vim.api.nvim_get_runtime_file("lua/ninetyfive/init.lua", false)[1] or "", ":h:h:h")
    local websocat_path = plugin_root .. '/websocat.x86_64-unknown-linux-musl'
    log.debug("websocket", "Using websocat at: " .. websocat_path)
    
    -- Make sure the binary is executable
    vim.fn.system('chmod +x ' .. vim.fn.shellescape(websocat_path))
    
    -- Create a buffer for websocket messages if it doesn't exist
    if not _G.Ninetyfive.websocket_buffer or not vim.api.nvim_buf_is_valid(_G.Ninetyfive.websocket_buffer) then
        -- Use pcall to handle potential errors
        local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
        if not ok then
            log.notify("websocket", vim.log.levels.ERROR, true, "Failed to create websocket buffer: " .. tostring(buf))
            return false
        end
        
        _G.Ninetyfive.websocket_buffer = buf
        
        -- Use pcall for setting buffer name too
        local ok2, err = pcall(vim.api.nvim_buf_set_name, buf, "NinetyfiveWebsocket")
        if not ok2 then
            log.debug("websocket", "Failed to set buffer name: " .. tostring(err))
            -- Continue anyway, not critical
        end
    end
    
    -- Clear the buffer
    vim.api.nvim_buf_set_lines(_G.Ninetyfive.websocket_buffer, 0, -1, false, {})
    
    -- Add header to the buffer
    vim.api.nvim_buf_set_lines(_G.Ninetyfive.websocket_buffer, 0, -1, false, {
        "Ninetyfive Websocket Connection",
        "Connected to: ws://127.0.0.1:1234",
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
        "ws://127.0.0.1:1234"
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
        log.notify("websocket", vim.log.levels.ERROR, true, "Failed to start websocat process")
        return false
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
    return true
  end

--- Toggle the plugin by calling the `enable`/`disable` methods respectively.
function Ninetyfive.toggle()
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    -- Check if the plugin is currently disabled
    local was_disabled = not state:get_enabled()
    
    main.toggle("public_api_toggle")
    
    -- If the plugin was disabled and is now enabled, set up autocommands and websocket
    if was_disabled and state:get_enabled() then
        log.debug("toggle", "Setting up autocommands and websocket after toggle")
        setup_autocommands()
        setup_websocket_connection()
    end
end

--- Initializes the plugin, sets event listeners and internal state.
function Ninetyfive.enable(scope)
    if _G.Ninetyfive.config == nil then
        _G.Ninetyfive.config = config.options
    end

    log.debug("init", "about to set up our stuff")
    
    -- Set up autocommands when plugin is enabled
    setup_autocommands()
    
    -- Set up websocket connection
    setup_websocket_connection()
      
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
end

_G.Ninetyfive = Ninetyfive

return _G.Ninetyfive
