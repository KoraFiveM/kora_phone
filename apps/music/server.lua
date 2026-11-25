-- Stations are phone items (Config.Server.Items.station limits how many). The item service validates every field.
local app = Phone.app('music')
local Services = KoraPhone.Services

local function payloadOf(payload) return type(payload) == 'table' and payload or {} end

app.callback('list', function(source)
    local device = KoraPhone.Permissions.requireDevice(source)
    if not device then error(PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Phone is unavailable'), 0) end
    return Services.Items.forDevice(device.id).stations
end, { rate = 'read' })

app.callback('save', function(source, payload)
    return Phone.unwrap(Services.Items.save(source, { kind = 'station', item = payloadOf(payload) }))
end, { rate = 'mutation' })

app.callback('remove', function(source, payload)
    return Phone.unwrap(Services.Items.remove(source, { kind = 'station', id = payloadOf(payload).id }))
end, { rate = 'mutation' })
