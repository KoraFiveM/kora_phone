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
    local body = Kora.lang('wallet.born', tostring(card.birthdate):sub(1, 20), table.concat(parts, ', '))
    Notifications.Push({
        title = Kora.lang('wallet.showed_id', card.name:sub(1, 45)),
        body = body,
        message = body,
        app = 'banking',
        urgent = true,
    })
end)

KoraPhone.Notifications = Notifications