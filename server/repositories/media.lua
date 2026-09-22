QBPhone.Repositories = QBPhone.Repositories or {}
local Media = {}
QBPhone.Repositories.Media = Media

local SELECT_COLUMNS = [[
    id, owner_device_id AS ownerDeviceId, storage_provider AS storageProvider,
    storage_key AS storageKey, public_url AS publicUrl, mime_type AS mimeType,
    byte_size AS byteSize, width, height, UNIX_TIMESTAMP(created_at) AS createdAt
]]

function Media.create(record)
    local id = MySQL.insert.await([[
        INSERT INTO phone_media
            (owner_device_id, storage_provider, storage_key, public_url, mime_type, byte_size, width, height, checksum)
        VALUES (?, ?, ?, ?, ?, ?, NULLIF(?, -1), NULLIF(?, -1), NULLIF(?, ''))
    ]], {
        -- nil would drop trailing parameters, so "none" is sent as a sentinel and turned back into NULL.
        record.ownerDeviceId, record.storageProvider, record.storageKey, record.publicUrl,
        record.mimeType, record.byteSize, record.width or -1, record.height or -1, record.checksum or ''
    })
    return id and Media.findOwned(record.ownerDeviceId, id) or nil
end

function Media.findOwned(deviceId, mediaId, includeDeleted)
    return MySQL.single.await(('SELECT %s FROM phone_media WHERE id = ? AND owner_device_id = ? %s LIMIT 1')
        :format(SELECT_COLUMNS, includeDeleted and '' or 'AND deleted_at IS NULL'), { mediaId, deviceId })
end

function Media.listOwned(deviceId, limit, cursor)
    local cursorSql = cursor and 'AND id < ?' or ''
    local params = cursor and { deviceId, cursor, limit } or { deviceId, limit }
    -- The gallery lists photos; clips live in the posts and messages that use them.
    return MySQL.query.await(("SELECT %s FROM phone_media WHERE owner_device_id = ? AND deleted_at IS NULL AND mime_type LIKE 'image/%%' %s ORDER BY id DESC LIMIT ?")
        :format(SELECT_COLUMNS, cursorSql), params) or {}
end

function Media.referenceCount(mediaId)
    return tonumber(MySQL.scalar.await([[
        SELECT
          (SELECT COUNT(*) FROM phone_contacts WHERE avatar_media_id = ?) +
          (SELECT COUNT(*) FROM phone_messages WHERE media_id = ? AND deleted_at IS NULL) +
          (SELECT COUNT(*) FROM phone_social_posts WHERE media_id = ? AND deleted_at IS NULL)
    ]], { mediaId, mediaId, mediaId })) or 0
end

function Media.countImages(deviceId)
    return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM phone_media WHERE owner_device_id = ? AND deleted_at IS NULL AND mime_type LIKE 'image/%'", { deviceId })) or 0
end

function Media.countRecentVideos(deviceId)
    return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM phone_media WHERE owner_device_id = ? AND mime_type LIKE 'video/%' AND created_at > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY)", { deviceId })) or 0
end

function Media.softDelete(deviceId, mediaId)
    return MySQL.update.await([[
        UPDATE phone_media SET deleted_at = CURRENT_TIMESTAMP
        WHERE id = ? AND owner_device_id = ? AND deleted_at IS NULL
    ]], { mediaId, deviceId }) > 0
end

function Media.hardDelete(mediaId)
    return MySQL.update.await('DELETE FROM phone_media WHERE id = ? AND deleted_at IS NOT NULL', { mediaId }) > 0
end

function Media.expiredDeleted(retentionHours, limit)
    return MySQL.query.await(([=[
        SELECT %s FROM phone_media
        WHERE deleted_at IS NOT NULL AND deleted_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? HOUR)
        ORDER BY deleted_at ASC LIMIT ?
    ]=]):format(SELECT_COLUMNS), { retentionHours, limit }) or {}
end

