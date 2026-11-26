-- Listings, status changes, reports and seller messages run the validated marketplace, moderation and messaging
-- services for the caller's own source. Each callback charges the same community bucket its old route did.
local app = Phone.app('classifieds')
local Services = KoraPhone.Services

local function payloadOf(payload) return type(payload) == 'table' and payload or {} end

app.callback('list', function(source, payload)
    payload = payloadOf(payload)
    local result = Phone.unwrap(Services.Marketplace.getListings(source, { limit = 30, cursor = payload.before }))
    local device = KoraPhone.Handsets.current(source, false)
    return { items = result.items, number = device and device.phoneNumber, moderator = Services.Moderation.isModerator(source) == true }
end, { rate = 'community.read' })

app.callback('create', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Marketplace.createListing(source, {
        title = payload.title, description = payload.description, category = 'other', price = payload.price,
        clientRequestId = payload.clientRequestId,
    }))
end, { rate = 'community.listing' })

app.callback('remove', function(source, payload)
    return Phone.unwrap(Services.Marketplace.setStatus(source, { id = payloadOf(payload).id }, 'removed'))
end, { rate = 'community.listing' })

app.callback('sold', function(source, payload)
    return Phone.unwrap(Services.Marketplace.setStatus(source, { id = payloadOf(payload).id }, 'sold'))
end, { rate = 'community.listing' })

app.callback('contact', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Marketplace.contactSeller(source, {
        id = payload.id, message = payload.message, clientRequestId = payload.clientRequestId,
    }))
end, { rate = 'community.contact' })

app.callback('report', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Moderation.report(source, {
        targetType = 'listing', targetId = payload.id, reason = payload.reason, details = payload.details,
    }))
end, { rate = 'community.report' })
