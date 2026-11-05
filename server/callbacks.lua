function KoraPhone.registerCallback(name, rateKey, handler)
    Kora.callback.register('kora_phone:server:' .. name, function(source, payload)
        if not KoraPhone.RateLimits.consume(source, rateKey) then
            return PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests')
        end
        payload = type(payload) == 'table' and payload or {}
        local apps = Config.Apps or {}
        local launchDenied = (name:match('^social:') and apps.social == false)
            or (name:match('^market:') and apps.classifieds == false)
            or (name:match('^moderation:') and apps.moderation == false)
            or (name=='transferBankMoney' and apps.banking == false)
        if launchDenied then return PhoneError(PhoneConstants.Errors.FORBIDDEN,'This app is not part of this release') end
        local selected=KoraPhone.Handsets and KoraPhone.Handsets.selected[source]
        local character=KoraPhone.GetCitizenId(source)
        local function run() return handler(source,payload) end
        local ok, result = xpcall(function()
            if KoraPhone.Handsets and name~='handsetAction' then
                return KoraPhone.Handsets.locked(source,run,{})
            end
            return run()
        end, debug.traceback)
        if not ok then
            print(('[kora_phone] callback %s failed for source %s: %s'):format(name, source, result))
            return PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed')
        end
        local intentionallyChanged=name=='handsetAction' and (payload.op=='select' or payload.op=='reset')
        if KoraPhone.GetCitizenId(source)~=character or (not intentionallyChanged and selected and KoraPhone.Handsets.selected[source]~=selected) then
            return PhoneError(PhoneConstants.Errors.FORBIDDEN,'Handset session changed')
        end
        if result and result.ok and (rateKey=='mutation' or rateKey=='sendMessage') and name~='handsetAction' then
            local d=KoraPhone.Handsets.current(source,false)
            if d then MySQL.update.await('UPDATE phone_handsets SET is_reset=0 WHERE id=?',{d.handsetId}) end
            SetTimeout(1500,function() if KoraPhone.Handsets.selected[source] then KoraPhone.Handsets.locked(source,KoraPhone.Handsets.backup,{}) end end)
        end
        return result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response')
    end)
end

KoraPhone.registerCallback('getBootstrap', 'bootstrap', KoraPhone.Services.Phone.bootstrap)
KoraPhone.registerCallback('saveSettings', 'mutation', KoraPhone.Services.Phone.saveSettings)
KoraPhone.registerCallback('unlockPhone', 'pin', KoraPhone.Services.Phone.unlock)
KoraPhone.registerCallback('lockPhone', 'mutation', KoraPhone.Services.Phone.lock)
KoraPhone.registerCallback('setPhonePin', 'pin', KoraPhone.Services.Phone.setPin)
KoraPhone.registerCallback('removePhonePin', 'pin', KoraPhone.Services.Phone.removePin)
KoraPhone.registerCallback('getContacts', 'read', KoraPhone.Services.Contacts.list)
KoraPhone.registerCallback('saveContact', 'mutation', KoraPhone.Services.Contacts.save)
KoraPhone.registerCallback('deleteContact', 'mutation', KoraPhone.Services.Contacts.delete)
KoraPhone.registerCallback('sendMessage', 'sendMessage', KoraPhone.Services.Messaging.send)
KoraPhone.registerCallback('getMessages', 'read', KoraPhone.Services.Messaging.list)
KoraPhone.registerCallback('getConversations', 'read', KoraPhone.Services.Messaging.listConversations)
KoraPhone.registerCallback('startDirectConversation', 'mutation', KoraPhone.Services.Messaging.startDirect)
KoraPhone.registerCallback('markConversationRead', 'mutation', KoraPhone.Services.Messaging.markRead)
KoraPhone.registerCallback('deleteMessageForSelf', 'mutation', KoraPhone.Services.Messaging.deleteForSelf)
KoraPhone.registerCallback('createGroup', 'mutation', KoraPhone.Services.Messaging.createGroup)
KoraPhone.registerCallback('leaveGroup', 'mutation', KoraPhone.Services.Messaging.leaveGroup)
KoraPhone.registerCallback('addGroupMember', 'mutation', KoraPhone.Services.Messaging.addMember)
KoraPhone.registerCallback('getBlocked', 'read', KoraPhone.Services.Blocking.list)
KoraPhone.registerCallback('setBlocked', 'mutation', KoraPhone.Services.Blocking.set)
KoraPhone.registerCallback('getMail', 'read', KoraPhone.Services.Mail.list)
KoraPhone.registerCallback('sendMail', 'sendMessage', KoraPhone.Services.Mail.send)
KoraPhone.registerCallback('readMail', 'mutation', KoraPhone.Services.Mail.markRead)
KoraPhone.registerCallback('deleteMail', 'mutation', KoraPhone.Services.Mail.delete)
KoraPhone.registerCallback('getProperties', 'read', KoraPhone.Services.Property.list)
KoraPhone.registerCallback('saveItem', 'mutation', KoraPhone.Services.Items.save)
KoraPhone.registerCallback('removeItem', 'mutation', KoraPhone.Services.Items.remove)
KoraPhone.registerCallback('getVehicles', 'read', KoraPhone.Services.Garage.list)
-- Lets the client tell a downed player with no phone item apart from one who simply cannot use it right now.
Kora.callback.register("kora_phone:server:hasPhone", function(source)
    return KoraPhone.HasPhone(source) == true
end)
