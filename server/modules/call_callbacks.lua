QBPhone.Modules = QBPhone.Modules or {}
local Module = {}
QBPhone.Modules.CallCallbacks = Module

local registered = false
local function invoke(source, cb, rateKey, handler, payload)
    if not QBPhone.RateLimits.consume(source, rateKey) then
        return cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
    end
    local ok, result = xpcall(function() return handler(source, payload) end, debug.traceback)
    if not ok then
        print(('[qbphone] call callback failed for source %s: %s'):format(source, result))
        return cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Call request failed'))
    end
    cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty call response'))
end

function Module.register()
    if registered then return end
    registered = true
    local handlers = {
        ['calls:start'] = { 'callStart', QBPhone.Services.Calling.start },
        ['calls:accept'] = { 'mutation', QBPhone.Services.Calling.accept },
        ['calls:reject'] = { 'mutation', QBPhone.Services.Calling.reject },
        ['calls:hangup'] = { 'mutation', QBPhone.Services.Calling.hangup },
        ['calls:history'] = { 'read', QBPhone.Services.Calling.history },
        ['calls:signal'] = { 'videoSignal', QBPhone.Services.Calling.videoSignal },
    }
    for name, definition in pairs(handlers) do
        QBPhone.QB.Functions.CreateCallback('qbphone:server:' .. name, function(source, cb, payload)
            invoke(source, cb, definition[1], definition[2], payload)
        end)
    end
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
end

return Module
