QBPhone.Repositories = QBPhone.Repositories or {}
local Messages = {}
QBPhone.Repositories.Messages = Messages

local function directKey(a, b)
    return ('%s:%s'):format(math.min(a, b), math.max(a, b))
end

function Messages.findDirectConversation(deviceA, deviceB)
    return MySQL.scalar.await([[
        SELECT c.id FROM phone_conversations c
        JOIN phone_conversation_members a ON a.conversation_id = c.id AND a.device_id = ? AND a.left_at IS NULL
        JOIN phone_conversation_members b ON b.conversation_id = c.id AND b.device_id = ? AND b.left_at IS NULL
        WHERE c.type = 'direct' AND (c.direct_key = ? OR c.direct_key IS NULL)
          AND (SELECT COUNT(*) FROM phone_conversation_members x WHERE x.conversation_id = c.id AND x.left_at IS NULL) = 2
        ORDER BY c.id ASC LIMIT 1
    ]], { deviceA, deviceB, directKey(deviceA, deviceB) })
end

function Messages.createDirectConversation(deviceA, deviceB)
    local existing = Messages.findDirectConversation(deviceA, deviceB)
    if existing then return existing end
    local key = directKey(deviceA, deviceB)
    local conversationId = MySQL.insert.await([[
        INSERT IGNORE INTO phone_conversations (type, created_by_device_id, direct_key)
        VALUES ('direct', ?, ?)
    ]], { deviceA, key })
    local created = conversationId and conversationId > 0
    if not created then
        conversationId = MySQL.scalar.await('SELECT id FROM phone_conversations WHERE direct_key = ? LIMIT 1', { key })
    end
    if not conversationId then return nil end
    local ok = MySQL.transaction.await({
        { query = 'INSERT IGNORE INTO phone_conversation_members (conversation_id, device_id) VALUES (?, ?)', values = { conversationId, deviceA } },
        { query = 'INSERT IGNORE INTO phone_conversation_members (conversation_id, device_id) VALUES (?, ?)', values = { conversationId, deviceB } },
    })
    if ok then return conversationId end
    if created then
        MySQL.update.await('DELETE FROM phone_conversations WHERE id = ? AND created_by_device_id = ?', { conversationId, deviceA })
    end
    return nil
end

function Messages.insert(conversationId, senderDeviceId, body, clientRequestId, mediaId, messageType)
    return MySQL.insert.await([[
        INSERT INTO phone_messages (conversation_id, sender_device_id, message_type, body, media_id, client_request_id)
        SELECT ?, ?, ?, ?, NULLIF(?, 0), NULLIF(?, '')
        WHERE EXISTS (SELECT 1 FROM phone_conversation_members
            WHERE conversation_id = ? AND device_id = ? AND left_at IS NULL)
    ]], { conversationId, senderDeviceId, messageType or 'text', body, mediaId or 0, clientRequestId, conversationId, senderDeviceId })
end

function Messages.findIdempotent(senderDeviceId, clientRequestId)
    return MySQL.single.await([[SELECT id, conversation_id AS conversationId, body
        FROM phone_messages WHERE sender_device_id = ? AND client_request_id = ? LIMIT 1]],
        { senderDeviceId, clientRequestId })
end

function Messages.getForDevice(messageId, deviceId)
    return MySQL.single.await([[
        SELECT m.id, m.conversation_id AS conversationId, m.message_type AS messageType,
               m.body, m.media_id AS mediaId, (m.sender_device_id = ?) AS isMine,
               sender.phone_number AS senderNumber, UNIX_TIMESTAMP(m.created_at) AS createdAt,
               md.public_url AS mediaUrl, md.mime_type AS mediaMime
        FROM phone_messages m
        JOIN phone_conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.device_id = ? AND cm.left_at IS NULL
        JOIN phone_devices sender ON sender.id = m.sender_device_id
        LEFT JOIN phone_media md ON md.id = m.media_id AND md.deleted_at IS NULL
        LEFT JOIN phone_message_deletions d ON d.message_id = m.id AND d.device_id = ?
        WHERE m.id = ? AND m.deleted_at IS NULL AND d.message_id IS NULL LIMIT 1
    ]], { deviceId, deviceId, deviceId, messageId })
end

