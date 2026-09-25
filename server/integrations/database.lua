QBPhone = QBPhone or {}
QBPhone.Database = {}

function QBPhone.Database.isReady()
    local ok = pcall(function() MySQL.scalar.await('SELECT 1') end)
    return ok
end

