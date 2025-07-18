local git = {}

-- Finds the root git repository for the current buffer, considering the use can have a cwd that
-- is not a git repository.
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
    -- Get the blob content
    local blob_command = string.format("git show %s:%s", hash, file)
    local blob = run_git_command(blob_command)
    if not blob then
        return nil
    end

    -- Get the diff
    local diff_command = string.format("git diff %s^ %s -- %s", hash, hash, file)
    local diff = run_git_command(diff_command)
    if not diff then
        return nil
    end

    -- Compress and encode blob and diff
    local encoded_blob = vim.base64.encode(blob)
    local encoded_diff = vim.base64.encode(diff)

    return {
        blob = encoded_blob,
        diff = encoded_diff,
    }
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

return git
