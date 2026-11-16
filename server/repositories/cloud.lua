KoraPhone.Repositories = KoraPhone.Repositories or {}
local Db = KoraPhone.Database
local Cloud = {}
KoraPhone.Repositories.Cloud = Cloud

-- Snapshots written before timestamps were exported as epoch seconds hold milliseconds.
local MILLISECOND_THRESHOLD = 100000000000

---Media a device can reach: its own gallery, shared links, mailbox attachments and contact avatars.
local SNAPSHOT_MEDIA_SQL = [[
    SELECT m.id, m.owner_device_id, m.storage_provider, m.storage_key, m.public_url,
           m.mime_type, m.byte_size, m.width, m.height,
           ((m.owner_device_id = ? AND m.deleted_at IS NULL)
               OR EXISTS(SELECT 1 FROM phone_gallery_links l WHERE l.media_id = m.id AND l.device_id = ?)) AS is_gallery
    FROM phone_media m
    WHERE (m.owner_device_id = ? AND m.deleted_at IS NULL)
        OR EXISTS(SELECT 1 FROM phone_gallery_links l WHERE l.media_id = m.id AND l.device_id = ?)
        OR EXISTS(SELECT 1 FROM phone_mailboxes b WHERE b.device_id = ? AND b.media_id = m.id)
        OR EXISTS(SELECT 1 FROM phone_contacts c WHERE c.owner_device_id = ? AND c.avatar_media_id = m.id)
]]

---Everything a cloud backup stores for a device, except its settings.
---@param deviceId integer
---@return table content { contacts, items, media, messages }
function Cloud.readContent(deviceId)
    return {
        contacts = Db.rows(
            'SELECT display_name, phone_number, is_favorite, avatar_media_id FROM phone_contacts WHERE owner_device_id = ?',
            { deviceId }),
        items = Db.rows('SELECT kind, item_key, payload FROM phone_items WHERE device_id = ?', { deviceId }),
        media = Db.rows(SNAPSHOT_MEDIA_SQL, { deviceId, deviceId, deviceId, deviceId, deviceId, deviceId }),
        messages = Db.rows([[
            SELECT peer_number, sender_number, body, request_id, UNIX_TIMESTAMP(created_at) AS created_at,
                   is_read, is_outgoing, media_id
            FROM phone_mailboxes WHERE device_id = ? ORDER BY id
        ]], { deviceId }),
    }
end

---Statements that empty a device before a restore or reset. Media rows are tombstoned, not deleted,
---so cloud-retained objects keep their provider keys.
---@param deviceId integer
---@return { sql: string, params: any[] }[]
function Cloud.clearContentStatements(deviceId)
    return {
        { sql = 'DELETE FROM phone_contacts WHERE owner_device_id = ?', params = { deviceId } },
        { sql = 'DELETE FROM phone_items WHERE device_id = ?', params = { deviceId } },
        { sql = 'DELETE FROM phone_mailboxes WHERE device_id = ?', params = { deviceId } },
        { sql = 'DELETE FROM phone_threads WHERE device_id = ?', params = { deviceId } },
        { sql = 'UPDATE phone_media SET deleted_at = CURRENT_TIMESTAMP WHERE owner_device_id = ?', params = { deviceId } },
        { sql = 'DELETE FROM phone_gallery_links WHERE device_id = ?', params = { deviceId } },
        {
            sql = 'INSERT IGNORE INTO phone_call_hidden (device_id, call_id) '
                .. 'SELECT ?, id FROM phone_calls WHERE caller_device_id = ? OR callee_device_id = ?',
            params = { deviceId, deviceId, deviceId },
        },
        { sql = 'DELETE FROM phone_blocks WHERE blocker_device_id = ?', params = { deviceId } },
    }
end

---@param accountId string
---@return number|nil revision
function Cloud.revision(accountId)
    return tonumber(Db.value('SELECT revision FROM phone_cloud_accounts WHERE id = ?', { accountId }))
end

---Writes a backup: new snapshot, bumped revisions and the media grants, atomically.
---@param accountId string
---@param handsetId string
---@param snapshotJson string
---@param mediaIds integer[]
---@return boolean
function Cloud.commitBackup(accountId, handsetId, snapshotJson, mediaIds)
    local statements = {
        {
            sql = 'UPDATE phone_cloud_accounts SET snapshot_json = ?, revision = revision + 1 WHERE id = ?',
            params = { snapshotJson, accountId },
        },
        { sql = 'UPDATE phone_handsets SET cloud_revision = cloud_revision + 1 WHERE id = ?', params = { handsetId } },
        { sql = 'DELETE FROM phone_cloud_media WHERE account_id = ?', params = { accountId } },
    }
    for _, mediaId in ipairs(mediaIds) do
        statements[#statements + 1] = {
            sql = 'INSERT IGNORE INTO phone_cloud_media (account_id, media_id) VALUES (?, ?)',
            params = { accountId, mediaId },
        }
    end
    return Db.transaction(statements)
end

