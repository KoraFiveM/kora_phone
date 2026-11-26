-- The contact book of the held handset. The services check the device, validate every field, and refuse a photo that
-- is not in the caller's own gallery.
local app = Phone.app('contacts')
local Services = KoraPhone.Services

local function payloadOf(payload) return type(payload) == 'table' and payload or {} end

app.callback('list', function(source)
    return Phone.unwrap(Services.Contacts.list(source)).items
end)

app.callback('save', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Contacts.save(source, {
        id = payload.id, displayName = payload.name, phoneNumber = payload.number,
        isFavorite = payload.favorite == true, avatarMediaId = payload.avatarMediaId,
    }))
end, { rate = 'mutation' })

app.callback('delete', function(source, payload)
    return Phone.unwrap(Services.Contacts.delete(source, { id = payloadOf(payload).id }))
end, { rate = 'mutation' })

-- The caller's own photos, for choosing a contact photo.
app.callback('photos', function(source)
    local items = Phone.unwrap(Services.Media.list(source, { limit = 50 })).items
    local photos = {}
    for _, item in ipairs(items) do
        if not tostring(item.mimeType or ''):find('^video') then photos[#photos + 1] = { id = item.id, url = item.publicUrl } end
    end
    return photos
end)
