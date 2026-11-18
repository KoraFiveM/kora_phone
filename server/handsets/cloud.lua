-- Cloud accounts: backups, registration and restore. A snapshot restores content, never number ownership.
local H = KoraPhone.Handsets
local Cloud = KoraPhone.Repositories.Cloud

local MAX_ACCOUNT_ID = 64
local MAX_RECOVERY_CODE = 128

---Everything a backup stores: the settings plus the device content.
---@param device table
---@return table snapshot
local function snapshot(device)
    local content = Cloud.readContent(device.id)
    content.settings = device.settingsJson
    return content
end

local function mediaIdsOf(saved)
    local ids = {}
    for _, media in ipairs(saved.media) do ids[#ids + 1] = media.id end
    return ids
end

---Runs `handler` while holding the account's lock, so two handsets cannot back up or restore at once.
---@param accountId any
---@param handler fun(): table
---@return table
function H.accountLock(accountId, handler)
    if type(accountId) ~= 'string' or #accountId > MAX_ACCOUNT_ID then return H.fail('Invalid cloud account') end
    if H.accountLocks[accountId] then return H.fail('Cloud account is busy; try again') end
    H.accountLocks[accountId] = true
    local ok, result = xpcall(handler, debug.traceback)
    H.accountLocks[accountId] = nil
    if not ok then
        Kora.logging.event('phone.cloud_operation_failed', 0, { level = 'error', message = 'Cloud operation failed', error = tostring(result) })
        return H.fail('Cloud operation failed')
    end
    return result
end

local function performBackup(src, device)
    if not H.online(src, device) then return H.fail('Connect to Wi-Fi or insert an active SIM') end
    local saved = snapshot(device)
    local encoded = json.encode(saved)
    if Cloud.revision(device.accountId) ~= tonumber(device.cloudRevision) then
        return H.fail('Cloud changed on another handset. Restore before backing up')
    end
    if not H.stillHeld(src, device) then return H.fail('Handset is no longer held') end
    if not Cloud.commitBackup(device.accountId, device.handsetId, encoded, mediaIdsOf(saved)) then
        return H.fail('Backup failed; your previous backup is unchanged')
    end
    return PhoneResult({ saved = true })
end

---Backs the held handset up to its cloud account.
---@param src integer
---@return table
function H.backup(src)
    local device, err = H.require(src)
    if not device then return err end
    if not device.accountId then return H.fail('No cloud account is signed in') end
    return H.accountLock(device.accountId, function() return performBackup(src, device) end)
end

local function restore(src, device, account)
    local content = account.snapshot_json and json.decode(account.snapshot_json) or { settings = '{}' }
    if not H.stillHeld(src, device) then return H.fail('Handset is no longer held') end
    if not Cloud.restore(device, account, content) then return H.fail('Cloud restore failed; try again') end
    TriggerClientEvent('kora_phone:client:contentCleared', src)
    KoraPhone.Sessions.close(src)
    return PhoneResult({ restored = true })
end

H.operations.registerCloud = {
    run = function(src, _, device)
        if device.accountId then return H.fail('An account is already signed in') end
        if not H.online(src, device) then return H.fail('An internet connection is required') end
        local accountId = H.randomId()
        local recoveryCode = exports[GetCurrentResourceName()]:randomHex(32)
        local initial = snapshot(device)
        if not H.stillHeld(src, device) then return H.fail('Handset is no longer held') end
        local registered = Cloud.register(accountId, H.citizenId(src), recoveryCode, json.encode(initial), device.handsetId)
        if not registered then return H.fail('Account registration failed') end
        for _, mediaId in ipairs(mediaIdsOf(initial)) do Cloud.grantMedia(accountId, mediaId) end
        return PhoneResult({ accountId = accountId, recoveryCode = recoveryCode })
    end,
}

H.operations.backup = {
    run = function(src)
        return H.backup(src)
    end,
}

H.operations.restoreCloud = {
    run = function(src, payload, device)
        if not H.online(src, device) then return H.fail('An internet connection is required') end
        local validRequest = type(payload.accountId) == 'string'
            and type(payload.code) == 'string'
            and #payload.code <= MAX_RECOVERY_CODE
        if not validRequest then return H.fail('Invalid recovery details') end
        return H.accountLock(payload.accountId, function()
            local account = Cloud.findByRecoveryCode(payload.accountId, payload.code)
            if not account then return H.fail('Invalid recovery details') end
            return restore(src, device, account)
        end)
    end,
}
