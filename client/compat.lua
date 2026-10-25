-- Legacy phone notifications never change money; balances come from the server.
RegisterNetEvent('qb-phone:client:RemoveBankMoney', function(amount)
    if type(amount) ~= 'number' or amount ~= amount or amount <= 0 or amount == math.huge then return end
    QBPhone.Notifications.Push({ title = 'Bank', message = ('$%s has been removed from your balance!'):format(amount), app = 'banking' })
end)
RegisterNetEvent('qb-phone:client:AddTransaction', function(_, _, message, title)
    if type(message) ~= 'string' or #message == 0 or #message > 1000
        or type(title) ~= 'string' or #title == 0 or #title > 100 then return end
    QBPhone.Notifications.Push({ title = 'Crypto', message = message, app = 'banking' })
    TriggerServerEvent('qb-phone:server:AddTransaction', { TransactionTitle = title, TransactionMessage = message })
end)
RegisterNetEvent('qb-phone:client:NewMailNotify', function(mail)
    if type(mail) ~= 'table' or type(mail.sender) ~= 'string' then return end
    TriggerEvent('qbphone:client:mail:new', { sender = mail.sender, subject = mail.subject })
end)
RegisterNetEvent('qb-phone:RefreshPhone', function() QBPhone.Bootstrap() end)
RegisterNetEvent('qb-phone:client:BillingEmail', function(data, paid, name)
    if type(data) ~= 'table' or type(data.amount) ~= 'number' or type(name) ~= 'string' then return end
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

RegisterNetEvent('qbphone:client:legacyTransactionSaved', function()
    QBPhone.SendNui('bank:updated')
end)
