QBPhone.Sessions = { bySource = {}, byNumber = {} }

function QBPhone.Sessions.open(source, device)
    QBPhone.Sessions.close(source)
    QBPhone.Sessions.bySource[source] = { deviceId = device.id, citizenId = QBPhone.GetCitizenId(source), phoneNumber = device.phoneNumber, unlocked = false, handsetId=device.handsetId }
    if device.cellular then QBPhone.Sessions.byNumber[device.phoneNumber] = source end
end

-- Reuse the live session (keeping its unlocked state) when the same device re-bootstraps.
function QBPhone.Sessions.ensure(source, device)
    local session = QBPhone.Sessions.bySource[source]
    if session and session.deviceId == device.id and session.phoneNumber==device.phoneNumber then return session end
    QBPhone.Sessions.open(source, device)
    return QBPhone.Sessions.bySource[source]
end

function QBPhone.Sessions.close(source)
    local session = QBPhone.Sessions.bySource[source]
    if session and QBPhone.Sessions.byNumber[session.phoneNumber] == source then
        QBPhone.Sessions.byNumber[session.phoneNumber] = nil
    end
    QBPhone.Sessions.bySource[source] = nil
end

function QBPhone.Sessions.sourceByNumber(number)
    local source = QBPhone.Sessions.byNumber[number]
    if not source then return nil end
    local session = QBPhone.Sessions.bySource[source]
    local citizenId = QBPhone.GetCitizenId(source)
    local device=QBPhone.Handsets.current(source,false)
    if not device or not device.cellular or device.phoneNumber~=number or not session or session.phoneNumber ~= number or session.citizenId ~= citizenId then
        QBPhone.Sessions.close(source)
        return nil
    end
    return source
end

AddEventHandler('playerDropped', function() QBPhone.Sessions.close(source); QBPhone.RateLimits.clear(source) end)
