KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Server exports and resource lifecycle for the app SDK.
local SDK = KoraPhone.SDK

local function invoking()
    return GetInvokingResource() or GetCurrentResourceName()
end

local function ownsApp(app, resource)
    return app ~= nil and (app.resource == resource or resource == GetCurrentResourceName())
end

exports('RegisterApp', function(manifest)
    return SDK.Registry.register(manifest, invoking(), { files = SDK.Discovery.files })
end)

exports('RemoveApp', function(id)
    return SDK.Registry.remove(id, invoking())
end)

exports('RegisterAppCallback', function(appId, name, handler)
    return SDK.Callbacks.register(appId, name, handler, invoking())
end)

--- Pushes an event to the player's open app iframe. Only the owning resource may send.
exports('SendAppEvent', function(source, appId, name, data)
    if type(source) ~= 'number' or source <= 0 then return false end
    if not ownsApp(SDK.Registry.get(appId), invoking()) then return false end
    if not SDK.Callbacks.validName(name) then return false end
    TriggerClientEvent('kora_phone:client:appEvent', source, appId, name, data)
    return true
end)

exports('GetInstalledApps', function(source)
    local citizenId = KoraPhone.Permissions.requirePlayer(source)
    if not citizenId then return {} end
    local device = KoraPhone.Services.Phone.getOrCreate(citizenId)
    return device and SDK.Install.list(device) or {}
end)

AddEventHandler('onServerResourceStart', function(resource)
    SDK.Discovery.scan(resource)
end)

AddEventHandler('onResourceStop', function(resource)
    SDK.Registry.removeByResource(resource)
end)

-- Apps already running when the phone starts (or restarts).
CreateThread(function()
    SDK.Discovery.scanAll()
end)
