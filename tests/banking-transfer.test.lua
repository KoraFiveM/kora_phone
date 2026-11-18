-- Phone transfers run on kora_banking's durable ExecuteTransaction. The mock below mimics its contract:
-- caller whitelist, per-key idempotency (same terms replay, different terms conflict), atomic funds check,
-- offline recipients, and statements executing in the same step as the money.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end

local history, nextId, banks, operations = {}, 1, {}, {}
local state = { allowed = true, forced = nil, online = true, calls = 0 }

local function fingerprint(request)
    local parts = {}
    for _, leg in ipairs(request.debits) do parts[#parts + 1] = 'd' .. leg.citizenid .. leg.amount end
    for _, leg in ipairs(request.credits) do parts[#parts + 1] = 'c' .. leg.citizenid .. leg.amount end
    parts[#parts + 1] = request.reason
    for _, statement in ipairs(request.statements or {}) do parts[#parts + 1] = table.concat(statement.values, '|') end
    return table.concat(parts, ',')
end

local function bankingExecute(key, request)
    state.calls = state.calls + 1
    if not state.allowed then return false, 'rejected', 'caller not allowed' end
    if state.forced then return false, state.forced, 'forced' end
    local print = fingerprint(request)
    local existing = operations[key]
    if existing then
        if existing.print ~= print then return false, 'conflict', 'terms differ' end
        return existing.receipt
    end
    local debit, credit = request.debits[1], request.credits[1]
    if (banks[debit.citizenid] or 0) < debit.amount then return false, 'insufficient_funds', 'low' end
    banks[debit.citizenid] = banks[debit.citizenid] - debit.amount
    banks[credit.citizenid] = (banks[credit.citizenid] or 0) + debit.amount
    for _, statement in ipairs(request.statements or {}) do
        local v = statement.values
        history[#history + 1] = { id = nextId, operationKey = v[1], senderDeviceId = v[2],
            recipientDeviceId = v[3], amount = v[4], createdAt = 1700000000 }
        nextId = nextId + 1
    end
    local receipt = { operationKey = key, status = 'completed', timestamp = 1700000000, amount = debit.amount, accounts = {} }
    operations[key] = { print = print, receipt = receipt }
    return receipt
end

Config = { Server = { Banking = { Enabled = true, Account = 'bank', MaximumTransfer = 1000000, HistoryPageSize = 30 } } }
PhoneConstants = { Errors = { CONFLICT = 'CONFLICT', INVALID_INPUT = 'INVALID_INPUT', NOT_FOUND = 'NOT_FOUND', INTERNAL = 'INTERNAL' } }
PhoneError = function(code, message, details) return { ok = false, error = { code = code, message = message, details = details } } end
PhoneResult = function(data) return { ok = true, data = data } end
PhoneValidation = {
    phoneNumber = function(v) return v, nil end,
    integer = function(v) if math.type(v) == 'integer' and v > 0 then return v end return nil, 'bad amount' end,
    string = function(v) if type(v) == 'string' and #v >= 8 then return v end return nil, 'bad string' end,
    page = function() return { limit = 30 } end,
}
GetResourceState = function() return 'started' end
Kora = {
    logging = { event = function() end },
    sql = {
        single = function(_, params)
            for _, row in ipairs(history) do if row.operationKey == params[1] then return row end end
        end,
        query = function(_, params)
            local rows = {}
            for index = #history, 1, -1 do
                local row = history[index]
                if row.senderDeviceId == params[1] or row.recipientDeviceId == params[2] then
                    rows[#rows + 1] = { id = row.id, senderDeviceId = row.senderDeviceId, recipientDeviceId = row.recipientDeviceId,
                        senderNumber = '555-0001', recipientNumber = '555-0002', amount = row.amount, createdAt = row.createdAt }
                end
            end
            return rows
        end,
    },
}
exports = {
    kora_banking = { ExecuteTransaction = function(_, key, request) return bankingExecute(key, request) end },
    kora_core = { getMoney = function(_, _, account) assert(account == 'bank'); return banks.ALICE end },
}
local devices = { [1] = { id = 11, ownerCitizenId = 'ALICE' }, [2] = { id = 22, ownerCitizenId = 'BOB' } }
KoraPhone = {
    Permissions = { requireDevice = function(source) return devices[source] end },
    GetCitizenId = function(source) return devices[source].ownerCitizenId end,
    GetPlayer = function(source) return { source = source, citizenid = devices[source].ownerCitizenId } end,
    Repositories = { Phones = { findByNumber = function(number)
        if number == '555-0002' then return devices[2] end
        if number == '555-0001' then return devices[1] end
    end } },
}
dofile('server/integrations/banking.lua')
dofile('server/repositories/transactions.lua')
dofile('server/services/banking.lua')
local transfer = KoraPhone.Services.Banking.transfer
local function request(amount, id, to) return { to = to or '555-0002', amount = amount, clientRequestId = id } end

-- Success: both legs and the history row commit together; Bob is offline (never loaded, only a citizen id).
banks.ALICE, banks.BOB = 500, 10
local result = transfer(1, request(200, 'request-0001'))
check(result.ok and not result.data.replayed, 'transfer succeeds')
check(banks.ALICE == 300 and banks.BOB == 210, 'offline recipient is credited by citizen id')
check(result.data.transaction.status == 'completed' and result.data.transaction.amount == 200, 'public transaction shape')
check(result.data.balance == 300, 'balance read back from kora_core')
check(#history == 1 and history[1].operationKey == 'transfer:ALICE:request-0001', 'history row written with the transaction')

-- Idempotent replay: no second debit, flagged as replayed.
result = transfer(1, request(200, 'request-0001'))
check(result.ok and result.data.replayed == true and banks.ALICE == 300 and #history == 1, 'replay does not move money twice')
check(state.calls == 1, 'a recorded replay is answered without calling kora_banking again')

-- Same request id with different terms is a conflict.
result = transfer(1, request(250, 'request-0001'))
check(not result.ok and result.error.code == 'CONFLICT' and banks.ALICE == 300, 'changed terms conflict')

-- Insufficient funds: nothing committed.
result = transfer(1, request(9000, 'request-0002'))
check(not result.ok and result.error.message == 'Insufficient funds' and banks.ALICE == 300 and #history == 1, 'insufficient funds')

-- Rejected caller maps to an internal error, never a partial move.
state.allowed = false
result = transfer(1, request(10, 'request-0003'))
check(not result.ok and result.error.code == 'INTERNAL', 'rejected caller')
state.allowed = true

-- Ambiguous replies are retryable and never compensated.
for _, code in ipairs({ 'pending', 'indeterminate', 'unavailable' }) do
    state.forced = code
    result = transfer(1, request(10, 'request-0004'))
    check(not result.ok and result.error.details.retryable == true and banks.ALICE == 300, code .. ' is retryable')
end
state.forced = nil
result = transfer(1, request(10, 'request-0004'))
check(result.ok and banks.ALICE == 290, 'identical retry after an ambiguous reply succeeds')

-- Phone-side validation stays in the phone.
check(transfer(1, request(10, 'request-0005', '555-0001')).error.code == 'INVALID_INPUT', 'self transfer refused')
check(transfer(1, request(10, 'request-0006', '555-9999')).error.code == 'NOT_FOUND', 'unknown recipient')
check(transfer(1, request(10, 'x' .. string.rep('y', 63))).ok == true, 'maximum request id accepted')
check(#KoraPhone.Repositories.Transactions.historyStatement('k', 1, 2, 3).values == 4, 'statement shape')

-- History keeps the web adapter shape (direction, peer, status).
local page = KoraPhone.Services.Banking.history(1, {})
check(page.ok and page.data.items[1].direction == 'outgoing' and page.data.items[1].peer == '555-0002', 'history shape')
print(('kora_phone banking transfer: %d checks passed'):format(checks))
