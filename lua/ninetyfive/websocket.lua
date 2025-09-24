local log = require("ninetyfive.util.log")
local suggestion = require("ninetyfive.suggestion")
local completion = require("ninetyfive.completion")
local git = require("ninetyfive.git")

local Websocket = {}

-- Reconnection settings
local reconnect_attempts = 0
local max_reconnect_attempts = 300
local reconnect_delay = 1000

-- Variable to store aggregated ghost text
local current_completion = nil
local buffer = nil
local active_text = nil

local home = vim.fn.expand("~")
local cache_path = home .. "/.ninetyfive/consent.json"
vim.fn.mkdir(home .. "/.ninetyfive", "p")

function Websocket.has_active()
    if not current_completion or not current_completion.completion then
        return false
    end

    -- scan through the list of parsed items
    for _, item in ipairs(current_completion.completion) do
        if item.v and tostring(item.v):match("%S") then
            return true
        end
    end

    return false
end

function Websocket.clear()
    current_completion = nil
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
        -- log.debug("websocket", "Error sending message: " .. tostring(result))
        return false
    end

    -- Check if the send was successful
    if result == 0 then
        -- log.debug("websocket", "Failed to send message to websocket")
        return false
    end

    -- log.debug("websocket", "Sent message to websocket")
    return true
end

local function send_file_content()
    local bufnr = vim.api.nvim_get_current_buf()
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

    if git.is_ignored(bufname) then
        log.debug("websocket", "skipping file-content message - file is git ignored")
        return
    end

    local message = vim.json.encode({
        type = "file-content",
        path = bufname,
        text = content,
    })

    if not Websocket.send_message(message) then
        log.debug("websocket", "Failed to send file-content message")
    end
end

local function get_indexing_consent(callback)
  local mode = (_G.Ninetyfive.config.indexing.mode) or "ask"
  local use_cache = (_G.Ninetyfive.config.indexing.cache_consent) ~= false

  -- check the config and short circuit
  if mode == "on" then
    callback(true)
    return
  elseif mode == "off" then
    callback(false)
    return
  end

  -- if caching is enabled, check it first
  if use_cache then
    local f = io.open(cache_path, "r")
    if f then
      local data = f:read("*a")
      f:close()
      local ok, parsed = pcall(vim.json.decode, data)
      if ok and parsed and parsed.consent ~= nil then
        callback(parsed.consent)
        return
      end
    end
  end

  vim.ui.select({ "Allow", "Deny" }, {
    prompt = "This extension can index your workspace to provide better completions. Would you like to allow this?",
  }, function(choice)
    if not choice then return end
    local consent = (choice == "Allow")

    -- persist it to our cache
    if use_cache then
      local ok, out = pcall(vim.json.encode, { consent = consent })
      if ok then
        local wf = io.open(cache_path, "w")
        if wf then
          wf:write(out)
          wf:close()
        end
      end
    end

    callback(consent)
  end)
end

local function set_workspace()
    local head = git.get_head()
    local git_root = git.get_repo_root()

    local repo = "unknown"
    if git_root then
        local repo_match = string.match(git_root, "/([^/]+)$")
        if repo_match then
            repo = repo_match
        end
    else
        local cwd = vim.fn.getcwd()
        local repo_match = string.match(cwd, "/([^/]+)$")
        if repo_match then
            repo = repo_match
        end
    end

    if head ~= nil and head.hash ~= "" then
        local set_workspace = vim.json.encode({
            type = "set-workspace",
            commitHash = head.hash,
            path = git_root,
            name = repo .. "/" .. head.branch,
            features = { "edits" },
        })

        if not Websocket.send_message(set_workspace) then
            log.debug("websocket", "Failed to set-workspace")
        end
    else
        local empty_workspace = vim.json.encode({
            type = "set-workspace",
            features = { "edits" },
        })

        if not Websocket.send_message(empty_workspace) then
            log.debug("websocket", "Failed to empty set-workspace")
        end

        local bufnr = vim.api.nvim_get_current_buf()
        local curr_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

        if active_text ~= curr_text then
            active_text = curr_text
            send_file_content()
            current_completion = nil
        end
    end
