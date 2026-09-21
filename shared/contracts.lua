PhoneContracts = {}

function PhoneContracts.contact(payload)
    if type(payload) ~= 'table' then return nil, 'payload must be an object' end
    local name, err = PhoneValidation.string(payload.displayName, 'displayName', 1, Config.Limits.ContactName)
    if not name then return nil, err end
    local number; number, err = PhoneValidation.phoneNumber(payload.phoneNumber)
    if not number then return nil, err end
    local id
    if payload.id ~= nil then id, err = PhoneValidation.integer(payload.id, 'id', 1); if not id then return nil, err end end
    local avatarMediaId
    if payload.avatarMediaId ~= nil then
        avatarMediaId, err = PhoneValidation.integer(payload.avatarMediaId, 'avatarMediaId', 1)
        if not avatarMediaId then return nil, err end
    end
    return { id = id, displayName = name, phoneNumber = number, isFavorite = payload.isFavorite == true, avatarMediaId = avatarMediaId }
end

PhoneContracts.Routes = {
    calls = { 'calls:start', 'calls:accept', 'calls:reject', 'calls:hangup', 'calls:history' },
    gallery = { 'gallery:list', 'gallery:delete', 'camera:capture' },
    bank = { 'bank:getData', 'bank:getTransactions', 'bank:transfer' },
    jobs = { 'jobs:getData', 'jobs:setDuty', 'jobs:runAction' },
    social = { 'social:createAccount', 'social:getFeed', 'social:getProfile', 'social:createPost',
        'social:deletePost', 'social:toggleLike', 'social:follow', 'social:unfollow',
        'social:createComment', 'social:getComments', 'social:block', 'social:report' },
    market = { 'market:getListings', 'market:getListing', 'market:createListing',
        'market:updateListing', 'market:removeListing', 'market:markSold', 'market:contactSeller' },
    moderation = { 'moderation:getQueue', 'moderation:resolve' }
}

function PhoneContracts.message(payload)
    if type(payload) ~= 'table' then return nil, 'payload must be an object' end
    local recipient, conversationId, err
    if payload.conversationId ~= nil then
        conversationId, err = PhoneValidation.integer(payload.conversationId, 'conversationId', 1)
        if not conversationId then return nil, err end
    else
        recipient, err = PhoneValidation.phoneNumber(payload.to)
        if not recipient then return nil, err end
    end
    -- A message is text, or a photo/clip from the sender's own media (text is then optional).
    local mediaId
    if payload.mediaId ~= nil then
        mediaId, err = PhoneValidation.integer(payload.mediaId, 'mediaId', 1)
        if not mediaId then return nil, err end
    end
    local body; body, err = PhoneValidation.string(payload.body == nil and '' or payload.body, 'body', mediaId and 0 or 1, Config.Limits.MessageBody, mediaId ~= nil)
    if not body then return nil, err end
    local clientRequestId; clientRequestId, err = PhoneValidation.string(payload.clientRequestId, 'clientRequestId', 8, 64)
    if not clientRequestId then return nil, err end
    return { to = recipient, conversationId = conversationId, body = body, mediaId = mediaId, clientRequestId = clientRequestId }
end

-- A new group chat: a name and 1 to 49 other phone numbers (duplicates dropped, order kept).
function PhoneContracts.group(payload)
    if type(payload) ~= 'table' then return nil, 'payload must be an object' end
    local name, err = PhoneValidation.string(payload.name, 'name', 1, Config.Limits.ConversationTitle)
    if not name then return nil, err end
    if type(payload.numbers) ~= 'table' or #payload.numbers < 1 or #payload.numbers > 49 then
        return nil, 'numbers must list 1 to 49 phone numbers'
    end
    local numbers, seen = {}, {}
    for _, raw in ipairs(payload.numbers) do
        local number; number, err = PhoneValidation.phoneNumber(raw)
        if not number then return nil, err end
        if not seen[number] then seen[number] = true; numbers[#numbers + 1] = number end
    end
    return { name = name, numbers = numbers }
end

-- One piece of phone mail: recipient number, subject, body and a request id (so a retry can't send it twice).
function PhoneContracts.mail(payload)
    if type(payload) ~= 'table' then return nil, 'payload must be an object' end
    local to, err = PhoneValidation.phoneNumber(payload.to)
    if not to then return nil, err end
    local subject; subject, err = PhoneValidation.string(payload.subject, 'subject', 1, 120)
    if not subject then return nil, err end
    local body; body, err = PhoneValidation.string(payload.body, 'body', 1, 4000)
    if not body then return nil, err end
    local clientRequestId; clientRequestId, err = PhoneValidation.string(payload.clientRequestId, 'clientRequestId', 8, 64)
    if not clientRequestId then return nil, err end
    return { to = to, subject = subject, body = body, clientRequestId = clientRequestId }
end
