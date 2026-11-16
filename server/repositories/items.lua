KoraPhone.Repositories = KoraPhone.Repositories or {}
local Items = {}
KoraPhone.Repositories.Items = Items

function Items.list(deviceId)
    return Kora.sql.query(
        'SELECT kind, item_key AS itemKey, payload FROM phone_items WHERE device_id = ? ORDER BY updated_at DESC',
        { deviceId }
    ) or {}
end

function Items.exists(deviceId, kind, key)
    return Kora.sql.scalar(
        'SELECT EXISTS(SELECT 1 FROM phone_items WHERE device_id = ? AND kind = ? AND item_key = ?)',
        { deviceId, kind, key }
    ) == 1
end

function Items.count(deviceId, kind)
    return tonumber(Kora.sql.scalar(
        'SELECT COUNT(*) FROM phone_items WHERE device_id = ? AND kind = ?',
        { deviceId, kind }
    )) or 0
end

function Items.upsert(deviceId, kind, key, payloadJson)
    return Kora.sql.update([[
        INSERT INTO phone_items (device_id, kind, item_key, payload) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE payload = VALUES(payload)
    ]], { deviceId, kind, key, payloadJson }) ~= nil
end

function Items.remove(deviceId, kind, key)
    local changed = Kora.sql.update(
        'DELETE FROM phone_items WHERE device_id = ? AND kind = ? AND item_key = ?',
        { deviceId, kind, key }
    )
    return (tonumber(changed) or 0) > 0
end