---@class PhoneSession
---@field deviceId integer
---@field citizenId string|nil
---@field phoneNumber string
---@field handsetId string
---@field unlocked boolean

KoraPhone.Sessions = { bySource = {}, byNumber = {} }
local Sessions = KoraPhone.Sessions

---Starts a locked session for the device, replacing any earlier one for the player.
---@param source integer
---@param device table
function KoraPhone.Sessions.open(source, device)
    Sessions.close(source)
    Sessions.bySource[source] = {
        deviceId = device.id,
        citizenId = KoraPhone.GetCitizenId(source),
        phoneNumber = device.phoneNumber,
        unlocked = false,
        handsetId = device.handsetId,
    }
    if device.cellular then Sessions.byNumber[device.phoneNumber] = source end
end

-- Reuse the live session (keeping its unlocked state) when the same device re-bootstraps.
---@param source integer
---@param device table
---@return PhoneSession
function KoraPhone.Sessions.ensure(source, device)
    local session = Sessions.bySource[source]
    if session and session.deviceId == device.id and session.phoneNumber == device.phoneNumber then
        return session
    end
    Sessions.open(source, device)
    return Sessions.bySource[source]
end

---@param source integer
function KoraPhone.Sessions.close(source)
    local session = Sessions.bySource[source]
    if session and Sessions.byNumber[session.phoneNumber] == source then
        Sessions.byNumber[session.phoneNumber] = nil
    end
    Sessions.bySource[source] = nil
end

---The player currently answering a number, or nil. A session that no longer matches the player's
---character, handset or SIM is closed instead of trusted.
---@param number string
---@return integer|nil source
function KoraPhone.Sessions.sourceByNumber(number)
    local source = Sessions.byNumber[number]
    if not source then return nil end
    local session = Sessions.bySource[source]
    local device = KoraPhone.Handsets.current(source, false)
    local stale = not device
        or not device.cellular
        or device.phoneNumber ~= number
        or not session
        or session.phoneNumber ~= number
        or session.citizenId ~= KoraPhone.GetCitizenId(source)
    if stale then
        Sessions.close(source)
        return nil
    end
    return source
end

AddEventHandler('playerDropped', function()
    Sessions.close(source)
    KoraPhone.RateLimits.clear(source)
end)
