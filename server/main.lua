math.randomseed(os.time())

CreateThread(function()
    local deadline = GetGameTimer() + Config.Server.DatabaseReadyTimeoutMs
    while GetGameTimer() < deadline and not QBPhone.Database.isReady() do Wait(250) end
    if not QBPhone.Database.isReady() then
        print('[qbphone] Database unavailable; stopping resource')
        StopResource(GetCurrentResourceName())
        return
    end
    local ready, reason = QBPhone.SchemaSetup.run()
    if not ready then
        print('[qbphone] Database setup failed, stopping resource: ' .. tostring(reason))
        StopResource(GetCurrentResourceName())
        return
    end
    local started,startError=pcall(function()
        QBPhone.Services.Calling.initialize()
        QBPhone.Handsets.start()
    end)
    if not started then
        print('[qbphone] handset setup failed: '..tostring(startError))
        QBPhone.Handsets.ready=false
        StopResource(GetCurrentResourceName()); return
    end
    print(('[qbphone] server foundation ready (v%s)'):format(GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown'))
end)

RegisterNetEvent('qbphone:server:phone:closed', function()
    local requestSource = source
    QBPhone.Services.Calling.disconnect(requestSource, 'phone_put_away')
    if not QBPhone.RateLimits.consume(requestSource, 'mutation') then return end
    local session = QBPhone.Sessions.bySource[requestSource]
    if session then session.unlocked = false end
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    -- Provision only when a physical handset is selected, after startup finishes.
end)

-- /phonereset [id]: wipes a player's phone settings and PIN so the setup screen shows again.
-- No id resets your own phone. Moderators only (qbphone.moderate ace or QBCore admin/god); console needs an id.
RegisterCommand('phonereset', function(caller, args)
    local function reply(msg)
        if caller == 0 then print('[qbphone] ' .. msg) else TriggerClientEvent('QBCore:Notify', caller, msg) end
    end
    if caller ~= 0 and not QBPhone.Services.Moderation.isModerator(caller) then return reply('No permission') end
    local target = tonumber(args[1]) or caller
    local citizenId = target ~= 0 and QBPhone.GetCitizenId(target)
    local device = citizenId and QBPhone.Handsets.current(target, false)
    if not device then return reply('No phone found for player ' .. tostring(args[1] or target)) end
    -- setupComplete=false, not '{}': the UI merges bootstrap settings over its cached ones, so a missing key would keep the old true.
    QBPhone.Repositories.Phones.updateSettings(device.id, json.encode({ setupComplete = false }))
    QBPhone.Repositories.Phones.clearPin(device.id)
    MySQL.update.await('UPDATE phone_handsets SET face_citizenid=NULL WHERE device_id=?',{device.id})
    TriggerClientEvent('qbphone:client:reset', target)
    reply(('Phone reset for player %d'):format(target))
end, false)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    QBPhone.Sessions.close(source)
end)

exports('GetPhoneNumber', function(source)
    local device = QBPhone.Handsets.current(source, false)
    return device and device.cellular and device.phoneNumber or nil
end)

exports('GetSourceByPhoneNumber', function(phoneNumber)
    local normalized = PhoneValidation.phoneNumber(phoneNumber)
    return normalized and QBPhone.Sessions.sourceByNumber(normalized) or nil
end)

exports('SendNotification', function(target, notification)
    if type(target) ~= 'number' or type(notification) ~= 'table' then return false end
    TriggerClientEvent('qbphone:client:notification', target, {
        app = tostring(notification.app or 'system'):sub(1, 32),
        title = tostring(notification.title or ''):sub(1, 80),
        body = tostring(notification.body or ''):sub(1, 240),
        message = tostring(notification.body or ''):sub(1, 240),
        data = type(notification.data) == 'table' and notification.data or {}
    })
    return true
end)
