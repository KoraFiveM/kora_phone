-- lua tests/apps-platform.test.lua  (from the resource root): Phone.app definitions, folder apps and handles
local H = dofile((arg and arg[0] or 'tests/x'):gsub('[^/\\]+$', '') .. 'sdk-helper.lua')
local test, equal = H.test, H.equal

---Loads the shared API and the server half on top of a fresh SDK. `defs` are { chunkname, source } pairs run in order.
local function boot(defs, extraFiles)
    local env = H.newServer()
    env.resources.kora_phone = { state = 'started', meta = { files = extraFiles or { 'apps/*/ui/*', 'apps/*/ui/**/*' } }, files = {} }
    _G.Phone = nil
    dofile(H.root .. '/shared/apps.lua')
    for _, def in ipairs(defs or {}) do
        local chunk = assert(load(def[2], '@kora_phone/' .. def[1]))
        chunk()
    end
    dofile(H.root .. '/server/sdk/apps.lua')
    return env
end

local NOTES = { 'apps/notes/app.lua', "Phone.app('notes', { name = 'Notes', icon = 'notebook', category = 'tools', permissions = { 'storage' }, defaultInstalled = true })" }

test('a folder app is registered with the SDK registry, owned by the phone resource', function()
    boot({ NOTES })
    local app = KoraPhone.SDK.Registry.get('notes')
    assert(app, 'notes was not registered')
    equal(app.resource, 'kora_phone')
    equal(app.entry, 'apps/notes/ui/index.html')
    equal(app.category, 'tools')
    equal(app.defaultInstalled, true)
    equal(KoraPhone.SDK.Registry.url(app), 'https://cfx-nui-kora_phone/apps/notes/ui/index.html')
end)

test('the folder name must match the id', function()
    local ok, err = pcall(function()
        boot({ { 'apps/notes/app.lua', "Phone.app('other', { name = 'X', icon = 'star' })" } })
    end)
    equal(ok, false)
    assert(tostring(err):find('folder name must match'), tostring(err))
end)

test('unknown fields and duplicate ids are rejected when defining', function()
    local ok, err = pcall(function()
        boot({ { 'apps/notes/app.lua', "Phone.app('notes', { name = 'X', icon = 'star', colour = 'red' })" } })
    end)
    equal(ok, false)
    assert(tostring(err):find('unknown field colour'), tostring(err))
    ok, err = pcall(function() boot({ NOTES, NOTES }) end)
    equal(ok, false)
    assert(tostring(err):find('already defined'), tostring(err))
end)

test('an invalid definition is logged and skipped, other apps still register', function()
    local env = boot({
        { 'apps/bad/app.lua', "Phone.app('bad', { name = '', icon = 'star' })" },
        NOTES,
    })
    equal(KoraPhone.SDK.Registry.get('bad'), nil)
    assert(KoraPhone.SDK.Registry.get('notes'))
    local rejected
    for _, log in ipairs(env.logs) do if log.code == 'phone.app.rejected' then rejected = log end end
    assert(rejected and rejected.fields.app == 'bad', 'rejection was not logged')
end)

test('an entry outside the files patterns is rejected', function()
    boot({ NOTES }, { 'ui/*' })
    equal(KoraPhone.SDK.Registry.get('notes'), nil)
end)

test('handle.callback registers a callback reachable through the gate', function()
    local env = boot({ NOTES })
    local app = Phone.app('notes')
    app.callback('echo', function(source, payload) return { from = source, payload = payload } end)
    env.device.settingsJson = '{}'
    local result = KoraPhone.SDK.Callbacks.invoke(5, 'notes', 'echo', { a = 1 })
    equal(result.ok, true)
    equal(result.data.from, 5)
    assert(env.callbacks['app:notes:echo'], 'kora_lib callback not registered')
end)

test('handle.callback raises on a bad name', function()
    boot({ NOTES })
    local ok = pcall(function() Phone.app('notes').callback('bad name!', function() end) end)
    equal(ok, false)
end)

