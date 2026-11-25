-- Run from the resource root: lua5.4 tests/gateway.test.lua
-- Covers server/callbacks.lua (route gateway driven by shared/routes.json) and server/rate_limits.lua
-- against stubbed FiveM natives, kora_lib and handsets.

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write('PASS ', name, '\n')
    else failed = failed + 1; io.stderr:write('FAIL ', name, ': ', tostring(err), '\n') end
end
local function equal(actual, expected, label)
    assert(actual == expected, ('%sexpected %s, got %s'):format(label and (label .. ': ') or '', tostring(expected), tostring(actual)))
end

local script = arg and arg[0] or 'tests/gateway.test.lua'
local root = script:gsub('[\\/]tests[\\/]gateway%.test%.lua$', '')
if root == script then root = '.' end

local function readFile(path)
    local f = assert(io.open(root .. '/' .. path, 'rb'))
    local text = f:read('a')
    f:close()
    return text
end

-- Minimal JSON decoder for routes.json (array of flat objects with string/null values).
local function decodeRoutes(text)
    local routes = {}
    for object in text:gmatch('{(.-)}') do
        local route = {}
        for key, value in object:gmatch('"(%w+)"%s*:%s*("?[^,"]*"?)') do
            route[key] = value == 'null' and nil or value:gsub('"', '')
        end
        routes[#routes + 1] = route
    end
    return routes
end

-- Environment ------------------------------------------------------------------------------------------
local now = 0
local timeouts, errors = {}, {}
local callbacks = {}
local citizen = 'CID1'
_G.GetGameTimer = function() return now end
_G.SetTimeout = function(_, fn) timeouts[#timeouts + 1] = fn end
_G.GetCurrentResourceName = function() return 'kora_phone' end
_G.LoadResourceFile = function(_, path) return readFile(path) end
_G.json = { decode = function() return decodeRoutes(readFile('shared/routes.json')) end }
_G.promise = { new = function()
    local p = {}
    function p:resolve(value) self.value = value end
    return p
end }
_G.Citizen = { Await = function(p) return p.value end }
_G.Kora = {
    callback = { register = function(name, fn) callbacks[name] = fn end },
    logging = { event = function(event) errors[#errors + 1] = event end },
}
_G.Config = {
    Apps = {},
    Handsets = { phone = true },
    Server = { RateLimits = {
        mutation = { capacity = 3, refillPerSecond = 1 },
        read = { capacity = 5, refillPerSecond = 5 },
        sdk = { capacity = 40, refillPerSecond = 10 },
    } },
}
dofile(root .. '/shared/constants.lua')

local lockCalls, clears, backups = 0, {}, 0
local selected = { [1] = 'h1' }
_G.KoraPhone = {
    Services = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end }),
    GetCitizenId = function() return citizen end,
    Handsets = {
        selected = selected,
        current = function() return { handsetId = 'h1' } end,
        clearReset = function(id) clears[#clears + 1] = id end,
        backup = function() backups = backups + 1 return { ok = true } end,
        locked = function(src, fn, payload) lockCalls = lockCalls + 1 return fn(src, payload) end,
    },
}
dofile(root .. '/server/rate_limits.lua')
dofile(root .. '/server/callbacks.lua')
local Routes = KoraPhone.Routes
local PREFIX = 'kora_phone:server:'

local function reset()
    now = 0
    KoraPhone.RateLimits.windows = {}
    lockCalls, clears, backups, errors, timeouts = 0, {}, 0, {}, {}
    citizen = 'CID1'
    selected[1] = 'h1'
    Config.Apps = {}
end

local function call(name, payload)
    return callbacks[PREFIX .. name](1, payload)
end

-- Tests ------------------------------------------------------------------------------------------------
test('every routes.json server name is registered exactly once', function()
    local seen = {}
    for _, route in ipairs(decodeRoutes(readFile('shared/routes.json'))) do
        assert(callbacks[route.server], route.server .. ' not registered')
        seen[route.server] = true
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    assert(count >= 60)
    assert(callbacks[PREFIX .. 'hasPhone'] and callbacks[PREFIX .. 'share:offer'])
end)

test('the sdk routes are registered, the legacy names are not', function()
    for _, name in ipairs({ 'apps:list', 'apps:notify', 'apps:storage:list' }) do
        assert(callbacks[PREFIX .. name], name)
    end
    assert(not callbacks[PREFIX .. 'legacy:getMail'] and not callbacks[PREFIX .. 'acceptLegacyMail'])
    equal(Routes.byName['apps:list'].rate, 'sdk')
end)

test('an unbound route answers INTERNAL and logs', function()
    reset()
    Routes.handlers['getContacts'] = nil
    local result = call('getContacts', {})
    equal(result.ok, false)
    equal(result.error.code, PhoneConstants.Errors.INTERNAL)
    equal(errors[1], 'phone.route_unbound')
end)

test('payload is normalised to a table', function()
    reset()
    local got
    Routes.handle('getContacts', function(_, payload) got = payload return PhoneResult({}) end)
    call('getContacts', 'junk')
    equal(type(got), 'table')
end)

test('rate limit is shared by every route of one bucket, and refills', function()
    reset()
    Routes.handle('lockPhone', function() return PhoneResult({}) end)
    Routes.handle('deleteContact', function() return PhoneResult({}) end)
    equal(call('lockPhone', {}).ok, true)
    equal(call('deleteContact', {}).ok, true)
    equal(call('lockPhone', {}).ok, true)
    local limited = call('deleteContact', {})
    equal(limited.error.code, PhoneConstants.Errors.RATE_LIMITED)
    now = 3001 -- window is capacity / refill = 3 s
    equal(call('lockPhone', {}).ok, true)
end)

test('limits convert burst/refill to max/window and fall back to mutation', function()
    local limit = KoraPhone.RateLimits.limitFor('read')
    equal(limit.max, 5); equal(limit.window, 1000)
    local sdk = KoraPhone.RateLimits.limitFor('sdk')
    equal(sdk.max, 40); equal(sdk.window, 4000)
    equal(KoraPhone.RateLimits.limitFor('nope').max, 3)
end)

test('rate limits are per player and clear() forgets a player', function()
    reset()
    for _ = 1, 3 do assert(KoraPhone.RateLimits.consume(1, 'mutation')) end
    assert(not KoraPhone.RateLimits.consume(1, 'mutation'))
    assert(KoraPhone.RateLimits.consume(2, 'mutation'))
    KoraPhone.RateLimits.clear(1)
    assert(KoraPhone.RateLimits.consume(1, 'mutation'))
end)

test('app gate from routes.json blocks a disabled app before the handler runs', function()
    reset()
    local ran = false
    Routes.handle('social:getFeed', function() ran = true return PhoneResult({}) end)
    Config.Apps = { social = false }
    local result = call('social:getFeed', {})
    equal(result.error.code, PhoneConstants.Errors.FORBIDDEN)
    equal(ran, false)
    Config.Apps = { social = true, flash = false }
    equal(call('social:getFeed', {}).ok, true)
end)

test('ordinary routes run inside the handset lock; handsetAction and lock=false do not', function()
    reset()
    Routes.handle('getContacts', function() return PhoneResult({}) end)
    call('getContacts', {})
    equal(lockCalls, 1)
    Routes.handle('handsetAction', function() return PhoneResult({}) end)
    call('handsetAction', {})
    equal(lockCalls, 1)
    Routes.handle('apps:list', function() return PhoneResult({}) end, { lock = false })
    call('apps:list', {})
    equal(lockCalls, 1)
end)

test('a throwing handler becomes INTERNAL', function()
    reset()
    Routes.handle('getContacts', function() error('boom') end)
    local result = call('getContacts', {})
    equal(result.error.code, PhoneConstants.Errors.INTERNAL)
    equal(errors[1], 'phone.callback_failed')
end)

test('session guard rejects a changed character or handset', function()
    reset()
    Routes.handle('getContacts', function() citizen = 'OTHER' return PhoneResult({}) end)
    equal(call('getContacts', {}).error.code, PhoneConstants.Errors.FORBIDDEN)
    reset()
    Routes.handle('getContacts', function() selected[1] = 'h2' return PhoneResult({}) end)
    equal(call('getContacts', {}).error.code, PhoneConstants.Errors.FORBIDDEN)
end)

test('handsetAction select/reset may change the selected handset', function()
    reset()
    Routes.handle('handsetAction', function() selected[1] = 'h2' return PhoneResult({}) end)
    equal(call('handsetAction', { op = 'select' }).ok, true)
    selected[1] = 'h1'
    equal(call('handsetAction', { op = 'other' }).ok, false)
end)

test('a successful mutation clears reset and schedules a locked backup', function()
    reset()
    Routes.handle('lockPhone', function() return PhoneResult({}) end)
    call('lockPhone', {})
    equal(clears[1], 'h1')
    equal(#timeouts, 1)
    timeouts[1]()
    equal(backups, 1)
    reset()
    Routes.handle('getContacts', function() return PhoneResult({}) end)
    call('getContacts', {})
    equal(#clears, 0)
end)

test('async routes reply through the callback and skip the handset lock', function()
    reset()
    Routes.handle('requestMediaUpload', function(_, _, reply) reply(PhoneResult({ token = 't' })) end, { async = true })
    local result = call('requestMediaUpload', {})
    equal(result.ok, true)
    equal(lockCalls, 0)
    Routes.handle('completeMediaUpload', function() error('boom') end, { async = true })
    equal(call('completeMediaUpload', {}).error.code, PhoneConstants.Errors.INTERNAL)
end)

test('sdk routes bind lazily to their module tables', function()
    reset()
    Routes.handle('apps:list', function(s, p)
        return (KoraPhone.SDK.routes['apps:list'])(s, p)
    end, { lock = false })
    KoraPhone.SDK = { routes = { ['apps:list'] = function() return PhoneResult({ apps = {} }) end } }
    -- the real binding in callbacks.lua is lazy: re-run it against the now present table
    dofile(root .. '/server/callbacks.lua')
    equal(call('apps:list', {}).ok, true)
    KoraPhone.SDK = nil
    equal(call('apps:list', {}).ok, false)
end)

test('registerCallback shim binds by name', function()
    reset()
    KoraPhone.registerCallback('getContacts', 'read', function() return PhoneResult({ shim = true }) end)
    equal(call('getContacts', {}).data.shim, true)
end)

io.write(('\ngateway: %d passed, %d failed\n'):format(passed, failed))
if failed > 0 then os.exit(1) end
