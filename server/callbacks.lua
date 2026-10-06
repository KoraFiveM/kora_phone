function QBPhone.registerCallback(name, rateKey, handler)
    exports.qbcore:createCallback('qbphone:server:' .. name, function(source, cb, payload)
        if not QBPhone.RateLimits.consume(source, rateKey) then
            cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
            return
        end
        payload = type(payload) == 'table' and payload or {}
        local ok, result = xpcall(function() return handler(source, payload) end, debug.traceback)
        if not ok then
            print(('[qbphone] callback %s failed for source %s: %s'):format(name, source, result))
            cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
            return
        end
        cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
    end)
end

QBPhone.registerCallback('getBootstrap', 'bootstrap', QBPhone.Services.Phone.bootstrap)
QBPhone.registerCallback('saveSettings', 'mutation', QBPhone.Services.Phone.saveSettings)
QBPhone.registerCallback('unlockPhone', 'pin', QBPhone.Services.Phone.unlock)
QBPhone.registerCallback('lockPhone', 'mutation', QBPhone.Services.Phone.lock)
QBPhone.registerCallback('setPhonePin', 'pin', QBPhone.Services.Phone.setPin)
QBPhone.registerCallback('removePhonePin', 'pin', QBPhone.Services.Phone.removePin)
QBPhone.registerCallback('getContacts', 'read', QBPhone.Services.Contacts.list)
QBPhone.registerCallback('saveContact', 'mutation', QBPhone.Services.Contacts.save)
QBPhone.registerCallback('deleteContact', 'mutation', QBPhone.Services.Contacts.delete)
QBPhone.registerCallback('sendMessage', 'sendMessage', QBPhone.Services.Messaging.send)
QBPhone.registerCallback('getMessages', 'read', QBPhone.Services.Messaging.list)
QBPhone.registerCallback('getConversations', 'read', QBPhone.Services.Messaging.listConversations)
QBPhone.registerCallback('startDirectConversation', 'mutation', QBPhone.Services.Messaging.startDirect)
QBPhone.registerCallback('markConversationRead', 'mutation', QBPhone.Services.Messaging.markRead)
QBPhone.registerCallback('deleteMessageForSelf', 'mutation', QBPhone.Services.Messaging.deleteForSelf)
QBPhone.registerCallback('createGroup', 'mutation', QBPhone.Services.Messaging.createGroup)
QBPhone.registerCallback('leaveGroup', 'mutation', QBPhone.Services.Messaging.leaveGroup)
QBPhone.registerCallback('addGroupMember', 'mutation', QBPhone.Services.Messaging.addMember)
QBPhone.registerCallback('getBlocked', 'read', QBPhone.Services.Blocking.list)
QBPhone.registerCallback('setBlocked', 'mutation', QBPhone.Services.Blocking.set)
QBPhone.registerCallback('getMail', 'read', QBPhone.Services.Mail.list)
QBPhone.registerCallback('sendMail', 'sendMessage', QBPhone.Services.Mail.send)
QBPhone.registerCallback('readMail', 'mutation', QBPhone.Services.Mail.markRead)
QBPhone.registerCallback('deleteMail', 'mutation', QBPhone.Services.Mail.delete)
QBPhone.registerCallback('getProperties', 'read', QBPhone.Services.Property.list)
QBPhone.registerCallback('saveItem', 'mutation', QBPhone.Services.Items.save)
QBPhone.registerCallback('removeItem', 'mutation', QBPhone.Services.Items.remove)
QBPhone.registerCallback('getVehicles', 'read', QBPhone.Services.Garage.list)
