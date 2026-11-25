-- The photos and clips of the held handset. The media service checks the device and that every item is the caller's own;
-- the UI only ever names an item id.
local app = Phone.app('gallery')

app.callback('list', function(source, payload)
    payload = type(payload) == 'table' and payload or {}
    local result = Phone.unwrap(KoraPhone.Services.Media.list(source, { limit = 60, cursor = payload.before }))
    local items = {}
    for _, item in ipairs(result.items) do
        items[#items + 1] = { id = item.id, url = item.publicUrl, kind = tostring(item.mimeType or ''):find('^video') and 'video' or 'photo', createdAt = item.createdAt }
    end
    return { items = items, next = result.nextCursor }
end, { rate = 'read' })

-- Media.delete answers through a callback (it may remove the stored file first): wait for that answer.
app.callback('delete', function(source, payload)
    payload = type(payload) == 'table' and payload or {}
    local answer = promise.new()
    KoraPhone.Services.Media.delete(source, { id = payload.id }, function(result) answer:resolve(result) end)
    return Phone.unwrap(Citizen.Await(answer))
end, { rate = 'mutation' })
