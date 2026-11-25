KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- All SQL for app storage. Values are stored as the JSON text the service encoded.
local Repository = {}
KoraPhone.SDK.StorageRepository = Repository

function Repository.get(deviceId, appId, key)
    return Kora.sql.scalar(
        'SELECT `value` FROM phone_app_storage WHERE device_id = ? AND app_id = ? AND `key` = ? LIMIT 1',
        { deviceId, appId, key }
    )
end

--- Byte length of one stored value, or nil when the key does not exist.
function Repository.size(deviceId, appId, key)
    return Kora.sql.scalar(
        'SELECT LENGTH(CAST(`value` AS CHAR)) FROM phone_app_storage WHERE device_id = ? AND app_id = ? AND `key` = ? LIMIT 1',
        { deviceId, appId, key }
    )
end

--- Row count and total value bytes for one app on one device.
function Repository.usage(deviceId, appId)
    local row = Kora.sql.single(
        'SELECT COUNT(*) AS keyCount, COALESCE(SUM(LENGTH(CAST(`value` AS CHAR))), 0) AS totalBytes '
            .. 'FROM phone_app_storage WHERE device_id = ? AND app_id = ?',
        { deviceId, appId }
    )
    return { keys = tonumber(row and row.keyCount) or 0, bytes = tonumber(row and row.totalBytes) or 0 }
end

--- Every key and raw JSON value one app keeps on one device, optionally limited to keys starting with `prefix`.
function Repository.list(deviceId, appId, prefix)
    local rows = Kora.sql.query(
        'SELECT `key`, `value` FROM phone_app_storage WHERE device_id = ? AND app_id = ? AND `key` LIKE ? ORDER BY `key`',
        { deviceId, appId, (prefix or ''):gsub('[%%_\\]', '\\%0') .. '%' }
    )
    return rows or {}
end

function Repository.set(deviceId, appId, key, encodedValue)
    local result = Kora.sql.execute(
        'INSERT INTO phone_app_storage (device_id, app_id, `key`, `value`) VALUES (?, ?, ?, ?) '
            .. 'ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), updated_at = CURRENT_TIMESTAMP',
        { deviceId, appId, key, encodedValue }
    )
    return result ~= nil
end

function Repository.remove(deviceId, appId, key)
    local removed = Kora.sql.update(
        'DELETE FROM phone_app_storage WHERE device_id = ? AND app_id = ? AND `key` = ?',
        { deviceId, appId, key }
    )
    return (tonumber(removed) or 0) > 0
end
