-- Money and the ID card come from the validated services (kora_banking transfers, kora_core identity); this only
-- hands them to the UI. The UI never sends an account, a sender or a character: the caller's source decides all of them.
local app = Phone.app('banking')
local Services = KoraPhone.Services

app.callback('overview', function(source)
    local bank = Phone.unwrap(Services.Banking.balance(source))
    local history = Phone.unwrap(Services.Banking.history(source, { limit = 50 }))
    return {
        balance = bank.balance, account = bank.number, holder = bank.holder,
        history = history.items,
        transfers = KoraPhone.Integrations.Banking.canTransfer() == true,
    }
end)

app.callback('transfer', function(source, payload)
    payload = type(payload) == 'table' and payload or {}
    -- Only these three fields are read: the request id lets a retried transfer reuse the same operation.
    local result = Phone.unwrap(Services.Banking.transfer(source, {
        to = payload.to, amount = payload.amount, clientRequestId = payload.clientRequestId,
    }))
    return { status = result and result.transaction and result.transaction.status or 'completed' }
end, { rate = 'bankTransfer' })

app.callback('idCard', function(source)
    return Phone.unwrap(Services.Wallet.get(source))
end)

app.callback('showId', function(source)
    return Phone.unwrap(Services.Wallet.show(source))
end)
