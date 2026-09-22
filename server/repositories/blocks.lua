QBPhone.Repositories = QBPhone.Repositories or {}
local Blocks = {}
QBPhone.Repositories.Blocks = Blocks

function Blocks.isEitherBlocked(deviceA, deviceB)
    return MySQL.scalar.await([[
        SELECT EXISTS(SELECT 1 FROM phone_blocks
        WHERE (blocker_device_id = ? AND blocked_device_id = ?)
           OR (blocker_device_id = ? AND blocked_device_id = ?))
    ]], { deviceA, deviceB, deviceB, deviceA }) == 1
end

function Blocks.set(blockerDeviceId, blockedDeviceId, blocked)
    if blocked then
        MySQL.insert.await('INSERT IGNORE INTO phone_blocks (blocker_device_id, blocked_device_id) VALUES (?, ?)',
            { blockerDeviceId, blockedDeviceId })
        return true
    end
    MySQL.update.await('DELETE FROM phone_blocks WHERE blocker_device_id = ? AND blocked_device_id = ?',
        { blockerDeviceId, blockedDeviceId })
    return false
end

-- The phone numbers this device has blocked (what the Settings list shows).
function Blocks.listBlocked(blockerDeviceId)
    return MySQL.query.await([[
        SELECT d.phone_number AS number FROM phone_blocks b JOIN phone_devices d ON d.id = b.blocked_device_id
        WHERE b.blocker_device_id = ? ORDER BY b.created_at DESC LIMIT 200
    ]], { blockerDeviceId }) or {}
end

function Blocks.list(blockerDeviceId, limit, cursor)
    local sql = [[SELECT b.blocked_device_id AS deviceId, p.handle, p.display_name AS displayName,
        UNIX_TIMESTAMP(b.created_at) AS createdAt FROM phone_blocks b
        LEFT JOIN phone_social_profiles p ON p.device_id = b.blocked_device_id
        WHERE b.blocker_device_id = ?]]
    local params = { blockerDeviceId }
    if cursor then sql = sql .. ' AND b.blocked_device_id < ?'; params[#params + 1] = cursor end
    sql = sql .. ' ORDER BY b.blocked_device_id DESC LIMIT ?'; params[#params + 1] = limit
    return MySQL.query.await(sql, params) or {}
end
