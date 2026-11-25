-- Recent calls of the held handset. The service checks the device; the UI cannot ask for anyone else's calls.
local app = Phone.app('phone')

app.callback('recent', function(source)
    local result = Phone.unwrap(KoraPhone.Services.Calling.history(source, { limit = 50 }))
    local device = KoraPhone.Handsets.current(source, false)
    return { items = result.items, number = device and device.phoneNumber }
end, { rate = 'read' })
