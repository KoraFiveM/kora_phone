-- Properties come from the housing tables named in Config.Server.Property; this only hands them to the UI.
local app = Phone.app('property')

app.callback('list', function(source)
    return Phone.unwrap(KoraPhone.Services.Property.list(source))
end)
