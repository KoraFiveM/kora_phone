local function registerAsync(name, rateKey, handler)
    Kora.callback.register('kora_phone:server:' .. name, function(source, payload)
        if not KoraPhone.RateLimits.consume(source, rateKey) then
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
            print(('[kora_phone] media callback %s failed: %s'):format(name, err))
            reply(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
        end
        return Citizen.Await(response)
    end)
end

registerAsync('requestMediaUpload', 'mediaUpload', KoraPhone.Services.Media.requestUpload)
registerAsync('completeMediaUpload', 'mediaUpload', KoraPhone.Services.Media.completeUpload)
KoraPhone.registerCallback('getGallery', 'read', KoraPhone.Services.Media.list)
registerAsync('deleteMedia', 'mutation', KoraPhone.Services.Media.delete)