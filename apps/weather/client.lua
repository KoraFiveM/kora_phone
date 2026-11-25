-- Weather comes straight from the game, so it matches whatever weather script the server runs.
local app = Phone.app('weather')

app.client('get', function()
    return KoraPhone.World.Weather()
end)