end

-- Function to send file delta (changes only)
local function send_file_delta(args)
    local bufnr = args.buf
    local bufname = vim.api.nvim_buf_get_name(bufnr)

    if git.is_ignored(bufname) then
        log.debug("websocket", "skipping file-delta message - file is git ignored")
        return
    end

    -- Get current content
    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local current_content = table.concat(current_lines, "\n")

    local prev = active_text
    local curr = current_content

    -- Find the first differing character
    local start_pos = 0
    local min_len = math.min(#prev, #curr)

    while start_pos < min_len do
        if
            string.sub(prev, start_pos + 1, start_pos + 1)
            ~= string.sub(curr, start_pos + 1, start_pos + 1)
        then
            break
        end
        start_pos = start_pos + 1
    end

    -- Find the end of the change
    local prev_end = #prev
    local curr_end = #curr

    while prev_end > start_pos and curr_end > start_pos do
        if string.sub(prev, prev_end, prev_end) ~= string.sub(curr, curr_end, curr_end) then
            break
        end
        prev_end = prev_end - 1
        curr_end = curr_end - 1
    end

    -- Calculate the replaced text
    local replaced_text = string.sub(prev, start_pos + 1, prev_end)
    local new_text = string.sub(curr, start_pos + 1, curr_end)

    if new_text == "" then
        return
    end

    -- Calculate end position
    local end_pos = start_pos + #replaced_text

    local message = vim.json.encode({
        type = "file-delta",
        path = bufname,
        start = start_pos,
        text = new_text,
        ["end"] = end_pos,
    })

    if not Websocket.send_message(message) then
        log.debug("websocket", "Failed to send file-delta message")
    end
end

local function request_completion(args)
    if current_completion ~= nil then
        return
    end

    local ok, err = pcall(function()
        -- Check that we're connected
        if
            not (_G.Ninetyfive and _G.Ninetyfive.websocket_job and _G.Ninetyfive.websocket_job > 0)
        then
            log.debug("websocket", "Skipping delta-completion-request - websocket not connected")
            return
        end

        local bufnr = args.buf
        local bufname = vim.api.nvim_buf_get_name(bufnr)

        if git.is_ignored(bufname) then
            log.debug("websocket", "Skipping delta-completion-request - file is git ignored")
            return
        end
        local cursor = vim.api.nvim_win_get_cursor(0)
        local line = cursor[1] - 1 -- Lua uses 0-based indexing for lines
        local col = cursor[2] -- Column is 0-based

        -- Get buffer content from start to cursor position
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line + 1, false)
        -- Adjust the last line to only include content up to the cursor
        if #lines > 0 then
            lines[#lines] = string.sub(lines[#lines], 1, col)
        end
        local content_to_cursor = table.concat(lines, "\n")

        -- Get byte position (length of content in bytes)
        local pos = #content_to_cursor

        -- Repo is the cwd? Is this generally correct with how people use neovim?
        local git_root = git.get_repo_root()
        local repo = "unknown"
        if git_root then
            local repo_match = string.match(git_root, "/([^/]+)$")
            if repo_match then
                repo = repo_match
            end
        else
            local cwd = vim.fn.getcwd()
            local repo_match = string.match(cwd, "/([^/]+)$")
            if repo_match then
                repo = repo_match
            end
        end

        -- Generate a request ID
        local request_id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))

        buffer = bufnr

        local message = vim.json.encode({
            type = "delta-completion-request",
            requestId = request_id,
            repo = repo,
            pos = pos,
        })

        log.debug("messages", "-> [delta-completion-request]", request_id, repo, pos)

        if not Websocket.send_message(message) then
            log.debug("websocket", "Failed to send delta-completion-request message")
        end

        current_completion = completion.new(request_id)
    end)

    if not ok then
        log.debug("websocket", "Error in CursorMovedI callback: " .. tostring(err))
    end

    -- Also clear any suggestions that were showing
    suggestion.clear()
