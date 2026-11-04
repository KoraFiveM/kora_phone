KoraPhone = KoraPhone or {}
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
    if KoraPhone.State.quiet and not urgent then return false end
    Kora.notify.send({ title = title, message = body, type = urgent and 'error' or 'info', duration = 4500 })
    if Config.Client.NotificationSound ~= false then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end
    return true
end

function Notifications.Push(notification)
    if not valid(notification) then return false end
    KoraPhone.SendNui('notification:push', notification)
    -- Do Not Disturb silences the on-screen native alert; urgent ones (a shown ID) still get through.
    if not KoraPhone.State.open and notification.native ~= false then
        Notifications.Native(notification.title, tostring(notification.message or ''), notification.urgent == true)
    end
    return true
end

RegisterNetEvent('kora_phone:client:notification', function(notification)
    Notifications.Push(notification)
end)

-- Someone nearby showed you their ID from their Wallet. The server builds the card.
RegisterNetEvent('kora_phone:client:wallet:shown', function(card)
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

RegisterCommand('testnotify', function(_, args)
    local kind = args[1]
    local samples = {
        { title = 'Jules Chen', body = 'Are you still on for Pillbox tonight?', app = 'messages' },
        { title = 'Missed call', body = '555-0109', app = 'phone' },
        { title = 'Wallet', body = 'You received $2,500 from Maya.', app = 'banking' },
        { title = 'New Mail', body = 'Your vehicle registration is ready.', app = 'mail' },
        { title = 'Pulse', body = 'Kai posted a new update.', app = 'social' },
        { title = 'Market', body = 'Your listing got a reply.', app = 'classifieds' },
        { title = 'Maps', body = 'Waypoint set to Pillbox Medical.', app = 'gps' },
        { title = 'Weather', body = 'Clear skies over Los Santos.', app = 'weather' },
        { title = 'Flash', body = 'Someone liked your clip.', app = 'flash' },
        { title = 'Clock', body = 'Alarm: Wake up.', app = 'clock' },
        { title = 'System', body = 'Phone connected.', app = 'system' },
    }
    if kind == 'sms' then
        TriggerEvent('kora_phone:client:messages:new', { id = 0, conversationId = 0, senderNumber = '5550109999', body = 'Test text from /testnotify', isMine = 0 })
        return
    end
    if kind == 'all' then
        for i, sample in ipairs(samples) do
            SetTimeout((i - 1) * 800, function()
                Notifications.Push({ title = sample.title, body = sample.body, message = sample.body, app = sample.app })
            end)
        end
        return
    end
    if kind then
        for _, sample in ipairs(samples) do
            if sample.app == kind then
                Notifications.Push({ title = sample.title, body = sample.body, message = sample.body, app = sample.app })
                return
            end
        end
        print('[kora_phone] /testnotify: unknown app "' .. kind .. '"')
        return
    end
    Notifications.Push({ title = samples[1].title, body = samples[1].body, message = samples[1].body, app = samples[1].app })
    print('[kora_phone] /testnotify [all|sms|messages|phone|banking|mail|social|classifieds|gps|weather|flash|clock|system]')
end, false)

KoraPhone.Notifications = Notifications