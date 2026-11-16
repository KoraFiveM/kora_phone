KoraPhone.Repositories = KoraPhone.Repositories or {}
local Db = KoraPhone.Database
local Mailboxes = {}
KoraPhone.Repositories.Mailboxes = Mailboxes

local MESSAGE_COLUMNS = [[
    b.id, b.body, b.is_outgoing, b.media_id AS mediaId, b.sender_number AS senderNumber,
    UNIX_TIMESTAMP(b.created_at) AS createdAt, m.public_url AS mediaUrl, m.mime_type AS mediaMime
]]

-- Beyond any real id, so "no cursor" can be bound as a number.
local MAX_ID = 9007199254740991

---@param deviceId integer
---@param threadId integer
---@return table|nil
function Mailboxes.findThread(deviceId, threadId)
    return Db.row('SELECT * FROM phone_threads WHERE id = ? AND device_id = ?', { threadId, deviceId })
end

---Returns the thread for a peer, creating it when missing.
---@param deviceId integer
---@param peerNumber string
---@return table|nil
function Mailboxes.ensureThread(deviceId, peerNumber)
    Db.write('INSERT IGNORE INTO phone_threads (device_id, peer_number) VALUES (?, ?)', { deviceId, peerNumber })
    return Db.row('SELECT * FROM phone_threads WHERE device_id = ? AND peer_number = ?', { deviceId, peerNumber })
end

---@param deviceId integer
---@param peerNumber string
---@return table|nil
function Mailboxes.latestMessage(deviceId, peerNumber)
    return Db.row([[
        SELECT id, body, UNIX_TIMESTAMP(created_at) AS at FROM phone_mailboxes
        WHERE device_id = ? AND peer_number = ? ORDER BY id DESC LIMIT 1
    ]], { deviceId, peerNumber })
end

---@param deviceId integer
---@param peerNumber string
---@return integer
function Mailboxes.unreadCount(deviceId, peerNumber)
    return Db.number(
        'SELECT COUNT(*) FROM phone_mailboxes WHERE device_id = ? AND peer_number = ? AND is_read = 0',
        { deviceId, peerNumber })
end

---One message with its media, scoped to the owning device.
---@param messageId integer
---@param deviceId integer
---@return table|nil
function Mailboxes.findMessage(messageId, deviceId)
    return Db.row(([[
        SELECT %s FROM phone_mailboxes b LEFT JOIN phone_media m ON m.id = b.media_id
        WHERE b.id = ? AND b.device_id = ?
    ]]):format(MESSAGE_COLUMNS), { messageId, deviceId })
end

---@param deviceId integer
---@param requestId string
---@return table|nil
function Mailboxes.findByRequest(deviceId, requestId)
    return Db.row('SELECT * FROM phone_mailboxes WHERE device_id = ? AND request_id = ?', { deviceId, requestId })
end

---@param deviceId integer
---@param requestId string
---@return integer|nil messageId
function Mailboxes.idByRequest(deviceId, requestId)
    return Db.value('SELECT id FROM phone_mailboxes WHERE device_id = ? AND request_id = ?', { deviceId, requestId })
end

---Threads newest first. `cursor` is the sort id of the last row seen, `cursorId` its thread id.
---@param deviceId integer
---@param limit integer
---@param cursor? integer
---@param cursorId? integer
---@return table[]
function Mailboxes.listThreads(deviceId, limit, cursor, cursorId)
    local params = { deviceId }
    local cursorSql = ''
    if cursor and cursorId then
        cursorSql = ' AND (COALESCE(b.id, t.id) < ? OR (COALESCE(b.id, t.id) = ? AND t.id < ?))'
        params[#params + 1] = cursor
        params[#params + 1] = cursor
        params[#params + 1] = cursorId
    elseif cursor then
        cursorSql = ' AND COALESCE(b.id, t.id) < ?'
        params[#params + 1] = cursor
    end
    params[#params + 1] = limit
    return Db.rows([[
        SELECT t.*, b.id AS lastMessageId, b.body AS lastMessagePreview,
               UNIX_TIMESTAMP(b.created_at) AS lastMessageAt, m.mime_type AS lastMediaMime,
               COALESCE(b.id, t.id) AS sortId,
               (SELECT COUNT(*) FROM phone_mailboxes unread WHERE unread.device_id = t.device_id
                    AND unread.peer_number = t.peer_number AND unread.is_read = 0) AS unreadCount
        FROM phone_threads t
        LEFT JOIN phone_mailboxes b ON b.id = (SELECT MAX(latest.id) FROM phone_mailboxes latest
            WHERE latest.device_id = t.device_id AND latest.peer_number = t.peer_number)
        LEFT JOIN phone_media m ON m.id = b.media_id
        WHERE t.device_id = ? ]] .. cursorSql .. [[
        ORDER BY COALESCE(b.id, t.id) DESC, t.id DESC LIMIT ?
    ]], params)
end

---Messages in one conversation, newest first.
---@param deviceId integer
---@param peerNumber string
---@param cursor? integer Return ids below this one.
---@param limit integer
---@return table[]
function Mailboxes.listMessages(deviceId, peerNumber, cursor, limit)
    return Db.rows(([[
        SELECT %s FROM phone_mailboxes b LEFT JOIN phone_media m ON m.id = b.media_id
        WHERE b.device_id = ? AND b.peer_number = ? AND b.id < ? ORDER BY b.id DESC LIMIT ?
    ]]):format(MESSAGE_COLUMNS), { deviceId, peerNumber, cursor or MAX_ID, limit })
end

---Writes the sender's copy and the recipient's copy of a text in one transaction.
---@param sender { deviceId: integer, number: string }
---@param recipientDeviceId integer
---@param message { peerNumber: string, body: string, mediaId: integer, requestId: string }
---@return boolean
function Mailboxes.deliver(sender, recipientDeviceId, message)
    return Db.transaction({
        {
            sql = 'INSERT INTO phone_mailboxes (device_id, peer_number, sender_number, body, media_id, request_id, is_read, is_outgoing) '
                .. 'VALUES (?, ?, ?, ?, NULLIF(?, 0), ?, 1, 1)',
            params = { sender.deviceId, message.peerNumber, sender.number, message.body, message.mediaId, message.requestId },
        },
        {
            sql = 'INSERT INTO phone_mailboxes (device_id, peer_number, sender_number, body, media_id, request_id, is_outgoing) '
                .. 'VALUES (?, ?, ?, ?, NULLIF(?, 0), ?, 0)',
            params = {
                recipientDeviceId, sender.number, sender.number, message.body, message.mediaId,
                Mailboxes.receivedRequestId(sender.deviceId, message.requestId),
            },
        },
    })
end

---The request id the recipient's copy is stored under, so a retry can find it.
---@param senderDeviceId integer
---@param requestId string
---@return string
function Mailboxes.receivedRequestId(senderDeviceId, requestId)
    return 'recv:' .. senderDeviceId .. ':' .. requestId
end

---@param deviceId integer
---@param peerNumber string
function Mailboxes.markRead(deviceId, peerNumber)
    Db.write('UPDATE phone_mailboxes SET is_read = 1 WHERE device_id = ? AND peer_number = ?', { deviceId, peerNumber })
end

---@param deviceId integer
---@param messageId integer
function Mailboxes.deleteForDevice(deviceId, messageId)
    Db.write('DELETE FROM phone_mailboxes WHERE device_id = ? AND id = ?', { deviceId, messageId })
end
