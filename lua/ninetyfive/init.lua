local main = require("ninetyfive.main")
local config = require("ninetyfive.config")
local log = require("ninetyfive.util.log")
local state = require("ninetyfive.state")

local Ninetyfive = {}

local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")
-- Variable to store aggregated ghost text
local aggregated_ghost_text = ""

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
    -- https://www.youtube.com/watch?v=F6GNPOXpfwU
    local ninetyfive_augroup = vim.api.nvim_create_augroup("Ninetyfive", { clear = true })
    
    -- Autocommand for cursor movement in insert mode
    vim.api.nvim_create_autocmd({"CursorMovedI"}, {
      pattern = "*",
      group = ninetyfive_augroup,
      callback = function(args)
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
          
          -- Repo is the cwd? Is this generally correct with how people use neovim?
          local cwd = vim.fn.getcwd()
          local repo = "unknown"
          local repo_match = string.match(cwd, "/([^/]+)$")
          if repo_match then
            repo = repo_match
          end
          
          -- Generate a request ID
          local requestId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
          
          -- Clear the aggregated ghost text when sending a new completion request
          aggregated_ghost_text = ""
          
          local message = vim.json.encode({
            type = "delta-completion-request",
            requestId = requestId,
            repo = repo,
            pos = pos
          })
          
          if not send_websocket_message(message) then
            log.debug("websocket", "Failed to send delta-completion-request message")
          end
        end)
        
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
        local ok, err = pcall(function()
          -- Check that we're connected
          if not (_G.Ninetyfive and _G.Ninetyfive.websocket_job and _G.Ninetyfive.websocket_job > 0) then
            log.debug("websocket", "Skipping buffer message - websocket not connected")
            return
          end
          
          local bufnr = args.buf
          local bufname = vim.api.nvim_buf_get_name(bufnr)
          local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
          
          local message = vim.json.encode({
            type = "file-content",
            path = bufname,
            text = content
          })
          
          if not send_websocket_message(message) then
            log.debug("websocket", "Failed to send file-content message")
          end
        end)
        
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
    local websocat_path = plugin_root .. '/websocat.aarch64-apple-darwin'
    log.debug("websocket", "Using websocat at: " .. websocat_path)
    
    -- Make sure the binary is executable
    vim.fn.system('chmod +x ' .. vim.fn.shellescape(websocat_path))
    
    -- Start the websocat process
    _G.Ninetyfive.websocket_job = vim.fn.jobstart({
        websocat_path,
        "wss://api.ninetyfive.gg"
    }, {
        on_stdout = function(_, data, _)
            if data and #data > 0 then
                local message = table.concat(data, "\n")
                if message ~= "" then
                    -- Try to parse the message as JSON
                    local ok, parsed = pcall(vim.json.decode, message)
                    if ok and parsed then
                        -- Check if the message has a type field
                        if parsed.type then
                            -- Handle specific message types
                            if parsed.type == "get-commit" or parsed.type == "get-blob" or parsed.type == "subscription-info" then
                                log.debug("websocket", "Received message of type: " .. parsed.type)
                                -- Just print for now
                                print("Received message of type: " .. parsed.type)
                            end
                        else
                            -- No type field, assume it's a completion request
                            -- Check if it has a 'v' field for ghost text
                            if parsed.v then
                                print("Received completion :o")
                                
                                -- Aggregate the ghost text
                                aggregated_ghost_text = aggregated_ghost_text .. parsed.v
                                
                                -- Get current buffer and cursor position
                                local bufnr = vim.api.nvim_get_current_buf()
                                local cursor = vim.api.nvim_win_get_cursor(0)
                                local line = cursor[1] - 1 -- Lua uses 0-based indexing for lines
                                local col = cursor[2] -- Column is 0-based
                                
                                -- Set ghost text with the aggregated content
                                vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_ns, 0, -1)
                                vim.api.nvim_buf_set_extmark(bufnr, ninetyfive_ns, line, col, {
                                    virt_text = {{aggregated_ghost_text, "Comment"}},
                                    virt_text_pos = "overlay",
                                    hl_mode = "combine",
                                })
                            end
                        end
                    end
                end
            end
        end,
        on_stderr = function(_, data, _)
            if data and #data > 0 then
                local message = table.concat(data, "\n")
                if message ~= "" then
                    print("Error: " .. message)
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            print("Websocket connection closed with exit code: " .. exit_code)
        end,
        stdout_buffered = false,
        stderr_buffered = false
    })
    
    if _G.Ninetyfive.websocket_job <= 0 then
        log.notify("websocket", vim.log.levels.ERROR, true, "Failed to start websocat process")
        return false
    end
    
    log.debug("websocket", "Started websocat process with job ID: " .. _G.Ninetyfive.websocket_job)
    
    vim.notify("Ninetyfive websocket connection established.", vim.log.levels.INFO)
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
