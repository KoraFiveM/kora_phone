-- The handsetAction entry point. Operations register themselves in H.operations from the other
-- handsets/* files and phone_commerce.lua; this file owns the dispatcher, status and Face ID.
local H = KoraPhone.Handsets
local Cloud = KoraPhone.Repositories.Cloud

---Phone and SIM items the player carries, for the "choose a handset / SIM" pickers.
local function carriedPhonesAndSims(src)
    local phones, sims = {}, {}
    for _, item in ipairs(H.heldHandsets(src)) do
        phones[#phones + 1] = { slot = item.slot, model = Config.Handsets[item.name], id = item.info and item.info.handsetId }
    end
    for _, item in ipairs(H.itemsNamed(src, Config.SimItem)) do
        sims[#sims + 1] = { slot = item.slot, id = item.info and item.info.simId }
    end
    return phones, sims
end

local function ownedAccounts(src)
    return Cloud.listOwned(H.citizenId(src))
end

---Status for a player with no usable handset: only what the shop counters need.
local function statusWithoutHandset(src)
    return PhoneResult({
        handset = { id = '', model = 'standard' },
        cellular = false,
        number = '',
        phones = {},
        sims = {},
        hotspots = {},
        shops = H.shopsNearby(src),
        simSwap = Config.SimSwap,
        accounts = ownedAccounts(src),
    })
end

local function handsetStatus(src, device)
    local phones, sims = carriedPhonesAndSims(src)
    return PhoneResult({
        handset = { id = device.handsetId, model = device.model },
        cellular = device.cellular,
        number = device.cellular and device.phoneNumber or '',
        sim = device.sim and { id = device.sim.id, status = device.sim.status },
        accountId = device.accountId,
        faceId = device.faceCitizenId ~= nil,
        wifi = H.wifi[src],
        online = H.online(src, device),
        phones = phones,
        sims = sims,
        hotspots = H.hotspotsNearby(src),
        shops = H.shopsNearby(src),
        simSwap = Config.SimSwap,
        accounts = ownedAccounts(src),
    })
end

H.operations.status = {
    needsDevice = false,
    run = function(src)
        if not H.current(src, true) then return statusWithoutHandset(src) end
        local device, err = H.require(src, true)
        if not device then return err end
        return handsetStatus(src, device)
    end,
}

H.operations.faceUnlock = {
    allowLocked = true,
    run = function(src, _, device)
        local enrolled = device.faceCitizenId == H.citizenId(src)
        if not enrolled or not (device.pinKdf or H.hasPin(device)) then
            return H.fail('Face ID did not recognise you')
        end
        local state = KoraPhone.Repositories.Phones.pinState(device.id)
        if state and (tonumber(state.lockedUntil) or 0) > os.time() then return H.fail('Unlock is temporarily locked') end
        if not H.stillHeld(src, device) then return H.fail('Handset is no longer held') end
        KoraPhone.Sessions.ensure(src, device).unlocked = true
        return PhoneResult({ unlocked = true })
    end,
}

H.operations.faceEnroll = {
    run = function(src, _, device)
        if not H.hasPin(device) then return H.fail('Set a backup PIN first') end
        KoraPhone.Repositories.Handsets.setFace(device.handsetId, H.citizenId(src))
        return PhoneResult(true)
    end,
}

---Entry point for the handsetAction callback.
---@param src integer
---@param payload table
---@return table
function H.action(src, payload)
    local operation = H.operations[payload.op]
    if operation and operation.needsDevice == false then return operation.run(src, payload) end
    local device, err = H.require(src, operation and operation.allowLocked or false)
    if not device then return err end
    if not operation then return H.fail('Unknown handset action') end
    return operation.run(src, payload, device)
end
