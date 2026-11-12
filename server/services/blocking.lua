KoraPhone.Services = KoraPhone.Services or {}
local Blocking = {}
KoraPhone.Services.Blocking = Blocking

-- Blocking a number stops calls, messages, mail and group adds between the two phones. The rest of
-- the server already checks Blocks.isEitherBlocked; this is the part that lets a player set it.
function Blocking.list(source)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    return PhoneResult({ items = KoraPhone.Repositories.Blocks.listBlocked(device.id) })
end

function Blocking.set(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    payload = type(payload) == 'table' and payload or {}
    local number, validationError = PhoneValidation.phoneNumber(payload.number)
    if not number then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    if type(payload.blocked) ~= 'boolean' then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'blocked must be a boolean') end
    if number == device.phoneNumber then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'You cannot block your own number') end
    local target = KoraPhone.Repositories.Phones.findByNumber(number)
    if not target then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'That number was not found') end
    KoraPhone.Repositories.Blocks.set(device.id, target.id, payload.blocked)
    return PhoneResult({ number = number, blocked = payload.blocked })
end