local git = {}

git.get_repo_root = function()
    local buffer_dir = vim.fn.expand("%:p:h")
    local handle =
        io.popen(string.format("cd %s && git rev-parse --show-toplevel 2> /dev/null", buffer_dir))
    if not handle then
        return nil
    end
    local result = handle:read("*a")
    handle:close()
    result = result:gsub("\n$", "")
    return result ~= "" and result or nil
end

local function run_git_command(cmd)
    local repo_root = git.get_repo_root()

    -- If not in a git repository, return nil
    if not repo_root then
        return nil
    end

    local full_cmd = string.format("cd %s && %s", repo_root, cmd)

    local handle = io.popen(full_cmd)
    if not handle then
        return nil
    end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("\n$", "")
end

git.get_head = function()
    local hash = run_git_command("git rev-parse HEAD")
    if not hash then
        return nil
    end

    local branch = run_git_command("git rev-parse --abbrev-ref HEAD")
    if not branch then
        return nil
    end

    return { hash = hash, branch = branch }
end

local function parse_diff_numstat(raw)
    local diff = {}
    for line in raw:gmatch("[^\r\n]+") do
        local additions, deletions, file = line:match("^(%d+)%s+(%d+)%s+(.*)$")
        if additions and deletions and file then
            local from, to = file:match("(.*) => (.*)")
            if from and to then
                table.insert(diff, {
                    from = from,
                    to = to,
                    additions = tonumber(additions),
                    deletions = tonumber(deletions),
                })
            else
                table.insert(diff, {
                    from = file,
                    to = file,
                    additions = tonumber(additions),
                    deletions = tonumber(deletions),
                })
            end
        end
    end
    return diff
end

local function parse_ls_tree(raw)
    local ls_tree = {}
    for line in raw:gmatch("[^\r\n]+") do
        local mode, type, object, size, file = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.*)$")
        if mode and type and object and size and file then
            table.insert(ls_tree, {
                mode = mode,
                type = type,
                object = object,
                size = size,
                file = file,
            })
        end
    end
    return ls_tree
end

function git.get_commit(hash)
    local diff_stdout = run_git_command(string.format("git show --numstat %s", hash))
    if not diff_stdout then
        return nil
    end

    local diff = parse_diff_numstat(diff_stdout)

    local commit_info =
        run_git_command(string.format("git log -1 --pretty=format:%%P%%n%%B %s", hash))
    if not commit_info then
        return nil
    end

    local parents, message = commit_info:match("([^\n]*)\n(.*)")
    local parent_hashes = {}
    for parent in parents:gmatch("%S+") do
        table.insert(parent_hashes, parent)
    end

    local ls_tree_stdout = run_git_command(string.format("git ls-tree -r -l --full-tree %s", hash))
    if not ls_tree_stdout then
        return nil
    end

    local ls_tree = parse_ls_tree(ls_tree_stdout)

    local files = {}
    for _, file in ipairs(diff) do
        if file.additions ~= nil and file.deletions ~= nil then
            local ls_tree_file = nil
            for _, tree_file in ipairs(ls_tree) do
                if tree_file.file == file.to then
                    ls_tree_file = tree_file
                    break
                end
            end
            if ls_tree_file then
                local combined_file = vim.tbl_extend("force", file, ls_tree_file)
                table.insert(files, combined_file)
            end
        end
    end

    return {
        parents = parent_hashes,
        message = message,
        files = files,
    }
end

function git.get_blob(hash, file)
    local ok, result = pcall(function()
        local blob_command = string.format("git show %s:%s", hash, file)
        local blob = run_git_command(blob_command)
        if not blob then
            return nil
        end

        local parent_line = run_git_command(string.format("git rev-list --parents -n 1 %s", hash))
        if not parent_line then
            return nil
        end
        local parents = vim.split(parent_line, "%s+")
        local parent = parents[2] -- first parent if exists

        local encoded_diff = ""
        if parent then
            -- only run diff if parent exists
            local diff_command = string.format("git diff %s %s -- %s", parent, hash, file)
            local diff = run_git_command(diff_command)
            if diff then
                encoded_diff = vim.base64.encode(diff)
            end
        end

        local encoded_blob = vim.base64.encode(blob)

        return {
            blob = encoded_blob,
            diff = encoded_diff,
        }
    end)

    if ok then
        return result
    else
        return nil
    end
end

function git.is_ignored(file_path)
    if not file_path or file_path == "" then
        return true
    end

    -- If not in a git repository, consider the file not ignored
    if not git.get_repo_root() then
        return false
    end

    local cmd = string.format("git check-ignore %s", file_path)
    local result, _ = run_git_command(cmd)

    -- An empty result means the file is not ignored
    return result ~= ""
end

local function run_git_command_at_root(cmd, callback)
  local repo_root = git.get_repo_root()
  if not repo_root then
    if callback then callback(nil) end
    return nil
  end
  
  if not callback then
    local result = vim.system({'sh', '-c', cmd}, { cwd = repo_root }):wait()
    if result.code == 0 then
      return result.stdout:gsub("\n$", "")
    else
      return nil
    end
  end
  
  vim.system({'sh', '-c', cmd}, { cwd = repo_root }, function(result)
    if result.code == 0 then
      callback(result.stdout:gsub("\n$", ""))
    else
      callback(nil)
    end
  end)
end