end

function Websocket.accept_edit()
    if current_completion then
        suggestion.accept_edit(current_completion)

        if current_completion.edit_index > #current_completion.edits then
            current_completion = nil
            return
        end

        -- Check next edit
        local edit = current_completion:next_edit()

        if not edit then
            return
        end

        if edit.text == "" then
            suggestion.showDeleteSuggestion(edit)
            current_completion.edit_index = current_completion.edit_index + 1
        elseif edit.start == edit["end"] then
            suggestion.showInsertSuggestion(edit.start, edit["end"], edit.text)
            current_completion.edit_index = current_completion.edit_index + 1
        else
            suggestion.showUpdateSuggestion(edit.start, edit["end"], edit.text)
            current_completion.edit_index = current_completion.edit_index + 1
        end
    end
end

function Websocket.accept()
    if
        current_completion ~= nil
        and #current_completion.completion > 0
        and buffer == vim.api.nvim_get_current_buf()
    then
        local bufnr = vim.api.nvim_get_current_buf()
        vim.b[bufnr].ninetyfive_accepting = true

        local built = {}
        for _, item in ipairs(current_completion.completion) do
            if item.v and item.v ~= vim.NIL then
                table.insert(built, tostring(item.v))
            end
        end
        local accepted_text = table.concat(built)

        suggestion.accept(current_completion)
        current_completion:consume(#accepted_text)

        local edit = current_completion:next_edit()

        -- Don't even show the edit description if there are no edits
        if not edit then
            return
        end
        -- After accepting we can process the edits
        suggestion.showEditDescription(current_completion)

        log.debug("messages", "checking if active")

        current_completion.is_active = true

        if edit.text == "" then
            suggestion.showDeleteSuggestion(edit)
        elseif edit.start == edit["end"] then
            suggestion.showInsertSuggestion(edit.start, edit["end"], edit.text)
        else
            suggestion.showUpdateSuggestion(edit.start, edit["end"], edit.text)
        end

        current_completion.edit_index = current_completion.edit_index + 1

        -- TODO: we only clear the completion once its been consumed, or cancelled...
    end
end

function Websocket.reject()
    -- TODO anything to send to the server?
    suggestion.clear()
end

-- Function to set up autocommands related to websocket functionality
function Websocket.setup_autocommands()
    -- Create an autogroup for Ninetyfive
    -- https://www.youtube.com/watch?v=F6GNPOXpfwU
    local ninetyfive_augroup = vim.api.nvim_create_augroup("Ninetyfive", { clear = true })

    -- Autocommand for cursor movement in insert mode
    -- CursorMovedI does not seem to trigger when you type in insert mode!!
    vim.api.nvim_create_autocmd({ "CursorMovedI" }, {
        pattern = "*",
        group = ninetyfive_augroup,
        callback = function(args)
            if vim.b[args.buf].ninetyfive_accepting then
                return
            end

            suggestion.clear()
            current_completion = nil
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChangedI" }, {
        pattern = "*",
        group = ninetyfive_augroup,
        callback = function(args)
            local bufnr = args.buf

            local filetype = vim.bo[bufnr].filetype

            -- We do not want to trigger when people are in the oil.nvim buffer
            if filetype == "oil" then
                return
            end

            if vim.b[bufnr].ninetyfive_accepting then
                return
            end

            suggestion.clear()
            current_completion = nil

            vim.schedule(function()
                local curr_text =
                    table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
                if active_text == nil then
                    send_file_content()
                    current_completion = nil
                else
                    send_file_content()

                    if
                        current_completion
                        and current_completion.is_closed
                        and current_completion.consumed
                            == string.len(current_completion.completion)
                    then
                        -- we have consumed the completion we're not in edit mode
                        if not current_completion.is_active then
                            current_completion = nil
                        end
                        --TODO this is missing the edit case
                    else
                        current_completion = nil
                    end
                end

                active_text = curr_text

                request_completion(args)
            end)
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            Websocket.shutdown()
        end,
        desc = "[ninetyfive] Close websocket connection on exit",
    })

    -- Autocommand for new buffer creation
    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
        pattern = "*",
        group = ninetyfive_augroup,
        callback = function(args)
            local bufnr = args.buf
            local filetype = vim.bo[bufnr].filetype

            -- We do not want to trigger when people are in the oil.nvim buffer
            if filetype == "oil" then
                return
            end
            
            local ok, err = pcall(function()
                -- Check that we're connected
                if
                    not (
                        _G.Ninetyfive
                        and _G.Ninetyfive.websocket_job
                        and _G.Ninetyfive.websocket_job > 0
                    )
                then
                    log.debug("websocket", "Skipping buffer message - websocket not connected")
                    return
                end

                -- TODO Is this the right way? This would be per buffer so may trigger more commit/blob requests?
                set_workspace()

                -- Send full file content for initial buffer load
                send_file_content()
            end)

            if not ok then
                log.debug("websocket", "Error in BufReadPost callback: " .. tostring(err))
            end
        end,
    })

    vim.api.nvim_create_autocmd("InsertLeave", {
        callback = function(args)
            -- We dont need to display suggestions when the user leaves insert mode
            suggestion.clear()
            current_completion = nil
            vim.b[args.buf].ninetyfive_accepting = false
        end,
    })
