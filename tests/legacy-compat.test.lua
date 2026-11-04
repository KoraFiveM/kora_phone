-- This file is installed as tests/legacy-compat.test.lua.
local handlers, aliases, nativeExports, callbacks, sent, queries = {}, {}, {}, {}, {}, {}
local citizen, device, allowRate, savedMail, money = 'CID', { id = 5, ownerCitizenId = 'CID' }, true, nil, 100
source = 12
Kora = { compat = { provideExport = function(identity, name, fn) aliases[identity .. ':' .. name] = fn end } }
exports = setmetatable({ kora_core = { getPlayerByCitizenId = function(_, id) return id == 'CID' and { source = 12 } end } }, {
    __call = function(_, name, fn) nativeExports[name] = fn end,
})
function RegisterNetEvent(name, fn) handlers[name] = fn end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerClientEvent(name, target, payload) sent[#sent + 1] = { name, target, payload } end
json = { encode = function(value) return value and 'encoded' end, decode = function() return { buttonEvent = 'job:accept', buttonData = { mission = 7 } } end }
PhoneConstants = { Errors = { NOT_FOUND = 'missing', INVALID_INPUT = 'invalid' } }
PhoneError = function(code) return { ok = false, error = code } end
PhoneResult = function(data) return { ok = true, data = data } end
PhoneValidation = { integer = function(value) return type(value) == 'number' and value > 0 and value % 1 == 0 and value or nil end }
KoraPhone = {
    GetCitizenId = function() return citizen end,
    RateLimits = { consume = function() return allowRate end },
    Permissions = { requireDevice = function() return device, PhoneError('locked') end },
    Repositories = { Mail = {
        insertLegacy = function(id, mail) savedMail = { citizen = id, mail = mail }; return 77 end,
        takeLegacyButton = function(id, owner, mailId)
            assert(id == 5 and owner == 'CID'); if mailId ~= 77 then return end
            return { buttonEvent = 'job:accept', buttonData = { mission = 7 } }
        end,
    } },
    Services = { Mail = { delete = function(src, payload) assert(src == 12 and payload.id == 77) end } },
    registerCallback = function(name, _, fn) callbacks[name] = fn end,
}
MySQL = { insert = { await = function(sql, values) queries[#queries + 1] = { sql, values }; return 1 end } }
dofile('server/compat/qb-phone.lua')
local payload = { sender = 'Job Office', subject = 'Delivery', message = 'Go<br>there', button = { enabled = true, buttonEvent = 'job:accept', buttonData = { mission = 7 } } }
assert(aliases['qb-phone:sendNewMailToOffline'] == nativeExports.sendNewMailToOffline)
local result = nativeExports.sendNewMailToOffline('OFFLINE', payload)
assert(result == nil and savedMail.citizen == 'OFFLINE' and #sent == 0)
assert(savedMail.mail.message == 'Go\nthere' and savedMail.mail.button.buttonEvent == 'job:accept')
handlers['qb-phone:server:sendNewMail'](payload)
assert(savedMail.citizen == 'CID' and sent[1][2] == 12)
local previous = savedMail
handlers['qb-phone:server:sendNewEventMail']('VICTIM', payload)
assert(savedMail == previous, 'clients must not choose another citizen mailbox')
source = 0
handlers['qb-phone:server:sendNewEventMail']('OFFLINE', payload)
assert(savedMail.citizen == 'OFFLINE')
source = 12
assert(not nativeExports.sendNewMailToOffline('CID', { sender = 'a', subject = 'b', message = {} }))
allowRate = false
previous = savedMail
handlers['qb-phone:server:sendNewMail'](payload)
assert(savedMail == previous)
allowRate = true
device = nil
assert(not callbacks.acceptLegacyMail(12, { id = 77 }).ok)
device = { id = 5, ownerCitizenId = 'CID' }
assert(not callbacks.acceptLegacyMail(12, { id = 99 }).ok)
assert(callbacks.acceptLegacyMail(12, { id = 77 }).data.buttonData.mission == 7)
handlers['qb-phone:server:AddTransaction']({ TransactionTitle = 'Credit', TransactionMessage = 'Received 5 BTC' })
assert(#queries == 1 and queries[1][2][1] == 'CID' and money == 100)
handlers['qb-phone:server:AddTransaction']({ TransactionTitle = 'Credit', TransactionMessage = {} })
assert(#queries == 1)

-- Native repository retains inbox/sent separation, ownership, cursor and one-use buttons.
local changed, queryValues = 1
MySQL.query = { await = function(sql, values) queryValues = values; queries[#queries + 1] = { sql, values }; return {} end }
MySQL.single = { await = function(sql, values) queryValues = values; return { legacy_button = 'encoded' } end }
MySQL.update = { await = function(sql, values) queryValues = values; return changed end }
dofile('server/repositories/mail.lua')
local repo = KoraPhone.Repositories.Mail
repo.list(5, 'inbox', 50, 100, 'CID')
assert(queryValues[1] == 5 and queryValues[2] == 'CID' and queryValues[3] == 100 and queryValues[4] == 50)
assert(queries[#queries][1]:find('LEFT JOIN', 1, true) and queries[#queries][1]:find('recipient_citizenid = ?', 1, true))
repo.list(5, 'sent', 50, nil, 'CID')
assert(queryValues[1] == 5 and queryValues[2] == 50 and not queries[#queries][1]:find('recipient_citizenid = ?', 1, true))
assert(repo.takeLegacyButton(5, 'CID', 77).buttonEvent == 'job:accept')
changed = 0
assert(not repo.takeLegacyButton(5, 'CID', 77), 'concurrent/replayed accepts must not execute twice')
repo.markRead(5, 77, 'CID')
assert(queryValues[3] == 'CID')

-- Client handlers send only informational state and server-checked action ids.
local nui, notifications, events, serverEvents = {}, {}, {}, {}
function RegisterNUICallback(name, fn) nui[name] = fn end
function TriggerEvent(name, payload) events[#events + 1] = { name, payload } end
function TriggerServerEvent(name, payload) serverEvents[#serverEvents + 1] = { name, payload } end
KoraPhone.Notifications = { Push = function(value) notifications[#notifications + 1] = value end }
KoraPhone.Bootstrap = function() end
KoraPhone.ServerCallback = function(name, payload, reply)
    assert(name == 'kora_phone:server:acceptLegacyMail' and payload.id == 77 and not payload.buttonEvent)
    reply(PhoneResult({ buttonEvent = 'trusted:action', buttonData = 5 }))
end
dofile('client/compat.lua')
handlers['qb-phone:client:RemoveBankMoney'](25)
assert(#notifications == 1 and money == 100)
handlers['qb-phone:client:AddTransaction']({}, {}, 'Earned 1 BTC', 'Credit')
assert(serverEvents[1][1] == 'qb-phone:server:AddTransaction')
local replied
nui['mail:accept']({ id = 77, buttonEvent = 'forged' }, function(result) replied = result.ok end)
assert(replied and events[#events][1] == 'trusted:action')
print('PASS legacy phone: offline/system mail, client ownership, one-use actions, rate limits, persistent notes and no money mutations')