SteviePhone = SteviePhone or {}
SteviePhone.QB = exports['qb-core']:GetCoreObject()

function SteviePhone.GetPlayer(source)
    if type(source) ~= 'number' then return nil end
    return SteviePhone.QB.Functions.GetPlayer(source)
end

function SteviePhone.GetCitizenId(source)
    local player = SteviePhone.GetPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

function SteviePhone.HasPhone(source)
    if not Config.RequirePhoneItem then return true end
    local player = SteviePhone.GetPlayer(source)
    return player and player.Functions.GetItemByName(Config.PhoneItem) ~= nil or false
end