test('handle.send and handle.notify target one player', function()
    local env = boot({ NOTES })
    local app = Phone.app('notes')
    equal(app.send(7, 'tick', { n = 1 }), true)
    equal(app.send(0, 'tick'), false)
    equal(app.notify(7, 'Hello', 'Body'), true)
    equal(app.notify(7, ''), false)
    equal(env.clientEvents[1].event, 'kora_phone:client:appEvent')
    equal(env.clientEvents[2].event, 'kora_phone:client:appNotify')
    equal(env.clientEvents[2].args[2], 'Notes')
end)

test('Phone.app on an undefined id explains what is wrong', function()
    boot({ NOTES })
    local ok, err = pcall(Phone.app, 'ghost')
    equal(ok, false)
    assert(tostring(err):find('no such app'), tostring(err))
end)

test('handle storage uses the held phone', function()
    local env = boot({ NOTES })
    KoraPhone.SDK.StorageRepository = KoraPhone.SDK.StorageRepository or {}
    local stored = {}
    KoraPhone.SDK.StorageRepository.get = function(_, _, key) return stored[key] end
    KoraPhone.SDK.StorageRepository.usage = function() return { keys = 0, bytes = 0 } end
    KoraPhone.SDK.StorageRepository.size = function() return nil end
    KoraPhone.SDK.StorageRepository.set = function(_, _, key, value) stored[key] = value return true end
    local app = Phone.app('notes')
    equal(app.setStorage(3, 'draft', { text = 'hi' }), true)
    equal(app.getStorage(3, 'draft').text, 'hi')
    assert(env.device)
end)

test('Phone.unwrap returns data and raises failures so the UI receives the real error', function()
    local env = boot({ NOTES })
    equal(Phone.unwrap(PhoneResult({ a = 1 })).a, 1)
    local ok, err = pcall(Phone.unwrap, PhoneError('CONFLICT', 'Garage is not available'))
    equal(ok, false)
    equal(err.error.code, 'CONFLICT')
    Phone.app('notes').callback('fails', function() return Phone.unwrap(PhoneError('CONFLICT', 'Not today')) end)
    local result = KoraPhone.SDK.Callbacks.invoke(5, 'notes', 'fails', {})
    equal(result.ok, false)
    equal(result.error.code, 'CONFLICT')
    equal(result.error.message, 'Not today')
    Phone.app('notes').callback('crashes', function() error('boom') end)
    equal(KoraPhone.SDK.Callbacks.invoke(5, 'notes', 'crashes', {}).error.code, PhoneConstants.Errors.INTERNAL)
    assert(env)
end)

test('an .svg icon becomes a nui:// URL inside the app folder; Config.Apps.<id> = false skips the app', function()
    boot({ { 'apps/notes/app.lua', "Phone.app('notes', { name = 'Notes', icon = 'icon.svg' })" } })
    equal(KoraPhone.SDK.Registry.get('notes').icon, 'nui://kora_phone/apps/notes/icon.svg')
    _G.Config = { Apps = { notes = false } }
    boot({ NOTES })
    equal(KoraPhone.SDK.Registry.get('notes'), nil)
    _G.Config = nil
end)

test('a callback can charge a strict rate bucket and is refused with RATE_LIMITED when it is empty', function()
    local env = boot({ NOTES })
    local charged = {}
    KoraPhone.RateLimits.consume = function(source, bucket) charged[#charged + 1] = bucket return #charged <= 2 end
    Phone.app('notes').callback('pay', function() return { paid = true } end, { rate = 'bankTransfer' })
    Phone.app('notes').callback('free', function() return { free = true } end)
    equal(KoraPhone.SDK.Callbacks.invoke(5, 'notes', 'pay', {}).ok, true)
    equal(KoraPhone.SDK.Callbacks.invoke(5, 'notes', 'free', {}).ok, true)
    equal(#charged, 1, 'a callback without a rate does not charge a bucket')
    equal(KoraPhone.SDK.Callbacks.invoke(5, 'notes', 'pay', {}).ok, true)
    local refused = KoraPhone.SDK.Callbacks.invoke(5, 'notes', 'pay', {})
    equal(refused.ok, false)
    equal(refused.error.code, PhoneConstants.Errors.RATE_LIMITED)
    equal(charged[1], 'bankTransfer')
    assert(env)
end)

H.finish('apps-platform')
