-- Handset lifecycle: item registration at start, shop stock, subscriptions, exports, and the hooks that
-- make the existing services work from the held handset instead of a character-owned device.
local H = KoraPhone.Handsets

local MODEL_NAMES = { standard = 'Orchard One', flip = 'Circuit Flip', fold = 'Atlas Fold' }
local SHOP_STOCK_PER_ITEM = 100
local SHOP_SLOTS = 64

-- Existing services resolve devices through the held handset.
KoraPhone.Permissions.requireDevice = H.require

KoraPhone.Services.Phone.getOrCreate = function(citizenId)
    for _, src in ipairs(GetPlayers()) do
        local player = tonumber(src)
        if H.citizenId(player) == citizenId then return H.current(player, true) end
    end
end

local function videoIceServers(src)
    local servers = {}
    for _, ice in ipairs(Config.Calls.Video.IceServers or {}) do servers[#servers + 1] = ice end
    local turn = exports[GetCurrentResourceName()]:turnCredentials(src)
    local urls = GetConvar('kora_phone_turn_urls', '')
    if turn and urls ~= '' then
        servers[#servers + 1] = { urls = urls, username = turn.username, credential = turn.credential }
    end
    return servers
end

local baseBootstrap = KoraPhone.Services.Phone.bootstrap
KoraPhone.Services.Phone.bootstrap = function(src)
    local device = H.current(src, true)
    if not device then return H.fail('No handset available') end
    local result = baseBootstrap(src)
    if not result.ok then return result end
    local info = result.data.device
    info.model = device.model
    info.handsetId = device.handsetId
    if not device.cellular then info.phoneNumber = '' end
    info.settings.phoneStyle = device.model
    info.settings.name = info.settings.name or MODEL_NAMES[device.model]
    if result.data.features and result.data.features.video then
        result.data.features.video.iceServers = videoIceServers(src)
    end
    return result
end

local function registerItems()
    for name, model in pairs(Config.Handsets) do
        exports.kora_core:registerShared('items', name, {
            name = name, label = MODEL_NAMES[model], weight = 250, type = 'item', image = 'phone.png',
            unique = true, useable = true, shouldClose = true, description = 'Personal handset',
        })
        exports.kora_core:createUseable(name, function(src, item)
            H.locked(src, H.action, { op = 'select', slot = item.slot })
            TriggerClientEvent('kora_phone:client:useHandset', src)
        end)
    end
    exports.kora_core:registerShared('items', Config.SimItem, {
        name = Config.SimItem, label = 'Mobile SIM', weight = 1, type = 'item', image = 'phone.png',
        unique = true, useable = false, description = 'Removable mobile subscription',
    })
end

local function registerShops()
    for id, shop in pairs(Config.PhoneServices.shops) do
        local items = {}
        for name, price in pairs(shop.prices) do
            items[#items + 1] = {
                name = name, price = price, amount = SHOP_STOCK_PER_ITEM, info = {}, type = 'item', slot = #items + 1,
            }
        end
        exports.kora_inventory:RegisterShop('kora_phone:' .. id, {
            label = shop.label, items = items, slots = SHOP_SLOTS, coords = shop.coords, distance = shop.distance,
            currency = 'bank', access = function(src) return H.shopStockAccess(src, id) end,
        })
    end
end

local function subscribe()
    H.subscription = exports.kora_core:onChange({ 'items' }, function(src)
        local handsetId = H.selected[src]
        if handsetId and not H.itemFor(src, handsetId) then H.revoke(src, 'possession_lost') end
    end)
    H.deathSubscription = exports.kora_core:onChange({ 'metadata' }, function(src)
        local player = KoraPhone.GetPlayer(src)
        local metadata = player and player.metadata or {}
        if H.selected[src] and (metadata.isdead or metadata.inlaststand) then H.revoke(src, 'player_dead') end
    end)
end

---Registers items, shops and subscriptions. Errors when the inventory gateway companion is missing.
function H.start()
    local gateway = pcall(function() exports.kora_inventory:PhoneItemTransaction(0, { op = 'probe' }) end)
    if not gateway then error('Install the kora_inventory PhoneItemTransaction companion before starting kora_phone') end
    registerItems()
    registerShops()
    subscribe()
    H.ready = true
    TriggerClientEvent('kora_phone:client:ready', -1)
end

AddEventHandler('playerDropped', function()
    H.selected[source] = nil
    H.wifi[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if H.subscription then exports.kora_core:offChange(H.subscription) end
    if H.deathSubscription then exports.kora_core:offChange(H.deathSubscription) end
end)

---A handset can be resold once it is factory reset, SIM-free, unlinked from any account and empty.
exports('CanResellHandset', function(src, slot)
    local item = exports.kora_core:getItemBySlot(src, slot)
    local handsetId = item and item.info and item.info.handsetId
    local device = handsetId and KoraPhone.Repositories.Handsets.findView(handsetId)
    if not device then return false end
    local isReset = device.isReset == 1 or device.isReset == true
    if not isReset or item.info.phoneSimId or device.accountId or device.pinKdf or device.faceCitizenId then
        return false
    end
    return KoraPhone.Repositories.Handsets.contentCount(device.id) == 0
end)
