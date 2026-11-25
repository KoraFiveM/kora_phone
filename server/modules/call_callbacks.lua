local bind = KoraPhone.Routes.handle
local Calling = KoraPhone.Services.Calling

bind('calls:videoControl', Calling.videoControl)
bind('calls:start', Calling.start)
bind('calls:accept', Calling.accept)
bind('calls:reject', Calling.reject)
bind('calls:hangup', Calling.hangup)
bind('calls:signal', Calling.videoSignal)

RegisterNetEvent('kora_phone:server:calls:voiceFailure', function(callId)
    local requestSource = source
    if KoraPhone.RateLimits.consume(requestSource, 'mutation') then
        Calling.voiceFailure(requestSource, callId)
    end
end)

RegisterNetEvent('kora_phone:server:calls:hangup', function(callId)
    local requestSource = source
    if KoraPhone.RateLimits.consume(requestSource, 'mutation') then
        Calling.hangup(requestSource, { id = callId })
    end
end)
