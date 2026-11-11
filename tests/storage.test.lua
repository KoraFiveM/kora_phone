-- Run outside FiveM with: lua tests/storage.test.lua
-- Exercises the media storage adapter (limits, the Fivemanage upload ticket and its verification) against
-- stubbed FiveM globals. The HTTP layer is faked, so this proves the checks, not the network.

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n")
    else failed = failed + 1; io.stderr:write("FAIL ", name, ": ", tostring(err), "\n") end
end
local function equal(actual, expected) assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual))) end

local script = arg and arg[0] or "tests/storage.test.lua"
local root = script:gsub("[\\/]tests[\\/]storage%.test%.lua$", "")
if root == script then root = "." end

-- ---- stubbed FiveM globals
local convars = {}
function GetConvar(name, default) return convars[name] or default end
local fakes = {}                                   -- "#name" -> decoded table, standing in for JSON bodies
json = { decode = function(text) if type(text) == 'string' and fakes[text] then return fakes[text] end error('bad json') end, encode = function() return '{}' end }
local http = { last = nil, status = 200, body = '#none' }
function PerformHttpRequest(url, callback, method, body, headers)
    http.last = { url = url, method = method, headers = headers }
    callback(http.status, http.body)
end
function SaveResourceFile() return true end
function GetCurrentResourceName() return 'kora_phone' end
function GetResourceState() return 'missing' end

KoraPhone = {}
Config = { Server = { Media = { Provider = 'fivemanage' } } }
dofile(root .. "/server/integrations/storage.lua")
local Storage = KoraPhone.Storage

local function reset(provider, extra)
    Config.Server.Media = { Provider = provider }
    for key, value in pairs(extra or {}) do Config.Server.Media[key] = value end
    convars = { kora_fivemanage_token = 'secret-token' }
    http.status, http.body = 200, '#none'
end
local function result(fn)
    local out
    fn(function(...) out = { ... } end)
    return out
end

local MB = 1024 * 1024
local ticket = function(over)
    local t = { mimeType = 'video/webm', byteSize = 5 * MB, expiresAt = os.time() + 120, token = 'tok', providerData = { tag = 'tag123' } }
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end
local GOOD_FILE = function(over)
    local f = { id = 'abcDEF123456', filename = 'clip.webm', type = 'video/webm', size = 1 * MB, url = 'https://r2.fivemanage.com/abc/clip.webm', metadata = { koraPhoneTicket = 'tag123' } }
    for k, v in pairs(over or {}) do f[k] = v end
    return f
end
local function serve(file, status)
    fakes['#file'] = { status = 'ok', data = file }
    http.status, http.body = status or 200, '#file'
end

test("images are always allowed within their limit; oversized and unknown types are not", function()
    reset('disabled')
    equal(Storage.validateRequest('image/jpeg', 1 * MB), true)
    local ok, why = Storage.validateRequest('image/jpeg', 99 * MB); equal(ok, false); equal(why, 'MEDIA_TOO_LARGE')
    ok, why = Storage.validateRequest('application/pdf', 100); equal(why, 'UNSUPPORTED_MEDIA_TYPE')
end)
test("video is refused by providers that cannot take a file from the phone", function()
    for _, provider in ipairs({ 'disabled', 'local-development' }) do
        reset(provider)
        local ok, why = Storage.validateRequest('video/webm', 1 * MB)
        equal(ok, false); equal(why, 'VIDEO_UNSUPPORTED'); equal(Storage.supportsVideo(), false)
    end
end)
test("video is accepted on fivemanage within its own, larger limit", function()
    reset('fivemanage')
    equal(Storage.supportsVideo(), true)
    equal(Storage.validateRequest('video/webm', 20 * MB), true)
    local ok, why = Storage.validateRequest('video/webm', 30 * MB); equal(ok, false); equal(why, 'MEDIA_TOO_LARGE')
    equal(Storage.maxBytesFor('video/mp4'), 24 * MB); equal(Storage.maxBytesFor('image/png'), 8 * MB)
end)
test("an unknown provider name falls back to disabled", function() reset('ftp'); equal(Storage.provider(), 'disabled') end)

