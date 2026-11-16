KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Delivers server pushes (exports.kora_phone:SendAppEvent / apps:notify) to the NUI.
-- The frame forwards `app:event` to the matching app iframe as an `event` message.
local Events = {}
KoraPhone.SDK.Events = Events

local NAME_PATTERN = '^[a-zA-Z0-9_:.-]+$'

function Events.deliver(appId, name, data)
    if type(appId) ~= 'string' or type(name) ~= 'string' then return false end
    if #name < 1 or #name > 48 or not name:match(NAME_PATTERN) then return false end
    SendNUIMessage({ type = 'app:event', app = appId, name = name, data = data })
    return true
end

function Events.notify(appId, appName, title, body)
    if type(title) ~= 'string' then return false end
    if KoraPhone.Notifications and KoraPhone.Notifications.Native then
        return KoraPhone.Notifications.Native(title, type(body) == 'string' and body or '', false)
    end
    return false
end

RegisterNetEvent('kora_phone:client:appEvent', function(appId, name, data)
    Events.deliver(appId, name, data)
end)

RegisterNetEvent('kora_phone:client:appNotify', function(appId, appName, title, body)
    Events.notify(appId, appName, title, body)
end)
