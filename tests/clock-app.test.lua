-- lua tests/clock-app.test.lua  (from the resource root): apps/clock/client.lua, the alarm scheduler
local script = arg and arg[0] or 'tests/x.lua'
local root = script:gsub('[\\/]tests[\\/][^\\/]+$', '')
if root == script then root = '.' end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 io.write('PASS ', name, '\n') else failed = failed + 1 io.stderr:write('FAIL ', name, ': ', tostring(err), '\n') end
end
local function equal(actual, expected, label) assert(actual == expected, ('%sexpected %s, got %s'):format(label and (label .. ': ') or '', tostring(expected), tostring(actual))) end

local env
local function boot(listResult)
    env = { notified = {}, sounds = {}, saved = {}, pushed = {}, now = { 2026, 11, 25, 8, 0 }, timeouts = {}, threads = {} }
    _G.KoraPhone = { State = { playerLoaded = true }, SDK = { Events = { deliver = function(id, name, data) env.pushed[#env.pushed + 1] = { id, name, data } return true end } } }
    _G.GetCurrentResourceName = function() return 'kora_phone' end
    _G.RegisterNetEvent = function() end
    _G.CreateThread = function(fn) env.threads[#env.threads + 1] = fn end
    _G.Wait = function() end
    _G.GetLocalTime = function() return table.unpack(env.now) end
    _G.Kora = {
        lang = function(key) return key end,
        notify = { send = function(n) env.notified[#env.notified + 1] = n end },
        sound = { playFrontend = function(name) env.sounds[#env.sounds + 1] = name end },
        timers = {
            setInterval = function(fn) env.tick = fn return 1 end,
            setTimeout = function(fn) fn() return 2 end,
        },
        logging = { event = function() end },
        callback = { trigger = function(name, payload)
            if name == 'app:clock:list' then return { ok = true, data = listResult or {} } end
            if name == 'app:clock:save' then env.saved[#env.saved + 1] = payload return { ok = true } end
        end },
    }
    _G.Phone = nil
    dofile(root .. '/shared/apps.lua')
    dofile(root .. '/client/sdk/apps.lua')
    assert(load(io.open(root .. '/apps/clock/app.lua'):read('a'), '@kora_phone/apps/clock/app.lua'))()
    assert(load(io.open(root .. '/apps/clock/client.lua'):read('a'), '@kora_phone/apps/clock/client.lua'))()
    return KoraPhone.Apps
end
local function sync(list) return KoraPhone.Apps.invokeClient('clock', 'sync', list) end

test('the page can hand the client its alarms, and a malformed list is cleaned', function()
    boot()
    equal(sync({ { id = 'a', time = '08:00', enabled = true, days = {} }, { id = 5 }, 'x', { id = 'b', time = 'bad' } }).ok, true)
end)

test('an enabled alarm rings once at its minute, with a notification, three beeps and a push to the page', function()
    boot()
    sync({ { id = 'a', label = 'Gym', time = '08:00', days = { 3 }, enabled = true } })   -- 2026-11-25 is a Wednesday (3)
    env.tick()
    equal(#env.notified, 1); equal(env.notified[1].message, 'Gym')
    equal(#env.sounds, 3)
    equal(env.pushed[1][2], 'ring'); equal(env.pushed[1][3].id, 'a')
    env.tick(); env.tick()
    equal(#env.notified, 1, 'the same minute never rings twice')
    env.now = { 2026, 11, 25, 8, 1 }
    env.tick()
    equal(#env.notified, 1, 'a different minute does not ring')
end)

test('repeat days are matched against the player date', function()
    boot()
    sync({ { id = 'thu', time = '08:00', days = { 4 }, enabled = true }, { id = 'sun', time = '08:00', days = { 0, 6 }, enabled = true } })
    env.tick()
    equal(#env.notified, 0, 'Wednesday is neither Thursday nor the weekend')
    env.now = { 2026, 11, 26, 8, 0 }   -- Thursday
    env.tick()
    equal(#env.notified, 1)
    env.now = { 2026, 11, 29, 8, 0 }   -- Sunday
    env.tick()
    equal(#env.notified, 2)
end)

test('a disabled alarm stays silent', function()
    boot()
    sync({ { id = 'a', time = '08:00', days = {}, enabled = false } })
    env.tick()
    equal(#env.notified, 0)
end)

test('a one-time alarm rings once and turns itself off on the server', function()
    boot()
    sync({ { id = 'once', label = 'Once', time = '08:00', days = {}, enabled = true } })
    env.tick()
    equal(#env.notified, 1)
    for _, fn in ipairs(env.threads) do pcall(fn) end
    local saved
    for _, payload in ipairs(env.saved) do if payload.id == 'once' then saved = payload end end
    assert(saved, 'the alarm was not saved as disabled')
    equal(saved.enabled, false)
    env.now = { 2026, 11, 26, 8, 0 }
    env.tick()
    equal(#env.notified, 1, 'it does not ring again the next day')
end)

test('nothing rings before the character is loaded', function()
    boot()
    sync({ { id = 'a', time = '08:00', days = {}, enabled = true } })
    KoraPhone.State.playerLoaded = false
    env.tick()
    equal(#env.notified, 0)
end)

io.write(('\nclock-app: %d passed, %d failed\n'):format(passed, failed))
if failed > 0 then os.exit(1) end
