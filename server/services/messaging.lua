SteviePhone.Services = SteviePhone.Services or {}
local Messaging = {}
SteviePhone.Services.Messaging = Messaging

local function requireConversation(device, payload)
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.conversationId, 'conversationId', 1)
    if not id then return nil, PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    if not SteviePhone.Repositories.Messages.isMember(device.id, id) then
        return nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Conversation was not found')
    end
    return id
end

local function startDirectFor(device, number)
    if number == device.phoneNumber then return nil, nil, PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Cannot message your own number') end
    local recipient = SteviePhone.Repositories.Phones.findByNumber(number)
    if not recipient then return nil, nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Recipient was not found') end
    if SteviePhone.Repositories.Blocks.isEitherBlocked(device.id, recipient.id) then
        return nil, nil, PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Messaging is unavailable for this contact')
    end
    local conversationId = SteviePhone.Repositories.Messages.findDirectConversation(device.id, recipient.id)
    if not conversationId then conversationId = SteviePhone.Repositories.Messages.createDirectConversation(device.id, recipient.id) end
    if not conversationId then return nil, nil, PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to create conversation') end
    return conversationId, recipient
end

function Messaging.startDirect(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local number, validationError = PhoneValidation.phoneNumber(type(payload) == 'table' and payload.to)
    if not number then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local id, _, startError = startDirectFor(device, number)
    if not id then return startError end
    return PhoneResult(SteviePhone.Repositories.Messages.getConversation(device.id, id))
end

function Messaging.send(source, payload)
    local sender, err = SteviePhone.Permissions.requireDevice(source)
    if not sender then return err end
    local message, validationError = PhoneContracts.message(payload)
    if not message then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local conversationId, recipient
    local recipients = {}
    if message.conversationId then
        conversationId, err = requireConversation(sender, { conversationId = message.conversationId })
        if not conversationId then return err end
        if SteviePhone.Repositories.Messages.conversationType(conversationId) == 'group' then
            for _, member in ipairs(SteviePhone.Repositories.Messages.otherMembers(conversationId, sender.id)) do
                -- Someone who blocked the sender (or was blocked) simply isn't notified; the rest still get it.
                if not SteviePhone.Repositories.Blocks.isEitherBlocked(sender.id, member.id) then recipients[#recipients + 1] = member end
            end
        else
            recipient = SteviePhone.Repositories.Messages.peerDevice(conversationId, sender.id)
            if not recipient then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Conversation was not found') end
            if SteviePhone.Repositories.Blocks.isEitherBlocked(sender.id, recipient.id) then
                return PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Messaging is unavailable for this contact')
            end
            recipients[1] = recipient
        end
    else
        conversationId, recipient, err = startDirectFor(sender, message.to)
        if not conversationId then return err end
        recipients[1] = recipient
    end
    local existing = SteviePhone.Repositories.Messages.findIdempotent(sender.id, message.clientRequestId)
    if existing then
        if tonumber(existing.conversationId) ~= tonumber(conversationId) or existing.body ~= message.body then
            return PhoneError(PhoneConstants.Errors.CONFLICT, 'Message request ID was already used for different message details')
        end
        local replay = SteviePhone.Repositories.Messages.getForDevice(existing.id, sender.id)
        if replay then replay.replayed = true end
        return replay and PhoneResult(replay) or PhoneError(PhoneConstants.Errors.CONFLICT, 'Message request was already processed')
    end
    local messageType = 'text'
    if message.mediaId then
        local media = SteviePhone.Repositories.Media.findOwned(sender.id, message.mediaId)
        if not media then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'That media was not found') end
        messageType = SteviePhone.Storage.isVideo(media.mimeType) and 'video' or 'image'
    end
    local ok, messageId = pcall(SteviePhone.Repositories.Messages.insert, conversationId, sender.id, message.body, message.clientRequestId, message.mediaId, messageType)
    if not ok or not messageId then
        existing = SteviePhone.Repositories.Messages.findIdempotent(sender.id, message.clientRequestId)
        if existing and tonumber(existing.conversationId) == tonumber(conversationId) and existing.body == message.body then
            local replay = SteviePhone.Repositories.Messages.getForDevice(existing.id, sender.id)
            if replay then replay.replayed = true end
            if replay then return PhoneResult(replay) end
        end
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to save message')
    end
    local saved = SteviePhone.Repositories.Messages.getForDevice(messageId, sender.id)
    for _, member in ipairs(recipients) do
        local target = SteviePhone.Sessions.sourceByNumber(member.phoneNumber)
        if target then
            TriggerClientEvent('stevie-phone:client:messages:new', target,
                SteviePhone.Repositories.Messages.getForDevice(messageId, member.id))
        end
    end
    return PhoneResult(saved)
end

function Messaging.createGroup(source, payload)
    local creator, err = SteviePhone.Permissions.requireDevice(source)
    if not creator then return err end
    local group, validationError = PhoneContracts.group(payload)
    if not group then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local deviceIds = { creator.id }
    for _, number in ipairs(group.numbers) do
        if number ~= creator.phoneNumber then
            local member = SteviePhone.Repositories.Phones.findByNumber(number)
            if not member then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'One of those numbers was not found') end
            if SteviePhone.Repositories.Blocks.isEitherBlocked(creator.id, member.id) then
                return PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Messaging is unavailable for one of those contacts')
            end
            deviceIds[#deviceIds + 1] = member.id
        end
    end
    if #deviceIds < 2 then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Add at least one other number') end
    local id = SteviePhone.Repositories.Messages.createGroup(creator.id, group.name, deviceIds)
    if not id then return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to create group') end
    return PhoneResult(SteviePhone.Repositories.Messages.getConversation(creator.id, id))
end

-- Any member can add someone to a group (up to 50 people). Blocks are respected.
function Messaging.addMember(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local conversationId; conversationId, err = requireConversation(device, payload)
    if not conversationId then return err end
    if SteviePhone.Repositories.Messages.conversationType(conversationId) ~= 'group' then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Group was not found')
    end
    local number, validationError = PhoneValidation.phoneNumber(payload.number)
    if not number then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local target = SteviePhone.Repositories.Phones.findByNumber(number)
    if not target then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'That number was not found') end
    if SteviePhone.Repositories.Blocks.isEitherBlocked(device.id, target.id) then
        return PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Messaging is unavailable for this contact')
    end
    if SteviePhone.Repositories.Messages.isMember(target.id, conversationId) then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'They are already in this group')
    end
    if SteviePhone.Repositories.Messages.memberCount(conversationId) >= 50 then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'This group is full')
    end
    SteviePhone.Repositories.Messages.addMember(conversationId, target.id)
    return PhoneResult({ conversationId = conversationId, added = number })
