local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
        end,
        post_once = child.stop,
    },
})

local function eval_lua(code)
    return child.lua_get(code)
end

local function setup_diff()
    child.lua([[
        _G.diff = require("ninetyfive.diff")
    ]])
end

-- ============ Empty cases ============

T["empty buffer - entire completion is ghost text"] = function()
    setup_diff()

    child.lua([[
        local result = diff.calculate_diff("hello", "", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(#result.edits, 1)
    MiniTest.expect.equality(result.edits[1].type, "ghost")
    MiniTest.expect.equality(result.edits[1].text, "hello")
    MiniTest.expect.equality(result.edits[1].offset, 0)
end

T["empty completion streaming - no edits"] = function()
    setup_diff()

    child.lua([[
        local result = diff.calculate_diff("", "existing", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(#result.edits, 0)
end

T["empty completion complete - marks buffer for deletion"] = function()
    setup_diff()

    child.lua([[
        local result = diff.calculate_diff("", "existing", true)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(#result.edits, 1)
    MiniTest.expect.equality(result.edits[1].type, "delete")
    MiniTest.expect.equality(result.edits[1].text, "existing")
end

T["both empty - no edits"] = function()
    setup_diff()

    child.lua([[
        local result = diff.calculate_diff("", "", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(#result.edits, 0)
end

-- ============ Exact match cases ============

T["exact match - only match edits"] = function()
    setup_diff()

    child.lua([[
        local result = diff.calculate_diff("hello", "hello", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")
    -- Should have 5 match edits (one per character)
    local match_count = 0
    for _, edit in ipairs(result.edits) do
        if edit.type == "match" then
            match_count = match_count + 1
        end
    end
    MiniTest.expect.equality(match_count, 5)

    -- No ghost or delete edits
    local ghost_count = 0
    local delete_count = 0
    for _, edit in ipairs(result.edits) do
        if edit.type == "ghost" then
            ghost_count = ghost_count + 1
        elseif edit.type == "delete" then
            delete_count = delete_count + 1
        end
    end
    MiniTest.expect.equality(ghost_count, 0)
    MiniTest.expect.equality(delete_count, 0)
end

-- ============ Partial match cases ============

T["partial match - ghost text for gap"] = function()
    setup_diff()

    -- completion: "getName", buffer: "get"
    -- Should match g-e-t, then ghost "Name"
    child.lua([[
        local result = diff.calculate_diff("getName", "get", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")

    local ghost_text = ""
    for _, edit in ipairs(result.edits) do
        if edit.type == "ghost" then
            ghost_text = ghost_text .. edit.text
        end
    end
    MiniTest.expect.equality(ghost_text, "Name")
end

T["interleaved insertions"] = function()
    setup_diff()

    -- completion: "axbyc", buffer: "xy"
    -- Should match x at pos 1, y at pos 3
    -- Ghost: "a" before x, "b" before y, "c" after y
    child.lua([[
        local result = diff.calculate_diff("axbyc", "xy", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")

    local ghosts = {}
    for _, edit in ipairs(result.edits) do
        if edit.type == "ghost" then
            table.insert(ghosts, { offset = edit.offset, text = edit.text })
        end
    end

    MiniTest.expect.equality(#ghosts, 3)
    MiniTest.expect.equality(ghosts[1].text, "a")
    MiniTest.expect.equality(ghosts[1].offset, 0)
    MiniTest.expect.equality(ghosts[2].text, "b")
    MiniTest.expect.equality(ghosts[2].offset, 1)
    MiniTest.expect.equality(ghosts[3].text, "c")
    MiniTest.expect.equality(ghosts[3].offset, 2)
end

-- ============ Levenshtein example from discussion ============

T["levenshtein example - shtein_distance vs shtein()"] = function()
    setup_diff()

    -- completion: "shtein_distance()", buffer: "shtein()"
    -- Should match s-h-t-e-i-n, insert "_distance" before "(", then match "()"
    child.lua([[
        local result = diff.calculate_diff("shtein_distance()", "shtein()", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")

    local ghost_text = ""
    for _, edit in ipairs(result.edits) do
        if edit.type == "ghost" then
            ghost_text = ghost_text .. edit.text
        end
    end
    MiniTest.expect.equality(ghost_text, "_distance")

    -- No deletions in streaming mode
    local has_delete = false
    for _, edit in ipairs(result.edits) do
        if edit.type == "delete" then
            has_delete = true
        end
    end
    MiniTest.expect.equality(has_delete, false)
end

T["levenshtein without parens - streaming no delete"] = function()
    setup_diff()

    -- completion: "shtein_distance", buffer: "shtein()"
    -- Should match s-h-t-e-i-n, insert "_distance", "()" unmatched
    -- Streaming: no delete marker
    child.lua([[
        local result = diff.calculate_diff("shtein_distance", "shtein()", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")

    local ghost_text = ""
    for _, edit in ipairs(result.edits) do
        if edit.type == "ghost" then
            ghost_text = ghost_text .. edit.text
        end
    end
    MiniTest.expect.equality(ghost_text, "_distance")

    -- No deletions in streaming mode
    local has_delete = false
    for _, edit in ipairs(result.edits) do
        if edit.type == "delete" then
            has_delete = true
        end
    end
    MiniTest.expect.equality(has_delete, false)
end

T["levenshtein without parens - complete has delete"] = function()
    setup_diff()

    -- completion: "shtein_distance", buffer: "shtein()"
    -- Complete mode: "()" should be marked for deletion
    child.lua([[
        local result = diff.calculate_diff("shtein_distance", "shtein()", true)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")

    local delete_text = ""
    for _, edit in ipairs(result.edits) do
        if edit.type == "delete" then
            delete_text = delete_text .. edit.text
        end
    end
    MiniTest.expect.equality(delete_text, "()")
end

-- ============ No matching chars ============

T["no matching chars - streaming"] = function()
    setup_diff()

    -- completion: "abc", buffer: "xyz"
    -- No chars match, ghost text at start, no delete
    child.lua([[
        local result = diff.calculate_diff("abc", "xyz", false)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")

    local ghost_text = ""
    for _, edit in ipairs(result.edits) do
        if edit.type == "ghost" then
            ghost_text = ghost_text .. edit.text
        end
    end
    MiniTest.expect.equality(ghost_text, "abc")

    -- No deletions in streaming
    local has_delete = false
    for _, edit in ipairs(result.edits) do
        if edit.type == "delete" then
            has_delete = true
        end
    end
    MiniTest.expect.equality(has_delete, false)
end

T["no matching chars - complete"] = function()
    setup_diff()

    -- completion: "abc", buffer: "xyz"
    -- Complete: ghost "abc" and delete "xyz"
    child.lua([[
        local result = diff.calculate_diff("abc", "xyz", true)
        _G.result = result
    ]])

    local result = eval_lua("_G.result")

    local ghost_text = ""
    local delete_text = ""
    for _, edit in ipairs(result.edits) do
        if edit.type == "ghost" then
            ghost_text = ghost_text .. edit.text
        elseif edit.type == "delete" then
            delete_text = delete_text .. edit.text
        end
    end
    MiniTest.expect.equality(ghost_text, "abc")
    MiniTest.expect.equality(delete_text, "xyz")
end

-- ============ Helper functions ============

T["get_ghost_text returns combined ghost text"] = function()
    setup_diff()

    child.lua([[
        local result = diff.calculate_diff("axbyc", "xy", false)
        _G.ghost = diff.get_ghost_text(result)
    ]])

    local ghost = eval_lua("_G.ghost")
    MiniTest.expect.equality(ghost, "abc")
end

T["has_deletions returns true when deletions exist"] = function()
    setup_diff()

    child.lua([[
        local result = diff.calculate_diff("abc", "xyz", true)
        _G.has_del = diff.has_deletions(result)
    ]])

    local has_del = eval_lua("_G.has_del")
    MiniTest.expect.equality(has_del, true)
end

T["has_deletions returns false in streaming mode"] = function()
    setup_diff()

    child.lua([[
        local result = diff.calculate_diff("abc", "xyz", false)
        _G.has_del = diff.has_deletions(result)
    ]])

    local has_del = eval_lua("_G.has_del")
    MiniTest.expect.equality(has_del, false)
end

return T
