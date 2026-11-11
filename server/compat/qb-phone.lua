-- Adapted from qbcore2/kora_phone-Stevie- legacy support; mail belongs to the current character.
local Repo=KoraPhone.Repositories.LegacyMail
local function text(value,maximum)
    return type(value)=='string' and #value>0 and #value<=maximum and value or nil
end
local function mailPayload(data,allowButton)
    if type(data)~='table' then return nil end
    local sender,subject,message=text(data.sender,100),text(data.subject,120),text(data.message,16000)
    if not sender or not subject or not message then return nil end
    message=message:gsub('<[bB][rR]%s*/?>','\n'):gsub('</[pP]>','\n'):gsub('<[^>]*>','')
    local button
    if allowButton and type(data.button)=='table' and data.button.enabled~=false and data.button.buttonEvent then
        if not text(data.button.buttonEvent,200) then return nil end
        local ok,encoded=pcall(json.encode,data.button.buttonData)
        if not ok or (encoded and #encoded>16000) then return nil end
        button={buttonEvent=data.button.buttonEvent,buttonData=data.button.buttonData}
    end
    return {sender=sender,subject=subject,message=message,button=button}
end
local function sendMail(citizenId,data,allowButton)
    local mail=mailPayload(data,allowButton)
    if not text(citizenId,64) or not mail then return false end
    local id=Repo.insert(citizenId,mail)
    if not id or id<=0 then return false end
    local player=exports.kora_core:getPlayerByCitizenId(citizenId)
    if player and player.source then
        local device=KoraPhone.Handsets.current(player.source,false)
        TriggerClientEvent('kora_phone:client:mail:new',player.source,{id=id,citizenId=citizenId,
            deviceId=device and tostring(device.id),sender=mail.sender,subject=mail.subject})
    end
    return true,id
end
local function sendOffline(citizenId,data) sendMail(citizenId,data,true) end
exports('sendNewMailToOffline',sendOffline)
Kora.compat.provideExport('qb-phone','sendNewMailToOffline',sendOffline)
RegisterNetEvent('qb-phone:server:sendNewMail',function(data)
    local src=source; local citizenId=KoraPhone.GetCitizenId(src)
    if citizenId and KoraPhone.RateLimits.consume(src,'sendMessage') then sendMail(citizenId,data,false) end
end)
AddEventHandler('qb-phone:server:sendNewEventMail',function(citizenId,data)
    if source and source>0 then return end
    sendMail(citizenId,data,true)
end)
local function access(src,payload)
    local device,err=KoraPhone.Permissions.requireDevice(src)
    if not device then return nil,nil,err end
    local citizenId=KoraPhone.GetCitizenId(src)
    if not citizenId or device.holderCitizenId~=citizenId then
        return nil,nil,PhoneError(PhoneConstants.Errors.FORBIDDEN,'Handset session changed')
    end
    local id=PhoneValidation.integer(type(payload)=='table' and payload.id,'id',1)
    return citizenId,id
end
local function list(src,payload,activity)
    local citizenId,_,err=access(src,payload); if not citizenId then return err end
    local page,validationError=PhoneValidation.page(payload)
    if not page then return PhoneError(PhoneConstants.Errors.INVALID_INPUT,validationError) end
    local rows=(activity and Repo.activity or Repo.list)(citizenId,page.limit,page.cursor)
    return PhoneResult({items=rows,nextCursor=#rows==page.limit and rows[#rows].id or nil})
end
KoraPhone.registerCallback('legacy:getMail','read',function(src,p) return list(src,p,false) end)
KoraPhone.registerCallback('legacy:getActivity','read',function(src,p) return list(src,p,true) end)
local function mutate(src,p,operation)
    local citizenId,id,err=access(src,p)
    if not citizenId then return err end
    if not id then return PhoneError(PhoneConstants.Errors.INVALID_INPUT,'Invalid mail') end
    local result=operation(citizenId,id)
    if result==nil or result==false then return PhoneError(PhoneConstants.Errors.NOT_FOUND,'Mail action is no longer available') end
    return PhoneResult(result)
end
KoraPhone.registerCallback('acceptLegacyMail','mutation',function(src,p) return mutate(src,p,Repo.takeButton) end)
KoraPhone.registerCallback('legacy:readMail','mutation',function(src,p) return mutate(src,p,Repo.markRead) end)
KoraPhone.registerCallback('legacy:deleteMail','mutation',function(src,p) return mutate(src,p,Repo.delete) end)
RegisterNetEvent('qb-phone:server:ClearButtonData',function(id)
    local src=source
    if KoraPhone.RateLimits.consume(src,'mutation') then mutate(src,{id=id},Repo.clearButton) end
end)
RegisterNetEvent('qb-phone:server:RemoveMail',function(id)
    local src=source
    if KoraPhone.RateLimits.consume(src,'mutation') then mutate(src,{id=id},Repo.delete) end
end)
RegisterNetEvent('qb-phone:server:AddTransaction',function(data)
    local src=source; local citizenId=KoraPhone.GetCitizenId(src)
    if not citizenId or type(data)~='table' or not KoraPhone.RateLimits.consume(src,'mutation') then return end
    local title,message=text(data.TransactionTitle,100),text(data.TransactionMessage,1000)
    if not title or not message then return end
    local id=MySQL.insert.await('INSERT INTO phone_legacy_transactions(citizenid,title,message) VALUES(?,?,?)',{citizenId,title,message})
    if id and id>0 then TriggerClientEvent('kora_phone:client:legacyTransactionSaved',src,{citizenId=citizenId}) end
end)