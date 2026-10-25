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

function Mail.list(deviceId, box, limit, cursor, citizenId)
    local inbox = box == 'inbox'
    local params = inbox and { deviceId, citizenId or '' } or { deviceId }
    local owner = inbox and '(m.recipient_device_id = ? OR m.recipient_citizenid = ?)'
        or 'm.sender_device_id = ?'
    local sql = ([[
        SELECT m.id, COALESCE(m.legacy_sender, peer.phone_number) AS peer, m.subject, m.body,
               UNIX_TIMESTAMP(m.created_at) AS createdAt, (m.legacy_sender IS NULL) AS canReply,
               (m.legacy_button IS NOT NULL) AS hasAction, %s AS unread
        FROM phone_mail m LEFT JOIN phone_devices peer ON peer.id = m.%s
        WHERE %s AND m.%s = 0
    ]]):format(inbox and '(m.read_at IS NULL)' or '0', inbox and 'sender_device_id' or 'recipient_device_id',
        owner, inbox and 'recipient_deleted' or 'sender_deleted')
    if cursor then sql = sql .. ' AND m.id < ?'; params[#params + 1] = cursor end
    sql = sql .. ' ORDER BY m.id DESC LIMIT ?'; params[#params + 1] = limit
    return MySQL.query.await(sql, params) or {}
end

function Mail.markRead(deviceId, id, citizenId)
    local changed = MySQL.update.await('UPDATE phone_mail SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP) WHERE id = ? AND (recipient_device_id = ? OR recipient_citizenid = ?)', { id, deviceId, citizenId or '' })
    return changed ~= nil
end

-- Each side removes only its own copy.
function Mail.delete(deviceId, id, citizenId)
    local received = tonumber(MySQL.update.await('UPDATE phone_mail SET recipient_deleted = 1 WHERE id = ? AND (recipient_device_id = ? OR recipient_citizenid = ?)', { id, deviceId, citizenId or '' })) or 0
    local sent = tonumber(MySQL.update.await('UPDATE phone_mail SET sender_deleted = 1 WHERE id = ? AND sender_device_id = ?', { id, deviceId })) or 0
    return received + sent > 0
end

function Mail.insertLegacy(citizenId, mail)
    return MySQL.insert.await([[
        INSERT INTO phone_mail (recipient_citizenid, legacy_sender, subject, body, legacy_button, sender_deleted)
        VALUES (?, ?, ?, ?, NULLIF(?, ''), 1)
    ]], { citizenId, mail.sender, mail.subject, mail.message, mail.button and json.encode(mail.button) or '' })
end

function Mail.takeLegacyButton(deviceId, citizenId, id)
    local row = MySQL.single.await([[
        SELECT legacy_button FROM phone_mail WHERE id = ? AND recipient_deleted = 0
        AND (recipient_device_id = ? OR recipient_citizenid = ?)
    ]], { id, deviceId, citizenId })
    if not row or not row.legacy_button then return nil end
    local ok, button = pcall(json.decode, row.legacy_button)
    if not ok or type(button) ~= 'table' then return nil end
    local changed = MySQL.update.await([[
        UPDATE phone_mail SET legacy_button = NULL WHERE id = ? AND recipient_deleted = 0
        AND (recipient_device_id = ? OR recipient_citizenid = ?) AND legacy_button IS NOT NULL
    ]], { id, deviceId, citizenId })
    return tonumber(changed) == 1 and button or nil
end