end

-- See: https://github.com/neovim/neovim/blob/master/test/testutil.lua#L390
local function pick_binary()
    local uv = vim.uv or vim.loop -- `vim.uv` is only available after 0.10
    local uname = uv.os_uname()
    local sysname = uname.sysname:lower()
    local arch = uname.machine

    local binaries = {
        darwin = {
            x86_64 = "/dist/go-ws-proxy-darwin-amd64",
            default = "/dist/go-ws-proxy-darwin-arm64",
        },
        linux = {
            x86_64 = "/dist/go-ws-proxy-linux-amd64",
            default = "/dist/go-ws-proxy-linux-arm64",
        },
        windows = {
            x86_64 = "/dist/go-ws-proxy-windows-amd64",
            default = "/dist/go-ws-proxy-windows-arm64",
        },
    }

    if binaries[sysname] then
        if type(binaries[sysname]) == "table" then
            return binaries[sysname][arch] or binaries[sysname].default
        end
        return binaries[sysname]
    end

    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
        return binaries.windows
    end

    return ""
end

function Websocket.shutdown()
    if _G.Ninetyfive.websocket_job then
        log.debug("websocket", "Shutting down websocket process")
        vim.fn.jobstop(_G.Ninetyfive.websocket_job)
        _G.Ninetyfive.websocket_job = nil
    end
end

