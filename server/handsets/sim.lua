-- SIM routing: which SIM a handset holds, the number it answers to, and the insert/remove flow.
local H = KoraPhone.Handsets
local Sims = KoraPhone.Repositories.Sims

local NUMBER_ATTEMPTS = 50

---Draws a subscriber number no SIM uses yet.
---@return string
local function newSimNumber()
    local digits = Config.PhoneNumber.SubscriberDigits
    local format = '%0' .. digits .. 'd'
    for _ = 1, NUMBER_ATTEMPTS do
        local number = Config.PhoneNumber.Prefix .. string.format(format, math.random(0, 10 ^ digits - 1))
        if not Sims.numberTaken(number) then return number end
    end
    error('Phone number space unavailable')
end

---Finishes a prepared SIM replacement: the new SIM takes the number and the old one is revoked.
---@param newSimId string
---@param handsetId string
---@return boolean committed
function H.reconcileReplacement(newSimId, handsetId)
    local job = Sims.findPreparedReplacement(newSimId, handsetId)
    if not job then return false end
    local oldHandset = Sims.handsetOf(job.old_sim_id)
    if oldHandset then H.revokeHandset(oldHandset, 'sim_replaced') end
    return Sims.activateReplacement(job, newSimId, handsetId)
end

---Ends the session of every player who has this handset selected.
---@param handsetId string
---@param reason string
---@param except? integer Player to leave alone.
function H.revokeHandset(handsetId, reason, except)
    for owner, selectedId in pairs(H.selected) do
        if selectedId == handsetId and owner ~= except then H.revoke(owner, reason) end
    end
end

---Reconciles a resolved handset with the SIM its inventory metadata names. Inventory metadata is the
---insertion authority; SQL is rebuilt on every use so a crash never leaves a number on two handsets.
---@param src integer
---@param item table The handset inventory item.
---@param device table Handset view from the repository.
---@return table|nil device With `phoneNumber`, `sim` and `cellular` filled in.
function H.syncSim(src, item, device)
    local simId = item.info and item.info.phoneSimId
    local sim = simId and Sims.findById(simId)
    if sim and sim.status == 'blocked' then
        H.reconcileReplacement(sim.id, device.handsetId)
        sim = Sims.findById(simId)
    end
    -- Duplicate metadata must never acquire another handset's number.
    if sim and sim.handset_id and sim.handset_id ~= device.handsetId then return nil end
    local number = sim and sim.status == 'active' and sim.phone_number or H.placeholderNumber(device.handsetId)
    if device.phoneNumber ~= number or (sim and sim.handset_id ~= device.handsetId) then
        if not Sims.attach(device, sim and sim.id, number) then return nil end
        if KoraPhone.Sessions.bySource[src] then
            KoraPhone.Services.Calling.disconnect(src, 'sim_changed')
            KoraPhone.Sessions.close(src)
        end
    end
    device.phoneNumber = number
    device.sim = sim
    device.cellular = sim ~= nil and sim.status == 'active'
    return device
end

-- The inventory gateway moves the SIM item in the same commit as the handset metadata. This confirms
-- the result so an older companion file cannot leave the SIM both inserted and loose (or lost on removal).
---@param src integer
---@param op 'insertSim'|'removeSim'
---@param request table
---@param info? table SIM metadata to hand back on removal.
---@return boolean ok
---@return string|nil problem
function H.settleSimItem(src, op, request, info)
    if op == 'insertSim' then
        local left = exports.kora_core:getItemBySlot(src, request.simSlot)
        local stillLoose = left and left.name == Config.SimItem and left.amount == 1
            and left.info and left.info.simId == request.simId
        if stillLoose then
            local removed, why = exports.kora_inventory:RemoveItem(src, Config.SimItem, 1, request.simSlot, 'phone-sim-install')
            if not removed then
                Kora.logging.warn('phone.sim_install_consume_failed', 'SIM install could not consume the SIM item', { reason = tostring(why) })
                return false, 'SIM item could not be moved into the phone'
            end
        end
        return true
    end
    for _, item in ipairs(H.itemsNamed(src, Config.SimItem)) do
        if item.info and item.info.simId == request.simId then return true end
    end
    if type(info) ~= 'table' or info.simId ~= request.simId then return false, 'SIM details are missing' end
    local added, why = exports.kora_inventory:AddItem(src, Config.SimItem, 1, nil, info, 'phone-sim-remove')
    if not added then
        Kora.logging.warn('phone.sim_removal_return_failed', 'SIM removal could not return the SIM item', { reason = tostring(why) })
        return false, 'No room to return the SIM to your inventory'
    end
    return true
