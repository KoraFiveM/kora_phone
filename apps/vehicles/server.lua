-- The character's vehicles come from kora_garages (Config.Server.Garage); this only hands them to the UI.
local app = Phone.app('vehicles')

app.callback('list', function(source)
    return Phone.unwrap(KoraPhone.Services.Garage.list(source))
end)
