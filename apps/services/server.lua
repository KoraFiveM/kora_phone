-- Job state and actions are kora_core's (through KoraPhone.Integrations.Jobs); the rules (grade, duty) stay in the service.
local app = Phone.app('services')

app.callback('get', function(source)
    return Phone.unwrap(KoraPhone.Services.Jobs.get(source))
end)

app.callback('setDuty', function(source, payload)
    return Phone.unwrap(KoraPhone.Services.Jobs.setDuty(source, payload))
end)

app.callback('runAction', function(source, payload)
    return Phone.unwrap(KoraPhone.Services.Jobs.runAction(source, payload))
end)
