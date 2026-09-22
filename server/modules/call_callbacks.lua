QBPhone.registerCallback('calls:start', 'callStart', QBPhone.Services.Calling.start)
QBPhone.registerCallback('calls:accept', 'mutation', QBPhone.Services.Calling.accept)
QBPhone.registerCallback('calls:reject', 'mutation', QBPhone.Services.Calling.reject)
QBPhone.registerCallback('calls:hangup', 'mutation', QBPhone.Services.Calling.hangup)
QBPhone.registerCallback('calls:history', 'read', QBPhone.Services.Calling.history)
QBPhone.registerCallback('calls:signal', 'videoSignal', QBPhone.Services.Calling.videoSignal)

RegisterNetEvent('qbphone:server:calls:voiceFailure', function(callId)
    local requestSource = source
    if QBPhone.RateLimits.consume(requestSource, 'mutation') then
        QBPhone.Services.Calling.voiceFailure(requestSource, callId)
    end
end)

RegisterNetEvent('qbphone:server:calls:hangup', function(callId)
    local requestSource = source
    if QBPhone.RateLimits.consume(requestSource, 'mutation') then
        QBPhone.Services.Calling.hangup(requestSource, { id = callId })
    end
end)
