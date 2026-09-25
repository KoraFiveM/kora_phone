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

-- A WebRTC signal (offer/answer/ICE candidate) relayed between the two participants of an active call.
function PhoneContracts.callSignal(payload)
    if type(payload) ~= 'table' then return nil, 'payload must be an object' end
    local id, err = PhoneValidation.string(payload.id, 'id', 32, 40)
    if not id then return nil, err end
    local kind = payload.kind
    if kind ~= 'offer' and kind ~= 'answer' and kind ~= 'ice' then return nil, 'kind must be offer, answer, or ice' end
    if kind == 'ice' then
        if type(payload.candidate) ~= 'table' then return nil, 'candidate must be an object' end
        local text; text, err = PhoneValidation.string(payload.candidate.candidate, 'candidate', 0, 2000, true)
        if not text then return nil, err end
        return { id = id, kind = kind, candidate = {
            candidate = text,
            sdpMid = type(payload.candidate.sdpMid) == 'string' and payload.candidate.sdpMid:sub(1, 64) or nil,
            sdpMLineIndex = type(payload.candidate.sdpMLineIndex) == 'number' and payload.candidate.sdpMLineIndex or nil,
        } }
    end
    if type(payload.sdp) ~= 'table' or payload.sdp.type ~= kind then return nil, 'sdp must be an ' .. kind .. ' description' end
    local text; text, err = PhoneValidation.string(payload.sdp.sdp, 'sdp', 1, 20000)
    if not text then return nil, err end
    return { id = id, kind = kind, sdp = { type = kind, sdp = text } }
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
