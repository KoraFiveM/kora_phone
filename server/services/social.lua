KoraPhone.Services = KoraPhone.Services or {}
local Social = {}
KoraPhone.Services.Social = Social

local function invalid(message) return PhoneError(PhoneConstants.Errors.INVALID_INPUT, message) end

local function requestId(payload)
    return PhoneValidation.string(type(payload) == 'table' and payload.clientRequestId, 'clientRequestId', 8, 64)
end

local function page(payload)
    local result, err = PhoneValidation.page(payload)
    if not result then return nil, invalid(err) end
    if result.limit > 50 then result.limit = 50 end
    return result
end

local function ownProfile(source, createRequired)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return nil, nil, err end
    local profile = KoraPhone.Repositories.Social.profileByDevice(device.id)
    if createRequired and not profile then
        return nil, nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Create a social profile first')
    end
    if profile and profile.isSuspended == 1 then
        return nil, nil, PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'Social account is suspended')
    end
    return device, profile
end

local function cleanHandle(value)
    local handle, err = PhoneValidation.string(value, 'handle', 3, 24)
    if not handle then return nil, err end
    handle = handle:lower()
    if not handle:match('^[a-z0-9_]+$') then return nil, 'handle may contain only letters, numbers and underscore' end
    return handle
end

function Social.createAccount(source, payload)
    local device, profile, err = ownProfile(source, false)
    if not device then return err end
    if profile then return PhoneError(PhoneConstants.Errors.CONFLICT, 'A social profile already exists') end
    payload = type(payload) == 'table' and payload or {}
    local handle, validationError = cleanHandle(payload.handle)
    if not handle then return invalid(validationError) end
    local displayName; displayName, validationError = PhoneValidation.string(payload.displayName, 'displayName', 1, 64)
    if not displayName then return invalid(validationError) end
    local bio; bio, validationError = PhoneValidation.string(payload.bio or '', 'bio', 0, 280, true)
    if not bio then return invalid(validationError) end
    local ok, created = pcall(KoraPhone.Repositories.Social.createProfile, device.id, handle, displayName, bio, payload.isPrivate == true)
    if not ok or not created then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Handle is unavailable') end
    return PhoneResult(created)
end

function Social.getFeed(source, payload)
    local device, profile, err = ownProfile(source, true)
    if not device then return err end
    local pagination, pageError = page(payload)
    if not pagination then return pageError end
    local rows = KoraPhone.Repositories.Social.feed(device.id, profile.id, pagination.limit, pagination.cursor)
    return PhoneResult({ items = rows, nextCursor = #rows == pagination.limit and rows[#rows].id or nil })
end

function Social.getProfile(source, payload)
    local device, _, err = ownProfile(source, false)
    if not device then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    local profile = KoraPhone.Repositories.Social.profileById(id)
    if not profile or profile.isSuspended == 1 or KoraPhone.Repositories.Blocks.isEitherBlocked(device.id, profile.deviceId) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Profile was not found')
    end
    profile.deviceId = nil
    return PhoneResult(profile)
end

function Social.createPost(source, payload)
    local device, profile, err = ownProfile(source, true)
    if not profile then return err end
    payload = type(payload) == 'table' and payload or {}
    -- A Flash post may carry one of the caller's own photos or clips (uploaded through the media provider).
    local mediaId, validationError
    if payload.mediaId ~= nil then
        mediaId, validationError = PhoneValidation.integer(payload.mediaId, 'mediaId', 1)
        if not mediaId then return invalid(validationError) end
        if not KoraPhone.Repositories.Media.findOwned(device.id, mediaId) then return invalid('That media was not found') end
    end
    local body; body, validationError = PhoneValidation.string(payload.body == nil and '' or payload.body, 'body', mediaId and 0 or 1, 5000, mediaId ~= nil)
    if not body then return invalid(validationError) end
    local idempotency; idempotency, validationError = requestId(payload)
    if not idempotency then return invalid(validationError) end
    local post, replayed = KoraPhone.Repositories.Social.insertPost(profile.id, body, idempotency, mediaId)
    if not post then return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to create post') end
    post.replayed = replayed
    return PhoneResult(post)
end

-- A poster removes their own post outright; a moderator can also take down someone else's
-- straight from the feed (the same removal a report's "remove content" action performs).
function Social.deletePost(source, payload)
    local _, profile, err = ownProfile(source, true)
    if not profile then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    local removed = KoraPhone.Repositories.Social.deletePost(profile.id, id)
    if not removed and KoraPhone.Services.Moderation.isModerator(source) then
        removed = KoraPhone.Repositories.Social.hidePostByModerator(id)
    end
    if not removed then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Post was not found') end
    return PhoneResult({ id = id })
end

function Social.deleteComment(source, payload)
    local _, profile, err = ownProfile(source, true)
    if not profile then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    local removed = KoraPhone.Repositories.Social.deleteComment(profile.id, id)
    if not removed and KoraPhone.Services.Moderation.isModerator(source) then
        removed = KoraPhone.Repositories.Social.hideCommentByModerator(id)
    end
    if not removed then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Comment was not found') end
    return PhoneResult({ id = id })
end

local function interactivePost(source, payload)
    local device, profile, err = ownProfile(source, true)
    if not device then return nil, nil, nil, err end
    local postId, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.postId, 'postId', 1)
    if not postId then return nil, nil, nil, invalid(validationError) end
    local post = KoraPhone.Repositories.Social.postInternal(postId)
    if not post or post.deletedAt or KoraPhone.Repositories.Blocks.isEitherBlocked(device.id, post.authorDeviceId) then
        return nil, nil, nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Post was not found')
    end
    if post.authorIsPrivate == 1 and post.authorProfileId ~= profile.id
        and not KoraPhone.Repositories.Social.isFollowing(profile.id, post.authorProfileId) then
        return nil, nil, nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Post was not found')
    end
    return device, profile, post
end

function Social.toggleLike(source, payload)
    local _, profile, post, err = interactivePost(source, payload)
    if not profile then return err end
    local liked = type(payload) == 'table' and payload.liked == true
    local count = KoraPhone.Repositories.Social.setLike(profile.id, post.id, liked)
    return PhoneResult({ postId = post.id, liked = liked, likeCount = count })
end

function Social.follow(source, payload, following)
    local device, profile, err = ownProfile(source, true)
    if not device then return err end
    local targetId, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.profileId, 'profileId', 1)
    if not targetId then return invalid(validationError) end
    if targetId == profile.id then return invalid('Cannot follow yourself') end
    local target = KoraPhone.Repositories.Social.profileById(targetId)
    if not target or target.isSuspended == 1 or KoraPhone.Repositories.Blocks.isEitherBlocked(device.id, target.deviceId) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Profile was not found')
    end
    if following and target.isPrivate == 1 then
        -- A private account must never be converted into an accepted follow by
        -- a single client request. Follow requests require a separate pending /
        -- accepted data model and are intentionally deferred.
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'This profile is private')
    end
    KoraPhone.Repositories.Social.setFollow(profile.id, targetId, following)
    return PhoneResult({ profileId = targetId, following = following })
