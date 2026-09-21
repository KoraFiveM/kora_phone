math.randomseed(os.time())

if SteviePhone.Modules and SteviePhone.Modules.CallCallbacks then
    SteviePhone.Modules.CallCallbacks.register()
end

CreateThread(function()
    local deadline = GetGameTimer() + Config.Server.DatabaseReadyTimeoutMs
    while GetGameTimer() < deadline and not SteviePhone.Database.isReady() do Wait(250) end
    if not SteviePhone.Database.isReady() then
        print('[stevie-phone] Database unavailable; stopping resource')
        StopResource(GetCurrentResourceName())
        return
    end
    local migrated, reason = SteviePhone.Migrations.run()
    if not migrated then
        print('[stevie-phone] Database setup failed, stopping resource: ' .. tostring(reason))
        StopResource(GetCurrentResourceName())
        return
    end
    print(('[stevie-phone] server foundation ready (v%s)'):format(GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown'))
end)

RegisterNetEvent('stevie-phone:server:phone:closed', function()
    local requestSource = source
    if not SteviePhone.RateLimits.consume(requestSource, 'mutation') then return end
    local session = SteviePhone.Sessions.bySource[requestSource]
    if session then session.unlocked = false end
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if not player or not player.PlayerData then return end
    local source = player.PlayerData.source
    local device = SteviePhone.Services.Phone.getOrCreate(player.PlayerData.citizenid)
    if source and device and SteviePhone.HasPhone(source) then SteviePhone.Sessions.open(source, device) end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    SteviePhone.Sessions.close(source)
end)

exports('GetPhoneNumber', function(source)
    local session = SteviePhone.Sessions.bySource[source]
    if session then return session.phoneNumber end
    local citizenId = SteviePhone.GetCitizenId(source)
    local device = citizenId and SteviePhone.Repositories.Phones.findByCitizenId(citizenId) or nil
    return device and device.phoneNumber or nil
end)

exports('GetSourceByPhoneNumber', function(phoneNumber)
    local normalized = PhoneValidation.phoneNumber(phoneNumber)
    return normalized and SteviePhone.Sessions.sourceByNumber(normalized) or nil
end)

exports('SendNotification', function(target, notification)
    if type(target) ~= 'number' or type(notification) ~= 'table' then return false end
    TriggerClientEvent('stevie-phone:client:notification', target, {
        app = tostring(notification.app or 'system'):sub(1, 32),
        title = tostring(notification.title or ''):sub(1, 80),
        body = tostring(notification.body or ''):sub(1, 240),
        message = tostring(notification.body or ''):sub(1, 240),
        data = type(notification.data) == 'table' and notification.data or {}
    })
    return true
end)