---Creates an account and links the handset to it. Media grants are added afterwards by grantMedia.
---@param accountId string
---@param citizenId string
---@param recoveryCode string
---@param snapshotJson string
---@param handsetId string
---@return boolean
function Cloud.register(accountId, citizenId, recoveryCode, snapshotJson, handsetId)
    return Db.transaction({
        {
            sql = 'INSERT INTO phone_cloud_accounts (id, owner_citizenid, recovery_hash, snapshot_json) '
                .. 'VALUES (?, ?, SHA2(?, 256), ?)',
            params = { accountId, citizenId, recoveryCode, snapshotJson },
        },
        {
            sql = 'UPDATE phone_handsets SET account_id = ?, cloud_revision = 0, is_reset = 0 WHERE id = ?',
            params = { accountId, handsetId },
        },
    })
end

---@param accountId string
---@param mediaId integer
function Cloud.grantMedia(accountId, mediaId)
    Db.write('INSERT IGNORE INTO phone_cloud_media (account_id, media_id) VALUES (?, ?)', { accountId, mediaId })
end

---@param accountId string
---@param recoveryCode string
---@return table|nil
function Cloud.findByRecoveryCode(accountId, recoveryCode)
    return Db.row('SELECT * FROM phone_cloud_accounts WHERE id = ? AND recovery_hash = SHA2(?, 256)', { accountId, recoveryCode })
end

---@param accountId string
---@param citizenId string
---@return table|nil
function Cloud.findOwned(accountId, citizenId)
    return Db.row('SELECT id FROM phone_cloud_accounts WHERE id = ? AND owner_citizenid = ?', { accountId, citizenId })
end

---@param citizenId string
---@param limit? integer
---@return table[] accounts Rows with `id`, oldest first.
function Cloud.listOwned(citizenId, limit)
    local sql = 'SELECT id FROM phone_cloud_accounts WHERE owner_citizenid = ? ORDER BY created_at'
    if limit then
        return Db.rows(sql .. ' LIMIT ' .. math.floor(limit), { citizenId })
    end
    return Db.rows(sql, { citizenId })
end

---Issues a new recovery code and signs every handset out of the account.
---@param accountId string
---@param recoveryCode string
---@return boolean
function Cloud.rotateRecovery(accountId, recoveryCode)
    return Db.transaction({
        {
            sql = 'UPDATE phone_cloud_accounts SET recovery_hash = SHA2(?, 256), revision = revision + 1 WHERE id = ?',
            params = { recoveryCode, accountId },
        },
        { sql = 'UPDATE phone_handsets SET account_id = NULL, cloud_revision = 0 WHERE account_id = ?', params = { accountId } },
    })
end

local function addTimestamp(createdAt)
    local number = tonumber(createdAt)
    if not number then return '?', createdAt end
    if number >= MILLISECOND_THRESHOLD then number = number / 1000 end
    return 'FROM_UNIXTIME(?)', math.floor(number)
end

---Replaces a device's content with a snapshot and links the handset to the account, atomically.
---Media grants are restored, never duplicated, and cloud-retained objects are never deleted.
---@param device table Handset view with `id` and `handsetId`.
---@param account table Account row with `id` and `revision`.
---@param content table Decoded snapshot.
---@return boolean
function Cloud.restore(device, account, content)
    local statements = Cloud.clearContentStatements(device.id)
    local function add(sql, params) statements[#statements + 1] = { sql = sql, params = params } end
    local mediaIds = {}
    for _, media in ipairs(content.media or {}) do
        mediaIds[tostring(media.id)] = media.id
        if media.is_gallery == nil or media.is_gallery == 1 or media.is_gallery == true then
            add('INSERT IGNORE INTO phone_gallery_links (device_id, media_id) SELECT ?, id FROM phone_media WHERE id = ?',
                { device.id, media.id })
        end
    end
    for _, contact in ipairs(content.contacts or {}) do
        add([[INSERT INTO phone_contacts (owner_device_id, display_name, phone_number, is_favorite, avatar_media_id)
            VALUES (?, ?, ?, ?, NULLIF(?, 0))]], {
            device.id, contact.display_name, contact.phone_number, contact.is_favorite,
            mediaIds[tostring(contact.avatar_media_id)] or 0,
        })
    end
    for _, item in ipairs(content.items or {}) do
        local payload = type(item.payload) == 'table' and json.encode(item.payload) or item.payload
        add('INSERT INTO phone_items (device_id, kind, item_key, payload) VALUES (?, ?, ?, ?)',
            { device.id, item.kind, item.item_key, payload })
    end
    for _, message in ipairs(content.messages or {}) do
        local createdSql, createdValue = addTimestamp(message.created_at)
        add(([[INSERT INTO phone_mailboxes
                (device_id, peer_number, sender_number, body, request_id, created_at, is_read, is_outgoing, media_id)
            VALUES (?, ?, ?, ?, ?, %s, ?, ?, NULLIF(?, 0))]]):format(createdSql), {
            device.id, message.peer_number, message.sender_number, message.body, message.request_id,
            createdValue, message.is_read, message.is_outgoing or 0, mediaIds[tostring(message.media_id)] or 0,
        })
        add('INSERT IGNORE INTO phone_threads (device_id, peer_number) VALUES (?, ?)', { device.id, message.peer_number })
    end
    local settings = type(content.settings) == 'table' and json.encode(content.settings) or content.settings or '{}'
    add('UPDATE phone_devices SET settings_json = ? WHERE id = ?', { settings, device.id })
    add('UPDATE phone_handsets SET account_id = ?, cloud_revision = ?, is_reset = 0 WHERE id = ?',
        { account.id, account.revision, device.handsetId })
    return Db.transaction(statements)
end
