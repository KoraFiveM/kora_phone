-- Run outside FiveM with: lua tests/share.test.lua
-- Share-your-number service (server/services/share.lua) against stubbed FiveM, kora_lib and repositories.

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write('PASS ', name, '\n')
    else failed = failed + 1; io.stderr:write('FAIL ', name, ': ', tostring(err), '\n') end
end
local function equal(actual, expected, label)
    assert(actual == expected, ('%sexpected %s, got %s'):format(label and (label .. ': ') or '', tostring(expected), tostring(actual)))
end

local script = arg and arg[0] or 'tests/share.test.lua'
local root = script:gsub('[\\/]tests[\\/]share%.test%.lua$', '')
if root == script then root = '.' end

dofile(root .. '/config/shared.lua')
dofile(root .. '/config/handsets.lua')
dofile(root .. '/shared/constants.lua')
dofile(root .. '/shared/validation.lua')

-- World: players 1..4. Positions in metres along x; 4 is in another routing bucket.
local now, timers, events, contacts, blocked, nextId
local players, positions, devices
local function reset()
    now, timers, events, contacts, blocked, nextId = 1000, {}, {}, {}, {}, 0
    players = {
        [1] = { citizenid = 'A', charinfo = { firstname = 'Ann' } },
        [2] = { citizenid = 'B', charinfo = { firstname = 'Ben' } },
        [3] = { citizenid = 'C', charinfo = { firstname = 'Cal' } },
    }
    positions = { [1] = 0, [2] = 2, [3] = 20 }
    devices = {
        [1] = { id = 11, phoneNumber = '5550000001', cellular = true },
        [2] = { id = 12, phoneNumber = '5550000002', cellular = true },
        [3] = { id = 13, phoneNumber = '@nosim', cellular = false },
    }
    local service = KoraPhone and KoraPhone.Services and KoraPhone.Services.Share
    if service then service.pending, service.byTarget, service.cooldown = {}, {}, {} end
end
reset()

