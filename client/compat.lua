-- Legacy phone notifications never change money; balances come from the server.
RegisterNetEvent('qb-phone:client:RemoveBankMoney', function(amount)
    if type(amount) ~= 'number' or amount ~= amount or amount <= 0 or amount == math.huge then return end
    QBPhone.Notifications.Push({ title = 'Bank', message = ('$%s has been removed from your balance!'):format(amount), app = 'mail' })
end)
RegisterNetEvent('qb-phone:client:AddTransaction', function(_, _, message, title)
    if type(message) ~= 'string' or #message == 0 or #message > 1000
        or type(title) ~= 'string' or #title == 0 or #title > 100 then return end
    QBPhone.Notifications.Push({ title = 'Crypto', message = message, app = 'mail' })
    TriggerServerEvent('qb-phone:server:AddTransaction', { TransactionTitle = title, TransactionMessage = message })
end)
RegisterNetEvent('qb-phone:client:NewMailNotify', function(mail)
    if type(mail) ~= 'table' or type(mail.sender) ~= 'string' then return end
    TriggerEvent('qbphone:client:mail:new', { sender = mail.sender, subject = mail.subject, citizenId=mail.citizenId, deviceId=mail.deviceId })
end)
RegisterNetEvent('qb-phone:RefreshPhone', function() QBPhone.Bootstrap() end)
RegisterNetEvent('qb-phone:client:BillingEmail', function(data, paid, name)
    if type(data) ~= 'table' or type(data.amount) ~= 'number' or data.amount~=data.amount or data.amount<=0 or data.amount==math.huge or type(name) ~= 'string' or #name>100 then return end
    TriggerServerEvent('qb-phone:server:sendNewMail', { sender = 'Billing Department',
        subject = paid and 'Invoice Paid' or 'Invoice Declined',
        message = ('Invoice Has Been %s From %s In The Amount Of $%s'):format(paid and 'Paid' or 'Declined', name, data.amount) })
end)

RegisterNUICallback('mail:accept', function(data, cb)
    QBPhone.ServerCallback('qbphone:server:acceptLegacyMail', { id = type(data) == 'table' and data.id }, function(result)
        if type(result) == 'table' and result.ok and type(result.data) == 'table' and type(result.data.buttonEvent) == 'string' then
            TriggerEvent(result.data.buttonEvent, result.data.buttonData)
        end
        cb(result)
    end)
end)

RegisterNetEvent('qbphone:client:legacyTransactionSaved', function(data)
    local player=exports.kora_core:getPlayerData()
    if type(data)~='table' or not player or data.citizenId~=player.citizenid then return end
    QBPhone.SendNui('legacy:activity')
end)

-- qb-phone:client:addPoliceAlert: sent by police and tracker scripts to an officer's client. Only an on-duty
-- officer sees it, as a phone notification; it never changes any state.
local function alertText(value, maximum)
    if type(value) == 'number' then value = tostring(value) end
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    return value ~= '' and value:sub(1, maximum) or nil
end
RegisterNetEvent('qb-phone:client:addPoliceAlert', function(alert)
    if type(alert) ~= 'table' then return end
    local player = exports.kora_core:getPlayerData()
    local job = player and player.job
    if type(job) ~= 'table' or job.onduty ~= true or (job.type ~= 'leo' and job.name ~= 'police') then return end
    local title = alertText(alert.title, 80) or 'Police alert'
    QBPhone.Notifications.Push({ title = title, message = alertText(alert.description, 500), app = 'system' })
end)

-- The kora_phone client exports (open / close / isOpen) for resources written for the legacy resource. They are
-- always available on this resource's own name, and also as exports.kora_phone unless
-- Config.compat.koraPhoneExports.enabled is false (the config key needs a restart to apply).
local compatExports = {
    open = function(app)
        if app ~= nil and type(app) ~= 'string' then return false, 'kora_phone: app must be a string' end
        return QBPhone.Open(app)
    end,
    close = function()
        if QBPhone.State.open then QBPhone.Close(false) end
        return true
    end,
    isOpen = function() return QBPhone.State.open == true end,
}
for name, fn in pairs(compatExports) do
    exports(name, fn)
    if Config.compat.koraPhoneExports.enabled and GetCurrentResourceName() ~= 'kora_phone' then
        Kora.compat.provideExport('kora_phone', name, fn)
    end
end
