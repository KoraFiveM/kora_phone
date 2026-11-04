KoraPhone.Sessions = { bySource = {}, byNumber = {} }

function KoraPhone.Sessions.open(source, device)
    KoraPhone.Sessions.close(source)
    KoraPhone.Sessions.bySource[source] = { deviceId = device.id, citizenId = KoraPhone.GetCitizenId(source), phoneNumber = device.phoneNumber, unlocked = false, handsetId=device.handsetId }
    if device.cellular then KoraPhone.Sessions.byNumber[device.phoneNumber] = source end
end

-- Reuse the live session (keeping its unlocked state) when the same device re-bootstraps.
function KoraPhone.Sessions.ensure(source, device)
    local session = KoraPhone.Sessions.bySource[source]
    if session and session.deviceId == device.id and session.phoneNumber==device.phoneNumber then return session end
    KoraPhone.Sessions.open(source, device)
    return KoraPhone.Sessions.bySource[source]
end

function KoraPhone.Sessions.close(source)
    local session = KoraPhone.Sessions.bySource[source]
    if session and KoraPhone.Sessions.byNumber[session.phoneNumber] == source then
        KoraPhone.Sessions.byNumber[session.phoneNumber] = nil
    end
    KoraPhone.Sessions.bySource[source] = nil
end

function KoraPhone.Sessions.sourceByNumber(number)
    local source = KoraPhone.Sessions.byNumber[number]
    if not source then return nil end
    local session = KoraPhone.Sessions.bySource[source]
    local citizenId = KoraPhone.GetCitizenId(source)
    local device=KoraPhone.Handsets.current(source,false)
    if not device or not device.cellular or device.phoneNumber~=number or not session or session.phoneNumber ~= number or session.citizenId ~= citizenId then
        KoraPhone.Sessions.close(source)
        return nil
    end
    return source
end

AddEventHandler('playerDropped', function() KoraPhone.Sessions.close(source); KoraPhone.RateLimits.clear(source) end)