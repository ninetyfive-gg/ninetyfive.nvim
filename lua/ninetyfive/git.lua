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

local function parse_diff_numstat(output)
    local files = {}
    for line in output:gmatch("[^\r\n]+") do
        local additions, deletions, file = line:match("(%d+)%s+(%d+)%s+(.+)")
        if additions and deletions and file then
            table.insert(files, {
                additions = tonumber(additions),
                deletions = tonumber(deletions),
                to = file,
            })
        end
    end
    return files
end

-- Parse `git ls-tree` output
local function parse_ls_tree(output)
    local files = {}
    for line in output:gmatch("[^\r\n]+") do
        local mode, type, hash, size, file = line:match("(%d+)%s+(%w+)%s+(%x+)%s+(%d+)%s+(.+)")
        if mode and type and hash and size and file then
            table.insert(files, {
                mode = mode,
                type = type,
                hash = hash,
                size = tonumber(size),
                file = file,
            })
        end
    end
    return files
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

-- Get commit details
function git.get_commit(repo_path, commit_hash)
    -- Run `git show --numstat` to get diff statistics
    local diff_output = run_git_command(
        string.format("cd %s && git show --numstat %s", repo_path, commit_hash)
    ) or ""
    local diff = parse_diff_numstat(diff_output)

    -- Run `git show --format=%P%n%B` to get commit metadata
    local commit_output = run_git_command(
        string.format("cd %s && git show --format=%%P%%n%%B --quiet %s", repo_path, commit_hash)
    ) or ""
    local parents, message = commit_output:match("([^\n]*)\n(.*)")
    parents = parents and vim.split(parents, " ") or {}

    -- Run `git ls-tree` to get file details
    local ls_tree_output = run_git_command(
        string.format("cd %s && git ls-tree -r -l --full-tree %s", repo_path, commit_hash)
    ) or ""
    local ls_tree = parse_ls_tree(ls_tree_output)

    -- Match diff files with ls-tree details
    local files = {}
    for _, file in ipairs(diff) do
        for _, ls_file in ipairs(ls_tree) do
            if ls_file.file == file.to then
                table.insert(files, vim.tbl_extend("force", file, ls_file))
                break
            end
        end
    end

    return {
        parents = parents,
        message = message,
        files = files,
    }
end

return git
