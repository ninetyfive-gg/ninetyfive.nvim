local log = require("ninetyfive.util.log")

local Websocket = {}

-- Variable to store aggregated ghost text
local completion = ""
local ninetyfive_ns = vim.api.nvim_create_namespace("ninetyfive_ghost_ns")

-- Function to set ghost text in the buffer
local function set_ghost_text(bufnr, line, col, message)
  -- Clear any existing extmarks in the buffer
  vim.api.nvim_buf_clear_namespace(bufnr, ninetyfive_ns, 0, -1)

  -- Set the ghost text using an extmark
  -- https://neovim.io/doc/user/api.html#nvim_buf_set_extmark()
  vim.api.nvim_buf_set_extmark(bufnr, ninetyfive_ns, line, col, {
    virt_text = {{message, "Comment"}}, -- "Comment" is the highlight group
    virt_text_pos = "overlay", -- Display the text at the end of the line
    hl_mode = "combine", -- Combine with existing highlights
  })
end

-- Function to send a message to the websocket
function Websocket.send_message(message)
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
  return true
end

-- Function to set up autocommands related to websocket functionality
function Websocket.setup_autocommands()
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
        completion = ""
        
        local message = vim.json.encode({
          type = "delta-completion-request",
          requestId = requestId,
          repo = repo,
          pos = pos
        })
        
        if not Websocket.send_message(message) then
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
        
        if not Websocket.send_message(message) then
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
function Websocket.setup_connection(server_uri)
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
  
  _G.Ninetyfive.websocket_job = vim.fn.jobstart({
      websocat_path,
      "wss://api.ninetyfive.gg"
  }, {
      on_stdout = function(_, data, _)
          if data and #data > 0 then
              local message = table.concat(data, "\n")
              if message ~= "" then
                  local ok, parsed = pcall(vim.json.decode, message)
                  if ok and parsed then
                      if parsed.type then
                          if parsed.type == "get-commit" or parsed.type == "get-blob" or parsed.type == "subscription-info" then
                              log.debug("websocket", "Received message of type: " .. parsed.type)
                              print("Received message of type: " .. parsed.type)
                          end
                      else
                          if parsed.v then
                              print("Received completion :o")
                              
                              completion = completion .. parsed.v
                              
                              -- Get current buffer and cursor position
                              local bufnr = vim.api.nvim_get_current_buf()
                              local cursor = vim.api.nvim_win_get_cursor(0)
                              local line = cursor[1] - 1 -- Lua uses 0-based indexing for lines
                              local col = cursor[2] -- Column is 0-based
                              
                              set_ghost_text(bufnr, line, col, completion)
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

function Websocket.get_completion()
  return completion
end

function Websocket.reset_completion()
  completion = ""
end

return Websocket
