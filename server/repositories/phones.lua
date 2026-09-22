QBPhone.Repositories = QBPhone.Repositories or {}
local Phones = {}
QBPhone.Repositories.Phones = Phones

function Phones.findByCitizenId(citizenId)
    return MySQL.single.await([[
        SELECT id, owner_citizenid AS ownerCitizenId, phone_number AS phoneNumber,
               label, settings_json AS settingsJson, (pin_hash IS NOT NULL) AS hasPin, is_active AS isActive,
               UNIX_TIMESTAMP(created_at) AS createdAt, UNIX_TIMESTAMP(updated_at) AS updatedAt
        FROM phone_devices WHERE owner_citizenid = ? AND is_active = 1 LIMIT 1
    ]], { citizenId })
end

function Phones.findByNumber(phoneNumber)
    return MySQL.single.await([[
        SELECT id, owner_citizenid AS ownerCitizenId, phone_number AS phoneNumber, is_active AS isActive
        FROM phone_devices WHERE phone_number = ? AND is_active = 1 LIMIT 1
    ]], { phoneNumber })
end

function Phones.numberExists(phoneNumber)
    return MySQL.scalar.await('SELECT EXISTS(SELECT 1 FROM phone_devices WHERE phone_number = ?)', { phoneNumber }) == 1
end

function Phones.create(citizenId, phoneNumber)
    local id = MySQL.insert.await([[
        INSERT INTO phone_devices (owner_citizenid, phone_number, label, settings_json, is_active)
        VALUES (?, ?, 'Personal', '{}', 1)
    ]], { citizenId, phoneNumber })
    return id and Phones.findByCitizenId(citizenId) or nil
end


function Phones.updateSettings(deviceId, settingsJson)
    return MySQL.update.await('UPDATE phone_devices SET settings_json = ? WHERE id = ? AND is_active = 1', { settingsJson, deviceId }) ~= nil
end

function Phones.pinState(deviceId)
    return MySQL.single.await(
        'SELECT (pin_hash IS NOT NULL) AS hasPin, pin_failed_attempts AS failed, pin_locked_until AS lockedUntil FROM phone_devices WHERE id = ? LIMIT 1',
        { deviceId })
end

function Phones.pinMatches(deviceId, pepper, pin)
    return MySQL.scalar.await(
        'SELECT pin_hash = SHA2(CONCAT(pin_salt, ?, ?), 256) FROM phone_devices WHERE id = ? AND pin_hash IS NOT NULL LIMIT 1',
        { pepper, pin, deviceId }) == 1
end

function Phones.setPin(deviceId, salt, pepper, pin)
    local changed = MySQL.update.await([[
        UPDATE phone_devices
        SET pin_salt = ?, pin_hash = SHA2(CONCAT(?, ?, ?), 256), pin_failed_attempts = 0, pin_locked_until = NULL
        WHERE id = ? AND is_active = 1
    ]], { salt, salt, pepper, pin, deviceId })
    return (tonumber(changed) or 0) > 0
end

-- pin_locked_until is assigned before pin_failed_attempts on purpose: MySQL and MariaDB
-- evaluate SET assignments left to right, so the second one must still see the old count.
function Phones.recordPinFailure(deviceId, maxAttempts, lockSeconds, now)
    MySQL.update.await([[
        UPDATE phone_devices
        SET pin_locked_until = IF(pin_failed_attempts + 1 >= ?, ?, pin_locked_until),
            pin_failed_attempts = IF(pin_failed_attempts + 1 >= ?, 0, pin_failed_attempts + 1)
        WHERE id = ?
    ]], { maxAttempts, now + lockSeconds, maxAttempts, deviceId })
end

function Phones.clearPinFailures(deviceId)
    MySQL.update.await('UPDATE phone_devices SET pin_failed_attempts = 0, pin_locked_until = NULL WHERE id = ?', { deviceId })
end

function Phones.clearPin(deviceId)
    local changed = MySQL.update.await([[
        UPDATE phone_devices
        SET pin_hash = NULL, pin_salt = NULL, pin_failed_attempts = 0, pin_locked_until = NULL
        WHERE id = ? AND is_active = 1
    ]], { deviceId })
    return (tonumber(changed) or 0) > 0
end
