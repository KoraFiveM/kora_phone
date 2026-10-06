QBPhone = QBPhone or {}

function QBPhone.GetPlayer(source)
    if type(source) ~= 'number' then return nil end
    return exports.qbcore:getPlayerData(source)
end

function QBPhone.GetCitizenId(source)
    local player = QBPhone.GetPlayer(source)
    return player and player.citizenid or nil
end

function QBPhone.HasPhone(source)
    if not Config.RequirePhoneItem then return true end
    local player = QBPhone.GetPlayer(source)
    return player and exports.qbcore:getItemByName(source, Config.PhoneItem) ~= nil or false
end

