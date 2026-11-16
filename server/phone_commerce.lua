-- Shop-counter services: buying handsets, cloud account recovery, SIM replacement and resale.
-- Staff can act for a customer, who must consent first.
local H = KoraPhone.Handsets
local Cloud = KoraPhone.Repositories.Cloud
local Handsets = KoraPhone.Repositories.Handsets
local Sims = KoraPhone.Repositories.Sims

local REQUEST_TTL_SECONDS = 30
local REQUEST_CLEANUP_MS = 31000
local MAX_ACCOUNT_ID = 64
local MAX_LISTED_ACCOUNTS = 10
local DEFAULT_RESALE_PERCENT = 50

local function shopStockId(shopId)
    return 'kora_phone:' .. shopId
end

---Finds the stock slot to sell. A handset with metadata is preferred over a blank one.
local function stockSlot(shopId, itemName)
    local slot
    for key, item in pairs(exports.kora_inventory:GetShopItems(shopStockId(shopId)) or {}) do
        local sameModel = Config.Handsets[itemName] and Config.Handsets[item.name] == Config.Handsets[itemName]
        if item.name == itemName or sameModel then
            local bound = item.info and item.info.handsetId
            if not slot or bound then slot = item.slot or key end
            if bound then break end
        end
    end
    return slot
end

local function buy(actor, target, payload, shop)
    if type(payload.item) ~= 'string' or not shop.prices[payload.item] then return H.fail('Item is unavailable') end
    local slot = stockSlot(payload.shop, payload.item)
    if not slot then return H.fail('Out of stock') end
    if target ~= actor then
        H.purchaseCustomers[target] = {
            shop = payload.shop,
            actor = actor,
            actorCharacter = H.citizenId(actor),
            character = H.citizenId(target),
        }
    end
    local invoked, ok, err = pcall(function()
        return exports.kora_inventory:BuyItem(target, shopStockId(payload.shop), slot, 1)
    end)
    H.purchaseCustomers[target] = nil
    if not invoked then return H.fail('Purchase failed; try again') end
    if not ok then return H.fail(tostring(err)) end
    return PhoneResult({ purchased = true })
end

