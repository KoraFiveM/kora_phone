KoraPhone.Repositories = KoraPhone.Repositories or {}
local Db = KoraPhone.Database
local Handsets = {}
KoraPhone.Repositories.Handsets = Handsets

local CLEAR_PIN_FIELDS = [[
    pin_hash = NULL, pin_salt = NULL, pin_failed_attempts = 0, pin_locked_until = NULL
]]

---The handset joined with its device, in the shape the handset service works with.
---JSON columns are cast to text so callers always decode a string.
---@param handsetId string
---@return table|nil
function Handsets.findView(handsetId)
    return Db.row([[
        SELECT d.id, d.owner_citizenid AS ownerCitizenId, d.phone_number AS phoneNumber,
               CAST(d.settings_json AS CHAR) AS settingsJson, d.label,
               (d.pin_hash IS NOT NULL OR h.pin_kdf IS NOT NULL) AS hasPin,
               h.id AS handsetId, h.model, h.account_id AS accountId, h.face_citizenid AS faceCitizenId,
               h.pin_kdf AS pinKdf, h.is_reset AS isReset, h.cloud_revision AS cloudRevision
        FROM phone_handsets h JOIN phone_devices d ON d.id = h.device_id WHERE h.id = ?
    ]], { handsetId })
end

---True when this character enrolled Face ID on the handset.
---@param handsetId string
---@param citizenId string
---@return boolean
function Handsets.faceEnrolledFor(handsetId, citizenId)
    return Db.row('SELECT 1 AS ok FROM phone_handsets WHERE id = ? AND face_citizenid = ?', { handsetId, citizenId }) ~= nil
end

---Creates a handset and its device together. The device carries a sentinel number until a SIM is inserted.
---@param handsetId string
---@param citizenId string
---@param sentinelNumber string
---@param model string
---@return boolean
function Handsets.createWithDevice(handsetId, citizenId, sentinelNumber, model)
    return Db.transaction({
        {
            sql = "INSERT INTO phone_devices (owner_citizenid, phone_number, label, settings_json) VALUES (?, ?, ?, '{}')",
            params = { citizenId, sentinelNumber, 'New handset' },
        },
        {
            sql = 'INSERT INTO phone_handsets (id, model, device_id) SELECT ?, ?, id FROM phone_devices WHERE phone_number = ?',
            params = { handsetId, model, sentinelNumber },
        },
    })
end

---Removes a handset that could not be bound to an inventory item.
---@param handsetId string
---@param deviceId integer
---@return boolean
function Handsets.deleteWithDevice(handsetId, deviceId)
    return Db.transaction({
        { sql = 'DELETE FROM phone_handsets WHERE id = ?', params = { handsetId } },
        { sql = 'DELETE FROM phone_devices WHERE id = ?', params = { deviceId } },
    })
end

---@param handsetId string
---@param citizenId string|nil nil clears the enrolment.
function Handsets.setFace(handsetId, citizenId)
    Db.write('UPDATE phone_handsets SET face_citizenid = ? WHERE id = ?', { citizenId, handsetId })
end

---Marks the handset as used again after a factory reset.
---@param handsetId string
function Handsets.clearReset(handsetId)
    Db.write('UPDATE phone_handsets SET is_reset = 0 WHERE id = ?', { handsetId })
end

---@param accountId string
---@return string[] handsetIds
function Handsets.idsForAccount(accountId)
    local ids = {}
    for _, row in ipairs(Db.rows('SELECT id FROM phone_handsets WHERE account_id = ?', { accountId })) do
        ids[#ids + 1] = row.id
    end
    return ids
end

---Rows of user content on a device. Zero means the handset is safe to resell.
---@param deviceId integer
---@return integer
function Handsets.contentCount(deviceId)
    return Db.number([[
        SELECT
            (SELECT COUNT(*) FROM phone_contacts WHERE owner_device_id = ?) +
            (SELECT COUNT(*) FROM phone_items WHERE device_id = ?) +
            (SELECT COUNT(*) FROM phone_mailboxes WHERE device_id = ?) +
            (SELECT COUNT(*) FROM phone_media WHERE owner_device_id = ? AND deleted_at IS NULL) +
            (SELECT COUNT(*) FROM phone_gallery_links WHERE device_id = ?) +
            (SELECT COUNT(*) FROM phone_calls c WHERE (c.caller_device_id = ? OR c.callee_device_id = ?)
                AND NOT EXISTS(SELECT 1 FROM phone_call_hidden h WHERE h.device_id = ? AND h.call_id = c.id))
    ]], { deviceId, deviceId, deviceId, deviceId, deviceId, deviceId, deviceId, deviceId })
end

---Factory reset: wipes the device content, PIN, Face ID and cloud link in one transaction.
---@param deviceId integer
---@param handsetId string
---@return boolean
function Handsets.factoryReset(deviceId, handsetId)
    local statements = KoraPhone.Repositories.Cloud.clearContentStatements(deviceId)
    statements[#statements + 1] = {
        sql = "UPDATE phone_devices SET settings_json = '{}', " .. CLEAR_PIN_FIELDS .. ' WHERE id = ?',
        params = { deviceId },
    }
    statements[#statements + 1] = {
        sql = 'UPDATE phone_handsets SET account_id = NULL, face_citizenid = NULL, pin_kdf = NULL, is_reset = 1, cloud_revision = 0 WHERE id = ?',
        params = { handsetId },
    }
    return Db.transaction(statements)
end
