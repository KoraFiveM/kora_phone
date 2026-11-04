KoraPhone.registerCallback('calls:start', 'callStart', KoraPhone.Services.Calling.start)
KoraPhone.registerCallback('calls:accept', 'mutation', KoraPhone.Services.Calling.accept)
KoraPhone.registerCallback('calls:reject', 'mutation', KoraPhone.Services.Calling.reject)
KoraPhone.registerCallback('calls:hangup', 'mutation', KoraPhone.Services.Calling.hangup)
KoraPhone.registerCallback('calls:history', 'read', KoraPhone.Services.Calling.history)
KoraPhone.registerCallback('calls:signal', 'videoSignal', KoraPhone.Services.Calling.videoSignal)

RegisterNetEvent('kora_phone:server:calls:voiceFailure', function(callId)
    local requestSource = source
    if KoraPhone.RateLimits.consume(requestSource, 'mutation') then
        KoraPhone.Services.Calling.voiceFailure(requestSource, callId)
    end
end)

RegisterNetEvent('kora_phone:server:calls:hangup', function(callId)
    local requestSource = source
    if KoraPhone.RateLimits.consume(requestSource, 'mutation') then
        KoraPhone.Services.Calling.hangup(requestSource, { id = callId })
    end
end)