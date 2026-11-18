math.randomseed(os.time())

local DATABASE_POLL_MS = 250

local function stopResource(event, message, reason)
    Kora.logging.event(event, 0, { level = 'error', message = message, error = reason and tostring(reason) or nil })
    StopResource(GetCurrentResourceName())
end

local function waitForDatabase()
    local deadline = GetGameTimer() + Config.Server.DatabaseReadyTimeoutMs
    while GetGameTimer() < deadline and not KoraPhone.Database.isReady() do Wait(DATABASE_POLL_MS) end
    return KoraPhone.Database.isReady()
end

CreateThread(function()
    if not waitForDatabase() then
        return stopResource('phone.database_unavailable', 'Database unavailable; stopping resource')
    end
    local ready, reason = KoraPhone.SchemaSetup.run()
    if not ready then
        return stopResource('phone.database_setup_failed', 'Database setup failed; stopping resource', reason)
    end
    local started, startError = pcall(function()
        KoraPhone.Services.Calling.initialize()
        KoraPhone.Handsets.start()
    end)
    if not started then
        KoraPhone.Handsets.ready = false
        return stopResource('phone.handset_setup_failed', 'Handset setup failed', startError)
    end
    Kora.logging.event('phone.server_ready', 0, {
        level = 'info', message = 'Server foundation ready',
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown',
    })
end)

RegisterNetEvent('kora_phone:server:phone:closed', function()
    local requestSource = source
    KoraPhone.Services.Calling.disconnect(requestSource, 'phone_put_away')
    if not KoraPhone.RateLimits.consume(requestSource, 'mutation') then return end
    local session = KoraPhone.Sessions.bySource[requestSource]
    if session then session.unlocked = false end
end)

-- /phonereset [id]: wipes a player's phone settings and PIN so the setup screen shows again.
-- No id resets your own phone. Moderators only (kora.phone.moderate ace or a kora_core admin/god permission); console needs an id.
RegisterCommand('phonereset', function(caller, args)
    local function reply(message)
        if caller == 0 then
            Kora.print.info('phone.reset_command', message)
        else
            Kora.notify.send(caller, { title = 'Phone', message = message, type = 'info', duration = 4000 })
        end
    end
    if caller ~= 0 and not KoraPhone.Services.Moderation.isModerator(caller) then return reply('No permission') end
    local target = tonumber(args[1]) or caller
    local citizenId = target ~= 0 and KoraPhone.GetCitizenId(target)
    local device = citizenId and KoraPhone.Handsets.current(target, false)
    if not device then return reply('No phone found for player ' .. tostring(args[1] or target)) end
    -- setupComplete=false, not '{}': the UI merges bootstrap settings over its cached ones, so a missing key would keep the old true.
    KoraPhone.Repositories.Phones.updateSettings(device.id, json.encode({ setupComplete = false }))
    -- Clearing the PIN also drops the handset's Face ID enrolment.
    KoraPhone.Repositories.Phones.clearPin(device.id)
    TriggerClientEvent('kora_phone:client:reset', target)
    reply(('Phone reset for player %d'):format(target))
end, false)

AddEventHandler('kora_core:server:playerUnloaded', function(src)
    KoraPhone.Sessions.close(src)
end)

exports('GetPhoneNumber', function(source)
    local device = KoraPhone.Handsets.current(source, false)
    return device and device.cellular and device.phoneNumber or nil
end)

exports('GetSourceByPhoneNumber', function(phoneNumber)
    local normalized = PhoneValidation.phoneNumber(phoneNumber)
    return normalized and KoraPhone.Sessions.sourceByNumber(normalized) or nil
end)

exports('SendNotification', function(target, notification)
    if type(target) ~= 'number' or type(notification) ~= 'table' then return false end
    TriggerClientEvent('kora_phone:client:notification', target, {
        app = tostring(notification.app or 'system'):sub(1, 32),
        title = tostring(notification.title or ''):sub(1, 80),
        body = tostring(notification.body or ''):sub(1, 240),
        message = tostring(notification.body or ''):sub(1, 240),
        data = type(notification.data) == 'table' and notification.data or {}
    })
    return true
end)