end

---@param src integer
---@param payload table
---@return boolean ok
---@return string|nil message
local function swapAllowed(src, payload)
    if Config.SimSwap == 'shop' or payload.shop then
        if not H.shopFor(src, payload.shop, true) then return false, 'Visit an authorised shop counter' end
    elseif Config.SimSwap ~= 'both' and Config.SimSwap ~= 'player' then
        return false, 'SIM swapping is disabled'
    end
    return true
end

---Makes sure the loose SIM item has a database row and that no other handset still lists it.
---@return table|nil sim
---@return string|nil message
local function prepareLooseSim(src, slot)
    local item = exports.kora_core:getItemBySlot(src, tonumber(slot) or -1)
    if not item or item.name ~= Config.SimItem or item.amount ~= 1 then return nil, 'SIM not found' end
    if not (item.info and item.info.simId) then
        local simId = H.randomId()
        Sims.insert(simId, newSimNumber(), H.citizenId(src))
        if not H.inventoryTx(src, { op = 'bindSim', simSlot = item.slot, itemName = item.name, simId = simId }) then
            return nil, 'Could not initialise SIM'
        end
        item = exports.kora_core:getItemBySlot(src, item.slot)
    end
    local sim = Sims.findById(item.info.simId)
    if not sim or sim.status ~= 'active' then return nil, 'SIM is unavailable' end
    sim.slot = item.slot
    if sim.handset_id then
        -- A held loose SIM proves removal even if SQL lagged behind the inventory commit.
        local oldHandset = sim.handset_id
        if not Sims.detach(oldHandset, sim) then return nil, 'Could not reconcile SIM removal' end
        H.revokeHandset(oldHandset, 'sim_removed', src)
    end
    return sim
end

---@param op 'insertSim'|'removeSim'
---@return fun(src: integer, payload: table, device: table): table
local function simSwap(op)
    return function(src, payload, device)
        if op == 'insertSim' and device.sim then return H.fail('Remove the current SIM first') end
        local allowed, denied = swapAllowed(src, payload)
        if not allowed then return H.fail(denied) end
        local handset = H.itemFor(src, device.handsetId)
        local request = { op = op, handsetSlot = handset.slot, handsetId = device.handsetId, simId = handset.info.phoneSimId }
        if op == 'insertSim' then
            local sim, problem = prepareLooseSim(src, payload.slot)
            if not sim then return H.fail(problem) end
            request.simSlot = sim.slot
            request.simId = sim.id
        end
        KoraPhone.Services.Calling.disconnect(src, 'sim_changed')
        local returnedInfo = op == 'removeSim' and handset.info.phoneSimInfo or nil
        local ok, reason = H.inventoryTx(src, request)
        if not ok then return H.fail(tostring(reason)) end
        if Config.ConsumeSimOnInstall ~= false then
            local settled, settleProblem = H.settleSimItem(src, op, request, returnedInfo)
            if not settled then return H.fail(settleProblem) end
        end
        H.current(src, false)
        KoraPhone.Sessions.close(src)
        return PhoneResult(true)
    end
end

H.operations.insertSim = { run = simSwap('insertSim') }
H.operations.removeSim = { run = simSwap('removeSim') }
