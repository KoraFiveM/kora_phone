SteviePhone.Sessions = { bySource = {}, byNumber = {} }

function SteviePhone.Sessions.open(source, device)
    SteviePhone.Sessions.close(source)
    SteviePhone.Sessions.bySource[source] = { deviceId = device.id, citizenId = device.ownerCitizenId, phoneNumber = device.phoneNumber, unlocked = false }
    SteviePhone.Sessions.byNumber[device.phoneNumber] = source
end

-- Reuse the live session (keeping its unlocked state) when the same device re-bootstraps.
function SteviePhone.Sessions.ensure(source, device)
    local session = SteviePhone.Sessions.bySource[source]
    if session and session.deviceId == device.id then return session end
    SteviePhone.Sessions.open(source, device)
    return SteviePhone.Sessions.bySource[source]
end

function SteviePhone.Sessions.close(source)
    local session = SteviePhone.Sessions.bySource[source]
    if session and SteviePhone.Sessions.byNumber[session.phoneNumber] == source then
        SteviePhone.Sessions.byNumber[session.phoneNumber] = nil
    end
    SteviePhone.Sessions.bySource[source] = nil
    SteviePhone.RateLimits.clear(source)
end

function SteviePhone.Sessions.sourceByNumber(number)
    local source = SteviePhone.Sessions.byNumber[number]
    if not source then return nil end
    local session = SteviePhone.Sessions.bySource[source]
    local citizenId = SteviePhone.GetCitizenId(source)
    if not session or session.phoneNumber ~= number or session.citizenId ~= citizenId or not SteviePhone.HasPhone(source) then
        SteviePhone.Sessions.close(source)
        return nil
    end
    return source
end

AddEventHandler('playerDropped', function() SteviePhone.Sessions.close(source) end)
