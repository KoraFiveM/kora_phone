SteviePhone.Services = SteviePhone.Services or {}
local Wallet = {}
SteviePhone.Services.Wallet = Wallet

local GENDERS = { [0] = 'Male', [1] = 'Female' }

-- Everything on the card is read from the server's copy of the character, never from the client.
local function card(source)
    local player = SteviePhone.GetPlayer(source)
    local pd = player and player.PlayerData
    if not pd or not pd.charinfo then return nil end
    local held = pd.metadata and pd.metadata.licences or {}
    local licences = {}
    for _, item in ipairs(Config.Server.Wallet.Licences) do
        licences[#licences + 1] = { id = item.id, label = item.label, valid = held[item.id] == true }
    end
    local gender = pd.charinfo.gender
    return {
        name = ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or ''),
        citizenId = pd.citizenid,
        birthdate = tostring(pd.charinfo.birthdate or ''),
        gender = GENDERS[tonumber(gender)] or (type(gender) == 'string' and gender or ''),
        nationality = tostring(pd.charinfo.nationality or ''),
        job = pd.job and pd.job.label or '',
        licences = licences,
    }
end

function Wallet.get(source)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local mine = card(source)
    if not mine then return PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'Character is not loaded') end
    return PhoneResult(mine)
end

-- Shows the caller's ID to the closest other player within Config.Server.Wallet.ShowDistance.
-- The distance check uses server-side ped positions, so a client cannot claim to be nearby.
function Wallet.show(source)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local mine = card(source)
    if not mine then return PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'Character is not loaded') end
    local origin = GetEntityCoords(GetPlayerPed(source))
    local nearest, best = nil, Config.Server.Wallet.ShowDistance
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target and target ~= source and SteviePhone.GetPlayer(target) then
            local ped = GetPlayerPed(target)
            if ped ~= 0 then
                local distance = #(GetEntityCoords(ped) - origin)
                if distance <= best then nearest, best = target, distance end
            end
        end
    end
    if not nearest then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'No one is close enough') end
    TriggerClientEvent('stevie-phone:client:wallet:shown', nearest, mine)
    return PhoneResult({ shown = true })
end
