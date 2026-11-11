KoraPhone.Repositories = KoraPhone.Repositories or {}
local Market = {}
KoraPhone.Repositories.Marketplace = Market

local selectListing = [[SELECT l.id, l.owner_device_id AS ownerDeviceId, l.title, l.description,
    l.category, l.price, l.status, UNIX_TIMESTAMP(l.created_at) AS createdAt,
    UNIX_TIMESTAMP(l.updated_at) AS updatedAt, p.handle AS sellerHandle, p.display_name AS sellerName
    FROM phone_market_listings l LEFT JOIN phone_social_profiles p ON p.device_id = l.owner_device_id]]

function Market.get(id)
    return MySQL.single.await(selectListing .. ' WHERE l.id = ? LIMIT 1', { id })
end

function Market.list(viewerDeviceId, limit, cursor, category)
    local sql = selectListing .. [[ WHERE l.status = 'active'
        AND NOT EXISTS(SELECT 1 FROM phone_blocks b WHERE
          (b.blocker_device_id = ? AND b.blocked_device_id = l.owner_device_id) OR
          (b.blocker_device_id = l.owner_device_id AND b.blocked_device_id = ?))]]
    local params = { viewerDeviceId, viewerDeviceId }
    if category then sql = sql .. ' AND l.category = ?'; params[#params + 1] = category end
    if cursor then sql = sql .. ' AND l.id < ?'; params[#params + 1] = cursor end
    sql = sql .. ' ORDER BY l.id DESC LIMIT ?'; params[#params + 1] = limit
    return MySQL.query.await(sql, params) or {}
end

function Market.create(ownerDeviceId, listing)
    local ok, id = pcall(MySQL.insert.await, [[INSERT INTO phone_market_listings
        (owner_device_id, title, description, category, price, client_request_id)
        VALUES (?, ?, ?, ?, ?, ?)]], { ownerDeviceId, listing.title, listing.description,
        listing.category, listing.price, listing.clientRequestId })
    if ok then return Market.get(id), false end
    local existing = MySQL.single.await(selectListing ..
        ' WHERE l.owner_device_id = ? AND l.client_request_id = ? LIMIT 1', { ownerDeviceId, listing.clientRequestId })
    return existing, existing ~= nil
end

function Market.update(ownerDeviceId, listingId, listing)
    local changed = MySQL.update.await([[UPDATE phone_market_listings SET title = ?, description = ?,
        category = ?, price = ? WHERE id = ? AND owner_device_id = ? AND status = 'active']],
        { listing.title, listing.description, listing.category, listing.price, listingId, ownerDeviceId })
    if changed == 0 then
        local owned = MySQL.scalar.await([[SELECT id FROM phone_market_listings
            WHERE id = ? AND owner_device_id = ? AND status = 'active']], { listingId, ownerDeviceId })
        if not owned then return nil end
    end
    return Market.get(listingId)
end

function Market.setStatus(ownerDeviceId, listingId, status)
    return MySQL.update.await([[UPDATE phone_market_listings SET status = ?
        WHERE id = ? AND owner_device_id = ? AND status = 'active']], { status, listingId, ownerDeviceId }) > 0
end

function Market.ownerPhone(ownerDeviceId)
    return MySQL.scalar.await('SELECT phone_number FROM phone_devices WHERE id = ? AND is_active = 1', { ownerDeviceId })
end

function Market.hideByModerator(listingId)
    return MySQL.update.await([[UPDATE phone_market_listings SET status = 'removed'
        WHERE id = ? AND status <> 'removed']], { listingId }) > 0
end