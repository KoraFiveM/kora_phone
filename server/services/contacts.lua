KoraPhone.Services = KoraPhone.Services or {}
local Contacts = {}
KoraPhone.Services.Contacts = Contacts

function Contacts.list(source)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    return PhoneResult({ items = KoraPhone.Repositories.Contacts.list(device.id) })
end

function Contacts.save(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local contact, validationError = PhoneContracts.contact(payload)
    if not contact then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    -- A contact photo must be one of the caller's own gallery photos, never an id or URL of someone else's.
    if contact.avatarMediaId and not KoraPhone.Repositories.Media.findOwned(device.id, contact.avatarMediaId) then
        return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'That photo was not found in your gallery')
    end
    local id = KoraPhone.Repositories.Contacts.upsert(device.id, contact)
    if not id then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Contact was not found') end
    contact.id = id
    return PhoneResult(contact)
end

function Contacts.delete(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    if not KoraPhone.Repositories.Contacts.delete(device.id, id) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Contact was not found')
    end
    return PhoneResult({ id = id })
end