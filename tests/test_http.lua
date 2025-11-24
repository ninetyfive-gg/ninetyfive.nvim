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

local function reset_http_module()
    child.lua([[
        package.loaded["ninetyfive.http"] = nil
        _G.http = require("ninetyfive.http")
    ]])
end

T["uses custom implementation when provided"] = function()
    reset_http_module()

    child.lua([[
        http._post_impl = function(url, headers, body)
            return true, 200, table.concat({url, headers[1], body}, "|")
        end
        http.using_libcurl = true
        local ok, status, body = http.post_json("http://example", { "h:1" }, "payload")
        _G.result = { ok = ok, status = status, body = body }
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(result.ok, true)
    MiniTest.expect.equality(result.status, 200)
    MiniTest.expect.equality(result.body, "http://example|h:1|payload")
end

T["falls back to curl shell when libcurl disabled"] = function()
    reset_http_module()

    child.lua([[
        local original_system = vim.system
        local original_exec = vim.fn.executable

        http._post_impl = nil
        http.using_libcurl = false

        vim.fn.executable = function(bin)
            if bin == "curl" then
                return 1
            end
            return original_exec(bin)
        end

        vim.system = function(cmd, opts)
            return {
                wait = function()
                    return { code = 0, stdout = "pong201", stderr = "" }
                end,
            }
        end

        local ok, status, body = http.post_json("http://example", { "h:1" }, "payload")
        _G.result = { ok = ok, status = status, body = body }

        -- restore
        vim.system = original_system
        vim.fn.executable = original_exec
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(result.ok, true)
    MiniTest.expect.equality(result.status, 201)
    MiniTest.expect.equality(result.body, "pong")
end

T["returns error when curl missing"] = function()
    reset_http_module()

    child.lua([[
        local original_exec = vim.fn.executable

        http._post_impl = nil
        http.using_libcurl = false

        vim.fn.executable = function()
            return 0
        end

        local ok, status, body = http.post_json("http://example", {}, "payload")
        _G.result = { ok = ok, status = status, body = body }

        vim.fn.executable = original_exec
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(result.ok, false)
    MiniTest.expect.equality(result.status, nil)
end

T["returns error on unparsable curl status"] = function()
    reset_http_module()

    child.lua([[
        local original_system = vim.system
        local original_exec = vim.fn.executable

        http._post_impl = nil
        http.using_libcurl = false

        vim.fn.executable = function()
            return 1
        end

        vim.system = function()
            return {
                wait = function()
                    return { code = 0, stdout = "bad-output", stderr = "" }
                end,
            }
        end

        local ok, status, body = http.post_json("http://example", {}, "payload")
        _G.result = { ok = ok, status = status, body = body }

        vim.system = original_system
        vim.fn.executable = original_exec
    ]])

    local result = eval_lua("_G.result")
    MiniTest.expect.equality(result.ok, false)
    MiniTest.expect.equality(result.status, nil)
end

T["libcurl flag reflects availability"] = function()
    reset_http_module()
    local has_libcurl = eval_lua("http.libcurl_available()")
    MiniTest.expect.equality(type(has_libcurl), "boolean")
end

return T
