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
    if not player then return false end
    for name in pairs(Config.Handsets) do if exports.qbcore:getItemByName(source,name) then return true end end
    return false
end

