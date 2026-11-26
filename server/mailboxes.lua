-- Delivery copies are owned by a handset, not by whoever later acquires its number.
local M = KoraPhone.Services.Messaging
local Mailboxes = KoraPhone.Repositories.Mailboxes

local BACKUP_DELAY_MS = 1500
local MAX_PAGE = 100
local DEFAULT_PAGE = 50
local MAX_ID = 9007199254740991
local GROUP_PREFIX = '@group:'

local function fail(text)
    return PhoneError(PhoneConstants.Errors.INVALID_INPUT, text)
end

local function isGroupArchive(peerNumber)
    return peerNumber:sub(1, #GROUP_PREFIX) == GROUP_PREFIX
end

local function threadTitle(peerNumber)
    return isGroupArchive(peerNumber) and 'Archived group' or nil
end

local function isTrue(value)
    return value == 1 or value == true
end

local function conversation(thread)
    local latest = Mailboxes.latestMessage(thread.device_id, thread.peer_number)
    return {
        id = thread.id,
        type = 'direct',
        peerPhoneNumber = thread.peer_number,
        title = threadTitle(thread.peer_number),
        lastMessageId = latest and latest.id,
        lastMessagePreview = latest and latest.body,
        lastMessageAt = latest and latest.at,
        unreadCount = Mailboxes.unreadCount(thread.device_id, thread.peer_number),
    }
end

---Adds the client-facing fields to a mailbox row.
local function decorate(item, thread)
    item.conversationId = thread.id
    item.isMine = isTrue(item.is_outgoing)
    item.is_outgoing = nil
    item.messageType = item.mediaId and 'image' or 'text'
    return item
end

local function message(id, device, thread)
    local item = Mailboxes.findMessage(id, device.id)
    return item and decorate(item, thread) or nil
end

-- A saved handset backup follows every change a delivered text makes, shortly after it settles.
local function scheduleBackup(target)
    KoraPhone.After(BACKUP_DELAY_MS, function()
        if KoraPhone.Handsets.selected[target] then
            KoraPhone.Handsets.locked(target, KoraPhone.Handsets.backup, {})
        end
    end)
end

function M.startDirect(src, p)
    local device, err = KoraPhone.Permissions.requireDevice(src)
    if not device then return err end
    local number, numberError = PhoneValidation.phoneNumber(p.to)
    if not number then return fail(numberError) end
    if not device.cellular then return fail('Insert an active SIM to start a conversation') end
    if number == device.phoneNumber then return fail('Cannot message your own number') end
    return PhoneResult(conversation(Mailboxes.ensureThread(device.id, number)))
end

local function parseCursor(p)
    local page, validationError = PhoneValidation.page(p)
    if not page then return nil, nil, validationError end
    if p.cursorId == nil then return page, nil end
    if not page.cursor then return nil, nil, 'cursor is required with cursorId' end
    local cursorId
    cursorId, validationError = PhoneValidation.integer(p.cursorId, 'cursorId', 1)
    if not cursorId then return nil, nil, validationError end
    return page, cursorId
end

function M.listConversations(src, p)
    local device, err = KoraPhone.Permissions.requireDevice(src)
    if not device then return err end
    local page, cursorId, cursorError = parseCursor(p)
    if not page then return fail(cursorError) end
    local threads = Mailboxes.listThreads(device.id, page.limit, page.cursor, cursorId)
    local results = {}
    for _, thread in ipairs(threads) do
        results[#results + 1] = {
            id = thread.id,
            type = 'direct',
            peerPhoneNumber = thread.peer_number,
            title = threadTitle(thread.peer_number),
            lastMessageId = thread.lastMessageId,
            lastMessagePreview = thread.lastMessagePreview,
            lastMessageAt = thread.lastMessageAt,
            sortId = tonumber(thread.sortId or thread.lastMessageId or thread.id),
            lastMediaMime = thread.lastMediaMime,
            unreadCount = tonumber(thread.unreadCount) or 0,
        }
    end
    local last = #results == page.limit and results[#results] or nil
    return PhoneResult({ items = results, nextCursor = last and last.sortId, nextCursorId = last and last.id })
end

function M.list(src, p)
    local device, err = KoraPhone.Permissions.requireDevice(src)
    if not device then return err end
    local thread = Mailboxes.findThread(device.id, tonumber(p.conversationId) or 0)
    if not thread then return fail('Conversation not found') end
    local limit = math.min(MAX_PAGE, math.max(1, tonumber(p.limit) or DEFAULT_PAGE))
    local items = Mailboxes.listMessages(device.id, thread.peer_number, tonumber(p.cursor) or MAX_ID, limit)
    for _, item in ipairs(items) do decorate(item, thread) end
    return PhoneResult({ items = items, nextCursor = #items == limit and items[#items].id or nil })
end

---Replays a previously stored send, or reports that the request id was reused for different content.
local function replayExisting(existing, device, thread, number, mediaId, body)
    local sameContent = existing.body == body
        and existing.peer_number == number
        and (tonumber(existing.media_id) or 0) == mediaId
    if not sameContent then return fail('Message request already used') end
    local saved = message(existing.id, device, thread)
    saved.replayed = true
    return PhoneResult(saved)
end

function M.send(src, p)
    local device, err = KoraPhone.Permissions.requireDevice(src)
    if not device then return err end
    if not device.cellular then return fail('An active SIM is required to send texts') end
    local contract, contractError = PhoneContracts.message(p)
    if not contract then return fail(contractError) end
    local thread = contract.conversationId and Mailboxes.findThread(device.id, tonumber(contract.conversationId) or 0)
    local number = PhoneValidation.phoneNumber(thread and thread.peer_number or contract.to)
    if not number then return fail('Archived group history is read-only') end
    local recipient = KoraPhone.Repositories.Phones.findByNumber(number)
    if not recipient or number == device.phoneNumber then return fail('That number is unavailable') end
    if KoraPhone.Repositories.Blocks.isEitherBlocked(device.id, recipient.id) then
        return fail('Messaging is unavailable for this contact')
    end
    thread = thread or Mailboxes.ensureThread(device.id, number)
    local recipientThread = Mailboxes.ensureThread(recipient.id, device.phoneNumber)
    local mediaId = tonumber(contract.mediaId) or 0
    if mediaId ~= 0 and not KoraPhone.Repositories.Media.findOwned(device.id, mediaId) then
        return fail('Media not found')
    end
    local requestId = tostring(contract.clientRequestId)
    local existing = Mailboxes.findByRequest(device.id, requestId)
    if existing then return replayExisting(existing, device, thread, number, mediaId, contract.body) end
    local delivered = Mailboxes.deliver(
        { deviceId = device.id, number = device.phoneNumber },
        recipient.id,
        { peerNumber = number, body = contract.body, mediaId = mediaId, requestId = requestId })
    if not delivered then return fail('Message could not be delivered') end
    local sentId = Mailboxes.idByRequest(device.id, requestId)
    local target = KoraPhone.Sessions.sourceByNumber(number)
    if target then
        local incomingId = Mailboxes.idByRequest(recipient.id, Mailboxes.receivedRequestId(device.id, requestId))
        local incoming = message(incomingId, recipient, recipientThread)
        incoming.deviceId = tostring(recipient.id)
        TriggerClientEvent('kora_phone:client:messages:new', target, incoming)
        scheduleBackup(target)
    end
    return PhoneResult(message(sentId, device, thread))
end

function M.markRead(src, p)
    local device, err = KoraPhone.Permissions.requireDevice(src)
    if not device then return err end
    local thread = Mailboxes.findThread(device.id, tonumber(p.conversationId) or 0)
    if not thread then return fail('Conversation not found') end
    Mailboxes.markRead(device.id, thread.peer_number)
    return PhoneResult(true)
end

function M.deleteForSelf(src, p)
    local device, err = KoraPhone.Permissions.requireDevice(src)
    if not device then return err end
    Mailboxes.deleteForDevice(device.id, tonumber(p.messageId) or 0)
    return PhoneResult(true)
end

-- Groups are preserved as readable archives; new group/social features are outside the launch apps.
local function groupDeferred()
    return fail('New group chats are not available in this release')
end

M.createGroup = groupDeferred
M.addMember = groupDeferred
M.leaveGroup = groupDeferred
