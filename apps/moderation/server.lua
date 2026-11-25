-- The queue and the decisions belong to the moderation service, which re-checks that the caller is a moderator.
local app = Phone.app('moderation')

app.callback('queue', function(source, payload)
    payload = type(payload) == 'table' and payload or {}
    return Phone.unwrap(KoraPhone.Services.Moderation.getQueue(source, { status = payload.status or 'open', limit = 50 })).items
end, { rate = 'community.moderation' })

app.callback('resolve', function(source, payload)
    payload = type(payload) == 'table' and payload or {}
    return Phone.unwrap(KoraPhone.Services.Moderation.resolve(source, {
        reportId = payload.reportId, action = payload.action, note = payload.note,
    }))
end, { rate = 'community.moderation' })
