-- Public companion contracts pinned to qb-phone 333e8132359b1c50c31c2bc6db8e8a64db6c93f6.
-- Mail and transaction notes are informational; none of these routes move money.
local function text(value, maximum)
    if type(value) ~= 'string' or #value == 0 or #value > maximum then return nil end
    return value
end

local function mailPayload(data)
    if type(data) ~= 'table' then return nil end
    local sender, subject, message = text(data.sender, 100), text(data.subject, 120), text(data.message, 16000)
    if not sender or not subject or not message then return nil end
    -- Legacy scripts use <br> and inline HTML; render safe text in the native phone.
    message = message:gsub('<[bB][rR]%s*/?>', '\n'):gsub('</[pP]>', '\n'):gsub('<[^>]*>', '')
    local button
    if type(data.button) == 'table' and data.button.enabled ~= false and data.button.buttonEvent then
        if not text(data.button.buttonEvent, 200) then return nil end
        local ok, encoded = pcall(json.encode, data.button.buttonData)
        if not ok or (encoded and #encoded > 16000) then return nil end
        button = { buttonEvent = data.button.buttonEvent, buttonData = data.button.buttonData }
    end
    return { sender = sender, subject = subject, message = message, button = button }
end

local function sendNewMailToOffline(citizenId, data)
    local mail = mailPayload(data)
    if not text(citizenId, 64) or not mail then return false, 'Invalid mail' end
    local id = QBPhone.Repositories.Mail.insertLegacy(citizenId, mail)
    if not id then return false, 'Mail was not saved' end
    local player = exports.qbcore:getPlayerByCitizenId(citizenId)
    if player and player.source then
        TriggerClientEvent('qbphone:client:mail:new', player.source, { id = id, sender = mail.sender, subject = mail.subject })
    end
    return true, id
end
local function sendOffline(citizenId, data)
    sendNewMailToOffline(citizenId, data) -- Upstream's export has no return value.
end
exports('sendNewMailToOffline', sendOffline)
QB.compat.provideExport('qb-phone', 'sendNewMailToOffline', sendOffline)

RegisterNetEvent('qb-phone:server:sendNewMail', function(data)
    local src = source
    local citizenId = QBPhone.GetCitizenId(src)
    if not citizenId or not QBPhone.RateLimits.consume(src, 'sendMessage') then return end
    sendNewMailToOffline(citizenId, data)
end)

-- An arbitrary recipient is a server-side capability, not a client-controlled write.
AddEventHandler('qb-phone:server:sendNewEventMail', function(citizenId, data)
    if source and source > 0 then return end
    sendNewMailToOffline(citizenId, data)
end)

local function takeButton(src, payload)
    local device, err = QBPhone.Permissions.requireDevice(src)
    if not device then return err end
    local id = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Invalid mail') end
    local button = QBPhone.Repositories.Mail.takeLegacyButton(device.id, device.ownerCitizenId, id)
    if not button then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Mail action is no longer available') end
    return PhoneResult(button)
end
QBPhone.registerCallback('acceptLegacyMail', 'mutation', takeButton)
RegisterNetEvent('qb-phone:server:ClearButtonData', function(id)
    local src = source
    if QBPhone.RateLimits.consume(src, 'mutation') then takeButton(src, { id = id }) end
end)
RegisterNetEvent('qb-phone:server:RemoveMail', function(id)
    local src = source
    if QBPhone.RateLimits.consume(src, 'mutation') then QBPhone.Services.Mail.delete(src, { id = id }) end
end)

RegisterNetEvent('qb-phone:server:AddTransaction', function(data)
    local src = source
    local citizenId = QBPhone.GetCitizenId(src)
    if not citizenId or type(data) ~= 'table' or not QBPhone.RateLimits.consume(src, 'mutation') then return end
    local title, message = text(data.TransactionTitle, 100), text(data.TransactionMessage, 1000)
    if not title or not message then return end
    local id = MySQL.insert.await('INSERT INTO phone_legacy_transactions (citizenid, title, message) VALUES (?, ?, ?)', { citizenId, title, message })
    if id and id > 0 then TriggerClientEvent('qbphone:client:legacyTransactionSaved', src) end
end)
