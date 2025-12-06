-- Test highlighting module
-- Run with: nvim --headless --cmd "set rtp+=." -c "luafile tests/test_highlighting.lua" -c "qa!"

_G.Ninetyfive = { config = { debug = false } }

local highlighting = require("ninetyfive.highlighting")

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, vim.inspect(expected), vim.inspect(actual)))
    end
end

local function assert_true(value, message)
    if not value then
        error(string.format("%s: expected truthy value, got %s", message, vim.inspect(value)))
    end
end

local function test_setup_creates_highlight()
    pcall(vim.api.nvim_set_hl, 0, "NinetyFiveGhost", {})
    highlighting.setup()
    local hl = vim.api.nvim_get_hl(0, { name = "NinetyFiveGhost" })

    assert_true(hl.fg or hl.ctermfg, "NinetyFiveGhost should have fg or ctermfg")
    assert_eq(hl.italic, true, "NinetyFiveGhost should be italic")
    print("PASS: test_setup_creates_highlight")
end

local function test_highlight_completion_format()
    local result = highlighting.highlight_completion("test", 0)

    assert_eq(type(result), "table", "Result should be a table")
    assert_true(#result >= 1, "Result should have at least one line")
    assert_eq(type(result[1][1]), "table", "Each line should contain segments")
    assert_eq(result[1][1][1], "test", "First segment text should be 'test'")
    print("PASS: test_highlight_completion_format")
end

local function test_highlight_completion_empty()
    local result = highlighting.highlight_completion("", 0)

    assert_eq(#result, 1, "Result should have one line")
    assert_eq(result[1][1][1], "", "Empty input should return empty text")
    print("PASS: test_highlight_completion_empty")
end

local function test_highlight_completion_multiline()
    local result = highlighting.highlight_completion("a\nb\nc", 0)

    assert_eq(#result, 3, "Should return 3 lines")
    assert_eq(result[1][1][1], "a", "First line")
    assert_eq(result[2][1][1], "b", "Second line")
    assert_eq(result[3][1][1], "c", "Third line")
    print("PASS: test_highlight_completion_multiline")
end

local function test_extmark_integration()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local ns = vim.api.nvim_create_namespace("test_ns")

    highlighting.setup()
    vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
        virt_text = { { "ghost", "NinetyFiveGhost" } },
    })

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    assert_eq(#marks, 1, "Should have one extmark")

    vim.api.nvim_buf_delete(bufnr, { force = true })
    print("PASS: test_extmark_integration")
end

local function test_clear_cache()
    highlighting.setup()
    highlighting.clear_cache()
    print("PASS: test_clear_cache")
end

local function test_blended_color_is_dimmer()
    -- Set a known background
    vim.api.nvim_set_hl(0, "Normal", { bg = 0x000000 })
    -- Set Comment to bright white
    vim.api.nvim_set_hl(0, "Comment", { fg = 0xffffff })

    highlighting.clear_cache()
    highlighting.setup()

    local hl = vim.api.nvim_get_hl(0, { name = "NinetyFiveGhost" })
    -- With 60% opacity blending white (0xffffff) with black (0x000000),
    -- result should be around 0x999999 (153, 153, 153)
    if hl.fg then
        assert_true(hl.fg < 0xffffff, "Blended color should be dimmer than original")
        assert_true(hl.fg > 0x000000, "Blended color should not be fully black")
    end
    print("PASS: test_blended_color_is_dimmer")
end

-- Run tests
print("=== Running highlighting tests ===")
local tests = {
    test_setup_creates_highlight,
    test_highlight_completion_format,
    test_highlight_completion_empty,
    test_highlight_completion_multiline,
    test_extmark_integration,
    test_clear_cache,
    test_blended_color_is_dimmer,
}

local passed, failed = 0, 0
for _, test in ipairs(tests) do
    local ok, err = pcall(test)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. tostring(err))
    end
end

print(string.format("=== %d passed, %d failed ===", passed, failed))
if failed > 0 then
    vim.cmd("cq 1")
end
