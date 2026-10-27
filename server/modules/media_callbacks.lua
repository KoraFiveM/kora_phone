local function registerAsync(name, rateKey, handler)
    QB.callback.register('qbphone:server:' .. name, function(source, payload)
        if not QBPhone.RateLimits.consume(source, rateKey) then
            return PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests')
        end
        local response = promise.new()
        local replied = false
        local function reply(result)
            if replied then return end
            replied = true
            response:resolve(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
        end
        local ok, err = xpcall(function() handler(source, payload, reply) end, debug.traceback)
        if not ok then
            print(('[qbphone] media callback %s failed: %s'):format(name, err))
            reply(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
        end
        return Citizen.Await(response)
    end)
end

registerAsync('requestMediaUpload', 'mediaUpload', QBPhone.Services.Media.requestUpload)
registerAsync('completeMediaUpload', 'mediaUpload', QBPhone.Services.Media.completeUpload)
QBPhone.registerCallback('getGallery', 'read', QBPhone.Services.Media.list)
registerAsync('deleteMedia', 'mutation', QBPhone.Services.Media.delete)
