function QBPhone.registerCallback(name, rateKey, handler)
    Kora.callback.register('qbphone:server:' .. name, function(source, payload)
        if not QBPhone.RateLimits.consume(source, rateKey) then
            return PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests')
        end
        payload = type(payload) == 'table' and payload or {}
        local launchDenied = name:match('^social:') or name:match('^market:') or name:match('^moderation:')
            or name=='createGroup' or name=='addGroupMember' or name=='leaveGroup'
            or name=='transferBankMoney' or name=='sendMail' or name=='runJobAction'
        if launchDenied then return PhoneError(PhoneConstants.Errors.FORBIDDEN,'This app is not part of this release') end
        local selected=QBPhone.Handsets and QBPhone.Handsets.selected[source]
        local character=QBPhone.GetCitizenId(source)
        local function run() return handler(source,payload) end
        local ok, result = xpcall(function()
            if QBPhone.Handsets and name~='handsetAction' then
                return QBPhone.Handsets.locked(source,run,{})
            end
            return run()
        end, debug.traceback)
        if not ok then
            print(('[qbphone] callback %s failed for source %s: %s'):format(name, source, result))
            return PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed')
        end
        local intentionallyChanged=name=='handsetAction' and (payload.op=='select' or payload.op=='reset')
        if QBPhone.GetCitizenId(source)~=character or (not intentionallyChanged and selected and QBPhone.Handsets.selected[source]~=selected) then
            return PhoneError(PhoneConstants.Errors.FORBIDDEN,'Handset session changed')
        end
        if result and result.ok and (rateKey=='mutation' or rateKey=='sendMessage') and name~='handsetAction' then
            local d=QBPhone.Handsets.current(source,false)
            if d then MySQL.update.await('UPDATE phone_handsets SET is_reset=0 WHERE id=?',{d.handsetId}) end
            SetTimeout(1500,function() if QBPhone.Handsets.selected[source] then QBPhone.Handsets.locked(source,QBPhone.Handsets.backup,{}) end end)
        end
        return result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response')
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
