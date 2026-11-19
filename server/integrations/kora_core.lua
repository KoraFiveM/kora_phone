-- Thin wrappers over kora_core's native exports (docs/api in kora_core).
KoraPhone = KoraPhone or {}

---@param source integer
---@return table|nil player Copy of the loaded character's PlayerData.
function KoraPhone.GetPlayer(source)
    if type(source) ~= 'number' then return nil end
    return exports.kora_core:getPlayer(source)
end

---@param source integer
---@return string|nil citizenid
function KoraPhone.GetCitizenId(source)
    if type(source) ~= 'number' then return nil end
    return exports.kora_core:getPlayerData(source, { 'citizenid' })
end

---True when the player holds at least one handset item (or no item is required).
---hasItem with a list means ALL of them, so the handset names are checked one by one.
---@param source integer
---@return boolean
function KoraPhone.HasPhone(source)
    if not Config.RequirePhoneItem then return true end
    if not KoraPhone.GetCitizenId(source) then return false end
    for name in pairs(Config.Handsets) do
        if exports.kora_core:hasItem(source, name, 1) then return true end
    end
    return false
end
