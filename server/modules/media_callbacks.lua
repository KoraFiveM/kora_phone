local function registerAsync(name, rateKey, handler)
    SteviePhone.QB.Functions.CreateCallback('stevie-phone:server:' .. name, function(source, cb, payload)
        if not SteviePhone.RateLimits.consume(source, rateKey) then
            return cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
        end
        local replied = false
        local function reply(result)
            if replied then return end
            replied = true
            cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
        end
        local ok, err = xpcall(function() handler(source, payload, reply) end, debug.traceback)
        if not ok then
            print(('[stevie-phone] media callback %s failed: %s'):format(name, err))
            reply(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
        end
    end)
end

local function registerSync(name, rateKey, handler)
    registerAsync(name, rateKey, function(source, payload, reply) reply(handler(source, payload)) end)
end

registerAsync('requestMediaUpload', 'mediaUpload', SteviePhone.Services.Media.requestUpload)
registerAsync('completeMediaUpload', 'mediaUpload', SteviePhone.Services.Media.completeUpload)
registerSync('getGallery', 'read', SteviePhone.Services.Media.list)
registerAsync('deleteMedia', 'mutation', SteviePhone.Services.Media.delete)