-- Function to set up websocket connection
function Websocket.setup_connection(server_uri, user_id, api_key)
    log.debug("websocket", "Setting up websocket connection")

    -- Path to the binary (relative to the plugin directory)
    -- Get the plugin's root directory in a way that works regardless of where Neovim is opened
    local plugin_root = vim.fn.fnamemodify(
        vim.api.nvim_get_runtime_file("lua/ninetyfive/init.lua", false)[1] or "",
        ":h:h:h"
    )
    local binary_path = plugin_root .. pick_binary()

    -- Build the websocket URI with query parameters
    local ws_uri = server_uri .. "?user_id=" .. user_id .. "&editor=neovim"

    if api_key and api_key ~= "" then
        ws_uri = ws_uri .. "&api_key=" .. api_key
    end

    get_indexing_consent(function(allowed)
        if not allowed then
            log.debug("websocket", "Indexing consent not granted, skipping git sync")
            return
        end

        if api_key and api_key ~= "" then
            print("indexing consent allowed and api key exists, syncing repository data...")

            vim.defer_fn(function()
                vim.schedule(function()
                    local ok, err = pcall(function()
                        local base_url = server_uri:gsub("^ws://", "http://"):gsub("^wss://", "https://")
                        local git_endpoint = base_url:gsub("/ws$", "") .. "/datasets"
                        
                        git.sync_current_repo(api_key, git_endpoint, 50) -- limit to 50 commits for now
                        
                        log.debug("websocket", "Git repository sync completed")
                    end)
                    
                    if not ok then
                        log.notify("websocket", vim.log.levels.ERROR, true, "Failed to sync git repository: " .. tostring(err))
                    end
                end)
            end, 2000)
        else
            log.debug("websocket", "No API key provided, skipping git sync")
        end
    end)

    _G.Ninetyfive.websocket_job = vim.fn.jobstart({
        binary_path,
        ws_uri,
    }, {
        on_stdout = function(_, data, _)
            if not data then
                return
            end

            for _, line in ipairs(data) do
                if line ~= "" then
                    log.debug("websocket", "Got message line from websocket: ", line)

                    local ok, parsed = pcall(vim.json.decode, line)
                    if not ok or type(parsed) ~= "table" then
                        log.debug("websocket", "Failed to parse JSON line: ", line)
                        goto continue
                    end

                    local msg_type = parsed.type

                    if msg_type == "subscription-info" then
                        log.debug("messages", "<- [subscription-info]", parsed)
                    elseif msg_type == "get-commit" then
                        local commit = git.get_commit(parsed.commitHash)
                        if commit then
                            local send_commit = vim.json.encode({
                                type = "commit",
                                commitHash = parsed.commitHash,
                                commit = commit,
                            })
                            if not Websocket.send_message(send_commit) then
                                log.debug("websocket", "Failed to send commit")
                            end
                        end
                    elseif msg_type == "get-blob" then
                        local blob = git.get_blob(parsed.commitHash, parsed.path)
                        if blob then
                            local send_blob = vim.json.encode({
                                type = "blob",
                                commitHash = parsed.commitHash,
                                objectHash = parsed.objectHash,
                                path = parsed.path,
                                blobBytes = blob.blob,
                                diffBytes = blob.diff,
                            })
                            log.debug("messages", "-> [blob]", send_blob)
                            if not Websocket.send_message(send_blob) then
                                log.debug("websocket", "Failed to send blob")
                            end
                        end
                    else
                        local c = current_completion
                        if c and c.request_id == parsed.r then
                            if parsed.v and parsed.v ~= vim.NIL then
                                table.insert(c.completion, parsed)
                            end
                            if parsed.e then
                                c.edits = parsed.e
                                c.edit_description = parsed.ed
                                c:close()
                            end
                            suggestion.show(c.completion)
                        end
                    end
                end
                ::continue::
            end
        end,
        on_stderr = function(_, data, _)
            if data and #data > 0 then
                local message = table.concat(data, "\n")
                if message ~= "" then
                    log.debug("websocket", "Failed to connect")
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            log.notify(
                "websocket",
                vim.log.levels.WARN,
                true,
                "websocket job exiting..."
            )
        end,
        stdout_buffered = false,
        stderr_buffered = false,
    })

    if _G.Ninetyfive.websocket_job <= 0 then
        log.notify("websocket", vim.log.levels.ERROR, true, "Failed to start process")
        return false
    end

    log.debug("websocket", "Started process with job ID: " .. _G.Ninetyfive.websocket_job)

    return true
end

function Websocket.get_completion()
    if current_completion == nil then
        return ""
    end

    return current_completion.completion
end

function Websocket.reset_completion()
    current_completion = nil
end

return Websocket
