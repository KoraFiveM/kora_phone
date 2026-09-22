QBPhone.Permissions = {}

function QBPhone.Permissions.requirePlayer(source)
    local citizenId = QBPhone.GetCitizenId(source)
    if not citizenId then return nil, PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'Character is not loaded') end
    if not QBPhone.HasPhone(source) then return nil, PhoneError(PhoneConstants.Errors.PHONE_REQUIRED, 'A phone is required') end
    return citizenId
end

-- A phone with a PIN refuses requests until the session is unlocked. Answering or ending a
-- call passes allowLocked so a locked phone can still take a call.
function QBPhone.Permissions.requireDevice(source, allowLocked)
    local citizenId, err = QBPhone.Permissions.requirePlayer(source)
    if not citizenId then return nil, err end
    local device = QBPhone.Services.Phone.getOrCreate(citizenId)
    if not device then return nil, PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to load phone') end
    if (device.hasPin == 1 or device.hasPin == true) and not allowLocked then
        local session = QBPhone.Sessions.bySource[source]
        if not (session and session.deviceId == device.id and session.unlocked) then
            return nil, PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Phone is locked')
        end
    end
    return device
end

