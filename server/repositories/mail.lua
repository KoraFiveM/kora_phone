QBPhone.Repositories = QBPhone.Repositories or {}
local Mail = {}
QBPhone.Repositories.Mail = Mail

-- Returns the new id, or nil when this request id was already used (a replay).
function Mail.insert(senderId, recipientId, subject, body, clientRequestId)
    local id = MySQL.insert.await([[
        INSERT IGNORE INTO phone_mail (sender_device_id, recipient_device_id, subject, body, client_request_id)
        VALUES (?, ?, ?, ?, ?)
    ]], { senderId, recipientId, subject, body, clientRequestId })
    return id and id > 0 and id or nil
end

function Mail.list(deviceId, box, limit, cursor)
    local inbox = box == 'inbox'
    local params = { deviceId }
    local sql = ([[
        SELECT m.id, peer.phone_number AS peer, m.subject, m.body, UNIX_TIMESTAMP(m.created_at) AS createdAt,
               %s AS unread
        FROM phone_mail m JOIN phone_devices peer ON peer.id = m.%s
        WHERE m.%s = ? AND m.%s = 0
    ]]):format(inbox and '(m.read_at IS NULL)' or '0', inbox and 'sender_device_id' or 'recipient_device_id',
        inbox and 'recipient_device_id' or 'sender_device_id', inbox and 'recipient_deleted' or 'sender_deleted')
    if cursor then sql = sql .. ' AND m.id < ?'; params[#params + 1] = cursor end
    sql = sql .. ' ORDER BY m.id DESC LIMIT ?'; params[#params + 1] = limit
    return MySQL.query.await(sql, params) or {}
end

function Mail.markRead(deviceId, id)
    local changed = MySQL.update.await('UPDATE phone_mail SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP) WHERE id = ? AND recipient_device_id = ?', { id, deviceId })
    return changed ~= nil
end

-- Each side removes only its own copy.
function Mail.delete(deviceId, id)
    local received = tonumber(MySQL.update.await('UPDATE phone_mail SET recipient_deleted = 1 WHERE id = ? AND recipient_device_id = ?', { id, deviceId })) or 0
    local sent = tonumber(MySQL.update.await('UPDATE phone_mail SET sender_deleted = 1 WHERE id = ? AND sender_device_id = ?', { id, deviceId })) or 0
    return received + sent > 0
end
