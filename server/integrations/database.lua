KoraPhone = KoraPhone or {}
KoraPhone.Database = {}

function KoraPhone.Database.isReady()
    local ok = pcall(function() MySQL.scalar.await('SELECT 1') end)
    return ok
end