-- This file is installed as tests/legacy-compat.test.lua.
local handlers, aliases, nativeExports, callbacks, sent, queries = {}, {}, {}, {}, {}, {}
local citizen, device, allowRate, savedMail, money = 'CID', { id = 5, holderCitizenId = 'CID' }, true, nil, 100
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
QBPhone = {
    GetCitizenId = function() return citizen end,
    RateLimits = { consume = function() return allowRate end },
    Permissions = { requireDevice = function() return device, PhoneError('locked') end },
    -- Handset architecture: system mail is character-owned (phone_legacy_mail), delivered to the selected handset.
    Handsets = { current = function() return device end },
    Repositories = { LegacyMail = {
        insert = function(id, mail) savedMail = { citizen = id, mail = mail }; return 77 end,
        takeButton = function(id, mailId)
            assert(id == 'CID'); if mailId ~= 77 then return end
            return { buttonEvent = 'job:accept', buttonData = { mission = 7 } }
        end,
        markRead = function() return true end, delete = function() return true end, clearButton = function() return true end,
        list = function() return {} end, activity = function() return {} end,
    } },
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
device = { id = 5, holderCitizenId = 'CID' }
assert(not callbacks.acceptLegacyMail(12, { id = 99 }).ok)
assert(callbacks.acceptLegacyMail(12, { id = 77 }).data.buttonData.mission == 7)
handlers['qb-phone:server:AddTransaction']({ TransactionTitle = 'Credit', TransactionMessage = 'Received 5 BTC' })
assert(#queries == 1 and queries[1][2][1] == 'CID' and money == 100)
handlers['qb-phone:server:AddTransaction']({ TransactionTitle = 'Credit', TransactionMessage = {} })
assert(#queries == 1)

-- The character-owned legacy mailbox keeps ownership, cursor paging and one-use buttons.
local changed, queryValues = 1
MySQL.query = { await = function(sql, values) queryValues = values; queries[#queries + 1] = { sql, values }; return {} end }
MySQL.single = { await = function(sql, values) queryValues = values; return { button_json = 'encoded' } end }
MySQL.update = { await = function(sql, values) queryValues = values; return changed end }
dofile('server/repositories/legacy_mail.lua')
local repo = QBPhone.Repositories.LegacyMail
repo.list('CID', 50, 100)
assert(queryValues[1] == 'CID' and queryValues[2] == 100 and queryValues[3] == 50)
assert(queries[#queries][1]:find('citizenid=?', 1, true) and queries[#queries][1]:find('LIMIT ?', 1, true))
repo.list('CID', 50)
assert(queryValues[2] == 9007199254740991, 'no cursor starts from the newest mail')
assert(repo.takeButton('CID', 77).buttonEvent == 'job:accept')
changed = 0
assert(not repo.takeButton('CID', 77), 'concurrent/replayed accepts must not execute twice')
repo.markRead('CID', 77)
assert(queryValues[1] == 77 and queryValues[2] == 'CID')

-- Client handlers send only informational state and server-checked action ids.
local nui, notifications, events, serverEvents = {}, {}, {}, {}
function RegisterNUICallback(name, fn) nui[name] = fn end
function TriggerEvent(name, payload) events[#events + 1] = { name, payload } end
function TriggerServerEvent(name, payload) serverEvents[#serverEvents + 1] = { name, payload } end
QBPhone.Notifications = { Push = function(value) notifications[#notifications + 1] = value end }
QBPhone.Bootstrap = function() end
Config = { compat = { koraPhoneExports = { enabled = true } } }
function GetCurrentResourceName() return 'kora_phone-stevie' end
QBPhone.State = { open = false }
QBPhone.Open, QBPhone.Close = function() return true end, function() end
QBPhone.ServerCallback = function(name, payload, reply)
    assert(name == 'qbphone:server:acceptLegacyMail' and payload.id == 77 and not payload.buttonEvent)
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
