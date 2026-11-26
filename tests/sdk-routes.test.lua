-- lua tests/sdk-routes.test.lua  (from the resource root): gate, install, callbacks, apps:* routes
local H = dofile((arg and arg[0] or 'tests/x'):gsub('[^/\\]+$', '') .. 'sdk-helper.lua')
local test, equal = H.test, H.equal

local env, routes
local function setup(manifestOverrides)
    env = H.newServer()
    env.player = { job = { name = 'police', grade = { level = 2 } } }
    env.resources.app_res = { state = 'started', meta = { files = { 'ui/*' } }, files = {} }
    assert(env.exports.RegisterApp(H.manifest(manifestOverrides)))
    routes = KoraPhone.SDK.routes
    -- in-memory storage
    local store = {}
    KoraPhone.SDK.StorageRepository = {
        get = function(d, a, k) return store[d .. a .. k] end,
        size = function(d, a, k) return store[d .. a .. k] and #store[d .. a .. k] end,
        usage = function() return { keys = 0, bytes = 0 } end,
        set = function(d, a, k, v) store[d .. a .. k] = v return true end,
        remove = function(d, a, k) store[d .. a .. k] = nil return true end,
        list = function(d, a, prefix)
            local rows = {}
            for key, value in pairs(store) do
                local k = key:sub(#(d .. a) + 1)
                if k:sub(1, #(prefix or '')) == (prefix or '') then rows[#rows + 1] = { key = k, value = value } end
            end
            return rows
        end,
    }
    env.store = store
end

local function code(result) return result.error and result.error.code end

test('every contract route is exposed for the gateway', function()
    setup()
    for _, name in ipairs({ 'apps:list', 'apps:install', 'apps:uninstall', 'apps:call', 'apps:storage:get',
        'apps:storage:set', 'apps:storage:list', 'apps:storage:remove', 'apps:contacts:list', 'apps:contacts:save', 'apps:notify' }) do
        equal(type(routes[name]), 'function', name)
    end
end)

test('apps:list returns registered apps with url and install state', function()
    setup()
    local result = routes['apps:list'](1, {})
    equal(result.ok, true)
    local app = result.data.apps[1]
    equal(app.id, 'demo-app')
    equal(app.installed, true) -- defaultInstalled
    equal(app.url, 'https://cfx-nui-app_res/ui/index.html')
end)

test('apps:list hides job-gated apps from other jobs unless installed', function()
    setup({ job = { name = 'ems' }, defaultInstalled = false })
    equal(#routes['apps:list'](1).data.apps, 0)
    env.player.job = { name = 'ems', grade = { level = 1 } }
    equal(#routes['apps:list'](1).data.apps, 1)
end)

test('every route refuses a locked phone', function()
    setup()
    env.deviceError = PhoneError('FORBIDDEN', 'Phone is locked')
    for name, fn in pairs(routes) do
        equal(code(fn(1, { app = 'demo-app', id = 'demo-app', name = 'x', key = 'k', value = 1, title = 't' })), 'FORBIDDEN', name)
    end
end)

-- Rate limiting is charged once, by the gateway (apps:* routes use the `sdk` bucket in
-- server/callbacks.lua) and by Kora.callback's rateLimit option for per-app callbacks.
-- The route handlers must not charge it a second time.
test('route handlers do not charge the rate limiter themselves', function()
    setup()
    env.limited = true
    for name, fn in pairs(routes) do
        local result = fn(1, { app = 'demo-app', id = 'demo-app', name = 'x', key = 'k', value = 1, title = 't' })
        assert(code(result) ~= 'RATE_LIMITED', name .. ' charged the limiter itself')
    end
end)

test('apps:storage:list returns the keys under a prefix and honours the storage permission', function()
    setup()
    equal(routes['apps:storage:set'](1, { app = 'demo-app', key = 'note:1', value = { t = 'a' } }).ok, true)
    equal(routes['apps:storage:set'](1, { app = 'demo-app', key = 'note:2', value = { t = 'b' } }).ok, true)
    equal(routes['apps:storage:set'](1, { app = 'demo-app', key = 'other', value = 1 }).ok, true)
    local listed = routes['apps:storage:list'](1, { app = 'demo-app', prefix = 'note:' })
    equal(listed.ok, true)
    equal(listed.data.values['note:1'].t, 'a')
    equal(listed.data.values['note:2'].t, 'b')
    equal(listed.data.values['other'], nil)
    equal(code(routes['apps:storage:list'](1, { app = 'demo-app', prefix = 'bad prefix!' })), 'INVALID_INPUT')
end)

test('unknown or malformed app ids are NOT_FOUND', function()
    setup()
    equal(code(routes['apps:storage:get'](1, { app = 'ghost', key = 'k' })), 'NOT_FOUND')
    equal(code(routes['apps:storage:get'](1, { app = 42, key = 'k' })), 'NOT_FOUND')
    equal(code(routes['apps:storage:get'](1, nil)), 'NOT_FOUND')
    equal(code(routes['apps:install'](1, { id = 'ghost' })), 'NOT_FOUND')
end)

test('an app that is not installed on the device is refused', function()
    setup({ defaultInstalled = false })
    equal(code(routes['apps:storage:get'](1, { app = 'demo-app', key = 'k' })), 'FORBIDDEN')
    assert(routes['apps:install'](1, { id = 'demo-app' }).ok)
    assert(routes['apps:storage:set'](1, { app = 'demo-app', key = 'k', value = 1 }).ok)
end)

test('install state is stored in device settings under sdkApps', function()
    setup({ defaultInstalled = false })
    routes['apps:install'](1, { id = 'demo-app' })
    local saved = json.decode(env.settingsWrites[#env.settingsWrites].json)
    equal(saved.sdkApps['demo-app'], true)
    routes['apps:uninstall'](1, { id = 'demo-app' })
    equal(json.decode(env.device.settingsJson).sdkApps['demo-app'], false)
    equal(#env.exports.GetInstalledApps(1), 0)
end)

test('a default app can be uninstalled and stays uninstalled', function()
    setup()
    routes['apps:uninstall'](1, { id = 'demo-app' })
    equal(routes['apps:list'](1).data.apps[1].installed, false)
    equal(code(routes['apps:storage:get'](1, { app = 'demo-app', key = 'k' })), 'FORBIDDEN')
end)

test('GetInstalledApps lists installed registered apps', function()
    setup()
    equal(env.exports.GetInstalledApps(1)[1], 'demo-app')
end)

test('Install.preserve copies sdkApps into replacement settings', function()
    setup()
    local settings = KoraPhone.SDK.Install.preserve('{"sdkApps":{"a":true},"x":1}', { volume = 3 })
    equal(settings.sdkApps.a, true)
    equal(settings.volume, 3)
    equal(KoraPhone.SDK.Install.preserve('garbage', { v = 1 }).sdkApps, nil)
end)

test('permissions are enforced from the registered manifest', function()
    setup({ permissions = { 'notify' } })
    equal(code(routes['apps:storage:set'](1, { app = 'demo-app', key = 'k', value = 1 })), 'FORBIDDEN')
    equal(code(routes['apps:contacts:list'](1, { app = 'demo-app' })), 'FORBIDDEN')
    equal(code(routes['apps:contacts:save'](1, { app = 'demo-app', name = 'A', number = '555' })), 'FORBIDDEN')
    assert(routes['apps:notify'](1, { app = 'demo-app', title = 'Hi' }).ok)
end)

test('client-supplied permission claims are ignored', function()
    setup({ permissions = {} })
    local result = routes['apps:storage:set'](1, { app = 'demo-app', key = 'k', value = 1, permissions = { 'storage' } })
    equal(code(result), 'FORBIDDEN')
end)

test('storage routes round-trip and validate', function()
    setup()
    assert(routes['apps:storage:set'](1, { app = 'demo-app', key = 'k', value = { n = 1 } }).ok)
    equal(routes['apps:storage:get'](1, { app = 'demo-app', key = 'k' }).data.value.n, 1)
    equal(code(routes['apps:storage:set'](1, { app = 'demo-app', key = 'bad key', value = 1 })), 'INVALID_INPUT')
    assert(routes['apps:storage:remove'](1, { app = 'demo-app', key = 'k' }).ok)
    equal(routes['apps:storage:get'](1, { app = 'demo-app', key = 'k' }).data.value, nil)
end)

test('contacts.read lists simplified contacts', function()
    setup({ permissions = { 'contacts.read', 'contacts.write' } })
    env.contacts = { { id = 3, displayName = 'Ann', phoneNumber = '555-0100', secret = 'x' } }
    local contacts = routes['apps:contacts:list'](1, { app = 'demo-app' }).data.contacts
    equal(contacts[1].name, 'Ann')
    equal(contacts[1].secret, nil)
end)

test('contacts.write validates and upserts onto the caller device only', function()
    setup({ permissions = { 'contacts.write' } })
    equal(code(routes['apps:contacts:save'](1, { app = 'demo-app', name = '', number = '555' })), 'INVALID_INPUT')
    equal(code(routes['apps:contacts:save'](1, { app = 'demo-app', name = 'A', number = 'abc' })), 'INVALID_INPUT')
    equal(code(routes['apps:contacts:save'](1, { app = 'demo-app', id = -1, name = 'A', number = '555' })), 'INVALID_INPUT')
    local result = routes['apps:contacts:save'](1, { app = 'demo-app', name = 'A', number = '555-0101', deviceId = 99 })
    equal(result.ok, true)
    equal(env.upserts[1].deviceId, 7)
end)

test('apps:notify validates and pushes a client event', function()
    setup()
    equal(code(routes['apps:notify'](1, { app = 'demo-app', title = '' })), 'INVALID_INPUT')
    equal(code(routes['apps:notify'](1, { app = 'demo-app', title = ('t'):rep(49) })), 'INVALID_INPUT')
    assert(routes['apps:notify'](1, { app = 'demo-app', title = 'Hi', body = 'there' }).ok)
    local event = env.clientEvents[#env.clientEvents]
    equal(event.event, 'kora_phone:client:appNotify')
    equal(event.args[3], 'Hi')
end)

-- Callbacks
test('RegisterAppCallback namespaces under app:<id>:<name> with a rate limit', function()
    setup()
    equal(env.exports.RegisterAppCallback('demo-app', 'ping', function(_, p) return { pong = p } end), true)
    local registered = env.callbacks['app:demo-app:ping']
    assert(registered)
    assert(registered.opts.rateLimit.max > 0 and registered.opts.rateLimit.window > 0)
end)

test('only the owning resource can register callbacks for an app', function()
    setup()
    env.invoking = 'thief'
    local ok, err = env.exports.RegisterAppCallback('demo-app', 'ping', function() end)
    equal(ok, false)
    assert(err:find('^FORBIDDEN'), err)
    env.invoking = 'app_res'
    equal(select(1, env.exports.RegisterAppCallback('ghost', 'ping', function() end)), false)
    equal(select(1, env.exports.RegisterAppCallback('demo-app', 'bad name!', function() end)), false)
    equal(select(1, env.exports.RegisterAppCallback('demo-app', ('n'):rep(49), function() end)), false)
    equal(select(1, env.exports.RegisterAppCallback('demo-app', 'ok', 'notfn')), false)
end)

test('funcref-style callable tables are accepted', function()
    setup()
    local ref = setmetatable({ __cfx_functionReference = 'ref' }, { __call = function() return 'x' end })
    equal(env.exports.RegisterAppCallback('demo-app', 'ref', ref), true)
end)

test('apps:call and the Kora.callback gateway share the same gate', function()
    setup({ defaultInstalled = false })
    env.exports.RegisterAppCallback('demo-app', 'ping', function(src, p) return { src = src, p = p } end)
    local gateway = env.callbacks['app:demo-app:ping'].fn
    equal(code(routes['apps:call'](5, { app = 'demo-app', name = 'ping' })), 'FORBIDDEN')
    equal(code(gateway(5, 1)), 'FORBIDDEN')
    routes['apps:install'](5, { id = 'demo-app' })
    local viaRoute = routes['apps:call'](5, { app = 'demo-app', name = 'ping', payload = 'hi' })
    equal(viaRoute.data.src, 5)
    equal(viaRoute.data.p, 'hi')
    equal(gateway(5, 'direct').data.p, 'direct')
end)

test('apps:call rejects unknown, malformed and cross-app callbacks', function()
    setup()
    env.exports.RegisterAppCallback('demo-app', 'ping', function() return 1 end)
    env.invoking = 'other_res'
    env.resources.other_res = { state = 'started', meta = { files = { 'ui/*' } }, files = {} }
    env.exports.RegisterApp(H.manifest({ id = 'other-app', defaultInstalled = true }))
    equal(code(routes['apps:call'](1, { app = 'demo-app', name = 'missing' })), 'NOT_FOUND')
    equal(code(routes['apps:call'](1, { app = 'other-app', name = 'ping' })), 'NOT_FOUND')
    equal(code(routes['apps:call'](1, { app = 'demo-app', name = 5 })), 'INVALID_INPUT')
end)

test('a throwing handler becomes INTERNAL and is logged without leaking the error', function()
    setup()
    env.exports.RegisterAppCallback('demo-app', 'boom', function() error('secret path') end)
    local result = routes['apps:call'](1, { app = 'demo-app', name = 'boom' })
    equal(code(result), 'INTERNAL_ERROR')
    assert(not result.error.message:find('secret'))
    equal(env.logs[#env.logs].code, 'phone.sdk.callback_failed')
end)

test('non-JSON and oversized results are refused', function()
    setup()
    env.exports.RegisterAppCallback('demo-app', 'fn', function() return function() end end)
    env.exports.RegisterAppCallback('demo-app', 'big', function() return ('x'):rep(70000) end)
    equal(code(routes['apps:call'](1, { app = 'demo-app', name = 'fn' })), 'INTERNAL_ERROR')
    equal(code(routes['apps:call'](1, { app = 'demo-app', name = 'big' })), 'INTERNAL_ERROR')
end)

test('removing an app unregisters its callbacks', function()
    setup()
    env.exports.RegisterAppCallback('demo-app', 'ping', function() return 1 end)
    env.exports.RemoveApp('demo-app')
    equal(env.callbacks['app:demo-app:ping'], nil)
    equal(code(routes['apps:call'](1, { app = 'demo-app', name = 'ping' })), 'NOT_FOUND')
end)

-- SendAppEvent
test('SendAppEvent pushes to the player only for the owning resource', function()
    setup()
    equal(env.exports.SendAppEvent(3, 'demo-app', 'tick', { n = 1 }), true)
    local event = env.clientEvents[#env.clientEvents]
    equal(event.event, 'kora_phone:client:appEvent')
    equal(event.target, 3)
    equal(event.args[2], 'tick')
    local before = #env.clientEvents
    env.invoking = 'thief'
    equal(env.exports.SendAppEvent(3, 'demo-app', 'tick', {}), false)
    env.invoking = 'app_res'
    equal(env.exports.SendAppEvent('3', 'demo-app', 'tick', {}), false)
    equal(env.exports.SendAppEvent(3, 'demo-app', 'bad name', {}), false)
    equal(env.exports.SendAppEvent(3, 'ghost', 'tick', {}), false)
    equal(#env.clientEvents, before)
end)

H.finish('sdk-routes')
