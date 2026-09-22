local function register(name, rateKey, handler)
    QBPhone.QB.Functions.CreateCallback('qbphone:server:' .. name, function(source, cb, payload)
        if not QBPhone.RateLimits.consume(source, rateKey) then
            cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
            return
        end
        local ok, result = xpcall(function() return handler(source, payload) end, debug.traceback)
        if not ok then
            print(('[qbphone] callback %s failed for source %s: %s'):format(name, source, result))
            cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
            return
        end
        cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
    end)
end

register('getBootstrap', 'bootstrap', QBPhone.Services.Phone.bootstrap)
register('saveSettings', 'mutation', QBPhone.Services.Phone.saveSettings)
register('unlockPhone', 'pin', QBPhone.Services.Phone.unlock)
register('lockPhone', 'mutation', QBPhone.Services.Phone.lock)
register('setPhonePin', 'pin', QBPhone.Services.Phone.setPin)
register('removePhonePin', 'pin', QBPhone.Services.Phone.removePin)
register('getContacts', 'read', QBPhone.Services.Contacts.list)
register('saveContact', 'mutation', QBPhone.Services.Contacts.save)
register('deleteContact', 'mutation', QBPhone.Services.Contacts.delete)
register('sendMessage', 'sendMessage', QBPhone.Services.Messaging.send)
register('getMessages', 'read', QBPhone.Services.Messaging.list)
register('getConversations', 'read', QBPhone.Services.Messaging.listConversations)
register('startDirectConversation', 'mutation', QBPhone.Services.Messaging.startDirect)
register('markConversationRead', 'mutation', QBPhone.Services.Messaging.markRead)
register('deleteMessageForSelf', 'mutation', QBPhone.Services.Messaging.deleteForSelf)
register('createGroup', 'mutation', QBPhone.Services.Messaging.createGroup)
register('leaveGroup', 'mutation', QBPhone.Services.Messaging.leaveGroup)
register('addGroupMember', 'mutation', QBPhone.Services.Messaging.addMember)
register('getBlocked', 'read', QBPhone.Services.Blocking.list)
register('setBlocked', 'mutation', QBPhone.Services.Blocking.set)
register('getMail', 'read', QBPhone.Services.Mail.list)
register('sendMail', 'sendMessage', QBPhone.Services.Mail.send)
register('readMail', 'mutation', QBPhone.Services.Mail.markRead)
register('deleteMail', 'mutation', QBPhone.Services.Mail.delete)
register('getProperties', 'read', QBPhone.Services.Property.list)
register('saveItem', 'mutation', QBPhone.Services.Items.save)
register('removeItem', 'mutation', QBPhone.Services.Items.remove)
register('getVehicles', 'read', QBPhone.Services.Garage.list)
