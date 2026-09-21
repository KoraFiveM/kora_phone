SteviePhone.Services = SteviePhone.Services or {}
local Mail = {}
SteviePhone.Services.Mail = Mail

local function invalid(message) return PhoneError(PhoneConstants.Errors.INVALID_INPUT, message) end

function Mail.list(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    payload = type(payload) == 'table' and payload or {}
    local box, boxError = PhoneValidation.enum(payload.box or 'inbox', 'box', { 'inbox', 'sent' })
    if not box then return invalid(boxError) end
    local page, pageError = PhoneValidation.page(payload)
    if not page then return invalid(pageError) end
    local rows = SteviePhone.Repositories.Mail.list(device.id, box, page.limit, page.cursor)
    return PhoneResult({ items = rows, nextCursor = #rows == page.limit and rows[#rows].id or nil })
end

function Mail.send(source, payload)
    local sender, err = SteviePhone.Permissions.requireDevice(source)
    if not sender then return err end
    local mail, validationError = PhoneContracts.mail(payload)
    if not mail then return invalid(validationError) end
    if mail.to == sender.phoneNumber then return invalid('Cannot mail your own number') end
    local recipient = SteviePhone.Repositories.Phones.findByNumber(mail.to)
    if not recipient then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Recipient was not found') end
    if SteviePhone.Repositories.Blocks.isEitherBlocked(sender.id, recipient.id) then
        return PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Mail is unavailable for this contact')
    end
    local id = SteviePhone.Repositories.Mail.insert(sender.id, recipient.id, mail.subject, mail.body, mail.clientRequestId)
    if not id then return PhoneResult({ sent = true, replayed = true }) end
    local target = SteviePhone.Sessions.sourceByNumber(recipient.phoneNumber)
    if target then
        TriggerClientEvent('stevie-phone:client:mail:new', target, { id = id, sender = sender.phoneNumber, subject = mail.subject })
    end
    return PhoneResult({ sent = true, id = id })
end

function Mail.markRead(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    SteviePhone.Repositories.Mail.markRead(device.id, id)
    return PhoneResult({ id = id })
end

function Mail.delete(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    if not SteviePhone.Repositories.Mail.delete(device.id, id) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Mail was not found')
    end
    return PhoneResult({ id = id })
end
