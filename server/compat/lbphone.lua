KoraPhone = KoraPhone or {}
KoraPhone.Compat = KoraPhone.Compat or {}

-- lb-phone server exports (https://docs.lbscripts.com/phone/exports/server-exports/), answered by this phone.
--
-- Scripts written for lb-phone call `exports['lb-phone']:Name(...)`. FiveM resolves that through the local event
-- `__cfx_export_lb-phone_Name`, which this file answers (the resource also declares `provide 'lb-phone'`, so
-- GetResourceState('lb-phone') reads as started). Every export lb-phone documents is answered:
--   * mapped      - does the real thing through this phone's own services
--   * unsupported - there is no Kora equivalent (Birdy, InstaPic, Trendy, DarkChat, crypto, mail addresses ...). The
--                   call returns lb-phone's documented failure value and logs ONE warning per calling resource, so
--                   a script never errors and the server owner can see what to replace.
-- docs/lb-phone.md lists each export with its status.
local Lb = { api = {}, status = {}, checks = {}, nextCheck = 1, nextNotification = 1, warned = {} }
KoraPhone.Compat.LbPhone = Lb
local api = Lb.api

local function mapped(name, fn) api[name] = fn; Lb.status[name] = 'mapped' end

local function unsupported(name, default, reason)
    Lb.status[name] = 'unsupported'
    api[name] = function(...)
        local resource = GetInvokingResource() or 'unknown'
        local key = resource .. ':' .. name
        if not Lb.warned[key] then
            Lb.warned[key] = true
            Kora.logging.event('phone.compat.unsupported', 0, {
                level = 'warn', message = 'lb-phone export has no equivalent in kora_phone',
                export = name, resource = resource, reason = reason,
            })
        end
        if type(default) == 'function' then return default(...) end
        return default
    end
end

-- Helpers ---------------------------------------------------------------------------------------

local function normalized(number)
    if type(number) ~= 'string' and type(number) ~= 'number' then return nil end
    return (PhoneValidation.phoneNumber(tostring(number)))
end

---A phone number, a player source or a character id -> the online player's source.
local function sourceOf(target)
    if type(target) == 'number' then return target end
    local number = normalized(target)
    if number then return KoraPhone.Sessions.sourceByNumber(number) end
    if type(target) == 'string' then
        local player = exports.kora_core:getPlayerByCitizenId(target)
        return player and player.source or nil
    end
end

local function deviceOfNumber(number)
    number = normalized(number)
    return number and KoraPhone.Repositories.Phones.findByNumber(number) or nil, number
end

local function numberOfSource(source)
    local device = KoraPhone.Handsets.current(source, false)
    return device and device.cellular and device.phoneNumber or nil
end

local function settingsOf(source)
    local device = KoraPhone.Handsets.current(source, false)
    if not device then return nil end
    local ok, decoded = pcall(json.decode, device.settingsJson or '{}')
    return ok and type(decoded) == 'table' and decoded or {}
end

local function text(value, max)
    return type(value) == 'string' and value:sub(1, max) or nil
end

local function push(source, data)
    TriggerClientEvent('kora_phone:client:notification', source, data)
end

-- Phone and player -------------------------------------------------------------------------------

mapped('GetEquippedPhoneNumber', function(target)
    local source = sourceOf(target)
    return source and numberOfSource(source) or nil
end)

mapped('GetSourceFromNumber', function(number)
    local normalizedNumber = normalized(number)
    return normalizedNumber and KoraPhone.Sessions.sourceByNumber(normalizedNumber) or false
end)

mapped('HasPhoneItem', function(source, number)
    if type(source) ~= 'number' or not KoraPhone.HasPhone(source) then return false end
    if number == nil then return true end
    return numberOfSource(source) == normalized(number)
end)

mapped('FormatNumber', function(number)
    return type(number) == 'string' and number or tostring(number or '')
end)

mapped('GetSettings', function(number)
    local source = sourceOf(number)
    return source and settingsOf(source) or nil
end)

mapped('HasAirplaneMode', function(number)
    local source = sourceOf(number)
    local settings = source and settingsOf(source)
    if not settings then return nil end
    return settings.airplane == true
end)

mapped('GetConfig', function()
    return { Framework = 'kora', PhoneNumber = { Prefix = Config.PhoneNumber.Prefix, Length = #Config.PhoneNumber.Prefix + Config.PhoneNumber.SubscriberDigits } }
end)

mapped('GetCellTowers', function() return {} end)

mapped('ContainsBlacklistedWord', function() return false end)

mapped('FactoryReset', function(number)
    local device = deviceOfNumber(number)
    if not device then return end
    -- Same effect as the in-game /resetphone command: setup runs again and the PIN is cleared.
    KoraPhone.Repositories.Phones.updateSettings(device.id, json.encode({ setupComplete = false }))
    KoraPhone.Repositories.Phones.clearPin(device.id)
    local source = sourceOf(number)
    if source then TriggerClientEvent('kora_phone:client:reset', source) end
end)

-- PINs are stored as salted hashes: there is nothing to hand back, by design.
mapped('GetPin', function() return nil end)

mapped('ResetSecurity', function(number)
    local device = deviceOfNumber(number)
    if device then KoraPhone.Repositories.Phones.clearPin(device.id) end
end)

-- Notifications ----------------------------------------------------------------------------------

local function notification(data, urgent)
    local body = text(data.content or data.body, 500) or ''
    local buttons = type(data.customData) == 'table' and data.customData.buttons or nil
    return {
        app = tostring(data.app or 'system'):lower():sub(1, 32),
        title = text(data.title, 80) or '',
        body = body, message = body,
        thumbnail = text(data.thumbnail, 300), avatar = text(data.avatar, 300),
        urgent = urgent or nil,
        data = type(buttons) == 'table' and { buttons = buttons } or {},
    }
end

mapped('SendNotification', function(target, data, cb)
    if type(data) ~= 'table' or (not data.title and not data.content) then return nil end
    local source = sourceOf(target)
    if not source then
        -- Kora keeps no stored notifications for phones that are off or not held, so an offline target gets nothing.
        if type(cb) == 'function' then cb(false) end
        return nil
    end
    push(source, notification(data))
    -- lb-phone saves (and numbers) notifications sent to a phone number; a source target shows once and has no id.
    local id
    if type(target) ~= 'number' then
        id = Lb.nextNotification
        Lb.nextNotification = id + 1
    end
    if type(cb) == 'function' then cb(id or true) end
    return id
end)

mapped('NotifyEveryone', function(_, data)
    if type(data) ~= 'table' or not data.title then return end
    local payload = notification(data)
    for source in pairs(KoraPhone.Sessions.bySource) do push(source, payload) end
end)

mapped('EmergencyNotification', function(source, data)
    if type(source) ~= 'number' or type(data) ~= 'table' then return nil end
    push(source, notification({ app = 'system', title = data.title, content = data.content }, true))
    local id = Lb.nextNotification
    Lb.nextNotification = id + 1
    return id
end)

-- Contacts, wallet, messages ---------------------------------------------------------------------

mapped('AddContact', function(phoneNumber, data)
    local device = deviceOfNumber(phoneNumber)
    local number = type(data) == 'table' and normalized(data.number)
    if not device or not number then return end
    local name = ((text(data.firstname, 40) or '') .. ' ' .. (text(data.lastname, 40) or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return end
    local existing = KoraPhone.Repositories.Contacts.findByNumber(device.id, number)
    KoraPhone.Repositories.Contacts.upsert(device.id, { id = existing, displayName = name, phoneNumber = number, isFavorite = false })
end)

mapped('AddTransaction', function(phoneNumber, amount, title)
    local device = deviceOfNumber(phoneNumber)
    if not device or type(amount) ~= 'number' then return end
    local sign = amount < 0 and '-' or '+'
    KoraPhone.SystemMail.addActivity(device.ownerCitizenId, text(title, 100) or 'Transaction', ('%s$%s'):format(sign, math.floor(math.abs(amount))))
end)

local requestCounter = 0
local function requestId()
    requestCounter = requestCounter + 1
    return ('lb-%d-%d'):format(os.time(), requestCounter)
end

local function sendMessage(from, to, body)
    local sender = deviceOfNumber(from)
    local recipient = normalized(to)
    if not sender or not recipient then return nil end
    local result = KoraPhone.Services.Messaging.sendAs(sender, { to = recipient, body = body, clientRequestId = requestId() })
    if not result or result.ok == false then return nil end
    local data = result.data or {}
    return { channelId = data.conversationId, messageId = data.id }
end

mapped('SendMessage', function(from, to, message, attachments, cb)
    local body = type(message) == 'string' and message or ''
    for _, url in ipairs(type(attachments) == 'table' and attachments or {}) do
        if type(url) == 'string' then body = body .. '\n[[photo:' .. url .. ']]' end
    end
    body = body:gsub('^\n', '')
    local result = body ~= '' and sendMessage(from, to, body) or nil
    if type(cb) == 'function' then cb(result and result.channelId or false) end
    return result
end)

mapped('SentMoney', function(from, to, amount)
    if type(amount) ~= 'number' then return end
    sendMessage(from, to, ('Sent you $%d'):format(math.floor(amount)))
end)

mapped('SendCoords', function(from, to, coords)
    if type(coords) ~= 'table' then return end
    local x, y = tonumber(coords.x or coords[1]), tonumber(coords.y or coords[2])
    if not x or not y then return end
    sendMessage(from, to, ('[[loc:%d,%d|Shared location]]'):format(math.floor(x + 0.5), math.floor(y + 0.5)))
end)

-- Mail: system mail is delivered to a character. `to` may be a phone number or a character id.
mapped('SendMail', function(data)
    if type(data) ~= 'table' or type(data.to) ~= 'string' then return false, 'invalid_recipient' end
    local device = deviceOfNumber(data.to)
    local citizenId = device and device.ownerCitizenId
    if not citizenId then
        local player = exports.kora_core:getPlayerByCitizenId(data.to)
        citizenId = player and data.to
    end
    if not citizenId then return false, 'unknown_recipient' end
    local id, err = KoraPhone.SystemMail.send(citizenId, {
        sender = data.sender or 'System', subject = data.subject or 'System mail', message = data.message or '',
    })
    if not id then return false, err end
    return true, id
end)

-- Calls ------------------------------------------------------------------------------------------

local function callOf(source)
    local device = KoraPhone.Handsets.current(source, false)
    local callId = device and KoraPhone.Services.Calling.callByDevice[device.id]
    return callId and KoraPhone.Services.Calling.activeById[callId] or nil, callId
end

mapped('IsInCall', function(source)
    if type(source) ~= 'number' then return false end
    local call, callId = callOf(source)
    if not call then return false end
    return true, callId, call
end)

mapped('GetCall', function(callId)
    local call = KoraPhone.Services.Calling.activeById[callId]
    if not call then return nil end
    return { callId = call.id, started = call.startedAt, answered = call.status == 'active', videoCall = false, hideCallerId = false,
        caller = { number = call.callerNumber, nearby = {} }, callee = { number = call.calleeNumber, nearby = {} } }
end)

mapped('EndCall', function(source, cb)
    local call = type(source) == 'number' and callOf(source)
    if not call then
        if type(cb) == 'function' then cb(false) end
        return false
    end
    local result = KoraPhone.Services.Calling.hangup(source, { id = call.id })
    local ok = result and result.ok ~= false
    if type(cb) == 'function' then cb(ok) end
    return ok
end)

unsupported('CreateCall', nil, 'calls are started by players through the Phone app')
unsupported('ForwardCall', function() return nil, 'call_ended' end, 'custom numbers and forwarding are not part of kora_phone')

-- Sharing, hooks, callbacks ------------------------------------------------------------------------

unsupported('AirShare', nil, 'use the Share phone number interaction; AirShare payloads are not supported')

mapped('AddCheck', function(event, handler)
    if type(event) ~= 'string' or not Kora.util.isCallable(handler) then return nil end
    local id = Lb.nextCheck
    Lb.nextCheck = id + 1
    Lb.checks[id] = { event = event, handler = handler }
    return id
end)

mapped('RemoveCheck', function(id)
    if not Lb.checks[id] then return false end
    Lb.checks[id] = nil
    return true
end)

---Runs the handlers an lb-phone script registered with AddCheck for `event`. False when any refuses the action.
function Lb.check(event, source, ...)
    for _, check in pairs(Lb.checks) do
        if check.event == event then
            local ok, allowed = pcall(check.handler, source, ...)
            if ok and allowed == false then return false end
        end
    end
    return true
end

local function callbackName(event) return 'lbphone:' .. tostring(event) end

mapped('RegisterCallback', function(event, handler, options)
    if type(event) ~= 'string' or not Kora.util.isCallable(handler) then return end
    local rate = type(options) == 'table' and tonumber(options.rateLimit) or nil
    Kora.callback.register(callbackName(event), function(source, ...) return handler(source, ...) end,
        rate and { rateLimit = { max = rate, window = 60000 } } or nil)
end)

mapped('BaseCallback', function(event, callback)
    if type(event) ~= 'string' or not Kora.util.isCallable(callback) then return end
    Kora.callback.register(callbackName(event), function(source, ...) return callback(source, numberOfSource(source), ...) end)
end)

mapped('AwaitClientCallback', function(event, source, ...)
    return Kora.callback.trigger(source, callbackName(event), ...)
end)

mapped('TriggerClientCallback', function(event, source, cb, ...)
    local args = table.pack(...)
    CreateThread(function()
        local ok, result = pcall(Kora.callback.trigger, source, callbackName(event), table.unpack(args, 1, args.n))
        if type(cb) == 'function' then cb(ok and result or nil) end
    end)
end)

-- Battery: handsets here have no battery model, so they are never dead and there is nothing to save.
mapped('SaveBattery', function() end)
mapped('SaveAllBatteries', function() end)
mapped('IsPhoneDead', function() return false end)

-- Everything below has no Kora equivalent. The default is lb-phone's documented "failed" return.
local NO_ACCOUNT = 'kora_phone has no per-app social accounts (Pulse and Flash use your phone number)'
unsupported('GetSocialMediaUsername', false, NO_ACCOUNT)
unsupported('ToggleVerified', false, NO_ACCOUNT)
unsupported('IsVerified', false, NO_ACCOUNT)
unsupported('ChangePassword', false, NO_ACCOUNT)
unsupported('PostBirdy', false, NO_ACCOUNT)
unsupported('GetBirdyPost', nil, NO_ACCOUNT)
unsupported('PostInstaPic', false, NO_ACCOUNT)
unsupported('DeleteBirdyAccount', false, NO_ACCOUNT)
unsupported('DeleteInstaPicAccount', false, NO_ACCOUNT)
unsupported('DeleteTrendyAccount', false, NO_ACCOUNT)
unsupported('CreateMailAccount', function() return false, 'unsupported' end, 'mail uses phone numbers, not email addresses')
unsupported('GetEmailAddress', nil, 'mail uses phone numbers, not email addresses')
unsupported('DeleteMail', false, 'system mail cannot be deleted by other resources')
unsupported('SendDarkChatMessage', false, 'there is no DarkChat app')
unsupported('SendDarkChatLocation', false, 'there is no DarkChat app')
unsupported('CreateDarkChatChannel', function() return false, 'unsupported' end, 'there is no DarkChat app')
unsupported('DeleteDarkChatChannel', false, 'there is no DarkChat app')
unsupported('AddUserToDarkChatChannel', false, 'there is no DarkChat app')
unsupported('RemoveUserFromDarkChatChannel', false, 'there is no DarkChat app')
unsupported('AddCrypto', false, 'there is no Crypto app')
unsupported('RemoveCrypto', false, 'there is no Crypto app')
unsupported('AddCustomCoin', nil, 'there is no Crypto app')
unsupported('GetCoin', nil, 'there is no Crypto app')
unsupported('GetOwnedCoin', false, 'there is no Crypto app')

-- Registration -----------------------------------------------------------------------------------

---Answers `exports['lb-phone']:Name(...)` for every export above. Returns how many were registered.
function Lb.register()
    local count = 0
    for name, handler in pairs(api) do
        AddEventHandler(('__cfx_export_lb-phone_%s'):format(name), function(setCallback) setCallback(handler) end)
        count = count + 1
    end
    return count
end

Lb.register()
