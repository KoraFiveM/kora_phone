QBPhone.Repositories = QBPhone.Repositories or {}
local Transactions = {}
QBPhone.Repositories.Transactions = Transactions

local function row(id)
    return MySQL.single.await([[
        SELECT id, sender_device_id AS senderDeviceId, recipient_device_id AS recipientDeviceId,
               sender_citizenid AS senderCitizenId, recipient_citizenid AS recipientCitizenId,
               amount, status, client_request_id AS clientRequestId, failure_code AS failureCode,
               UNIX_TIMESTAMP(created_at) AS createdAt, UNIX_TIMESTAMP(completed_at) AS completedAt
        FROM phone_economy_audit WHERE id = ? LIMIT 1
    ]], { id })
end

function Transactions.findIdempotent(senderCitizenId, clientRequestId)
    return MySQL.single.await([[
        SELECT id, sender_device_id AS senderDeviceId, recipient_device_id AS recipientDeviceId,
               sender_citizenid AS senderCitizenId, recipient_citizenid AS recipientCitizenId,
               amount, status, client_request_id AS clientRequestId, failure_code AS failureCode,
               UNIX_TIMESTAMP(created_at) AS createdAt, UNIX_TIMESTAMP(completed_at) AS completedAt
        FROM phone_economy_audit
        WHERE sender_citizenid = ? AND client_request_id = ? LIMIT 1
    ]], { senderCitizenId, clientRequestId })
end

function Transactions.claim(senderDeviceId, recipientDeviceId, senderCitizenId, recipientCitizenId, amount, clientRequestId)
    local affected = MySQL.update.await([[
        INSERT IGNORE INTO phone_economy_audit
            (sender_device_id, recipient_device_id, sender_citizenid, recipient_citizenid,
             amount, status, client_request_id)
        VALUES (?, ?, ?, ?, ?, 'pending', ?)
    ]], { senderDeviceId, recipientDeviceId, senderCitizenId, recipientCitizenId, amount, clientRequestId })
    local transaction = Transactions.findIdempotent(senderCitizenId, clientRequestId)
    return affected == 1, transaction
end

function Transactions.finish(id, status, failureCode)
    local affected = MySQL.update.await([[
        UPDATE phone_economy_audit
        SET status = ?, failure_code = ?, completed_at = CURRENT_TIMESTAMP
        WHERE id = ? AND status = 'pending'
    ]], { status, failureCode, id })
    return affected == 1 and row(id) or row(id)
end

function Transactions.listForDevice(deviceId, page)
    local limit = math.min(page.limit, Config.Server.Banking.HistoryPageSize or page.limit)
    local params = { deviceId, deviceId }
    local cursorClause = ''
    if page.cursor then
        cursorClause = ' AND t.id < ?'
        params[#params + 1] = page.cursor
    end
    params[#params + 1] = limit + 1
    local rows = MySQL.query.await([[
        SELECT t.id, t.sender_device_id AS senderDeviceId, t.recipient_device_id AS recipientDeviceId,
               s.phone_number AS senderNumber, r.phone_number AS recipientNumber,
               t.amount, t.status, t.failure_code AS failureCode,
               UNIX_TIMESTAMP(t.created_at) AS createdAt, UNIX_TIMESTAMP(t.completed_at) AS completedAt
        FROM phone_economy_audit t
        LEFT JOIN phone_devices s ON s.id = t.sender_device_id
        LEFT JOIN phone_devices r ON r.id = t.recipient_device_id
        WHERE (t.sender_device_id = ? OR t.recipient_device_id = ?) ]] .. cursorClause .. [[
        ORDER BY t.id DESC LIMIT ?
    ]], params)
    local hasMore = #rows > limit
    if hasMore then rows[#rows] = nil end
    for _, item in ipairs(rows) do
        item.direction = tonumber(item.senderDeviceId) == tonumber(deviceId) and 'outgoing' or 'incoming'
        -- The other person's number, so the history can say who it was.
        item.peer = item.direction == 'outgoing' and item.recipientNumber or item.senderNumber
        item.senderDeviceId = nil
        item.recipientDeviceId = nil
        item.senderNumber = nil
        item.recipientNumber = nil
    end
    return rows, hasMore and rows[#rows] and rows[#rows].id or nil
end