end

function Messaging.leaveGroup(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local conversationId; conversationId, err = requireConversation(device, payload)
    if not conversationId then return err end
    if not SteviePhone.Repositories.Messages.leave(device.id, conversationId) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Group was not found')
    end
    return PhoneResult({ conversationId = conversationId })
end

function Messaging.list(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local conversationId; conversationId, err = requireConversation(device, payload)
    if not conversationId then return err end
    local page, validationError = PhoneValidation.page(payload)
    if not page then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local rows = SteviePhone.Repositories.Messages.listForConversation(device.id, conversationId, page.limit, page.cursor)
    return PhoneResult({ items = rows, nextCursor = #rows == page.limit and rows[#rows].id or nil })
end

function Messaging.listConversations(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local page, validationError = PhoneValidation.page(payload)
    if not page then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local rows = SteviePhone.Repositories.Messages.listConversations(device.id, page.limit, page.cursor)
    return PhoneResult({ items = rows, nextCursor = #rows == page.limit and rows[#rows].sortId or nil })
end

function Messaging.markRead(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local conversationId; conversationId, err = requireConversation(device, payload)
    if not conversationId then return err end
    local messageId
    if type(payload) == 'table' and payload.messageId ~= nil then
        messageId, err = PhoneValidation.integer(payload.messageId, 'messageId', 1)
        if not messageId then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, err) end
    end
    local changed, resolved = SteviePhone.Repositories.Messages.markRead(device.id, conversationId, messageId)
    if not changed and messageId then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Message was not found') end
    return PhoneResult({ conversationId = conversationId, messageId = resolved })
end

function Messaging.deleteForSelf(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.messageId, 'messageId', 1)
    if not id then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    if not SteviePhone.Repositories.Messages.deleteForDevice(device.id, id) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Message was not found')
    end
    return PhoneResult({ messageId = id })
end
