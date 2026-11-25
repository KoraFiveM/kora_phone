-- System mail and Activity are character-owned and delivered by trusted server scripts (docs/system-mail.md).
-- These callbacks run the existing routes, which check that the handset still belongs to the caller's character.
local app = Phone.app('mail')

local function route(name, payload, source)
    return Phone.unwrap(KoraPhone.SystemMail.routes[name](source, payload))
end

local function page(payload)
    payload = type(payload) == 'table' and payload or {}
    return { limit = 50, cursor = payload.before }
end

app.callback('inbox', function(source, payload) return route('mail:system:list', page(payload), source).items end)
app.callback('activity', function(source, payload) return route('mail:system:activity', page(payload), source).items end)

local function byId(name)
    return function(source, payload)
        payload = type(payload) == 'table' and payload or {}
        return route(name, { id = payload.id }, source)
    end
end

app.callback('read', byId('mail:system:read'), { rate = 'mutation' })
app.callback('delete', byId('mail:system:delete'), { rate = 'mutation' })
-- Accept consumes the mail's one-use button once, then the server fires the nominated event itself.
app.callback('accept', byId('mail:system:accept'), { rate = 'mutation' })
