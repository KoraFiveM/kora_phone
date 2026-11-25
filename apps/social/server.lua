-- Chats, groups and blocks run the same validated services as every other messaging screen, for the caller's own device.
-- The UI names conversations, numbers and one of its own gallery items; it never names a sender, device or account.
local app = Phone.app('social')
local Services = KoraPhone.Services

local function payloadOf(payload) return type(payload) == 'table' and payload or {} end

app.callback('config', function(source)
    local device = KoraPhone.Handsets.current(source, false)
    local video = KoraPhone.Storage.supportsVideo()
    return {
        number = device and device.phoneNumber,
        flash = video and { maxSeconds = KoraPhone.Storage.Config().MaxVideoSeconds, maxBytes = KoraPhone.Storage.Config().MaxVideoBytes } or false,
    }
end, { rate = 'read' })

app.callback('conversations', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Messaging.listConversations(source, { limit = 50, cursor = payload.before, cursorId = payload.cursorId })).items
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

app.callback('createGroup', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Messaging.createGroup(source, { name = payload.name, numbers = payload.numbers }))
end, { rate = 'mutation' })

app.callback('addMember', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Messaging.addMember(source, { conversationId = payload.id, number = payload.number }))
end, { rate = 'mutation' })

app.callback('leaveGroup', function(source, payload)
    return Phone.unwrap(Services.Messaging.leaveGroup(source, { conversationId = payloadOf(payload).id }))
end, { rate = 'mutation' })

app.callback('block', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Blocking.set(source, { number = payload.number, blocked = payload.blocked == true }))
end, { rate = 'mutation' })

app.callback('photos', function(source)
    local items = Phone.unwrap(Services.Media.list(source, { limit = 50 })).items
    local photos = {}
    for _, item in ipairs(items) do
        if not tostring(item.mimeType or ''):find('^video') then photos[#photos + 1] = { id = item.id, url = item.publicUrl } end
    end
    return photos
end, { rate = 'read' })
