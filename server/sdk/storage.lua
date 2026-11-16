KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Per app, per device key/value storage with hard quotas. Returns `(value, err)` where err
-- is a PhoneError, so route handlers can hand it straight back.
local Storage = {}
KoraPhone.SDK.Storage = Storage

Storage.LIMITS = { keys = 64, valueBytes = 16 * 1024, totalBytes = 128 * 1024, keyLength = 64 }

local function repo() return KoraPhone.SDK.StorageRepository end
local function invalid(message) return nil, PhoneError(PhoneConstants.Errors.INVALID_INPUT, message) end

-- Quota checks read usage, then write: two overlapping writes for the same device and app could both
-- pass the check. Serialise them per (device, app). Outside FiveM (tests) there is nothing to yield on.
local locks = {}
local function withLock(deviceId, appId, fn)
    if not (promise and Citizen and Citizen.Await) then return fn() end
    local lockKey = ('%s:%s'):format(deviceId, appId)
    while locks[lockKey] do Citizen.Await(locks[lockKey]) end
    local gate = promise.new()
    locks[lockKey] = gate
    local results = table.pack(pcall(fn))
    locks[lockKey] = nil
    gate:resolve(true)
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
end

function Storage.validKey(key)
    return type(key) == 'string' and #key >= 1 and #key <= Storage.LIMITS.keyLength and key:match('^[%w_.:-]+$') ~= nil
end

function Storage.get(deviceId, appId, key)
    if not Storage.validKey(key) then return invalid('Invalid storage key') end
    local raw = repo().get(deviceId, appId, key)
    if raw == nil then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if not ok then return nil end
    return decoded
end

function Storage.set(deviceId, appId, key, value)
    if not Storage.validKey(key) then return invalid('Invalid storage key') end
    if value == nil then return invalid('Storage value is required') end
    local ok, encoded = pcall(json.encode, value)
    if not ok or type(encoded) ~= 'string' then return invalid('Storage value must be JSON') end
    local limits = Storage.LIMITS
    if #encoded > limits.valueBytes then
        return nil, PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Storage value exceeds 16 KB')
    end

    return withLock(deviceId, appId, function()
        local usage = repo().usage(deviceId, appId)
        local existing = tonumber(repo().size(deviceId, appId, key))
        if not existing and usage.keys >= limits.keys then
            return nil, PhoneError(PhoneConstants.Errors.CONFLICT, 'Storage key limit reached (64)')
        end
        if usage.bytes - (existing or 0) + #encoded > limits.totalBytes then
            return nil, PhoneError(PhoneConstants.Errors.CONFLICT, 'Storage quota exceeded (128 KB)')
        end
        if not repo().set(deviceId, appId, key, encoded) then
            return nil, PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to save storage value')
        end
        return true
    end)
end

function Storage.remove(deviceId, appId, key)
    if not Storage.validKey(key) then return invalid('Invalid storage key') end
    repo().remove(deviceId, appId, key)
    return true
end
