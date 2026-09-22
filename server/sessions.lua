QBPhone.Sessions = { bySource = {}, byNumber = {} }

function QBPhone.Sessions.open(source, device)
    QBPhone.Sessions.close(source)
    QBPhone.Sessions.bySource[source] = { deviceId = device.id, citizenId = device.ownerCitizenId, phoneNumber = device.phoneNumber, unlocked = false }
    QBPhone.Sessions.byNumber[device.phoneNumber] = source
end

-- Reuse the live session (keeping its unlocked state) when the same device re-bootstraps.
function QBPhone.Sessions.ensure(source, device)
    local session = QBPhone.Sessions.bySource[source]
    if session and session.deviceId == device.id then return session end
    QBPhone.Sessions.open(source, device)
    return QBPhone.Sessions.bySource[source]
end

function QBPhone.Sessions.close(source)
    local session = QBPhone.Sessions.bySource[source]
    if session and QBPhone.Sessions.byNumber[session.phoneNumber] == source then
        QBPhone.Sessions.byNumber[session.phoneNumber] = nil
    end
    QBPhone.Sessions.bySource[source] = nil
    QBPhone.RateLimits.clear(source)
end

function QBPhone.Sessions.sourceByNumber(number)
    local source = QBPhone.Sessions.byNumber[number]
    if not source then return nil end
    local session = QBPhone.Sessions.bySource[source]
    local citizenId = QBPhone.GetCitizenId(source)
    if not session or session.phoneNumber ~= number or session.citizenId ~= citizenId or not QBPhone.HasPhone(source) then
        QBPhone.Sessions.close(source)
        return nil
    end
    return source
end

AddEventHandler('playerDropped', function() QBPhone.Sessions.close(source) end)
