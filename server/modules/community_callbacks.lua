-- Community callback registration. This module must load after repositories,
-- services, rate_limits and permissions.
local function register(name, rateKey, handler)
    QBPhone.QB.Functions.CreateCallback('qbphone:server:' .. name, function(source, cb, payload)
        if not QBPhone.RateLimits.consume(source, 'community.' .. rateKey) then
            cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
            return
        end
        local ok, result = xpcall(function()
            return handler(source, type(payload) == 'table' and payload or {})
        end, debug.traceback)
        if not ok then
            print(('[qbphone] community callback %s failed for source %s'):format(name, source))
            cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
            return
        end
        cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
    end)
end

register('social:createAccount', 'profile', QBPhone.Services.Social.createAccount)
register('social:getFeed', 'read', QBPhone.Services.Social.getFeed)
register('social:getProfile', 'read', QBPhone.Services.Social.getProfile)
register('social:createPost', 'post', QBPhone.Services.Social.createPost)
register('social:deletePost', 'post', QBPhone.Services.Social.deletePost)
register('social:toggleLike', 'reaction', QBPhone.Services.Social.toggleLike)
register('social:follow', 'follow', function(source, payload) return QBPhone.Services.Social.follow(source, payload, true) end)
register('social:unfollow', 'follow', function(source, payload) return QBPhone.Services.Social.follow(source, payload, false) end)
register('social:createComment', 'comment', QBPhone.Services.Social.createComment)
register('social:deleteComment', 'comment', QBPhone.Services.Social.deleteComment)
register('social:getComments', 'read', QBPhone.Services.Social.getComments)
register('social:block', 'block', QBPhone.Services.Social.setBlock)
register('contacts:block', 'block', QBPhone.Services.Social.setBlock)
register('social:report', 'report', QBPhone.Services.Moderation.report)

register('market:getListings', 'read', QBPhone.Services.Marketplace.getListings)
register('market:getListing', 'read', QBPhone.Services.Marketplace.getListing)
register('market:createListing', 'listing', QBPhone.Services.Marketplace.createListing)
register('market:updateListing', 'listing', QBPhone.Services.Marketplace.updateListing)
register('market:removeListing', 'listing', function(source, payload)
    return QBPhone.Services.Marketplace.setStatus(source, payload, 'removed')
end)
register('market:markSold', 'listing', function(source, payload)
    return QBPhone.Services.Marketplace.setStatus(source, payload, 'sold')
end)
register('market:contactSeller', 'contact', QBPhone.Services.Marketplace.contactSeller)

register('moderation:getQueue', 'moderation', QBPhone.Services.Moderation.getQueue)
register('moderation:resolve', 'moderation', QBPhone.Services.Moderation.resolve)
