QBPhone.Repositories = QBPhone.Repositories or {}
local Contacts = {}
QBPhone.Repositories.Contacts = Contacts

local function findOwnedId(deviceId, phoneNumber)
    return MySQL.scalar.await(
        'SELECT id FROM phone_contacts WHERE owner_device_id = ? AND phone_number = ? LIMIT 1',
        { deviceId, phoneNumber }
    )
end

function Contacts.list(deviceId)
    return MySQL.query.await([[
        SELECT c.id, c.display_name AS displayName, c.phone_number AS phoneNumber,
               c.avatar_media_id AS avatarMediaId, m.public_url AS photo, c.is_favorite AS isFavorite,
               UNIX_TIMESTAMP(c.updated_at) AS updatedAt
        FROM phone_contacts c LEFT JOIN phone_media m ON m.id = c.avatar_media_id AND m.deleted_at IS NULL
        WHERE c.owner_device_id = ? ORDER BY c.is_favorite DESC, c.display_name ASC
    ]], { deviceId }) or {}
end

function Contacts.upsert(deviceId, contact)
    if contact.id then
        local changed = MySQL.update.await([[
            UPDATE phone_contacts SET display_name = ?, phone_number = ?, is_favorite = ?, avatar_media_id = NULLIF(?, 0), updated_at = CURRENT_TIMESTAMP
            WHERE id = ? AND owner_device_id = ?
        ]], { contact.displayName, contact.phoneNumber, contact.isFavorite and 1 or 0, contact.avatarMediaId or 0, contact.id, deviceId })
        if changed > 0 then return contact.id end
        -- MySQL reports zero affected rows when an owned contact is saved
        -- without changing its values. Distinguish that from a foreign ID.
        local owned = MySQL.scalar.await(
            'SELECT id FROM phone_contacts WHERE id = ? AND owner_device_id = ? LIMIT 1',
            { contact.id, deviceId }
        )
        return owned
    end
    MySQL.insert.await([[
        INSERT INTO phone_contacts (owner_device_id, display_name, phone_number, is_favorite, avatar_media_id)
        VALUES (?, ?, ?, ?, NULLIF(?, 0))
        ON DUPLICATE KEY UPDATE display_name = VALUES(display_name), is_favorite = VALUES(is_favorite),
            avatar_media_id = VALUES(avatar_media_id), updated_at = CURRENT_TIMESTAMP
    ]], { deviceId, contact.displayName, contact.phoneNumber, contact.isFavorite and 1 or 0, contact.avatarMediaId or 0 })
    return findOwnedId(deviceId, contact.phoneNumber)
end

function Contacts.delete(deviceId, contactId)
    return MySQL.update.await('DELETE FROM phone_contacts WHERE id = ? AND owner_device_id = ?', { contactId, deviceId }) > 0
end