function Messages.listConversations(deviceId, limit, cursor, onlyId)
    local filters, params = { 'cm.device_id = ?', 'cm.left_at IS NULL' }, { deviceId, deviceId, deviceId }
    if cursor then filters[#filters + 1] = 'COALESCE(last_message.id, c.id) < ?'; params[#params + 1] = cursor end
    if onlyId then filters[#filters + 1] = 'c.id = ?'; params[#params + 1] = onlyId end
    params[#params + 1] = limit
    return MySQL.query.await(([[
        SELECT c.id, c.type, c.title, peer.phone_number AS peerPhoneNumber,
               COALESCE(contact.display_name, peer.phone_number, c.title, 'Conversation') AS displayLabel,
               last_message.id AS lastMessageId, last_message.body AS lastMessagePreview,
               UNIX_TIMESTAMP(last_message.created_at) AS lastMessageAt,
               COALESCE((SELECT COUNT(*) FROM phone_messages unread
                   LEFT JOIN phone_message_deletions ud ON ud.message_id = unread.id AND ud.device_id = ?
                   WHERE unread.conversation_id = c.id AND unread.deleted_at IS NULL AND ud.message_id IS NULL
                     AND unread.sender_device_id <> cm.device_id
                     AND unread.id > COALESCE(cm.last_read_message_id, 0)), 0) AS unreadCount,
               (SELECT md.mime_type FROM phone_media md WHERE md.id = last_message.media_id) AS lastMediaMime,
               COALESCE(last_message.id, c.id) AS sortId
        FROM phone_conversation_members cm JOIN phone_conversations c ON c.id = cm.conversation_id
        LEFT JOIN phone_conversation_members pm ON pm.conversation_id = c.id AND pm.device_id <> cm.device_id
             AND pm.left_at IS NULL AND c.type = 'direct'
        LEFT JOIN phone_devices peer ON peer.id = pm.device_id
        LEFT JOIN phone_contacts contact ON contact.owner_device_id = cm.device_id AND contact.phone_number = peer.phone_number
        LEFT JOIN phone_messages last_message ON last_message.id = (
            SELECT MAX(latest.id) FROM phone_messages latest
            LEFT JOIN phone_message_deletions ld ON ld.message_id = latest.id AND ld.device_id = ?
            WHERE latest.conversation_id = c.id AND latest.deleted_at IS NULL AND ld.message_id IS NULL)
        WHERE %s ORDER BY sortId DESC LIMIT ?
    ]]):format(table.concat(filters, ' AND ')), params) or {}
end

function Messages.conversationType(conversationId)
    return MySQL.scalar.await('SELECT type FROM phone_conversations WHERE id = ? LIMIT 1', { conversationId })
end

function Messages.otherMembers(conversationId, deviceId)
    return MySQL.query.await([[
        SELECT d.id, d.phone_number AS phoneNumber FROM phone_conversation_members cm
        JOIN phone_devices d ON d.id = cm.device_id AND d.is_active = 1
        WHERE cm.conversation_id = ? AND cm.device_id <> ? AND cm.left_at IS NULL
    ]], { conversationId, deviceId }) or {}
end

-- The conversation row is created first (its id is needed), then all members in one transaction;
-- if that fails the empty conversation is removed again.
function Messages.createGroup(creatorId, title, deviceIds)
    local id = MySQL.insert.await("INSERT INTO phone_conversations (type, title, created_by_device_id) VALUES ('group', ?, ?)", { title, creatorId })
    if not id or id <= 0 then return nil end
    local queries = {}
    for _, deviceId in ipairs(deviceIds) do
        queries[#queries + 1] = { query = 'INSERT IGNORE INTO phone_conversation_members (conversation_id, device_id) VALUES (?, ?)', values = { id, deviceId } }
    end
    if MySQL.transaction.await(queries) then return id end
    MySQL.update.await('DELETE FROM phone_conversations WHERE id = ? AND created_by_device_id = ?', { id, creatorId })
    return nil
end

function Messages.memberCount(conversationId)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM phone_conversation_members WHERE conversation_id = ? AND left_at IS NULL', { conversationId })) or 0
end

-- Adds a member, or brings back someone who left.
function Messages.addMember(conversationId, deviceId)
    MySQL.update.await([[
        INSERT INTO phone_conversation_members (conversation_id, device_id) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE left_at = NULL, joined_at = CURRENT_TIMESTAMP
    ]], { conversationId, deviceId })
end

function Messages.leave(deviceId, conversationId)
    local changed = MySQL.update.await([[
        UPDATE phone_conversation_members cm JOIN phone_conversations c ON c.id = cm.conversation_id
        SET cm.left_at = CURRENT_TIMESTAMP
        WHERE cm.device_id = ? AND cm.conversation_id = ? AND cm.left_at IS NULL AND c.type = 'group'
    ]], { deviceId, conversationId })
    return (tonumber(changed) or 0) > 0
end

function Messages.getConversation(deviceId, conversationId)
    return Messages.listConversations(deviceId, 1, nil, conversationId)[1]
end

function Messages.listForConversation(deviceId, conversationId, limit, cursor)
    local sql = [[
        SELECT m.id, m.conversation_id AS conversationId, m.message_type AS messageType,
               m.body, m.media_id AS mediaId, (m.sender_device_id = ?) AS isMine,
               sender.phone_number AS senderNumber, UNIX_TIMESTAMP(m.created_at) AS createdAt,
               md.public_url AS mediaUrl, md.mime_type AS mediaMime
        FROM phone_messages m
        JOIN phone_conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.device_id = ? AND cm.left_at IS NULL
        JOIN phone_devices sender ON sender.id = m.sender_device_id
        LEFT JOIN phone_media md ON md.id = m.media_id AND md.deleted_at IS NULL
        LEFT JOIN phone_message_deletions d ON d.message_id = m.id AND d.device_id = ?
        WHERE m.conversation_id = ? AND m.deleted_at IS NULL AND d.message_id IS NULL
    ]]
    local params = { deviceId, deviceId, deviceId, conversationId }
    if cursor then sql = sql .. ' AND m.id < ?'; params[#params + 1] = cursor end
    sql = sql .. ' ORDER BY m.id DESC LIMIT ?'; params[#params + 1] = limit
    return MySQL.query.await(sql, params) or {}
end

function Messages.isMember(deviceId, conversationId)
    return MySQL.scalar.await('SELECT EXISTS(SELECT 1 FROM phone_conversation_members WHERE device_id = ? AND conversation_id = ? AND left_at IS NULL)', { deviceId, conversationId }) == 1
end

function Messages.peerDevice(conversationId, deviceId)
    return MySQL.single.await([[
        SELECT d.id, d.phone_number AS phoneNumber FROM phone_conversation_members cm
        JOIN phone_devices d ON d.id = cm.device_id AND d.is_active = 1
        WHERE cm.conversation_id = ? AND cm.device_id <> ? AND cm.left_at IS NULL LIMIT 1
    ]], { conversationId, deviceId })
end

function Messages.markRead(deviceId, conversationId, messageId)
    if not messageId then messageId = MySQL.scalar.await('SELECT MAX(id) FROM phone_messages WHERE conversation_id = ? AND deleted_at IS NULL', { conversationId }) end
    if not messageId then return true, nil end
    local changed = MySQL.update.await([[
        UPDATE phone_conversation_members cm
        SET cm.last_read_message_id = GREATEST(COALESCE(cm.last_read_message_id, 0), ?)
        WHERE cm.device_id = ? AND cm.conversation_id = ? AND cm.left_at IS NULL
          AND EXISTS (SELECT 1 FROM phone_messages m WHERE m.id = ? AND m.conversation_id = cm.conversation_id)
    ]], { messageId, deviceId, conversationId, messageId })
    if changed and changed > 0 then return true, messageId end
    local exists = MySQL.scalar.await([[
        SELECT EXISTS(SELECT 1 FROM phone_messages
        WHERE id = ? AND conversation_id = ? AND deleted_at IS NULL)
    ]], { messageId, conversationId }) == 1
    return exists, messageId
end

function Messages.deleteForDevice(deviceId, messageId)
    local changed = MySQL.update.await([[
        INSERT IGNORE INTO phone_message_deletions (message_id, device_id)
        SELECT m.id, ? FROM phone_messages m
        JOIN phone_conversation_members cm ON cm.conversation_id = m.conversation_id
        WHERE m.id = ? AND cm.device_id = ? AND cm.left_at IS NULL
    ]], { deviceId, messageId, deviceId })
    return changed and changed > 0
end
