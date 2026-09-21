local function register(name, rateKey, handler)
    SteviePhone.QB.Functions.CreateCallback('stevie-phone:server:' .. name, function(source, cb, payload)
        if not SteviePhone.RateLimits.consume(source, rateKey) then
            cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
            return
        end
        local ok, result = xpcall(function() return handler(source, payload) end, debug.traceback)
        if not ok then
            print(('[stevie-phone] callback %s failed for source %s: %s'):format(name, source, result))
            cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
            return
        end
        cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
    end)
end

register('getBootstrap', 'bootstrap', SteviePhone.Services.Phone.bootstrap)
register('saveSettings', 'mutation', SteviePhone.Services.Phone.saveSettings)
register('unlockPhone', 'pin', SteviePhone.Services.Phone.unlock)
register('lockPhone', 'mutation', SteviePhone.Services.Phone.lock)
register('setPhonePin', 'pin', SteviePhone.Services.Phone.setPin)
register('removePhonePin', 'pin', SteviePhone.Services.Phone.removePin)
register('getContacts', 'read', SteviePhone.Services.Contacts.list)
register('saveContact', 'mutation', SteviePhone.Services.Contacts.save)
register('deleteContact', 'mutation', SteviePhone.Services.Contacts.delete)
register('sendMessage', 'sendMessage', SteviePhone.Services.Messaging.send)
register('getMessages', 'read', SteviePhone.Services.Messaging.list)
register('getConversations', 'read', SteviePhone.Services.Messaging.listConversations)
register('startDirectConversation', 'mutation', SteviePhone.Services.Messaging.startDirect)
register('markConversationRead', 'mutation', SteviePhone.Services.Messaging.markRead)
register('deleteMessageForSelf', 'mutation', SteviePhone.Services.Messaging.deleteForSelf)
register('createGroup', 'mutation', SteviePhone.Services.Messaging.createGroup)
register('leaveGroup', 'mutation', SteviePhone.Services.Messaging.leaveGroup)
register('addGroupMember', 'mutation', SteviePhone.Services.Messaging.addMember)
register('getBlocked', 'read', SteviePhone.Services.Blocking.list)
register('setBlocked', 'mutation', SteviePhone.Services.Blocking.set)
register('getMail', 'read', SteviePhone.Services.Mail.list)
register('sendMail', 'sendMessage', SteviePhone.Services.Mail.send)
register('readMail', 'mutation', SteviePhone.Services.Mail.markRead)
register('deleteMail', 'mutation', SteviePhone.Services.Mail.delete)
register('getProperties', 'read', SteviePhone.Services.Property.list)
register('saveItem', 'mutation', SteviePhone.Services.Items.save)
register('removeItem', 'mutation', SteviePhone.Services.Items.remove)
register('getVehicles', 'read', SteviePhone.Services.Garage.list)
