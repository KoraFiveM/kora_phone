KoraPhone.Repositories = KoraPhone.Repositories or {}
local Db = KoraPhone.Database
local Phones = {}
KoraPhone.Repositories.Phones = Phones

local CLEAR_LEGACY_PIN = [[
    pin_hash = NULL, pin_salt = NULL, pin_failed_attempts = 0, pin_locked_until = NULL
]]

---@param citizenId string
---@return table|nil
function Phones.findByCitizenId(citizenId)
    return Db.row([[
        SELECT id, owner_citizenid AS ownerCitizenId, phone_number AS phoneNumber,
               label, CAST(settings_json AS CHAR) AS settingsJson, (pin_hash IS NOT NULL) AS hasPin, is_active AS isActive,
               UNIX_TIMESTAMP(created_at) AS createdAt, UNIX_TIMESTAMP(updated_at) AS updatedAt
        FROM phone_devices WHERE owner_citizenid = ? AND is_active = 1 LIMIT 1
    ]], { citizenId })
end

---Resolves the device that currently holds an active SIM with this number.
---@param phoneNumber string
---@return table|nil
function Phones.findByNumber(phoneNumber)
    return Db.row([[
        SELECT d.id, d.owner_citizenid AS ownerCitizenId, s.phone_number AS phoneNumber, 1 AS isActive
        FROM phone_sims s
        JOIN phone_handsets h ON h.id = s.handset_id
        JOIN phone_devices d ON d.id = h.device_id
        WHERE s.phone_number = ? AND s.status = 'active' LIMIT 1
    ]], { phoneNumber })
end

---@param phoneNumber string
---@return boolean
function Phones.numberExists(phoneNumber)
    return Db.flag('SELECT EXISTS(SELECT 1 FROM phone_devices WHERE phone_number = ?)', { phoneNumber })
end

---@param citizenId string
---@param phoneNumber string
---@return table|nil
function Phones.create(citizenId, phoneNumber)
    local id = Db.insert([[
        INSERT INTO phone_devices (owner_citizenid, phone_number, label, settings_json, is_active)
        VALUES (?, ?, 'Personal', '{}', 1)
    ]], { citizenId, phoneNumber })
    return id and Phones.findByCitizenId(citizenId) or nil
end

---@param deviceId integer
---@param settingsJson string
---@return boolean
function Phones.updateSettings(deviceId, settingsJson)
    return Db.write('UPDATE phone_devices SET settings_json = ? WHERE id = ? AND is_active = 1', { settingsJson, deviceId }) ~= nil
end

---A PIN exists when either the legacy hash or the handset KDF is set.
---@param deviceId integer
---@return table|nil state { hasPin, failed, lockedUntil }
function Phones.pinState(deviceId)
    return Db.row([[
        SELECT (d.pin_hash IS NOT NULL OR h.pin_kdf IS NOT NULL) AS hasPin,
               d.pin_failed_attempts AS failed, d.pin_locked_until AS lockedUntil
        FROM phone_devices d LEFT JOIN phone_handsets h ON h.device_id = d.id
        WHERE d.id = ? LIMIT 1
    ]], { deviceId })
end

---@param deviceId integer
---@return string|nil kdf The handset's PIN KDF string, nil for legacy or no PIN.
function Phones.pinKdf(deviceId)
    local row = Db.row('SELECT pin_kdf FROM phone_handsets WHERE device_id = ?', { deviceId })
    return row and row.pin_kdf or nil
end

---Compares against the legacy salted SHA-256 hash, computed in SQL so Lua never holds a PIN hash.
---@param deviceId integer
---@param pepper string
---@param pin string
---@return boolean
function Phones.legacyPinMatches(deviceId, pepper, pin)
    return Db.flag(
        'SELECT pin_hash = SHA2(CONCAT(pin_salt, ?, ?), 256) FROM phone_devices WHERE id = ? AND pin_hash IS NOT NULL LIMIT 1',
        { pepper, pin, deviceId })
end

---Stores the handset KDF and drops any legacy hash in one transaction.
---@param deviceId integer
---@param kdf string
---@return boolean
function Phones.setPinKdf(deviceId, kdf)
    return Db.transaction({
        { sql = 'UPDATE phone_handsets SET pin_kdf = ?, is_reset = 0 WHERE device_id = ?', params = { kdf, deviceId } },
        { sql = 'UPDATE phone_devices SET ' .. CLEAR_LEGACY_PIN .. ' WHERE id = ?', params = { deviceId } },
    })
end

-- pin_locked_until is assigned before pin_failed_attempts on purpose: MySQL and MariaDB
-- evaluate SET assignments left to right, so the second one must still see the old count.
---@param deviceId integer
---@param maxAttempts integer
---@param lockSeconds integer
---@param now integer
function Phones.recordPinFailure(deviceId, maxAttempts, lockSeconds, now)
    Db.write([[
        UPDATE phone_devices
        SET pin_locked_until = IF(pin_failed_attempts + 1 >= ?, ?, pin_locked_until),
            pin_failed_attempts = IF(pin_failed_attempts + 1 >= ?, 0, pin_failed_attempts + 1)
        WHERE id = ?
    ]], { maxAttempts, now + lockSeconds, maxAttempts, deviceId })
end

---@param deviceId integer
function Phones.clearPinFailures(deviceId)
    Db.write('UPDATE phone_devices SET pin_failed_attempts = 0, pin_locked_until = NULL WHERE id = ?', { deviceId })
end

---Removes both PIN forms and the Face ID enrolment bound to it.
---@param deviceId integer
---@return boolean
function Phones.clearPin(deviceId)
    return Db.transaction({
        { sql = 'UPDATE phone_handsets SET pin_kdf = NULL, face_citizenid = NULL WHERE device_id = ?', params = { deviceId } },
        { sql = 'UPDATE phone_devices SET ' .. CLEAR_LEGACY_PIN .. ' WHERE id = ?', params = { deviceId } },
    })
end