local function get_commit_hashes(max_entries)
  max_entries = max_entries or 100
  
  local cmd = string.format("git log --format=%%H --oneline --no-merges origin/HEAD..HEAD -%d", max_entries)
  local output = run_git_command_at_root(cmd)

  if not output or output == "" then
    print("No unpushed commits found, getting recent commits from current branch...")
    cmd = string.format("git log --format=%%H --oneline --no-merges -%d", max_entries)
    output = run_git_command_at_root(cmd)
  end

  if not output or output == "" then
    return {}
  end
  
  local commits = {}
  for line in output:gmatch("[^\r\n]+") do
    if line ~= "" then
      local hash, message = line:match("^(%w+)%s+(.+)$")
      if hash then
        table.insert(commits, {
          hash = hash,
          message = message or "Commit message"
        })
      end
    end
  end
  
  return commits
end

function git.get_git_blobs(commit_hash)
  local blobs = {}
  local repo_root = git.get_repo_root()
  
  if not repo_root then
    return blobs
  end
  
  local commit_info = git.get_commit(commit_hash)
  if not commit_info then
    return blobs
  end
  
  for _, file_info in ipairs(commit_info.files) do
    local file_path = file_info.to or file_info.file
    
    if not git.is_ignored(file_path) then
      local blob_data = git.get_blob(commit_hash, file_path)
      
      if blob_data then
        table.insert(blobs, {
          object_hash = file_info.object,
          commit_hash = commit_hash,
          path = file_path,
          next = blob_data.blob, -- already base64 encoded
          diff = blob_data.diff ~= "" and blob_data.diff or nil -- already base64 encoded
        })
      else
        print("failed to get blob for file: " .. file_path)
      end
    end
  end
  
  return blobs
end

function git.get_all_commits_and_blobs(max_entries)
  local commits = {}
  local blobs = {}
  
  if not git.get_repo_root() then
    return { commits = commits, blobs = blobs }
  end
  
  print("fetching commit/blob info...")
  
  commits = get_commit_hashes(max_entries)
  
  if #commits == 0 then
    print("no commits found for current branch")
    return { commits = commits, blobs = blobs }
  end
  
  for _, commit in ipairs(commits) do
    local commit_blobs = git.get_git_blobs(commit.hash)
    for _, blob in ipairs(commit_blobs) do
      table.insert(blobs, blob)
    end
  end
  
  return { commits = commits, blobs = blobs }
end

function git.send_blobs_to_endpoint(job_data, api_key, endpoint_url)
  local CHUNK_SIZE = 100
  local blobs = job_data.blobs
  
  local total_chunks = math.ceil(#blobs / CHUNK_SIZE)
  
  for i = 1, #blobs, CHUNK_SIZE do
    local chunk = {}
    local end_idx = math.min(i + CHUNK_SIZE - 1, #blobs)
    
    for j = i, end_idx do
      table.insert(chunk, blobs[j])
    end
    
    local chunk_number = math.floor((i - 1) / CHUNK_SIZE) + 1
    
    local chunk_blobs = {}
    for _, blob in ipairs(chunk) do
      table.insert(chunk_blobs, {
        object_hash = blob.object_hash,
        commit_hash = blob.commit_hash,
        path = blob.path,
        next = blob.next, -- already base64 encoded from git.get_blob
        diff = blob.diff or vim.NIL -- already base64 encoded or nil
      })
    end
    
    local chunk_commits = {}
    for _, commit in ipairs(job_data.commits) do
      table.insert(chunk_commits, {
        hash = type(commit) == "string" and commit or commit.hash,
        message = type(commit) == "string" and "Commit message" or (commit.message or "Commit message")
      })
    end
    
    local payload = {
      blobs = chunk_blobs,
      commits = chunk_commits,
      branch_name = job_data.branch_name,
      repo_name = job_data.repo_name
    }
    
    local json_payload = vim.json.encode(payload)
    
    local curl_cmd = string.format(
      'curl -s -w "%%{http_code}" -X POST "%s" -H "Content-Type: application/json" -H "x-api-key: %s" -d %s',
      endpoint_url,
      api_key,
      "'" .. json_payload:gsub("'", "'\"'\"'") .. "'"
    )
    
    local handle = io.popen(curl_cmd)
    if not handle then
      return
    end
    
    local response = handle:read("*a")
    local success, exit_type, exit_code = handle:close()
    
    if not success then
      print("request failed for chunk " .. chunk_number .. "/" .. total_chunks)
      return
    end
    
    local http_code = response:match("(%d+)$")
    local response_body = response:gsub("%d+$", "")
    
    if http_code and tonumber(http_code) >= 200 and tonumber(http_code) < 300 then
      print("successfully sent chunk " .. chunk_number .. "/" .. total_chunks)
      
      local ok, response_data = pcall(vim.json.decode, response_body)
      if ok and response_data then
        print("Response:", vim.inspect(response_data))
      end
    else
      print("response:", response_body)
    end
    
    ::continue::
    
    if i + CHUNK_SIZE <= #blobs then
      vim.wait(100)
    end
  end
end

function git.sync_repo_data(api_key, endpoint_url, branch_name, repo_name, max_entries)
  max_entries = max_entries or 100
  
  local head_info = git.get_head()
  if not head_info then
    return
  end
  
  branch_name = branch_name or head_info.branch
  
  if not repo_name then
    local repo_root = git.get_repo_root()
    if repo_root then
      repo_name = repo_root:match("([^/]+)$") or "unknown"
    else
      repo_name = "unknown"
    end
  end
  
  local result = git.get_all_commits_and_blobs(max_entries)
  
  if #result.commits == 0 and #result.blobs == 0 then
    print("no commits or blobs found")
    return
  end
  
  local job_data = {
    commits = result.commits,
    blobs = result.blobs,
    branch_name = branch_name,
    repo_name = repo_name
  }
  
  git.send_blobs_to_endpoint(job_data, api_key, endpoint_url)
end

function git.sync_current_repo(api_key, endpoint_url, max_entries)
  git.sync_repo_data(api_key, endpoint_url, nil, nil, max_entries)
end

return git
