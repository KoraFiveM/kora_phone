QBPhone = QBPhone or {}
local Notifications = {}

local function valid(notification)
    return type(notification) == 'table'
        and type(notification.title) == 'string'
        and #notification.title <= 80
        and (notification.message == nil or (type(notification.message) == 'string' and #notification.message <= 500))
end

-- The on-screen note and tone for something that arrives while the phone is closed. Do Not Disturb silences
-- it unless it's urgent. (The UI hides with the phone, so this is the only way a closed phone gets noticed.)
function Notifications.Native(title, body, urgent)
    if QBPhone.State.quiet and not urgent then return false end
    QB.notify.send({ title = title, message = body, type = urgent and 'error' or 'info', duration = 4500 })
    if Config.Client.NotificationSound ~= false then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end
    return true
end

function Notifications.Push(notification)
    if not valid(notification) then return false end
    QB.nui.send('notification:push', notification)
    -- Do Not Disturb silences the on-screen native alert; urgent ones (a shown ID) still get through.
    if not QBPhone.State.open and notification.native ~= false then
        Notifications.Native(notification.title, tostring(notification.message or ''), notification.urgent == true)
    end
    return true
end

RegisterNetEvent('qbphone:client:notification', function(notification)
    Notifications.Push(notification)
end)

-- Someone nearby showed you their ID from their Wallet. The server builds the card.
RegisterNetEvent('qbphone:client:wallet:shown', function(card)
    if type(card) ~= 'table' or type(card.name) ~= 'string' or type(card.licences) ~= 'table' then return end
    local parts = {}
    for _, licence in ipairs(card.licences) do
        if type(licence) == 'table' and type(licence.label) == 'string' then
            parts[#parts + 1] = licence.label:sub(1, 30) .. (licence.valid and ' ✓' or ' ✗')
        end
    end
    local body = ('Born %s · %s'):format(tostring(card.birthdate):sub(1, 20), table.concat(parts, ', '))
    Notifications.Push({ title = card.name:sub(1, 45) .. ' showed you their ID', body = body, message = body, app = 'banking', urgent = true })
end)

-- Solo testing: set Config.Debug = true in config/shared.lua, restart the resource, then
-- use /phonetest [message|sms|wallet|system|long]. Off by default, never registered in production.
if Config.Debug then
    local samples = {
        message = { title = 'Jules Chen', body = 'Are you still on for Pillbox tonight?', app = 'messages' },
        wallet = { title = 'Wallet', body = 'You received $2,500 from Maya.', app = 'banking' },
        system = { title = 'System', body = 'Unknown app id: tapping should land on home.', app = 'system' },
        long = { title = 'A very long notification title that keeps going', body = string.rep('Long body text. ', 12), app = 'messages' },
    }
    RegisterCommand('phonetest', function(_, args)
        local kind = args[1] or 'message'
        if kind == 'sms' then
            -- Exercises the same event the server sends for a real incoming text.
            TriggerEvent('qbphone:client:messages:new', { id = 0, conversationId = 0, senderNumber = '5550109999', body = 'Test text from /phonetest', isMine = 0 })
            return
        end
        local sample = samples[kind]
        if not sample then
            print('[qbphone] /phonetest kinds: message, sms, wallet, system, long')
            return
        end
        Notifications.Push({ title = sample.title, body = sample.body, message = sample.body, app = sample.app, native = false })
    end, false)
end

QBPhone.Notifications = Notifications
