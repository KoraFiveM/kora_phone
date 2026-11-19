-- Handset identity: which physical handset a player is using, provisioning new ones and factory reset.
local H = KoraPhone.Handsets
local Handsets = KoraPhone.Repositories.Handsets

---With several phones in the bag, resume the one enrolled for this character rather than whichever
---comes first. Face ID and PIN belong to one handset.
local function enrolledHandset(held, citizenId)
    for _, item in ipairs(held) do
        local handsetId = item.info and item.info.handsetId
        if handsetId and Handsets.faceEnrolledFor(handsetId, citizenId) then return item end
    end
end

---Chooses the handset to use when nothing is selected yet (after a relog or restart).
---@param src integer
---@return table|nil item
local function chooseHandset(src)
    local preferred = H.preferredSlot[src]
    if preferred then
        local item = exports.kora_core:getItemBySlot(src, preferred)
        return item and Config.Handsets[item.name] and item or nil
    end
    local held = H.heldHandsets(src)
    local settings = Config.Server and Config.Server.Handsets
    if #held > 1 and not (settings and settings.ResumeEnrolledHandset == false) then
        return enrolledHandset(held, H.citizenId(src)) or held[1]
    end
    return held[1]
end

---Creates the database rows for a handset item that has none and binds them to the item.
---@param src integer
---@param item table
---@return table|nil item The bound item, nil when provisioning could not start.
local function provision(src, item)
    local handsetId = H.randomId()
    local created = Handsets.createWithDevice(
        handsetId, H.citizenId(src), H.placeholderNumber(handsetId), Config.Handsets[item.name])
    if not created then return nil end
    local ok, err = H.inventoryTx(src, {
        op = 'bindHandset', handsetSlot = item.slot, itemName = item.name, handsetId = handsetId,
    })
    if not ok then
        local orphan = Handsets.findView(handsetId)
        Handsets.deleteWithDevice(handsetId, orphan and orphan.id or 0)
        error('Could not bind handset: ' .. tostring(err))
    end
    return exports.kora_core:getItemBySlot(src, item.slot)
end

local function resolve(src, provisionIfMissing)
    if not H.ready or not H.citizenId(src) then return nil end
    local handsetId = H.selected[src]
    local item = handsetId and H.itemFor(src, handsetId)
    if handsetId and not item then
        H.revoke(src, 'possession_lost')
        return nil
    end
    if not item then
        item = chooseHandset(src)
        -- Stacked phone items cannot carry per-handset data.
        if not item or item.amount ~= 1 then return nil end
        if not (item.info and item.info.handsetId) then
            if not provisionIfMissing then return nil end
            item = provision(src, item)
            if not (item and item.info and item.info.handsetId) then return nil end
        end
        handsetId = item.info.handsetId
        H.selected[src] = handsetId
    end
    local device = Handsets.findView(handsetId)
    if not device or device.model ~= Config.Handsets[item.name] then return nil end
    return H.syncSim(src, item, device)
end

---Resolves the handset a player is holding, with its SIM and number.
---Re-checks possession afterwards so an inventory change during the SQL work revokes the session.
---@param src integer
---@param provisionIfMissing? boolean Create a handset for an unbound phone item.
---@return table|nil device
function H.current(src, provisionIfMissing)
    local me = coroutine.running()
    -- Re-entry from inside the running resolution stays refused; a parallel request (apps load several screens at
    -- once) waits for it instead of reading as "no handset".
    if H.resolving[src] == me then return nil end
    local deadline = GetGameTimer() + 5000
    while H.resolving[src] and GetGameTimer() < deadline do Wait(0) end
    if H.resolving[src] then return nil end
    local expectedCharacter = H.citizenId(src)
    H.resolving[src] = me
    local ok, value = xpcall(function() return resolve(src, provisionIfMissing) end, debug.traceback)
    H.resolving[src] = nil
    if not ok then
        Kora.logging.event('phone.handset_resolution_failed', src, { level = 'error', message = 'Handset resolution failed', error = tostring(value) })
        return nil
    end
    if value then
        local changed = H.citizenId(src) ~= expectedCharacter
            or H.selected[src] ~= value.handsetId
            or not H.itemFor(src, value.handsetId)
        if changed then
            H.revoke(src, 'possession_lost')
            return nil
        end
        value.holderCitizenId = expectedCharacter
    end
    return value
end

H.operations.select = {
    needsDevice = false,
    run = function(src, payload)
        local item = exports.kora_core:getItemBySlot(src, tonumber(payload.slot) or -1)
        if not item or not Config.Handsets[item.name] then return H.fail('Handset not found') end
        H.revoke(src, 'handset_changed')
        H.selected[src] = item.info and item.info.handsetId
        -- Provision the requested slot, not whichever phone happens to be first.
        if not H.selected[src] then
            H.preferredSlot[src] = tonumber(payload.slot)
            local device = H.current(src, true)
            H.preferredSlot[src] = nil
            if not device then return H.fail('Could not provision handset') end
        end
        return PhoneResult({ selected = true })
    end,
}

H.operations.reset = {
    run = function(src, _, device)
        if device.sim then return H.fail('Remove the SIM before resetting for resale') end
        if not Handsets.factoryReset(device.id, device.handsetId) then return H.fail('Reset failed') end
        H.revoke(src, 'factory_reset')
        return PhoneResult(true)
    end,
}
