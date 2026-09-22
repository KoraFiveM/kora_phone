QBPhone = QBPhone or {}
QBPhone.Database = {}

function QBPhone.Database.transaction(queries)
    return MySQL.transaction.await(queries)
end

function QBPhone.Database.isReady()
    local ok = pcall(function() MySQL.scalar.await('SELECT 1') end)
    return ok
end

