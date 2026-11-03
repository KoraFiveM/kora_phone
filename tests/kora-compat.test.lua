-- The legacy kora_phone export surface and the qb-phone police alert, answered by this resource.
-- Run from the resource root: lua5.4 tests/kora-compat.test.lua
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function equal(actual, expected, message)
    assert(actual == expected, ('%s: expected %s, got %s'):format(message or 'value', tostring(expected), tostring(actual)))
    checks = checks + 1
end

local function newEnv(resource, enabled)
    local state = { native = {}, provided = {}, handlers = {}, mail = {}, messages = {}, queries = {}, notifications = {} }
    local env = setmetatable({}, { __index = _G })
    env.Config = { compat = { koraPhoneExports = { enabled = enabled } } }
    env.GetCurrentResourceName = function() return resource end
    env.Kora = { compat = { provideExport = function(identity, name, fn) state.provided[identity .. ':' .. name] = fn end } }
    env.exports = setmetatable({}, { __call = function(_, name, fn) state.native[name] = fn end })
    env.RegisterNetEvent = function(name, fn) state.handlers[name] = fn end
    env.state = state
    return env, state
end

local function load(env, file)
    return assert(loadfile(file, 't', env))()
end

-- ---- server exports --------------------------------------------------------------------------------------------
local function server(resource, enabled)
    local env, state = newEnv(resource, enabled)
    local online = { CID = 7 }
    local devices = { [7] = { cellular = true, phoneNumber = '5550001111' }, [8] = { cellular = false, phoneNumber = '@abc' } }
    env.QBPhone = {
        GetCitizenId = function(src) return src == 7 and 'CID' or src == 8 and 'NOSIM' or nil end,
        HasPhone = function(src) return src == 7 end,
        Handsets = { current = function(src) return devices[src] end },
        Compat = { sendMail = function(citizenId, data, allowButton)
            state.mail[#state.mail + 1] = { citizenId, data, allowButton }
            return data.sender ~= nil, 1
        end },
        Services = { Messaging = { deliverSystem = function(from, to, content)
            state.messages[#state.messages + 1] = { from, to, content }
            return true
        end } },
    }
    env.exports.kora_core = { getPlayerByCitizenId = function(_, citizenId)
        return online[citizenId] and { source = online[citizenId] } or nil
    end }
    env.MySQL = { single = { await = function(sql, params)
        state.queries[#state.queries + 1] = { sql, params }
        return params[1] == 'OFFLINE' and { phone_number = '5550002222' } or nil
    end } }
    load(env, 'server/compat/kora-phone.lua')
    return env, state
end

local env, state = server('kora_phone-stevie', true)
for _, name in ipairs({ 'sendMailToOffline', 'sendMail', 'sendMessage', 'getNumber', 'getNumberByCitizenId', 'hasPhone' }) do
    check(type(state.native[name]) == 'function', 'native camelCase export ' .. name)
    check(state.provided['kora_phone:' .. name] == state.native[name], 'kora_phone identity answers ' .. name)
end
check(state.native.sendNewMailToOffline == nil, 'the upstream void sendNewMailToOffline stays in server/compat/qb-phone.lua')
check(type(state.provided['kora_phone:sendNewMailToOffline']) == 'function', 'kora_phone:sendNewMailToOffline is bridged')

local ok, err = state.native.sendMailToOffline('CID', { sender = 'Property recovery', subject = 's', message = 'm' })
equal(ok, true, 'offline mail is delivered'); equal(state.mail[1][1], 'CID')
equal(state.mail[1][3], true, 'trusted server mail may carry an Accept action')
ok, err = state.native.sendMailToOffline('CID', { subject = 's' })
equal(ok, false, 'invalid mail is refused'); check(type(err) == 'string', 'a reason is returned')
equal(state.native.sendMail(7, { sender = 'a', subject = 'b', message = 'c' }), true)
equal(state.mail[#state.mail][1], 'CID', 'sendMail resolves the character of the source')
equal((state.native.sendMail(99, { sender = 'a', subject = 'b', message = 'c' })), false, 'unknown source')
equal(state.native.getNumber(7), '5550001111')
equal(state.native.getNumber(8), nil, 'a handset without an active SIM has no number')
equal(state.native.getNumberByCitizenId('CID'), '5550001111', 'online character uses the selected handset')
equal(#state.queries, 0, 'no SQL for an online character')
equal(state.native.getNumberByCitizenId('OFFLINE'), '5550002222', 'offline character uses the active SIM')
check(state.queries[1][1]:find('LIMIT 1', 1, true) and state.queries[1][1]:find("status='active'", 1, true), 'bounded SIM lookup')
equal(state.native.getNumberByCitizenId('NOBODY'), nil)
equal(state.native.getNumberByCitizenId(5), nil, 'non-string ids are refused')
equal(state.native.hasPhone(7), true); equal(state.native.hasPhone(8), false)
equal(state.native.sendMessage('5550003333', '5550001111', 'hello'), true)
equal(state.messages[1][3], 'hello')

-- config key off: only the resource's own camelCase exports remain
env, state = server('kora_phone-stevie', false)
check(type(state.native.sendMail) == 'function', 'native aliases stay available')
check(next(state.provided) == nil, 'compat.koraPhoneExports.enabled = false registers no kora_phone export')

-- folder named kora_phone already answers as kora_phone
env, state = server('kora_phone', true)
check(type(state.native.getNumber) == 'function' and next(state.provided) == nil, 'no duplicate bridge when named kora_phone')

-- ---- system messages (mailboxes.lua) ---------------------------------------------------------------------------
do
    local e, s = newEnv('kora_phone-stevie', true)
    local rows, events, blocked = {}, {}, false
    e.PhoneValidation = { phoneNumber = function(value)
        local digits = type(value) == 'string' and value:gsub('%D', '') or nil
        return digits and #digits == 10 and digits or nil, 'invalid'
    end }
    e.PhoneError = function(...) return { ok = false, ... } end
    e.PhoneResult = function(data) return { ok = true, data = data } end
    e.PhoneConstants = { Errors = {} }
    e.Config.Limits = { MessageBody = 20 }
    e.exports[ 'kora_phone-stevie' ] = { randomHex = function() return 'abcd' end }
    e.TriggerClientEvent = function(name, target, payload) events[#events + 1] = { name, target, payload } end
    e.SetTimeout = function() end
    local devices = { ['5550001111'] = { id = 1, phoneNumber = '5550001111' }, ['5550003333'] = { id = 3, phoneNumber = '5550003333' } }
    e.QBPhone = {
        Services = { Messaging = {} }, Repositories = { Media = {} },
        Sessions = { sourceByNumber = function(number) return number == '5550001111' and 7 or nil end },
        Handsets = { selected = {}, locked = function() end },
    }
    e.QBPhone.Repositories.Phones = { findByNumber = function(number) return devices[number] end }
    e.QBPhone.Repositories.Blocks = { isEitherBlocked = function() return blocked end }
    e.MySQL = {
        update = { await = function(sql, values) rows[#rows + 1] = { sql, values }; return 1 end },
        insert = { await = function(sql, values) rows[#rows + 1] = { sql, values }; return 55 end },
        single = { await = function(sql, values)
            if sql:find('phone_threads', 1, true) then return { id = 9, device_id = values[1], peer_number = values[2] } end
            return { id = 55, body = 'hello', is_outgoing = 0, senderNumber = '5550003333', createdAt = 1 }
        end },
        scalar = { await = function() return 0 end },
        query = { await = function() return {} end },
    }
    load(e, 'server/mailboxes.lua')
    local deliver = e.QBPhone.Services.Messaging.deliverSystem
    local sent = deliver('5550003333', '5550001111', '  hello  ')
    equal(sent, true, 'system text is delivered')
    local insert = rows[#rows]
    check(insert[1]:find('INSERT INTO phone_mailboxes', 1, true), 'stored in the recipient mailbox')
    equal(insert[2][1], 1, 'recipient handset'); equal(insert[2][2], '5550003333', 'thread peer'); equal(insert[2][4], 'hello', 'trimmed body')
    check(insert[2][5]:find('^sys:'), 'unique system request id')
    equal(events[1][1], 'qbphone:client:messages:new'); equal(events[1][2], 7, 'online recipient is notified')
    equal(deliver('nope', '5550001111', 'x'), false); equal(deliver('5550003333', 'nope', 'x'), false)
    equal(deliver('5550003333', '5550001111', ''), false, 'empty body'); equal(deliver('5550003333', '5550001111', ('x'):rep(21)), false, 'too long')
    equal(deliver('5550001111', '5550001111', 'x'), false, 'cannot text itself')
    equal(deliver('5550003333', '5559999999', 'x'), false, 'unknown recipient')
    blocked = true
    equal(deliver('5550003333', '5550001111', 'x'), false, 'a blocked pair is refused')
end

-- ---- client: police alert and open / close / isOpen -----------------------------------------------------------
do
    local e, s = newEnv('kora_phone-stevie', true)
    local pushed, player = {}, { job = { name = 'police', onduty = true } }
    e.exports.kora_core = { getPlayerData = function() return player end }
    e.RegisterNUICallback = function() end
    e.TriggerEvent, e.TriggerServerEvent = function() end, function() end
    e.QBPhone = { State = { open = false }, Notifications = { Push = function(n) pushed[#pushed + 1] = n; return true end },
        Bootstrap = function() end, ServerCallback = function() end, SendNui = function() end }
    local opened
    e.QBPhone.Open = function(app) opened = app or 'home'; e.QBPhone.State.open = true; return true end
    e.QBPhone.Close = function() e.QBPhone.State.open = false end
    load(e, 'client/compat.lua')
    local alert = s.handlers['qb-phone:client:addPoliceAlert']
    alert({ title = 'Anklet location', description = 'Marked on your map', coords = { x = 1, y = 2, z = 3 } })
    equal(#pushed, 1, 'on-duty officer sees the alert'); equal(pushed[1].title, 'Anklet location'); equal(pushed[1].message, 'Marked on your map')
    alert({ description = 5 }); equal(pushed[2].title, 'Police alert', 'default title'); equal(pushed[2].message, '5')
    alert({ title = ('t'):rep(200) }); equal(#pushed[3].title, 80, 'title is bounded')
    alert('nope'); alert({ title = {} })
    equal(#pushed, 4, 'a non-table payload is ignored; an unusable title falls back to the default')
    player.job.onduty = false; alert({ title = 'x' }); equal(#pushed, 4, 'off-duty officer is not alerted')
    player.job = { name = 'ambulance', onduty = true }; alert({ title = 'x' }); equal(#pushed, 4, 'other jobs are not alerted')
    player.job = { name = 'sheriff', type = 'leo', onduty = true }; alert({ title = 'x' }); equal(#pushed, 5, 'leo job type counts as police')

    for _, name in ipairs({ 'open', 'close', 'isOpen' }) do
        check(type(s.native[name]) == 'function', 'native ' .. name)
        check(s.provided['kora_phone:' .. name] == s.native[name], 'kora_phone:' .. name)
    end
    equal(s.native.isOpen(), false)
    equal(s.native.open('messages'), true); equal(opened, 'messages'); equal(s.native.isOpen(), true)
    local refused, reason = s.native.open({})
    equal(refused, false); check(type(reason) == 'string')
    equal(s.native.close(), true); equal(s.native.isOpen(), false)
    equal(s.native.close(), true, 'closing a closed phone is harmless')

    local e2, s2 = newEnv('kora_phone-stevie', false)
    e2.exports.kora_core = e.exports.kora_core
    e2.RegisterNUICallback = function() end
    e2.QBPhone = e.QBPhone
    load(e2, 'client/compat.lua')
    check(s2.native.open and next(s2.provided) == nil, 'client exports follow compat.koraPhoneExports.enabled')
end

print(('PASS kora_phone compatibility: %d checks'):format(checks))
