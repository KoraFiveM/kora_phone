-- lua tests/lbphone-compat.test.lua  (from the resource root): the lb-phone server exports
local H = dofile((arg and arg[0] or 'tests/x'):gsub('[^/\\]+$', '') .. 'sdk-helper.lua')
local test, equal = H.test, H.equal

-- Every server export https://docs.lbscripts.com/phone/exports/server-exports/ documents.
local DOCUMENTED = {
    'GetConfig', 'GetCellTowers', 'FormatNumber', 'AirShare', 'ContainsBlacklistedWord', 'AddCheck', 'RemoveCheck',
    'GetSocialMediaUsername', 'ToggleVerified', 'IsVerified', 'ChangePassword', 'PostBirdy', 'GetBirdyPost', 'PostInstaPic',
    'DeleteBirdyAccount', 'DeleteInstaPicAccount', 'DeleteTrendyAccount',
    'FactoryReset', 'GetEquippedPhoneNumber', 'GetSourceFromNumber', 'HasPhoneItem', 'GetSettings', 'HasAirplaneMode',
    'SendNotification', 'NotifyEveryone', 'EmergencyNotification', 'AddContact', 'AddTransaction', 'GetPin', 'ResetSecurity',
    'CreateMailAccount', 'GetEmailAddress', 'SendMail', 'DeleteMail', 'SendMessage', 'SentMoney', 'SendCoords',
    'SendDarkChatMessage', 'SendDarkChatLocation', 'CreateDarkChatChannel', 'DeleteDarkChatChannel',
    'AddUserToDarkChatChannel', 'RemoveUserFromDarkChatChannel', 'SaveBattery', 'SaveAllBatteries', 'IsPhoneDead',
    'CreateCall', 'GetCall', 'EndCall', 'IsInCall', 'ForwardCall',
    'AddCrypto', 'RemoveCrypto', 'AddCustomCoin', 'GetCoin', 'GetOwnedCoin',
    'RegisterCallback', 'BaseCallback', 'AwaitClientCallback', 'TriggerClientCallback',
}

local env, Lb, exportsByName

