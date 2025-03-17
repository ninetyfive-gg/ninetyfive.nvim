local git = {}

local function run_git_command(cmd)
    local handle = io.popen(cmd)
    if not handle then
        return nil, "Failed"
    end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("\n$", "")
end

-- "Public" api
git.is_available = function()
    return vim.fn.executable("git") == 1
end

git.get_head = function()
    local hash = run_git_command("git rev-parse HEAD")
    if not hash then
        return nil, "Failed to get commit hash"
    end

    local branch = run_git_command("git rev-parse --abbrev-ref HEAD")
    if not branch then
        return nil, "Failed to get branch name"
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
        return nil, "Failed to get diff"
    end

    local diff = parse_diff_numstat(diff_stdout)

    local commit_info =
        run_git_command(string.format("git log -1 --pretty=format:%%P%%n%%B %s", hash))
    if not commit_info then
        return nil, "Failed to get commit info"
    end

    local parents, message = commit_info:match("([^\n]*)\n(.*)")
    local parent_hashes = {}
    for parent in parents:gmatch("%S+") do
        table.insert(parent_hashes, parent)
    end

    local ls_tree_stdout = run_git_command(string.format("git ls-tree -r -l --full-tree %s", hash))
    if not ls_tree_stdout then
        return nil, "Failed to get ls-tree"
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
    local blob, blob_err = run_git_command(blob_command)
    if not blob then
        return nil, "Failed to get blob: " .. (blob_err or "")
    end

    -- Get the diff
    local diff_command = string.format("git diff %s^ %s -- %s", hash, hash, file)
    local diff, diff_err = run_git_command(diff_command)
    if not diff then
        return nil, "Failed to get diff: " .. (diff_err or "")
    end

    -- Compress and encode blob and diff
    local encoded_blob = vim.base64.encode(blob)
    local encoded_diff = vim.base64.encode(diff)

    return {
        blob = encoded_blob,
        diff = encoded_diff,
    }
end

return git
