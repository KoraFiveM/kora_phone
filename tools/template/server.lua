-- Server code. Delete this file when the app has no server logic.
local app = Phone.app('__ID__')

-- The UI reaches this with `phone.callback('ping', payload)`. Never trust the payload.
app.callback('ping', function(source, payload)
    local message = type(payload) == 'table' and type(payload.message) == 'string' and payload.message:sub(1, 64) or ''
    return { pong = true, echo = message }
end)
