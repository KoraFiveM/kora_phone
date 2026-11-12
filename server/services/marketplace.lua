KoraPhone.Services = KoraPhone.Services or {}
local Market = {}
KoraPhone.Services.Marketplace = Market

local categories = { 'vehicle', 'property', 'electronics', 'services', 'other' }
local function invalid(message) return PhoneError(PhoneConstants.Errors.INVALID_INPUT, message) end

local function publicListing(listing, viewerDeviceId)
    if not listing then return nil end
    return {
        id = listing.id, title = listing.title, description = listing.description,
        category = listing.category, price = listing.price, status = listing.status,
        createdAt = listing.createdAt, updatedAt = listing.updatedAt,
        sellerHandle = listing.sellerHandle, sellerName = listing.sellerName,
        isOwner = listing.ownerDeviceId == viewerDeviceId,
    }
end

local function validatedListing(payload, needsRequestId)
    if type(payload) ~= 'table' then return nil, 'payload must be an object' end
    local title, err = PhoneValidation.string(payload.title, 'title', 1, 80)
    if not title then return nil, err end
    local description; description, err = PhoneValidation.string(payload.description or '', 'description', 0, 2000, true)
    if not description then return nil, err end
    local category; category, err = PhoneValidation.enum(payload.category or 'other', 'category', categories)
    if not category then return nil, err end
    local price; price, err = PhoneValidation.integer(payload.price, 'price', 0, 1000000000)
    if not price then return nil, err end
    local clientRequestId
    if needsRequestId then
        clientRequestId, err = PhoneValidation.string(payload.clientRequestId, 'clientRequestId', 8, 64)
        if not clientRequestId then return nil, err end
    end
    return { title = title, description = description, category = category, price = price, clientRequestId = clientRequestId }
end

function Market.getListings(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local pagination, validationError = PhoneValidation.page(payload)
    if not pagination then return invalid(validationError) end
    pagination.limit = math.min(pagination.limit, 50)
    local category
    if type(payload) == 'table' and payload.category ~= nil then
        category, validationError = PhoneValidation.enum(payload.category, 'category', categories)
        if not category then return invalid(validationError) end
    end
    local rows = KoraPhone.Repositories.Marketplace.list(device.id, pagination.limit, pagination.cursor, category)
    local items = {}
    for i, row in ipairs(rows) do items[i] = publicListing(row, device.id) end
    return PhoneResult({ items = items, nextCursor = #rows == pagination.limit and rows[#rows].id or nil })
end

function Market.getListing(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    local listing = KoraPhone.Repositories.Marketplace.get(id)
    if not listing or (listing.status ~= 'active' and listing.ownerDeviceId ~= device.id)
        or KoraPhone.Repositories.Blocks.isEitherBlocked(device.id, listing.ownerDeviceId) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Listing was not found')
    end
    return PhoneResult(publicListing(listing, device.id))
end

function Market.createListing(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local listing, validationError = validatedListing(payload, true)
    if not listing then return invalid(validationError) end
    local saved, replayed = KoraPhone.Repositories.Marketplace.create(device.id, listing)
    if not saved then return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to create listing') end
    local result = publicListing(saved, device.id); result.replayed = replayed
    return PhoneResult(result)
end

function Market.updateListing(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    local listing; listing, validationError = validatedListing(payload, false)
    if not listing then return invalid(validationError) end
    local saved = KoraPhone.Repositories.Marketplace.update(device.id, id, listing)
    if not saved then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Listing was not found') end
    return PhoneResult(publicListing(saved, device.id))
end

-- Marking sold is owner-only; removing a listing can also be done by a moderator straight
-- from the feed (the same removal a report's "remove content" action performs).
function Market.setStatus(source, payload, status)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    local changed = KoraPhone.Repositories.Marketplace.setStatus(device.id, id, status)
    if not changed and status == 'removed' and KoraPhone.Services.Moderation.isModerator(source) then
        changed = KoraPhone.Repositories.Marketplace.hideByModerator(id)
    end
    if not changed then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Listing was not found') end
    return PhoneResult({ id = id, status = status })
end

function Market.contactSeller(source, payload)
    local buyer, err = KoraPhone.Permissions.requireDevice(source)
    if not buyer then return err end
    local id, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not id then return invalid(validationError) end
    local listing = KoraPhone.Repositories.Marketplace.get(id)
    if not listing or listing.status ~= 'active'
        or KoraPhone.Repositories.Blocks.isEitherBlocked(buyer.id, listing and listing.ownerDeviceId or 0) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Listing was not found')
    end
    if listing.ownerDeviceId == buyer.id then return invalid('Cannot contact yourself') end
    local body; body, validationError = PhoneValidation.string(payload.message, 'message', 1, 1000)
    if not body then return invalid(validationError) end
    local request; request, validationError = PhoneValidation.string(payload.clientRequestId, 'clientRequestId', 8, 64)
    if not request then return invalid(validationError) end
    local phoneNumber = KoraPhone.Repositories.Marketplace.ownerPhone(listing.ownerDeviceId)
    if not phoneNumber then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Seller is unavailable') end
    -- Reuse the messaging service so membership, persistence and idempotency
    -- follow exactly the same server-authoritative path as normal messages.
    return KoraPhone.Services.Messaging.send(source, {
        to = phoneNumber,
        body = ('Marketplace: %s\n%s'):format(listing.title, body),
        clientRequestId = request,
    })
end