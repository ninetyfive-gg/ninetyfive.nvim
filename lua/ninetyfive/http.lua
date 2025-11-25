local log = require("ninetyfive.util.log")

local M = {
    using_libcurl = false,
    reason = nil,
    _post_impl = nil,
}

local ok_ffi, ffi = pcall(require, "ffi")

-- Try loading libcurl via LuaJIT FFI so we can reuse TLS sessions between requests.
-- Falls back to spawning the curl CLI if FFI/libcurl is unavailable.
local curl
if ok_ffi then
    local lib_names = {
        "libcurl.so.4",
        "libcurl.so",
        "libcurl.4.dylib",
        "libcurl.dylib",
        "libcurl.dll",
        "libcurl-4.dll",
        "libcurl-x64.dll",
        "curl",
    }

    ffi.cdef([[
    typedef void CURL;
    typedef void CURLSH;
    typedef int CURLcode;
    typedef int CURLINFO;
    typedef int CURLSHcode;
    typedef int CURLSHoption;
    typedef int curl_socket_t;
    typedef size_t (*curl_write_callback)(char *ptr, size_t size, size_t nmemb, void *userdata);

    struct curl_slist {
        char *data;
        struct curl_slist *next;
    };

    CURLcode curl_global_init(long flags);
    void curl_global_cleanup(void);
    const char *curl_easy_strerror(CURLcode);

    CURL *curl_easy_init(void);
    CURLcode curl_easy_setopt(CURL *curl, int option, ...);
    CURLcode curl_easy_perform(CURL *curl);
    CURLcode curl_easy_getinfo(CURL *curl, CURLINFO info, ...);
    void curl_easy_cleanup(CURL *curl);

    struct curl_slist *curl_slist_append(struct curl_slist *list, const char *data);
    void curl_slist_free_all(struct curl_slist *list);

    CURLSH *curl_share_init(void);
    CURLSHcode curl_share_setopt(CURLSH *sh, CURLSHoption option, ...);
    CURLSHcode curl_share_cleanup(CURLSH *sh);
    ]])

    local function try_load()
        for _, name in ipairs(lib_names) do
            local ok, lib = pcall(ffi.load, name)
            if ok then
                return lib
            end
        end
        return nil, "libcurl not found in search paths"
    end

    curl, M.reason = try_load()

    if curl then
        -- Copied numeric constants from curl/curl.h to avoid relying on headers at runtime.
        local CURL_GLOBAL_DEFAULT = 3

        local CURLOPT_URL = 10002
        local CURLOPT_POSTFIELDS = 10015
        local CURLOPT_COPYPOSTFIELDS = 10165
        local CURLOPT_POSTFIELDSIZE = 60
        local CURLOPT_HTTPHEADER = 10023
        local CURLOPT_USERAGENT = 10018
        local CURLOPT_FOLLOWLOCATION = 52
        local CURLOPT_NOSIGNAL = 99
        local CURLOPT_TCP_KEEPALIVE = 213
        local CURLOPT_WRITEFUNCTION = 20011
        local CURLOPT_WRITEDATA = 10001
        local CURLOPT_ACCEPT_ENCODING = 10102
        local CURLOPT_SHARE = 10100

        local CURLINFO_RESPONSE_CODE = 0x200002

        local CURLSHOPT_SHARE = 1
        local CURL_LOCK_DATA_SSL_SESSION = 4

        local global_inited = curl.curl_global_init(CURL_GLOBAL_DEFAULT) == 0
        local shared_handle = global_inited and curl.curl_share_init() or nil
        if shared_handle then
            curl.curl_share_setopt(shared_handle, CURLSHOPT_SHARE, CURL_LOCK_DATA_SSL_SESSION)
        else
            M.reason = "failed to init curl share handle"
        end

        local easy = (global_inited and curl.curl_easy_init()) or nil

        local response_buffer = {}
        local write_cb = ffi.cast("curl_write_callback", function(ptr, size, nmemb, _)
            local bytes = tonumber(size * nmemb)
            if bytes > 0 then
                table.insert(response_buffer, ffi.string(ptr, bytes))
            end
            return bytes
        end)

        local function with_headers(header_tbl)
            local list = nil
            for _, h in ipairs(header_tbl) do
                list = curl.curl_slist_append(list, h)
            end
            return list
        end

        local function cleanup_headers(list)
            if list ~= nil then
                curl.curl_slist_free_all(list)
            end
        end

        local function post_with_libcurl(url, headers, body)
            if not (global_inited and shared_handle and easy) then
                return false, nil, "libcurl not initialized"
            end

            response_buffer = {}

            local header_list = with_headers(headers)

            curl.curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1)
            curl.curl_easy_setopt(easy, CURLOPT_TCP_KEEPALIVE, 1)
            curl.curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1)
            curl.curl_easy_setopt(easy, CURLOPT_URL, url)
            curl.curl_easy_setopt(easy, CURLOPT_USERAGENT, "ninetyfive.nvim")
            curl.curl_easy_setopt(easy, CURLOPT_HTTPHEADER, header_list)
            curl.curl_easy_setopt(easy, CURLOPT_ACCEPT_ENCODING, "")
            curl.curl_easy_setopt(easy, CURLOPT_COPYPOSTFIELDS, body)
            curl.curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, write_cb)
            curl.curl_easy_setopt(easy, CURLOPT_WRITEDATA, nil)
            curl.curl_easy_setopt(easy, CURLOPT_SHARE, shared_handle)

            local res = curl.curl_easy_perform(easy)

            local status = ffi.new("long[1]")
            curl.curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, status)

            cleanup_headers(header_list)

            if res ~= 0 then
                local err = ffi.string(curl.curl_easy_strerror(res))
                return false, tonumber(status[0]), err
            end

            return true, tonumber(status[0]), table.concat(response_buffer)
        end

        if global_inited and shared_handle and easy then
            M._post_impl = post_with_libcurl
            M.using_libcurl = true
            M.reason = nil
        end
    end
else
    M.reason = "LuaJIT FFI unavailable"
end

local function shell_post(url, headers, body)
    if vim.fn.executable("curl") ~= 1 then
        return false, nil, "curl executable not found"
    end

    local cmd = { "curl", "-sS", "-X", "POST", url, "-w", "%{http_code}" }
    for _, h in ipairs(headers) do
        table.insert(cmd, "-H")
        table.insert(cmd, h)
    end

    table.insert(cmd, "--data")
    table.insert(cmd, body)

    local out
    if vim.system then
        local result = vim.system(cmd, { text = true }):wait()
        if not result or result.code ~= 0 or not result.stdout then
            local err = (result and result.stderr) or "curl failed"
            return false, nil, err
        end
        out = result.stdout
    else
        local ok, output = pcall(vim.fn.system, cmd)
        if not ok then
            return false, nil, "curl failed"
        end
        out = output
    end

    local status = tonumber(out:sub(-3))
    if not status then
        return false, nil, "unable to parse curl http status"
    end
    local resp_body = out:sub(1, #out - 3)

    return true, status, resp_body
end

--- POST JSON to a URL. Returns ok, status_code, body_or_error.
---@param url string
---@param headers string[]
---@param body string
---@return boolean, number|nil, string|nil
function M.post_json(url, headers, body)
    local impl = M._post_impl or shell_post
    return impl(url, headers, body)
end

function M.libcurl_available()
    return M.using_libcurl
end

return M
