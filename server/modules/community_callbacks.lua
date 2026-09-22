-- Community callback registration. This module must load after repositories,
-- services, rate_limits and permissions.
local function register(name, rateKey, handler)
    SteviePhone.QB.Functions.CreateCallback('stevie-phone:server:' .. name, function(source, cb, payload)
        if not SteviePhone.RateLimits.consume(source, 'community.' .. rateKey) then
            cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
            return
        end
        local ok, result = xpcall(function()
            return handler(source, type(payload) == 'table' and payload or {})
        end, debug.traceback)
        if not ok then
            print(('[stevie-phone] community callback %s failed for source %s'):format(name, source))
            cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
            return
        end
        cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
    end)
end

register('social:createAccount', 'profile', SteviePhone.Services.Social.createAccount)
register('social:getFeed', 'read', SteviePhone.Services.Social.getFeed)
register('social:getProfile', 'read', SteviePhone.Services.Social.getProfile)
register('social:createPost', 'post', SteviePhone.Services.Social.createPost)
register('social:deletePost', 'post', SteviePhone.Services.Social.deletePost)
register('social:toggleLike', 'reaction', SteviePhone.Services.Social.toggleLike)
register('social:follow', 'follow', function(source, payload) return SteviePhone.Services.Social.follow(source, payload, true) end)
register('social:unfollow', 'follow', function(source, payload) return SteviePhone.Services.Social.follow(source, payload, false) end)
register('social:createComment', 'comment', SteviePhone.Services.Social.createComment)
register('social:deleteComment', 'comment', SteviePhone.Services.Social.deleteComment)
register('social:getComments', 'read', SteviePhone.Services.Social.getComments)
register('social:block', 'block', SteviePhone.Services.Social.setBlock)
register('contacts:block', 'block', SteviePhone.Services.Social.setBlock)
register('social:report', 'report', SteviePhone.Services.Moderation.report)

register('market:getListings', 'read', SteviePhone.Services.Marketplace.getListings)
register('market:getListing', 'read', SteviePhone.Services.Marketplace.getListing)
register('market:createListing', 'listing', SteviePhone.Services.Marketplace.createListing)
register('market:updateListing', 'listing', SteviePhone.Services.Marketplace.updateListing)
register('market:removeListing', 'listing', function(source, payload)
    return SteviePhone.Services.Marketplace.setStatus(source, payload, 'removed')
end)
register('market:markSold', 'listing', function(source, payload)
    return SteviePhone.Services.Marketplace.setStatus(source, payload, 'sold')
end)
register('market:contactSeller', 'contact', SteviePhone.Services.Marketplace.contactSeller)

register('moderation:getQueue', 'moderation', SteviePhone.Services.Moderation.getQueue)
register('moderation:resolve', 'moderation', SteviePhone.Services.Moderation.resolve)
