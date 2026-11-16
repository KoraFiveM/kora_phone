KoraPhone = KoraPhone or {}
KoraPhone.Integrations = KoraPhone.Integrations or {}

--- Thin wrapper over kora_core (balances) and kora_banking (durable transfers).
local Banking = {}
KoraPhone.Integrations.Banking = Banking

function Banking.isEnabled()
    return Config.Server.Banking.Enabled == true
end

---@param player table|nil kora_core player data (needs `source`)
---@return integer|nil
function Banking.getBalance(player)
    if not Banking.isEnabled() or not player or not player.source then return nil end
    local value = tonumber(exports.kora_core:getMoney(player.source, Config.Server.Banking.Account))
    if not value then return nil end
    return math.max(0, math.floor(value))
end

--- Transfers need kora_banking, which whitelists this resource in `Config.transactionCallers`.
function Banking.canTransfer()
    return Banking.isEnabled() and GetResourceState('kora_banking') == 'started'
end

--- Runs one atomic, idempotent bank move. Yields. Never compensates: an ambiguous
--- code (`pending`, `indeterminate`, `unavailable`) must be retried with the same key.
---@param operationKey string
---@param request table `{ debits, credits, reason, statements }`
---@return table|nil receipt
---@return string|nil code kora_banking error code
---@return string|nil message
function Banking.execute(operationKey, request)
    local ok, receipt, code, message = pcall(function()
        return exports.kora_banking:ExecuteTransaction(operationKey, request)
    end)
    if not ok then return nil, 'unavailable', tostring(receipt) end
    if type(receipt) ~= 'table' then return nil, code or 'unavailable', message end
    return receipt
end
