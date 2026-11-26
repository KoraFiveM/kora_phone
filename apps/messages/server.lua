-- Conversations and messages of the held handset. The messaging service checks the device, membership of the
-- conversation, blocks and idempotency; the UI only names conversations, numbers and a gallery item of its own.
local app = Phone.app('messages')
local Services = KoraPhone.Services

local function payloadOf(payload) return type(payload) == 'table' and payload or {} end

app.callback('conversations', function(source, payload)
    payload = payloadOf(payload)
    local result = Phone.unwrap(Services.Messaging.listConversations(source, { limit = 50, cursor = payload.before, cursorId = payload.cursorId }))
    local device = KoraPhone.Handsets.current(source, false)
    return { items = result.items, number = device and device.phoneNumber }
end, { rate = 'read' })

app.callback('start', function(source, payload)
    return Phone.unwrap(Services.Messaging.startDirect(source, { to = payloadOf(payload).number }))
end, { rate = 'mutation' })

app.callback('thread', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Messaging.list(source, { conversationId = payload.id, limit = 50, cursor = payload.before })).items
end, { rate = 'read' })

app.callback('send', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Messaging.send(source, {
        conversationId = payload.conversationId, body = payload.body, mediaId = payload.mediaId, clientRequestId = payload.clientRequestId,
    }))
end, { rate = 'sendMessage' })

app.callback('read', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Messaging.markRead(source, { conversationId = payload.id, messageId = payload.messageId }))
end, { rate = 'mutation' })

app.callback('delete', function(source, payload)
    return Phone.unwrap(Services.Messaging.deleteForSelf(source, { messageId = payloadOf(payload).messageId }))
end, { rate = 'mutation' })

-- The caller's own photos, for attaching one to a message.
app.callback('photos', function(source)
    local items = Phone.unwrap(Services.Media.list(source, { limit = 50 })).items
    local photos = {}
    for _, item in ipairs(items) do
        if not tostring(item.mimeType or ''):find('^video') then photos[#photos + 1] = { id = item.id, url = item.publicUrl } end
    end
    return photos
end, { rate = 'read' })
