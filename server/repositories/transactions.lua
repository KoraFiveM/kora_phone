KoraPhone.Repositories = KoraPhone.Repositories or {}

--- Per-device transfer history. Rows are written by the money transaction itself
--- (see `Transactions.historyStatement`), never by a separate step.
local Transactions = {}
KoraPhone.Repositories.Transactions = Transactions

--- Builds the kora_sql checked-transaction statement that kora_banking runs in
--- the same database transaction as the money legs.
---@param operationKey string
---@param senderDeviceId integer
---@param recipientDeviceId integer
---@param amount integer
---@return table
function Transactions.historyStatement(operationKey, senderDeviceId, recipientDeviceId, amount)
    return {
        query = [[
            INSERT INTO phone_bank_history (operation_key, sender_device_id, recipient_device_id, amount)
            VALUES (?, ?, ?, ?)
        ]],
        values = { operationKey, senderDeviceId, recipientDeviceId, amount },
        expectedRows = 1,
    }
end

local function publicRow(item)
    return {
        id = item.id,
        amount = tonumber(item.amount),
        status = 'completed',
        createdAt = item.createdAt,
        completedAt = item.createdAt,
    }
end

--- Finds a recorded transfer by its kora_banking operation key.
---@param operationKey string
---@return table|nil row `{ id, senderDeviceId, recipientDeviceId, amount, createdAt }`
function Transactions.findByKey(operationKey)
    return Kora.sql.single([[
        SELECT id, sender_device_id AS senderDeviceId, recipient_device_id AS recipientDeviceId,
               amount, UNIX_TIMESTAMP(created_at) AS createdAt
        FROM phone_bank_history WHERE operation_key = ? LIMIT 1
    ]], { operationKey })
end

Transactions.public = publicRow

function Transactions.listForDevice(deviceId, page)
    local limit = math.min(page.limit, Config.Server.Banking.HistoryPageSize or page.limit)
    local params = { deviceId, deviceId }
    local cursorClause = ''
    if page.cursor then
        cursorClause = ' AND t.id < ?'
        params[#params + 1] = page.cursor
    end
    params[#params + 1] = limit + 1
    local rows = Kora.sql.query([[
        SELECT t.id, t.sender_device_id AS senderDeviceId, t.recipient_device_id AS recipientDeviceId,
               s.phone_number AS senderNumber, r.phone_number AS recipientNumber,
               t.amount, UNIX_TIMESTAMP(t.created_at) AS createdAt
        FROM phone_bank_history t
        LEFT JOIN phone_devices s ON s.id = t.sender_device_id
        LEFT JOIN phone_devices r ON r.id = t.recipient_device_id
        WHERE (t.sender_device_id = ? OR t.recipient_device_id = ?) ]] .. cursorClause .. [[
        ORDER BY t.id DESC LIMIT ?
    ]], params)
    local hasMore = #rows > limit
    if hasMore then rows[#rows] = nil end
    local items = {}
    for index, item in ipairs(rows) do
        local outgoing = tonumber(item.senderDeviceId) == tonumber(deviceId)
        local entry = publicRow(item)
        entry.direction = outgoing and 'outgoing' or 'incoming'
        -- The other person's number, so the history can say who it was.
        entry.peer = outgoing and item.recipientNumber or item.senderNumber
        items[index] = entry
    end
    return items, hasMore and items[#items] and items[#items].id or nil
end
