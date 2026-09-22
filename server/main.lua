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

-- /phonereset [id]: wipes a player's phone settings and PIN so the setup screen shows again.
-- No id resets your own phone. Moderators only (steviephone.moderate ace or QBCore admin/god); console needs an id.
RegisterCommand('phonereset', function(caller, args)
    local function reply(msg)
        if caller == 0 then print('[stevie-phone] ' .. msg) else TriggerClientEvent('QBCore:Notify', caller, msg) end
    end
    if caller ~= 0 and not SteviePhone.Services.Moderation.isModerator(caller) then return reply('No permission') end
    local target = tonumber(args[1]) or caller
    local citizenId = target ~= 0 and SteviePhone.GetCitizenId(target)
    local device = citizenId and SteviePhone.Repositories.Phones.findByCitizenId(citizenId)
    if not device then return reply('No phone found for player ' .. tostring(args[1] or target)) end
    -- setupComplete=false, not '{}': the UI merges bootstrap settings over its cached ones, so a missing key would keep the old true.
    SteviePhone.Repositories.Phones.updateSettings(device.id, json.encode({ setupComplete = false }))
    SteviePhone.Repositories.Phones.clearPin(device.id)
    TriggerClientEvent('stevie-phone:client:reset', target)
    reply(('Phone reset for player %d'):format(target))
end, false)

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