os.time = function() return now end
function GetPlayerName(src) return players[src] and ('p' .. src) or nil end
function GetCurrentResourceName() return 'kora_phone' end
function SetTimeout(ms, fn) timers[#timers + 1] = { at = ms, fn = fn } end
function TriggerClientEvent(name, target, data) events[#events + 1] = { name = name, target = target, data = data } end
local handlers = {}
function AddEventHandler(name, fn) handlers[name] = fn end
exports = setmetatable({}, { __index = function() return { randomHex = function() nextId = nextId + 1; return 'id' .. nextId end } end })
Kora = { world = { resolveNearbyPlayer = function(a, b, opts)
    if not positions[a] or not positions[b] then return nil, 'unavailable' end
    return math.abs(positions[a] - positions[b]) <= opts.maxDistance and 1 or nil
end } }
KoraPhone = {
    GetPlayer = function(src) return players[src] end,
    GetCitizenId = function(src) return players[src] and players[src].citizenid end,
    HasPhone = function(src) return devices[src] ~= nil end,
    Permissions = { requireDevice = function(src) return devices[src] or nil, PhoneError('PHONE_REQUIRED', 'A phone is required') end },
    Handsets = { current = function(src) return devices[src] end },
    Repositories = {
        Blocks = { isEitherBlocked = function(a, b) return blocked[a .. ':' .. b] or blocked[b .. ':' .. a] or false end },
        Phones = { findByNumber = function(number)
            for _, d in pairs(devices) do if d.phoneNumber == number and d.cellular then return d end end
        end },
        Contacts = {
            findByNumber = function(deviceId, number) return contacts[deviceId .. ':' .. number] and 1 or nil end,
            upsert = function(deviceId, c) contacts[deviceId .. ':' .. c.phoneNumber] = c.displayName; return 1 end,
        },
    },
}
dofile(root .. '/server/services/share.lua')
local Share = KoraPhone.Services.Share

local function requestFor(target)
    for i = #events, 1, -1 do
        if events[i].name == 'kora_phone:client:share:request' and events[i].target == target then return events[i].data end
    end
end

test('offer reaches the nearby target and saves nothing yet', function()
    reset()
    local r = Share.offer(1, { target = 2, label = 'Annie' })
    assert(r.ok, 'offer failed')
    local req = requestFor(2)
    equal(req.number, '5550000001'); equal(req.label, 'Annie'); equal(req.expiresIn, 30)
    equal(next(contacts), nil, 'contacts')
end)

test('accept saves the sharer under the chosen name, once', function()
    reset()
    Share.offer(1, { target = 2, label = 'Annie' })
    local id = requestFor(2).id
    local r = Share.answer(2, { id = id, accept = true, name = 'Ann from the bar' })
    assert(r.ok, 'answer failed'); equal(contacts['12:5550000001'], 'Ann from the bar')
    equal(Share.answer(2, { id = id, accept = true }).ok, false, 'second answer')
end)

test('share back saves the receiver on the sharer phone', function()
    reset()
    Share.offer(1, { target = 2 })
    local r = Share.answer(2, { id = requestFor(2).id, accept = true, shareBack = true })
    assert(r.ok and r.data.sharedBack, 'not shared back'); equal(contacts['11:5550000002'], 'Ben')
    equal(contacts['12:5550000001'], 'Ann', 'default label is the first name')
end)

test('decline saves nothing and tells the sharer', function()
    reset()
    Share.offer(1, { target = 2 })
    assert(Share.answer(2, { id = requestFor(2).id, accept = false }).data.declined)
    equal(next(contacts), nil); equal(events[#events].target, 1)
end)

test('only the target can answer', function()
    reset()
    Share.offer(1, { target = 2 })
    equal(Share.answer(3, { id = requestFor(2).id, accept = true }).ok, false)
    equal(next(contacts), nil)
end)

test('refuses far, self, unknown and SIM-less sharers', function()
    reset()
    equal(Share.offer(1, { target = 3 }).ok, false, 'far')
    equal(Share.offer(1, { target = 1 }).ok, false, 'self')
    equal(Share.offer(1, { target = 9 }).ok, false, 'unknown')
    equal(Share.offer(1, { target = '2; drop' }).ok, false, 'garbage')
    positions[3] = 1
    equal(Share.offer(3, { target = 2 }).ok, false, 'no SIM')
end)

test('expired requests cannot be accepted', function()
    reset()
    Share.offer(1, { target = 2 })
    local id = requestFor(2).id
    now = now + 31
    equal(Share.answer(2, { id = id, accept = true }).ok, false)
    equal(next(contacts), nil)
end)

test('expiry timer clears the request and tells the sharer', function()
    reset()
    Share.offer(1, { target = 2 })
    for _, t in ipairs(timers) do if t.at == 31000 then t.fn() end end
    equal(Share.byTarget[2], nil); equal(events[#events].target, 1)
end)

test('one open request per target and a per-pair cooldown', function()
    reset()
    positions[3] = 1; devices[3] = { id = 13, phoneNumber = '5550000003', cellular = true }
    assert(Share.offer(1, { target = 2 }).ok)
    equal(Share.offer(3, { target = 2 }).error.code, 'CONFLICT')
    Share.answer(2, { id = requestFor(2).id, accept = false })
    equal(Share.offer(1, { target = 2 }).error.code, 'RATE_LIMITED')
    now = now + 21
    assert(Share.offer(1, { target = 2 }).ok, 'after cooldown')
end)

test('a receiver who walked away cannot accept', function()
    reset()
    Share.offer(1, { target = 2 })
    positions[2] = 15
    equal(Share.answer(2, { id = requestFor(2).id, accept = true }).ok, false)
end)

test('a block suppresses the prompt without telling the sharer', function()
    reset()
    blocked['12:11'] = true
    assert(Share.offer(1, { target = 2 }).ok)
    equal(requestFor(2), nil)
end)

test('a SIM swap after the offer refuses the save', function()
    reset()
    Share.offer(1, { target = 2 })
    devices[1].cellular = false
    equal(Share.answer(2, { id = requestFor(2).id, accept = true }).ok, false)
end)

test('existing contacts are not overwritten', function()
    reset()
    contacts['12:5550000001'] = 'Mum'
    Share.offer(1, { target = 2, label = 'Ann' })
    local r = Share.answer(2, { id = requestFor(2).id, accept = true })
    assert(r.ok and r.data.existing); equal(contacts['12:5550000001'], 'Mum')
end)

test('disabled config refuses offers', function()
    reset()
    Config.ShareNumber.Enabled = false
    equal(Share.offer(1, { target = 2 }).ok, false)
    Config.ShareNumber.Enabled = true
end)

test('control characters in the label fall back to the first name', function()
    reset()
    Share.offer(1, { target = 2, label = 'bad\1name' })
    equal(requestFor(2).label, 'Ann')
end)

test('playerDropped forgets open requests', function()
    reset()
    Share.offer(1, { target = 2 })
    source = 1; handlers.playerDropped()
    equal(Share.byTarget[2], nil)
end)

io.write(('%d passed, %d failed\n'):format(passed, failed))
if failed > 0 then os.exit(1) end
