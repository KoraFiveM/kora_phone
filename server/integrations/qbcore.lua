KoraPhone = KoraPhone or {}

function KoraPhone.GetPlayer(source)
    if type(source) ~= 'number' then return nil end
    return exports.kora_core:getPlayerData(source)
end

function KoraPhone.GetCitizenId(source)
    local player = KoraPhone.GetPlayer(source)
    return player and player.citizenid or nil
end

function KoraPhone.HasPhone(source)
    if not Config.RequirePhoneItem then return true end
    local player = KoraPhone.GetPlayer(source)
    if not player then return false end
    for name in pairs(Config.Handsets) do if exports.kora_core:getItemByName(source,name) then return true end end
    return false
end