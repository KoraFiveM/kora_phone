-- Handsets own local profiles; SIMs route numbers; cloud snapshots never grant number ownership.
-- This file holds the shared state and the helpers every other handsets/* file builds on.

---@class KoraPhoneHandsets
---@field selected table<integer, string> Handset id each player has selected.
---@field wifi table<integer, string> Wi-Fi hotspot id each player joined.
---@field busy table<integer, boolean> Players with a handset operation in flight.
---@field resolving table<integer, boolean> Players whose handset is being resolved right now.
---@field accountLocks table<string, boolean> Cloud accounts with an operation in flight.
---@field purchaseCustomers table<integer, table> One-shot grants for a shop purchase made for a customer.
---@field serviceRequests table<string, table> Pending shop-service requests awaiting customer consent.
---@field preferredSlot table<integer, integer> Slot to provision while selecting a handset.
---@field operations table<string, HandsetOperation> Operations reachable through the handsetAction callback.
---@field ready boolean
KoraPhone.Handsets = {
    selected = {},
    wifi = {},
    busy = {},
    resolving = {},
    accountLocks = {},
    purchaseCustomers = {},
    serviceRequests = {},
    preferredSlot = {},
    operations = {},
    ready = false,
}
local H = KoraPhone.Handsets

---@class HandsetOperation
---@field run fun(src: integer, payload: table, device?: table): table
---@field needsDevice? boolean Defaults to true: the dispatcher resolves the held handset first.
---@field allowLocked? boolean Usable while the phone is PIN locked.

local PLACEHOLDER_ID_LENGTH = 20

---@return string
function H.randomId()
    return exports[GetCurrentResourceName()]:randomHex(16)
end

---@param message string
function H.fail(message)
    return PhoneError(PhoneConstants.Errors.FORBIDDEN, message)
end

---@param src integer
---@return string|nil
function H.citizenId(src)
    return KoraPhone.GetCitizenId(src)
end

---Every inventory stack of one item name, read through kora_core.
---@param src integer
---@param name string
---@return table[]
function H.itemsNamed(src, name)
    return exports.kora_core:getItemsByName(src, name) or {}
end

---Every handset item the player holds, in slot order.
---@param src integer
---@return table[]
function H.heldHandsets(src)
    local held = {}
    for name in pairs(Config.Handsets) do
        for _, item in ipairs(H.itemsNamed(src, name)) do held[#held + 1] = item end
    end
    table.sort(held, function(a, b) return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0) end)
    return held
end

-- A handset without a SIM carries a placeholder number derived from its id.
---@param handsetId string
---@return string
function H.placeholderNumber(handsetId)
    return '@' .. handsetId:sub(1, PLACEHOLDER_ID_LENGTH)
end

---The inventory item that carries a handset id, when the player still holds it.
---@param src integer
---@param handsetId string
---@return table|nil
function H.itemFor(src, handsetId)
    for _, item in ipairs(H.heldHandsets(src)) do
        if item.info and item.info.handsetId == handsetId then return item end
    end
end

---The one call site for kora_inventory's atomic phone item gateway (bind/insert/remove/replace/resell).
---@param src integer
---@param request table
---@return boolean ok
---@return any reason
function H.inventoryTx(src, request)
    return exports.kora_inventory:PhoneItemTransaction(src, request)
end

---Ends a player's phone session: selection, Wi-Fi, voice and any live call.
---@param src integer
---@param reason? string
function H.revoke(src, reason)
    local session = KoraPhone.Sessions.bySource[src]
    local deviceId = session and session.deviceId
    local calling = KoraPhone.Services.Calling
    local callId = deviceId and calling.callByDevice and calling.callByDevice[deviceId]
    KoraPhone.Sessions.close(src)
    H.selected[src] = nil
    H.wifi[src] = nil
    if KoraPhone.Integrations and KoraPhone.Integrations.Voice then KoraPhone.Integrations.Voice.leave(src) end
    TriggerClientEvent('kora_phone:client:sessionRevoked', src)
    -- Item observers run inside inventory commits; retire SQL call state outside that lock.
    if callId then
        SetTimeout(0, function()
            calling.disconnectDevice(deviceId, reason or 'handset_changed', callId)
        end)
    end
end

---True while the player still holds the exact handset the device was resolved for.
---@param src integer
---@param device table
---@return boolean
function H.stillHeld(src, device)
    return device ~= nil
        and H.citizenId(src) == device.holderCitizenId
        and H.selected[src] == device.handsetId
        and H.itemFor(src, device.handsetId) ~= nil
end

local function hasPin(device)
    return device.hasPin == 1 or device.hasPin == true
end
H.hasPin = hasPin

---Resolves the held handset for a request, refusing when the player is down or the phone is locked.
---@param src integer
---@param allowLocked? boolean
---@return table|nil device
---@return table|nil error
function H.require(src, allowLocked)
    local player = KoraPhone.GetPlayer(src)
    local metadata = player and player.metadata or {}
    if metadata.isdead or metadata.inlaststand then
        if H.selected[src] then H.revoke(src, 'player_dead') end
        return nil, H.fail('You cannot use a phone right now')
    end
    local device = H.current(src, true)
    if not device then return nil, H.fail('Select a valid handset in your inventory') end
    local session = KoraPhone.Sessions.ensure(src, device)
    if not allowLocked and hasPin(device) and not session.unlocked then
        return nil, H.fail('Phone is locked')
    end
    return device
end

---Serialises handset operations per player.
---@param src integer
---@param handler fun(src: integer, payload: table): table
---@param payload table
---@return table
function H.locked(src, handler, payload)
    if H.busy[src] then return H.fail('Another phone operation is in progress') end
    H.busy[src] = true
    local ok, result = xpcall(function() return handler(src, payload) end, debug.traceback)
    H.busy[src] = nil
    if not ok then
        Kora.logging.event('phone.handset_operation_failed', src, { level = 'error', message = 'Handset operation failed', error = tostring(result) })
        return H.fail('Phone operation failed')
    end
    return result
end

---Marks a handset as used again. Called after any successful mutation.
---@param handsetId string
function H.clearReset(handsetId)
    KoraPhone.Repositories.Handsets.clearReset(handsetId)
end
