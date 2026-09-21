SteviePhone = SteviePhone or {}
SteviePhone.Database = {}

function SteviePhone.Database.transaction(queries)
    return MySQL.transaction.await(queries)
end

function SteviePhone.Database.isReady()
    local ok = pcall(function() MySQL.scalar.await('SELECT 1') end)
    return ok
end

