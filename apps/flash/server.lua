-- The public feed. Every callback runs the same validated service the old routes did, for the caller's own profile and device, and
-- charges the same community bucket. The UI never names an author or a device.
local app = Phone.app('flash')
local Services = KoraPhone.Services
local MAX_BODY = 1900

local function payloadOf(payload) return type(payload) == 'table' and payload or {} end

app.callback('config', function(source)
    local device = KoraPhone.Handsets.current(source, false)
    local player = KoraPhone.GetPlayer(source)
    local video = KoraPhone.Storage.supportsVideo()
    return {
        number = device and device.phoneNumber,
        moderator = Services.Moderation.isModerator(source) == true,
        media = KoraPhone.Storage.provider() ~= 'disabled',
        installedPulse = (function()
            local pulse, handset = KoraPhone.SDK.Registry.get('social'), KoraPhone.Permissions.requireDevice(source)
            return pulse ~= nil and handset ~= nil and KoraPhone.SDK.Install.isInstalled(handset, pulse)
        end)(),
        character = player and player.charinfo and ((player.charinfo.firstname or '') .. ' ' .. (player.charinfo.lastname or '')) or nil,
        flash = video and { maxSeconds = KoraPhone.Storage.Config().MaxVideoSeconds, maxBytes = KoraPhone.Storage.Config().MaxVideoBytes } or false,
    }
end, { rate = 'read' })

app.callback('feed', function(source, payload)
    return Phone.unwrap(Services.Social.getFeed(source, { limit = 30, cursor = payloadOf(payload).before })).items
end, { rate = 'community.read' })

app.callback('createProfile', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Social.createAccount(source, { handle = payload.handle, displayName = payload.displayName }))
end, { rate = 'community.profile' })

app.callback('post', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Social.createPost(source, { body = payload.body, mediaId = payload.mediaId, clientRequestId = payload.clientRequestId }))
end, { rate = 'community.post' })

app.callback('remove', function(source, payload)
    return Phone.unwrap(Services.Social.deletePost(source, { id = payloadOf(payload).id }))
end, { rate = 'community.post' })

app.callback('like', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Social.toggleLike(source, { postId = payload.id, liked = payload.liked == true }))
end, { rate = 'community.reaction' })

app.callback('comments', function(source, payload)
    return Phone.unwrap(Services.Social.getComments(source, { postId = payloadOf(payload).id, limit = 50 })).items
end, { rate = 'community.read' })

app.callback('comment', function(source, payload)
    payload = payloadOf(payload)
    return Phone.unwrap(Services.Social.createComment(source, { postId = payload.id, body = payload.body, clientRequestId = payload.clientRequestId }))
end, { rate = 'community.comment' })

app.callback('removeComment', function(source, payload)
    return Phone.unwrap(Services.Social.deleteComment(source, { id = payloadOf(payload).id }))
end, { rate = 'community.comment' })

-- Sharing a moment into a Pulse chat: the chats the caller is in, then the message itself.
app.callback('chats', function(source)
    return Phone.unwrap(Services.Messaging.listConversations(source, { limit = 50 })).items
end, { rate = 'read' })

app.callback('share', function(source, payload)
    payload = payloadOf(payload)
    -- The clip belongs to whoever posted it, so it travels as a link the receiver's phone plays, plus the caption as text.
    local url = type(payload.mediaUrl) == 'string' and payload.mediaUrl or ''
    local tooLong = #url > MAX_BODY
    local linked = url:find('^https://') ~= nil and url ~= '' and not tooLong
    if linked then
        local token = (payload.mediaKind == 'video' and '[[video:%s]]' or '[[photo:%s]]'):format(url)
        Phone.unwrap(Services.Messaging.send(source, { conversationId = payload.conversationId, body = token, clientRequestId = payload.clientRequestId }))
    end
    local caption = type(payload.body) == 'string' and payload.body or ''
    local text = caption
    if tooLong then text = (caption ~= '' and (caption .. '\n') or '') .. url end
    text = text:sub(1, MAX_BODY)
    if text ~= '' or not linked then
        if text == '' then text = 'A moment from Flash' end
        Phone.unwrap(Services.Messaging.send(source, {
            conversationId = payload.conversationId, body = text,
            clientRequestId = linked and (tostring(payload.clientRequestId) .. ':t') or payload.clientRequestId,
        }))
    end
    return { shared = true }
end, { rate = 'sendMessage' })
