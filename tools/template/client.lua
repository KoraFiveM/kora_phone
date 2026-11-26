-- Client code. Delete this file when the app needs nothing from the game client.
local app = Phone.app('__ID__')

-- The UI reaches this with `phone.client('where', {})`.
app.client('where', function()
    local coords = GetEntityCoords(PlayerPedId())
    return { x = coords.x, y = coords.y }
end)
