-- What the map needs from the game: the blips other scripts registered, where you are, and the waypoint.
local app = Phone.app('gps')

app.client('blips', function() return KoraPhone.Map.Blips() end)
app.client('here', function() return KoraPhone.World.Location() end)
app.client('waypoint', function(payload)
    payload = type(payload) == 'table' and payload or {}
    return KoraPhone.World.Waypoint(payload.x, payload.y)
end)
