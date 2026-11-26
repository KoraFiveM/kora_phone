local app = Phone.app('property')

-- "Take me home": sets the map waypoint to the property entrance.
app.client('waypoint', function(payload)
    payload = type(payload) == 'table' and payload or {}
    return KoraPhone.World.Waypoint(payload.x, payload.y)
end)
