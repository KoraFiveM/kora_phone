-- The `kora_phone` export surface (what kora_housing, kora_police and other resources call), answered by this
-- resource. The camelCase exports are always available on this resource's own name; they are also registered
-- under the `kora_phone` identity unless Config.compat.koraPhoneExports.enabled is false. They are mutually
-- exclusive with the legacy kora_phone resource: run one phone provider.
local function numberOfSource(source)
    local device = QBPhone.Handsets.current(source, false)
    return device and device.cellular and device.phoneNumber or nil
end

local function numberByCitizenId(citizenId)
    if type(citizenId) ~= 'string' or citizenId == '' then return nil end
    local player = exports.kora_core:getPlayerByCitizenId(citizenId)
    local online = player and player.source and numberOfSource(player.source)
    if online then return online end
    -- Offline (or no SIM in the selected handset): the number of the character's active SIM.
    local sim = MySQL.single.await(
        "SELECT phone_number FROM phone_sims WHERE owner_citizenid=? AND status='active' ORDER BY created_at,id LIMIT 1",
        { citizenId })
    return sim and sim.phone_number or nil
end

local function sendMailToOffline(citizenId, data)
    if not QBPhone.Compat.sendMail(citizenId, data, true) then
        return false, 'kora_phone: mail was not delivered'
    end
    return true
end

local function sendMailTo(source, data)
    local citizenId = QBPhone.GetCitizenId(source)
    if not citizenId then return false, 'kora_phone: that player is not registered' end
    return sendMailToOffline(citizenId, data)
end

local function sendMessage(from, to, content)
    return QBPhone.Services.Messaging.deliverSystem(from, to, content)
end

local function hasPhone(source)
    return QBPhone.HasPhone(source) == true
end

local api = {
    sendMailToOffline = sendMailToOffline,
    sendNewMailToOffline = sendMailToOffline,
    sendMail = sendMailTo,
    sendMessage = sendMessage,
    getNumber = numberOfSource,
    getNumberByCitizenId = numberByCitizenId,
    hasPhone = hasPhone,
}

for name, fn in pairs(api) do
    -- sendNewMailToOffline keeps its upstream (void) native export in server/compat/qb-phone.lua.
    if name ~= 'sendNewMailToOffline' then exports(name, fn) end
end

-- A resource folder literally named kora_phone already answers as kora_phone.
if Config.compat.koraPhoneExports.enabled and GetCurrentResourceName() ~= 'kora_phone' then
    for name, fn in pairs(api) do Kora.compat.provideExport('kora_phone', name, fn) end
end
