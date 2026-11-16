-- lua tests/sdk-registry.test.lua  (from the resource root)
local H = dofile((arg and arg[0] or 'tests/x'):gsub('[^/\\]+$', '') .. 'sdk-helper.lua')
local test, equal = H.test, H.equal

local env = H.newServer()
local Registry = KoraPhone.SDK.Registry

local function fresh()
    env = H.newServer()
    Registry = KoraPhone.SDK.Registry
    for _, name in ipairs({ 'app_res', 'thief', 'other_res' }) do
        env.resources[name] = { state = 'started', meta = { files = { 'ui/*' } }, files = {} }
    end
end

test('RegisterApp export registers for the invoking resource', function()
    fresh()
    env.invoking = 'app_res'
    local ok = env.exports.RegisterApp(H.manifest())
    equal(ok, true)
    equal(Registry.get('demo-app').resource, 'app_res')
end)

test('RegisterApp returns (false, INVALID_MANIFEST) for bad input', function()
    fresh()
    local ok, err = env.exports.RegisterApp(H.manifest({ permissions = { 'nope' } }))
    equal(ok, false)
    assert(err:find('^INVALID_MANIFEST: '), err)
end)

test('first registrant wins, other resources get CONFLICT', function()
    fresh()
    env.exports.RegisterApp(H.manifest())
    env.invoking = 'thief'
    local ok, err = env.exports.RegisterApp(H.manifest({ name = 'Stolen' }))
    equal(ok, false)
    assert(err:find('^CONFLICT'), err)
    equal(Registry.get('demo-app').name, 'Demo')
    env.invoking = 'app_res'
    equal(env.exports.RegisterApp(H.manifest({ name = 'Renamed' })), true)
    equal(Registry.get('demo-app').name, 'Renamed')
end)

test('entry must be listed in the resource files when they can be read', function()
    fresh()
    env.resources.app_res = { state = 'started', meta = { file = { 'ui/other.html' } }, files = {} }
    local ok, err = env.exports.RegisterApp(H.manifest())
    equal(ok, false)
    assert(err:find('not listed'), err)
    env.resources.app_res.meta.files = { 'ui/*' }
    equal(env.exports.RegisterApp(H.manifest()), true)
end)

test('RemoveApp only works for the owner', function()
    fresh()
    env.exports.RegisterApp(H.manifest())
    env.invoking = 'thief'
    equal(env.exports.RemoveApp('demo-app'), false)
    env.invoking = 'app_res'
    equal(env.exports.RemoveApp('demo-app'), true)
    equal(Registry.get('demo-app'), nil)
    equal(env.exports.RemoveApp('demo-app'), false)
end)

test('onResourceStop removes only that resource apps and their callbacks', function()
    fresh()
    env.exports.RegisterApp(H.manifest())
    env.exports.RegisterAppCallback('demo-app', 'ping', function() return 1 end)
    env.invoking = 'other_res'
    env.exports.RegisterApp(H.manifest({ id = 'other-app' }))
    assert(env.callbacks['app:demo-app:ping'])
    env.handlers.onResourceStop('app_res')
    equal(Registry.get('demo-app'), nil)
    equal(env.callbacks['app:demo-app:ping'], nil)
    assert(Registry.get('other-app'))
end)

test('list is sorted and url points at cfx-nui', function()
    fresh()
    env.exports.RegisterApp(H.manifest({ id = 'zeta' }))
    env.exports.RegisterApp(H.manifest({ id = 'alpha' }))
    equal(Registry.list()[1].id, 'alpha')
    equal(Registry.url(Registry.get('zeta')), 'https://cfx-nui-app_res/ui/index.html')
end)

test('jobMatches respects name and grade', function()
    fresh()
    env.exports.RegisterApp(H.manifest({ job = { name = 'police', grade = 2 } }))
    local app = Registry.get('demo-app')
    equal(Registry.jobMatches(app, { name = 'police', grade = { level = 3 } }), true)
    equal(Registry.jobMatches(app, { name = 'police', grade = { level = 2 } }), true) -- one-based minimum
    equal(Registry.jobMatches(app, { name = 'police', grade = { level = 1 } }), false)
    equal(Registry.jobMatches(app, { name = 'ems', grade = 9 }), false)
    equal(Registry.jobMatches(app, nil), false)
end)

-- Discovery
local function declare(resource, path, content, extra)
    env.resources[resource] = {
        state = 'started',
        meta = { kora_phone_app = { path }, files = { 'ui/*' } },
        files = { [path] = content },
    }
    for key, value in pairs(extra or {}) do env.resources[resource][key] = value end
end

test('discovery reads kora_phone_app metadata on resource start', function()
    fresh()
    declare('meta_res', 'app.json', json.encode(H.manifest({ id = 'meta-app' })))
    env.handlers.onServerResourceStart('meta_res')
    equal(Registry.get('meta-app').resource, 'meta_res')
end)

test('discovery logs and skips bad json, big files, missing files and bad manifests', function()
    fresh()
    declare('bad_json', 'app.json', '{nope')
    declare('bad_manifest', 'app.json', json.encode(H.manifest({ id = 'bad-m', hack = 1 })))
    declare('big', 'app.json', ('x'):rep(20000))
    declare('missing', 'app.json', nil)
    for _, name in ipairs({ 'bad_json', 'bad_manifest', 'big', 'missing' }) do
        env.handlers.onServerResourceStart(name)
    end
    equal(#Registry.list(), 0)
    equal(#env.logs, 4)
    equal(env.logs[1].code, 'phone.sdk.manifest_rejected')
end)

test('scanAll registers already-started resources only', function()
    fresh()
    declare('running', 'app.json', json.encode(H.manifest({ id = 'running-app' })))
    declare('stopped', 'app.json', json.encode(H.manifest({ id = 'stopped-app' })), { state = 'stopped' })
    equal(KoraPhone.SDK.Discovery.scanAll(), 1)
    assert(Registry.get('running-app'))
    equal(Registry.get('stopped-app'), nil)
end)

test('the phone resource itself is never scanned', function()
    fresh()
    declare('kora_phone', 'app.json', json.encode(H.manifest({ id = 'self-app' })))
    equal(KoraPhone.SDK.Discovery.scan('kora_phone'), 0)
end)

test('a resource may declare several manifests', function()
    fresh()
    env.resources.multi = {
        state = 'started', meta = { kora_phone_app = { 'a.json', 'b.json' }, files = { 'ui/*' } },
        files = { ['a.json'] = json.encode(H.manifest({ id = 'multi-a' })), ['b.json'] = json.encode(H.manifest({ id = 'multi-b' })) },
    }
    equal(KoraPhone.SDK.Discovery.scan('multi'), 2)
end)

H.finish('sdk-registry')
