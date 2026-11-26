-- The saved places come from the server config (Config.Server.Maps.Locations); the map itself and the blips are client side.
local app = Phone.app('gps')

app.callback('places', function()
    local places = {}
    for _, place in ipairs(Config.Server.Maps.Locations or {}) do
        places[#places + 1] = { label = tostring(place.label or ''), x = tonumber(place.x), y = tonumber(place.y) }
    end
    return places
end, { rate = 'read' })