end

function Social.createComment(source, payload)
    local _, profile, post, err = interactivePost(source, payload)
    if not profile then return err end
    local body, validationError = PhoneValidation.string(payload.body, 'body', 1, 1000)
    if not body then return invalid(validationError) end
    local idempotency; idempotency, validationError = requestId(payload)
    if not idempotency then return invalid(validationError) end
    local comment = KoraPhone.Repositories.Social.insertComment(post.id, profile.id, body, idempotency)
    return comment and PhoneResult(comment) or PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to create comment')
end

function Social.getComments(source, payload)
    local device, profile, err = ownProfile(source, false)
    if not device then return err end
    local postId, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.postId, 'postId', 1)
    if not postId then return invalid(validationError) end
    local post = KoraPhone.Repositories.Social.postInternal(postId)
    if not post or post.deletedAt or KoraPhone.Repositories.Blocks.isEitherBlocked(device.id, post.authorDeviceId) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Post was not found')
    end
    if post.authorIsPrivate == 1 and (not profile or post.authorProfileId ~= profile.id)
        and not KoraPhone.Repositories.Social.isFollowing(profile and profile.id, post.authorProfileId) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Post was not found')
    end
    local pagination, pageError = page(payload)
    if not pagination then return pageError end
    local rows = KoraPhone.Repositories.Social.comments(postId, device.id, pagination.limit, pagination.cursor)
    return PhoneResult({ items = rows, nextCursor = #rows == pagination.limit and rows[#rows].id or nil })
end

function Social.setBlock(source, payload)
    local device, profile, err = ownProfile(source, false)
    if not device then return err end
    local targetId, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.profileId, 'profileId', 1)
    if not targetId then return invalid(validationError) end
    local target = KoraPhone.Repositories.Social.profileById(targetId)
    if not target then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Profile was not found') end
    if target.deviceId == device.id then return invalid('Cannot block yourself') end
    local blocked = type(payload) == 'table' and payload.blocked == true
    KoraPhone.Repositories.Blocks.set(device.id, target.deviceId, blocked)
    if blocked and profile then KoraPhone.Repositories.Social.removeFollowsBetween(profile.id, target.id) end
    return PhoneResult({ profileId = targetId, blocked = blocked })
end