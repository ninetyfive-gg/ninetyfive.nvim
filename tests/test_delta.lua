local Helpers = dofile("tests/helpers.lua")

local child = Helpers.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            child.lua([[_G.delta = require("ninetyfive.delta")]])
        end,
        post_once = child.stop,
    },
})

-- ============ Basic insertions ============

T["insert at end"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("hello", "hello world")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 5)
    MiniTest.expect.equality(r.end_pos, 5)
    MiniTest.expect.equality(r.text, " world")
end

T["insert at start"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("world", "hello world")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 0)
    MiniTest.expect.equality(r.end_pos, 0)
    MiniTest.expect.equality(r.text, "hello ")
end

T["insert in middle"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("helloworld", "hello world")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 5)
    MiniTest.expect.equality(r.end_pos, 5)
    MiniTest.expect.equality(r.text, " ")
end

-- ============ Basic deletions ============

T["delete from end"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("hello world", "hello")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 5)
    MiniTest.expect.equality(r.end_pos, 11)
    MiniTest.expect.equality(r.text, "")
end

T["delete from start"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("hello world", "world")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 0)
    MiniTest.expect.equality(r.end_pos, 6)
    MiniTest.expect.equality(r.text, "")
end

T["delete from middle"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("hello world", "helloworld")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 5)
    MiniTest.expect.equality(r.end_pos, 6)
    MiniTest.expect.equality(r.text, "")
end

-- ============ Replacements ============

T["replace single char"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("hello", "hallo")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 1)
    MiniTest.expect.equality(r.end_pos, 2)
    MiniTest.expect.equality(r.text, "a")
end

T["replace multiple chars"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("hello world", "hello there")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 6)
    MiniTest.expect.equality(r.end_pos, 11)
    MiniTest.expect.equality(r.text, "there")
end

-- ============ Edge cases ============

T["identical strings"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("hello", "hello")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 5)
    MiniTest.expect.equality(r.end_pos, 5)
    MiniTest.expect.equality(r.text, "")
end

T["empty to non-empty"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("", "hello")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 0)
    MiniTest.expect.equality(r.end_pos, 0)
    MiniTest.expect.equality(r.text, "hello")
end

T["non-empty to empty"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("hello", "")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 0)
    MiniTest.expect.equality(r.end_pos, 5)
    MiniTest.expect.equality(r.text, "")
end

T["both empty"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("", "")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 0)
    MiniTest.expect.equality(r.end_pos, 0)
    MiniTest.expect.equality(r.text, "")
end

-- ============ Multiline ============

T["insert newline"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("line1line2", "line1\nline2")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 5)
    MiniTest.expect.equality(r.end_pos, 5)
    MiniTest.expect.equality(r.text, "\n")
end

T["delete newline"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("line1\nline2", "line1line2")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 5)
    MiniTest.expect.equality(r.end_pos, 6)
    MiniTest.expect.equality(r.text, "")
end

T["add new line at end"] = function()
    child.lua([[
        local start, end_pos, text = delta.compute_delta("line1", "line1\nline2")
        _G.result = { start = start, end_pos = end_pos, text = text }
    ]])
    local r = child.lua_get("_G.result")
    MiniTest.expect.equality(r.start, 5)
    MiniTest.expect.equality(r.end_pos, 5)
    MiniTest.expect.equality(r.text, "\nline2")
end

return T