local function boot()
    env = H.newServer()
    env.sent, env.contacts, env.activities, env.mails, env.messages, env.hung = {}, {}, {}, {}, {}, {}
    env.numbers = { ['1234567890'] = 5 }     -- number -> source
    _G.Config = { PhoneNumber = { Prefix = '555', SubscriberDigits = 4 }, Server = {} }
    _G.PhoneValidation = {
        phoneNumber = function(value)
            if type(value) ~= 'string' then return nil, 'x' end
            value = value:gsub('[^%d]', '')
            if #value ~= 7 or value:sub(1, 3) ~= '555' then return nil, 'x' end
            return value
        end,
    }
    local devices = { [1] = { id = 11, ownerCitizenId = 'CID-A', phoneNumber = '5550001', cellular = true, settingsJson = '{"airplane":true}' } }
    KoraPhone.GetCitizenId = function() return 'CID1' end
    KoraPhone.HasPhone = function(source) return source == 1 end
    KoraPhone.Handsets = { current = function(source) return devices[source] end }
    KoraPhone.Sessions = {
        bySource = { [1] = {}, [2] = {} },
        sourceByNumber = function(number) return number == '5550001' and 1 or number == '5550002' and 2 or nil end,
    }
    KoraPhone.Repositories.Phones.findByNumber = function(number)
        if number == '5550001' then return { id = 11, ownerCitizenId = 'CID-A', phoneNumber = number } end
        if number == '5550002' then return { id = 12, ownerCitizenId = 'CID-B', phoneNumber = number } end
    end
    KoraPhone.Repositories.Phones.updateSettings = function(id, jsonText) env.settingsWrites[#env.settingsWrites + 1] = { id = id, json = jsonText } return true end
    KoraPhone.Repositories.Phones.clearPin = function(id) env.pinCleared = id end
    KoraPhone.Repositories.Contacts.findByNumber = function() return nil end
    KoraPhone.Repositories.Contacts.upsert = function(deviceId, contact) env.contacts[#env.contacts + 1] = { deviceId = deviceId, contact = contact } return 1 end
    KoraPhone.SystemMail = {
        addActivity = function(cid, title, message) env.activities[#env.activities + 1] = { cid, title, message } return 1 end,
        send = function(cid, mail) env.mails[#env.mails + 1] = { cid, mail } return 77 end,
    }
    KoraPhone.Services.Messaging = { sendAs = function(sender, payload)
        env.messages[#env.messages + 1] = { sender = sender, payload = payload }
        return PhoneResult({ id = 900, conversationId = 31 })
    end }
    KoraPhone.Services.Calling = { callByDevice = { [11] = 'c1' }, activeById = { c1 = { id = 'c1', startedAt = 1, status = 'active', callerNumber = '5550001', calleeNumber = '5550002' } },
        hangup = function(source, payload) env.hung[#env.hung + 1] = { source, payload.id } return PhoneResult(true) end }
    _G.exports.kora_core = { getPlayerByCitizenId = function(_, cid) return cid == 'CID-B' and { source = 2 } or nil end }
    _G.CreateThread = function(fn) fn() end
    _G.TriggerClientEvent = function(event, target, ...) env.sent[#env.sent + 1] = { event = event, target = target, args = { ... } } end
    exportsByName = {}
    _G.AddEventHandler = function(event, fn)
        local name = event:match('^__cfx_export_lb%-phone_(.+)$')
        if name then fn(function(handler) exportsByName[name] = handler end) end
    end
    _G.Kora.callback.trigger = function(target, name, ...) return { target, name, ... } end
    _G.GetInvokingResource = function() return env.invoking end
    dofile(H.root .. '/server/compat/lbphone.lua')
    Lb = KoraPhone.Compat.LbPhone
end

test('every documented lb-phone server export is answered', function()
    boot()
    for _, name in ipairs(DOCUMENTED) do assert(type(exportsByName[name]) == 'function', name .. ' is not answered') end
    local mappedCount = 0
    for _, status in pairs(Lb.status) do if status == 'mapped' then mappedCount = mappedCount + 1 end end
    assert(mappedCount >= 30, 'expected at least 30 mapped exports, got ' .. mappedCount)
end)

test('number and source lookups', function()
    boot()
    equal(exportsByName.GetEquippedPhoneNumber(1), '5550001')
    equal(exportsByName.GetEquippedPhoneNumber(99), nil)
    equal(exportsByName.GetEquippedPhoneNumber('CID-B'), nil)
    equal(exportsByName.GetSourceFromNumber('555-0001'), 1)
    equal(exportsByName.GetSourceFromNumber('0000000'), false)
    equal(exportsByName.HasPhoneItem(1), true)
    equal(exportsByName.HasPhoneItem(1, '5550001'), true)
    equal(exportsByName.HasPhoneItem(1, '5550002'), false)
    equal(exportsByName.HasPhoneItem(2), false)
    equal(exportsByName.HasAirplaneMode('5550001'), true)
    equal(exportsByName.HasAirplaneMode('5550002'), nil)
    equal(exportsByName.GetSettings('5550001').airplane, true)
end)

test('SendNotification to a source shows once; to a number it returns an id; offline returns nil', function()
    boot()
    equal(exportsByName.SendNotification(1, { app = 'Mail', title = 'Hi', content = 'Body' }), nil)
    equal(env.sent[1].event, 'kora_phone:client:notification')
    equal(env.sent[1].args[1].app, 'mail')
    equal(env.sent[1].args[1].body, 'Body')
    local id = exportsByName.SendNotification('5550002', { app = 'Mail', title = 'Hi' })
    equal(type(id), 'number')
    equal(env.sent[2].target, 2)
    equal(exportsByName.SendNotification('5559999', { title = 'x' }), nil)
    equal(exportsByName.SendNotification(1, {}), nil)
    local seen
    exportsByName.SendNotification('5550001', { title = 'cb' }, function(v) seen = v end)
    equal(type(seen), 'number')
end)

test('buttons travel with the notification', function()
    boot()
    exportsByName.SendNotification(1, { title = 'T', customData = { buttons = { { title = 'Read', event = 'x:y' } } } })
    equal(env.sent[1].args[1].data.buttons[1].event, 'x:y')
end)

test('NotifyEveryone reaches every online phone, EmergencyNotification is urgent', function()
    boot()
    exportsByName.NotifyEveryone('online', { app = 'Settings', title = 'All' })
    equal(#env.sent, 2)
    env.sent = {}
    assert(type(exportsByName.EmergencyNotification(1, { title = 'Alert', content = 'Run' })) == 'number')
    equal(env.sent[1].args[1].urgent, true)
end)

test('AddContact and AddTransaction write to the right character', function()
    boot()
    exportsByName.AddContact('5550001', { number = '5550002', firstname = 'John', lastname = 'Doe' })
    equal(env.contacts[1].deviceId, 11)
    equal(env.contacts[1].contact.displayName, 'John Doe')
    equal(env.contacts[1].contact.phoneNumber, '5550002')
    exportsByName.AddContact('5550001', { number = 'bad', firstname = 'X' })
    equal(#env.contacts, 1)
    exportsByName.AddTransaction('5550001', -25.5, 'Taxi')
    equal(env.activities[1][1], 'CID-A')
    equal(env.activities[1][3], '-$25')
end)

test('SendMessage sends as the number, adds attachments as photo tokens and reports the ids', function()
    boot()
    local got
    local result = exportsByName.SendMessage('5550001', '5550002', 'hello', { 'https://x/y.png' }, function(channel) got = channel end)
    equal(result.channelId, 31)
    equal(result.messageId, 900)
    equal(got, 31)
    equal(env.messages[1].sender.id, 11)
    equal(env.messages[1].payload.to, '5550002')
    equal(env.messages[1].payload.body, 'hello\n[[photo:https://x/y.png]]')
    assert(#env.messages[1].payload.clientRequestId >= 8)
    equal(exportsByName.SendMessage('5550001', 'nope', 'hello'), nil)
    equal(exportsByName.SendMessage('5559999', '5550002', 'hello'), nil)
    exportsByName.SendCoords('5550001', '5550002', { x = 10.7, y = -4.2 })
    equal(env.messages[2].payload.body, '[[loc:11,-4|Shared location]]')
    exportsByName.SentMoney('5550001', '5550002', 40)
    equal(env.messages[3].payload.body, 'Sent you $40')
end)

test('SendMail delivers system mail to a number or a character id', function()
    boot()
    local ok, id = exportsByName.SendMail({ to = '5550002', subject = 'Order', message = 'Ready' })
    equal(ok, true); equal(id, 77)
    equal(env.mails[1][1], 'CID-B')
    equal(env.mails[1][2].subject, 'Order')
    ok = exportsByName.SendMail({ to = 'CID-B', message = 'x' })
    equal(ok, true)
    local failed, reason = exportsByName.SendMail({ to = 'someone@example.com' })
    equal(failed, false); equal(reason, 'unknown_recipient')
end)

test('IsInCall, GetCall and EndCall follow the call service', function()
    boot()
    local inCall, callId = exportsByName.IsInCall(1)
    equal(inCall, true); equal(callId, 'c1')
    equal(exportsByName.IsInCall(2), false)
    equal(exportsByName.GetCall('c1').caller.number, '5550001')
    equal(exportsByName.GetCall('zzz'), nil)
    equal(exportsByName.EndCall(1), true)
    equal(env.hung[1][2], 'c1')
    equal(exportsByName.EndCall(2), false)
end)

test('FactoryReset and ResetSecurity act on the phone with that number; GetPin never reveals a PIN', function()
    boot()
    exportsByName.FactoryReset('5550001')
    equal(env.settingsWrites[1].id, 11)
    assert(env.settingsWrites[1].json:find('setupComplete'), env.settingsWrites[1].json)
    equal(env.pinCleared, 11)
    env.pinCleared = nil
    exportsByName.ResetSecurity('5550002')
    equal(env.pinCleared, 12)
    equal(exportsByName.GetPin('5550001'), nil)
end)

test('AddCheck handlers can refuse an action; RemoveCheck removes them', function()
    boot()
    local id = exportsByName.AddCheck('postBirdy', function() return false end)
    equal(Lb.check('postBirdy', 1), false)
    equal(Lb.check('buyCrypto', 1), true)
    equal(exportsByName.RemoveCheck(id), true)
    equal(Lb.check('postBirdy', 1), true)
    equal(exportsByName.RemoveCheck(id), false)
end)

test('callback exports register under a namespaced Kora callback', function()
    boot()
    exportsByName.RegisterCallback('lookup', function(source, a) return a * 2 end)
    equal(env.callbacks['lbphone:lookup'].fn(1, 4), 8)
    exportsByName.BaseCallback('mine', function(source, number) return number end)
    equal(env.callbacks['lbphone:mine'].fn(1), '5550001')
    local result = exportsByName.AwaitClientCallback('ping', 1, 'a')
    equal(result[2], 'lbphone:ping')
    local async
    exportsByName.TriggerClientCallback('ping', 1, function(v) async = v end, 'b')
    equal(async[3], 'b')
end)

test('unsupported exports return the documented failure and warn once per resource', function()
    boot()
    env.invoking = 'script_a'
    equal(exportsByName.PostBirdy('user', 'hi'), false)
    equal(exportsByName.PostBirdy('user', 'again'), false)
    local ok, reason = exportsByName.CreateMailAccount('a@b.c', 'pw')
    equal(ok, false); equal(reason, 'unsupported')
    equal(exportsByName.GetEmailAddress('5550001'), nil)
    equal(exportsByName.IsPhoneDead('5550001'), false)
    local warnings = 0
    for _, log in ipairs(env.logs) do if log.code == 'phone.compat.unsupported' and log.fields.export == 'PostBirdy' then warnings = warnings + 1 end end
    equal(warnings, 1)
    env.invoking = 'script_b'
    exportsByName.PostBirdy('user', 'hi')
    warnings = 0
    for _, log in ipairs(env.logs) do if log.code == 'phone.compat.unsupported' and log.fields.export == 'PostBirdy' then warnings = warnings + 1 end end
    equal(warnings, 2)
end)

H.finish('lbphone-compat')
