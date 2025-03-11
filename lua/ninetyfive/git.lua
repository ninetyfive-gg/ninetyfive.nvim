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

return git
