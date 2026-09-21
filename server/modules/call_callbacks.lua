SteviePhone.Modules = SteviePhone.Modules or {}
local Module = {}
SteviePhone.Modules.CallCallbacks = Module

local registered = false
local function invoke(source, cb, rateKey, handler, payload)
    if not SteviePhone.RateLimits.consume(source, rateKey) then
        return cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
    end
    local ok, result = xpcall(function() return handler(source, payload) end, debug.traceback)
    if not ok then
        print(('[stevie-phone] call callback failed for source %s: %s'):format(source, result))
        return cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Call request failed'))
    end
    cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty call response'))
end

function Module.register()
    if registered then return end
    registered = true
    local handlers = {
        ['calls:start'] = { 'callStart', SteviePhone.Services.Calling.start },
        ['calls:accept'] = { 'mutation', SteviePhone.Services.Calling.accept },
        ['calls:reject'] = { 'mutation', SteviePhone.Services.Calling.reject },
        ['calls:hangup'] = { 'mutation', SteviePhone.Services.Calling.hangup },
        ['calls:history'] = { 'read', SteviePhone.Services.Calling.history },
    }
    for name, definition in pairs(handlers) do
        SteviePhone.QB.Functions.CreateCallback('stevie-phone:server:' .. name, function(source, cb, payload)
            invoke(source, cb, definition[1], definition[2], payload)
        end)
    end
    RegisterNetEvent('stevie-phone:server:calls:voiceFailure', function(callId)
        local requestSource = source
        if SteviePhone.RateLimits.consume(requestSource, 'mutation') then
            SteviePhone.Services.Calling.voiceFailure(requestSource, callId)
        end
    end)
    RegisterNetEvent('stevie-phone:server:calls:hangup', function(callId)
        local requestSource = source
        if SteviePhone.RateLimits.consume(requestSource, 'mutation') then
            SteviePhone.Services.Calling.hangup(requestSource, { id = callId })
        end
    end)
end

return Module
