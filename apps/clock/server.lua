-- Alarms are phone items (Config.Server.Items.alarm limits how many). The item service validates every field and the
-- limit; the client script rings them, so this only stores and lists.
local app = Phone.app('clock')
local Services = KoraPhone.Services

local function payloadOf(payload) return type(payload) == 'table' and payload or {} end

app.callback('list', function(source)
    local device = KoraPhone.Permissions.requireDevice(source)
    if not device then error(PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Phone is unavailable'), 0) end
    return Services.Items.forDevice(device.id).alarms
end, { rate = 'read' })

app.callback('save', function(source, payload)
    return Phone.unwrap(Services.Items.save(source, { kind = 'alarm', item = payloadOf(payload) }))
end, { rate = 'mutation' })

app.callback('remove', function(source, payload)
    return Phone.unwrap(Services.Items.remove(source, { kind = 'alarm', id = payloadOf(payload).id }))
end, { rate = 'mutation' })