test("begin asks Fivemanage for a presigned URL with the server-only token", function()
    reset('fivemanage')
    fakes['#begin'] = { status = 'ok', data = { presignedUrl = 'https://api.fivemanage.com/api/v3/file/presigned-url/jwt' } }
    http.body = '#begin'
    local r = result(function(cb) Storage.begin(ticket(), cb) end)
    equal(r[1], true)
    equal(r[2].mode, 'direct-upload'); equal(r[2].uploadUrl, 'https://api.fivemanage.com/api/v3/file/presigned-url/jwt'); equal(r[2].field, 'file')
    assert(r[2].tag and #r[2].tag > 10, 'a tag is issued'); equal(r[4].tag, r[2].tag)
    assert(http.last.url:find('/api/v3/file/presigned%-url%?expiresAt=%d+$'), 'expiry is requested')
    equal(http.last.headers.Authorization, 'secret-token'); equal(http.last.method, 'GET')
    assert(r[2].token == 'tok' and r[2].apiToken == nil, 'the API token is never part of the instruction')
end)
test("begin refuses to hand out an upload URL on a host that is not allowlisted", function()
    reset('fivemanage')
    fakes['#evil'] = { data = { presignedUrl = 'https://evil.example.com/steal' } }
    http.body = '#evil'
    local r = result(function(cb) Storage.begin(ticket(), cb) end)
    equal(r[1], false); equal(r[3], 'UPLOAD_HOST_DENIED')
end)
test("begin fails cleanly with no token, and when Fivemanage rejects the request", function()
    reset('fivemanage'); convars = {}
    equal(result(function(cb) Storage.begin(ticket(), cb) end)[3], 'PROVIDER_MISCONFIGURED')
    reset('fivemanage'); http.status = 401
    equal(result(function(cb) Storage.begin(ticket(), cb) end)[3], 'PROVIDER_BEGIN_FAILED')
end)
test("the token can also come from config, but the convar wins", function()
    reset('fivemanage', { Fivemanage = { Token = 'from-config' } }); convars = {}
    fakes['#begin'] = { data = { presignedUrl = 'https://fmapi.net/api/v3/file/presigned-url/x' } }; http.body = '#begin'
    result(function(cb) Storage.begin(ticket(), cb) end); equal(http.last.headers.Authorization, 'from-config')
    convars = { kora_fivemanage_token = 'from-convar' }
    result(function(cb) Storage.begin(ticket(), cb) end); equal(http.last.headers.Authorization, 'from-convar')
end)

test("complete accepts a verified upload and records what Fivemanage reports, not what the phone said", function()
    reset('fivemanage'); serve(GOOD_FILE())
    local r = result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)
    equal(r[1], true); equal(r[2].storageProvider, 'fivemanage'); equal(r[2].storageKey, 'abcDEF123456')
    equal(r[2].byteSize, 1 * MB); equal(r[2].publicUrl, 'https://r2.fivemanage.com/abc/clip.webm'); equal(r[2].mimeType, 'video/webm')
    assert(http.last.url:find('/api/v3/file/abcDEF123456$'), 'the file is looked up by its id')
end)
test("camera photos accept provider categories and JPEG aliases", function()
    for _, kind in ipairs({ 'image', 'image/jpeg', 'jpeg', 'jpg', 'image/webp' }) do
        reset('fivemanage'); serve(GOOD_FILE({ type = kind }))
        local r = result(function(cb) Storage.completeFivemanage(ticket({ mimeType = 'image/jpeg' }), 'abcDEF123456', cb) end)
        equal(r[1], true)
        equal(r[2].mimeType, 'image/jpeg')
    end
    for _, kind in ipairs({ 'video', 'video/webm', 'not-jpeg', 'application/pdf' }) do
        reset('fivemanage'); serve(GOOD_FILE({ type = kind }))
        equal(result(function(cb) Storage.completeFivemanage(ticket({ mimeType = 'image/jpeg' }), 'abcDEF123456', cb) end)[3], 'UPLOAD_MISMATCH')
    end
end)

test("complete rejects a file bigger than the ticket allowed", function()
    reset('fivemanage'); serve(GOOD_FILE({ size = 9 * MB }))
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[3], 'UPLOAD_MISMATCH')
end)
test("complete rejects the wrong kind of file", function()
    reset('fivemanage'); serve(GOOD_FILE({ type = 'image/png' }))
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[3], 'UPLOAD_MISMATCH')
    serve(GOOD_FILE({ type = 'webm' }))   -- a bare subtype is fine
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[1], true)
end)
test("complete rejects a public URL outside the allowlist, but accepts an operator's custom domain", function()
    reset('fivemanage'); serve(GOOD_FILE({ url = 'https://evil.example.com/x.webm', originalUrl = 'https://evil.example.com/y.webm' }))
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[3], 'PUBLIC_HOST_DENIED')
    reset('fivemanage', { AllowedPublicHosts = { 'cdn.myserver.com' } }); serve(GOOD_FILE({ url = 'https://cdn.myserver.com/x.webm' }))
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[1], true)
end)
test("complete rejects a mismatched file id and malformed receipts", function()
    reset('fivemanage'); serve(GOOD_FILE({ id = 'someoneElse123' }))
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[3], 'UPLOAD_NOT_VERIFIED')
    for _, bad in ipairs({ '', 'a/b', '../../etc', 'x', string.rep('a', 65), 'has space!' }) do
        equal(result(function(cb) Storage.completeFivemanage(ticket(), bad, cb) end)[3], 'INVALID_RECEIPT')
    end
    equal(result(function(cb) Storage.completeFivemanage(ticket(), nil, cb) end)[3], 'INVALID_RECEIPT')
end)
test("complete refuses a file whose ticket tag is someone else's", function()
    reset('fivemanage'); serve(GOOD_FILE({ metadata = { koraPhoneTicket = 'other-ticket' } }))
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[3], 'UPLOAD_NOT_BOUND')
end)
test("RequireTag makes an untagged upload fail; otherwise it is allowed", function()
    reset('fivemanage'); serve(GOOD_FILE({ metadata = {} }))
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[1], true)
    reset('fivemanage', { Fivemanage = { RequireTag = true } }); serve(GOOD_FILE({ metadata = {} }))
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[3], 'UPLOAD_NOT_BOUND')
end)
test("a Fivemanage error or an unreadable answer fails verification", function()
    reset('fivemanage'); serve(GOOD_FILE(), 404)
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[3], 'UPLOAD_NOT_VERIFIED')
    http.status, http.body = 200, 'not-json'
    equal(result(function(cb) Storage.completeFivemanage(ticket(), 'abcDEF123456', cb) end)[3], 'UPLOAD_NOT_VERIFIED')
end)
test("deleting a Fivemanage record just forgets it (their API has no delete)", function()
    reset('fivemanage')
    equal(result(function(cb) Storage.delete({ storageProvider = 'fivemanage', storageKey = 'abc' }, cb) end)[1], true)
end)

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end