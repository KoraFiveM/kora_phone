-- Sharing where you are, and setting a waypoint to a location someone shared.
local app = Phone.app('social')

app.client('here', function() return KoraPhone.World.Location() end)
app.client('waypoint', function(payload)
    payload = type(payload) == 'table' and payload or {}
    return KoraPhone.World.Waypoint(payload.x, payload.y)
end)
