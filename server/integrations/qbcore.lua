QBPhone = QBPhone or {}
QBPhone.QB = exports['qb-core']:GetCoreObject()

function QBPhone.GetPlayer(source)
    if type(source) ~= 'number' then return nil end
    return QBPhone.QB.Functions.GetPlayer(source)
end

function QBPhone.GetCitizenId(source)
    local player = QBPhone.GetPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

function QBPhone.HasPhone(source)
    if not Config.RequirePhoneItem then return true end
    local player = QBPhone.GetPlayer(source)
    return player and player.Functions.GetItemByName(Config.PhoneItem) ~= nil or false
end

