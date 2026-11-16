-- Place-bound services: Wi-Fi hotspots and shop counters. Distances are checked on the server.
local H = KoraPhone.Handsets

local DEFAULT_SHOP_DISTANCE = 3

---True when the player stands within `radius` of `point` in the given routing bucket.
---@param src integer
---@param point { x: number, y: number, z: number }
---@param radius number
---@param bucket? integer
---@return boolean
function H.near(src, point, radius, bucket)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetPlayerRoutingBucket(src) ~= (bucket or 0) then return false end
    local pos = GetEntityCoords(ped)
    local dx, dy, dz = pos.x - point.x, pos.y - point.y, pos.z - point.z
    return dx * dx + dy * dy + dz * dz <= radius * radius
end

---A configured shop, when the player is at its counter. With `employee`, a business shop also needs
---the player on duty in its job at the required grade.
---@param src integer
---@param shopId any
---@param employee? boolean
---@return table|nil shop
function H.shopFor(src, shopId, employee)
    local shop = type(shopId) == 'string' and Config.PhoneServices.shops[shopId]
    if not shop or not H.citizenId(src) then return nil end
    if not H.near(src, shop.coords, shop.distance or DEFAULT_SHOP_DISTANCE, shop.bucket) then return nil end
    if employee and shop.job and not KoraPhone.Integrations.Jobs.onDutyAt(src, shop.job, shop.grade) then return nil end
    return shop
end

---Shops whose counter the player is standing at, in the shape the UI lists them.
---@param src integer
---@return table[]
function H.shopsNearby(src)
    local shops = {}
    for id, shop in pairs(Config.PhoneServices.shops) do
        if H.shopFor(src, id, false) then
            shops[#shops + 1] = { id = id, label = shop.label, prices = shop.prices, business = shop.job ~= nil }
        end
    end
    return shops
end

---Hotspots within range of the player.
---@param src integer
---@return table[]
function H.hotspotsNearby(src)
    local hotspots = {}
    for id, wifi in pairs(Config.PhoneServices.wifi) do
        if H.near(src, wifi.coords, wifi.radius, wifi.bucket) then
            hotspots[#hotspots + 1] = { id = id, label = wifi.label, private = wifi.passwordConvar ~= nil }
        end
    end
    return hotspots
end

-- Customer grants are consumed by the one trusted BuyItem open, never retained in an inventory session.
---@param src integer
---@param shopId string
---@return boolean
function H.shopStockAccess(src, shopId)
    if H.shopFor(src, shopId, true) then return true end
    local grant = H.purchaseCustomers[src]
    H.purchaseCustomers[src] = nil
    if not grant then return false end
    return grant.shop == shopId
        and grant.character == H.citizenId(src)
        and grant.actorCharacter == H.citizenId(grant.actor)
        and H.shopFor(grant.actor, shopId, true) ~= nil
        and H.shopFor(src, shopId, false) ~= nil
end

---A handset is online through its SIM, or through a hotspot it joined and is still near.
---@param src integer
---@param device table
---@return boolean
function H.online(src, device)
    if device.cellular then return true end
    local hotspot = H.wifi[src] and Config.PhoneServices.wifi[H.wifi[src]]
    return hotspot and H.near(src, hotspot.coords, hotspot.radius, hotspot.bucket) or false
end

H.operations.wifi = {
    run = function(src, payload)
        local hotspot = type(payload.id) == 'string' and Config.PhoneServices.wifi[payload.id]
        if not hotspot or not H.near(src, hotspot.coords, hotspot.radius, hotspot.bucket) then
            return H.fail('Wi-Fi is out of range')
        end
        if hotspot.passwordConvar then
            local expected = GetConvar(hotspot.passwordConvar, '')
            if expected == '' or payload.password ~= expected then return H.fail('Incorrect Wi-Fi password') end
        end
        H.wifi[src] = payload.id
        return PhoneResult(true)
    end,
}