---Picks the account to recover. An empty id works when the character owns exactly one.
local function resolveRecoveryAccount(payload, citizenId)
    if payload.accountId ~= '' then return payload.accountId end
    local owned = Cloud.listOwned(citizenId, MAX_LISTED_ACCOUNTS)
    if #owned == 1 then return owned[1].id end
    local ids = {}
    for _, account in ipairs(owned) do ids[#ids + 1] = account.id end
    if #owned == 0 then return nil, 'No cloud account is registered to this character' end
    return nil, 'Choose an account ID: ' .. table.concat(ids, ', ')
end

local function recoverCloud(_, target, payload, shop)
    if type(payload.accountId) ~= 'string' or #payload.accountId > MAX_ACCOUNT_ID then return H.fail('Invalid account') end
    local citizenId = H.citizenId(target)
    local accountId, problem = resolveRecoveryAccount(payload, citizenId)
    if not accountId then return H.fail(problem) end
    payload.accountId = accountId
    return H.accountLock(accountId, function()
        local account = Cloud.findOwned(accountId, citizenId)
        if not account then return H.fail('Account does not belong to this character') end
        local fee = shop.recoveryFee
        if fee > 0 and not exports.kora_core:removeMoney(target, 'bank', fee, 'phone account recovery', true) then
            return H.fail('Insufficient bank funds')
        end
        local code = exports[GetCurrentResourceName()]:randomHex(32)
        for _, handsetId in ipairs(Handsets.idsForAccount(account.id)) do
            H.revokeHandset(handsetId, 'cloud_account_recovered', target)
        end
        if not Cloud.rotateRecovery(account.id, code) then
            if fee > 0 then exports.kora_core:addMoney(target, 'bank', fee, 'phone recovery refund', true) end
            return H.fail('Recovery failed; your fee was refunded')
        end
        return PhoneResult({ accountId = account.id, recoveryCode = code })
    end)
end

local function replaceSim(_, target, payload, shop)
    local number = PhoneValidation.phoneNumber(payload.number)
    if not number then return H.fail('Enter your existing phone number') end
    local citizenId = H.citizenId(target)
    local old = Sims.findOwnedSubscription(number, citizenId)
    if not old then return H.fail('That subscription does not belong to this character') end
    local device, err = H.require(target)
    if not device then return err end
    -- Install the replacement into the selected handset. An unrelated SIM must be removed first.
    if device.sim and device.sim.id ~= old.id then
        return H.fail('Remove the other SIM before replacing this subscription')
    end
    local item = H.itemFor(target, device.handsetId)
    if not item then return H.fail('Handset is no longer held') end
    local newId = H.randomId()
    -- Prepare the new SIM as blocked. Metadata commits before activation, so crashes fail closed.
    Sims.prepareReplacement(newId, H.randomId(), old.id, device.handsetId, number, citizenId)
    local ok, reason = H.inventoryTx(target, {
        op = 'replaceSim',
        handsetSlot = item.slot,
        handsetId = device.handsetId,
        simId = item.info.phoneSimId or '',
        newSimId = newId,
        fee = shop.replacementFee,
    })
    if not ok then
        Sims.cancelReplacement(newId)
        return H.fail(tostring(reason))
    end
    if old.handset_id then H.revokeHandset(old.handset_id, 'sim_replaced') end
    if not H.reconcileReplacement(newId, device.handsetId) then
        return H.fail('Replacement is pending; reopen this handset to retry activation without another fee')
    end
    H.selected[target] = device.handsetId
    H.current(target, false)
    return PhoneResult({ number = number, replaced = true })
end

local function resell(_, target, payload, shop)
    local slot = tonumber(payload.slot)
    local sellable = slot and slot % 1 == 0 and exports[GetCurrentResourceName()]:CanResellHandset(target, slot)
    if not sellable then return H.fail('Factory reset and remove the SIM before resale') end
    local item = exports.kora_core:getItemBySlot(target, slot)
    local price = shop.prices[item.name] or shop.prices.phone_standard
    if not price then return H.fail('This shop does not buy that handset') end
    local ok, reason = H.inventoryTx(target, {
        op = 'resell',
        handsetSlot = slot,
        handsetId = item.info.handsetId,
        payout = math.floor(price * (shop.resalePercent or DEFAULT_RESALE_PERCENT) / 100),
        shopId = shopStockId(payload.shop),
        salePrice = price,
    })
    if not ok then return H.fail(tostring(reason)) end
    return PhoneResult({ sold = true })
end

local services = { buy = buy, recoverCloud = recoverCloud, replaceSim = replaceSim, resell = resell }

---Asks the customer to approve a service staff want to run for them.
local function requestConsent(actor, target, payload, shop)
    local requestId = H.randomId()
    H.serviceRequests[requestId] = {
        actor = actor,
        actorCharacter = H.citizenId(actor),
        target = target,
        payload = payload,
        expires = os.time() + REQUEST_TTL_SECONDS,
        character = H.citizenId(target),
    }
    SetTimeout(REQUEST_CLEANUP_MS, function() H.serviceRequests[requestId] = nil end)
    TriggerClientEvent('kora_phone:client:serviceRequest', target, {
        id = requestId, label = shop.label, operation = payload.op,
    })
    return PhoneResult({ pending = true })
end

---Runs a shop service for `actor`. When staff act for another player, the customer must consent first.
---@param actor integer
---@param payload table
---@param approved? boolean The customer already consented.
---@return table
function H.commerce(actor, payload, approved)
    local shop = H.shopFor(actor, payload.shop, true)
    if not shop then return H.fail('Visit an authorised shop counter') end
    local target = tonumber(payload.target) or actor
    local atCounter = target % 1 == 0 and H.shopFor(target, payload.shop, false) ~= nil
    if not atCounter or (target ~= actor and not shop.job) then return H.fail('Customer must be at this counter') end
    if target ~= actor and not approved then return requestConsent(actor, target, payload, shop) end
    local service = services[payload.op]
    if not service then return H.fail('Unknown shop service') end
    return service(actor, target, payload, shop)
end

---The customer's answer to a staff-initiated service request.
---@param src integer
---@param payload { id: string, accept: boolean }
---@return table
function H.consent(src, payload)
    local request = type(payload.id) == 'string' and H.serviceRequests[payload.id]
    if not request or request.target ~= src then return H.fail('Service request expired') end
    H.serviceRequests[payload.id] = nil
    if payload.accept ~= true then return PhoneResult({ declined = true }) end
    local stale = request.expires < os.time()
        or request.character ~= H.citizenId(src)
        or request.actorCharacter ~= H.citizenId(request.actor)
    if stale then return H.fail('Service request expired') end
    local result = H.commerce(request.actor, request.payload, true)
    TriggerClientEvent('kora_phone:client:serviceResult', src, result)
    return result
end

for name in pairs(services) do
    H.operations[name] = {
        needsDevice = false,
        run = function(src, payload) return H.commerce(src, payload) end,
    }
end

H.operations.consent = {
    needsDevice = false,
    run = function(src, payload) return H.consent(src, payload) end,
}
