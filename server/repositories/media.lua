KoraPhone.Repositories = KoraPhone.Repositories or {}
local Db = KoraPhone.Database
local Media = {}
KoraPhone.Repositories.Media = Media

local SELECT_COLUMNS = [[
    m.id, m.owner_device_id AS ownerDeviceId, m.storage_provider AS storageProvider,
    m.storage_key AS storageKey, m.public_url AS publicUrl, m.mime_type AS mimeType,
    m.byte_size AS byteSize, m.width, m.height, UNIX_TIMESTAMP(m.created_at) AS createdAt
]]

-- A device sees its own live media plus anything linked into its gallery (restored or shared).
local REACHABLE_SQL = [[
    ((m.owner_device_id = ? AND m.deleted_at IS NULL)
        OR EXISTS(SELECT 1 FROM phone_gallery_links l WHERE l.device_id = ? AND l.media_id = m.id))
]]

-- Beyond any real id, so "no cursor" can be bound as a number.
local MAX_ID = 9007199254740991

---@param record table
---@return table|nil
function Media.create(record)
    local id = Db.insert([[
        INSERT INTO phone_media
            (owner_device_id, storage_provider, storage_key, public_url, mime_type, byte_size, width, height, checksum)
        VALUES (?, ?, ?, ?, ?, ?, NULLIF(?, -1), NULLIF(?, -1), NULLIF(?, ''))
    ]], {
        -- nil would drop trailing parameters, so "none" is sent as a sentinel and turned back into NULL.
        record.ownerDeviceId, record.storageProvider, record.storageKey, record.publicUrl,
        record.mimeType, record.byteSize, record.width or -1, record.height or -1, record.checksum or '',
    })
    return id and Media.findOwned(record.ownerDeviceId, id) or nil
end

---@param deviceId integer
---@param mediaId integer
---@return table|nil
function Media.findOwned(deviceId, mediaId)
    return Db.row(('SELECT %s FROM phone_media m WHERE m.id = ? AND %s'):format(SELECT_COLUMNS, REACHABLE_SQL),
        { mediaId, deviceId, deviceId })
end

---Gallery listing: camera photos and recorded clips, newest first.
---@param deviceId integer
---@param limit integer
---@param cursor? integer
---@return table[]
function Media.listOwned(deviceId, limit, cursor)
    return Db.rows(([[
        SELECT %s FROM phone_media m
        WHERE m.id < ? AND (m.mime_type LIKE 'image/%%' OR m.mime_type LIKE 'video/%%') AND %s
        ORDER BY m.id DESC LIMIT ?
    ]]):format(SELECT_COLUMNS, REACHABLE_SQL), { cursor or MAX_ID, deviceId, deviceId, limit })
end

---Everything that still points at a media row. Zero means the stored object may be deleted.
---@param mediaId integer
---@return integer
function Media.referenceCount(mediaId)
    return Db.number([[
        SELECT
            (SELECT COUNT(*) FROM phone_contacts WHERE avatar_media_id = ?) +
            (SELECT COUNT(*) FROM phone_messages WHERE media_id = ? AND deleted_at IS NULL) +
            (SELECT COUNT(*) FROM phone_social_posts WHERE media_id = ? AND deleted_at IS NULL) +
            (SELECT COUNT(*) FROM phone_cloud_media WHERE media_id = ?) +
            (SELECT COUNT(*) FROM phone_gallery_links WHERE media_id = ?) +
            (SELECT COUNT(*) FROM phone_mailboxes WHERE media_id = ?)
    ]], { mediaId, mediaId, mediaId, mediaId, mediaId, mediaId })
end

---@param deviceId integer
---@return integer
function Media.countImages(deviceId)
    return Db.number(
        "SELECT COUNT(*) FROM phone_media WHERE owner_device_id = ? AND deleted_at IS NULL AND mime_type LIKE 'image/%'",
        { deviceId })
end

---@param deviceId integer
---@return integer
function Media.countRecentVideos(deviceId)
    return Db.number([[
        SELECT COUNT(*) FROM phone_media
        WHERE owner_device_id = ? AND mime_type LIKE 'video/%' AND created_at > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY)
    ]], { deviceId })
end

---Removes the device's gallery link and tombstones the row it owns.
---@param deviceId integer
---@param mediaId integer
---@return boolean found False when the device cannot reach the media.
function Media.softDelete(deviceId, mediaId)
    if not Media.findOwned(deviceId, mediaId) then return false end
    Db.write('DELETE FROM phone_gallery_links WHERE device_id = ? AND media_id = ?', { deviceId, mediaId })
    Db.write('UPDATE phone_media SET deleted_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_device_id = ?', { mediaId, deviceId })
    return true
end

---@param mediaId integer
---@return boolean
function Media.hardDelete(mediaId)
    return Db.changed('DELETE FROM phone_media WHERE id = ? AND deleted_at IS NOT NULL', { mediaId })
end

---Tombstoned rows past retention that nothing references any more.
---@param retentionHours integer
---@param limit integer
---@return table[]
function Media.expiredDeleted(retentionHours, limit)
    return Db.rows(([[
        SELECT %s FROM phone_media m
        WHERE m.deleted_at IS NOT NULL AND m.deleted_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? HOUR)
            AND NOT EXISTS(SELECT 1 FROM phone_cloud_media c WHERE c.media_id = m.id)
            AND NOT EXISTS(SELECT 1 FROM phone_gallery_links l WHERE l.media_id = m.id)
            AND NOT EXISTS(SELECT 1 FROM phone_mailboxes b WHERE b.media_id = m.id)
            AND NOT EXISTS(SELECT 1 FROM phone_contacts c WHERE c.avatar_media_id = m.id)
            AND NOT EXISTS(SELECT 1 FROM phone_messages b WHERE b.media_id = m.id)
            AND NOT EXISTS(SELECT 1 FROM phone_social_posts p WHERE p.media_id = m.id)
        ORDER BY m.deleted_at LIMIT ?
    ]]):format(SELECT_COLUMNS), { retentionHours, limit })
end
