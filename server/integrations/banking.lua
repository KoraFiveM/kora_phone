QBPhone = QBPhone or {}
QBPhone.Integrations = QBPhone.Integrations or {}

local Banking = {}
QBPhone.Integrations.Banking = Banking

-- QBCore's in-memory player money API cannot participate in the SQL audit
-- transaction. Transfers therefore stay disabled unless the operator opts in
-- to the compensating-transfer path explicitly.
Config.Server.Banking = Config.Server.Banking or {}
local bankingConfig = Config.Server.Banking
if bankingConfig.Enabled == nil then bankingConfig.Enabled = true end
bankingConfig.Account = bankingConfig.Account or 'bank'
bankingConfig.MaximumTransfer = tonumber(bankingConfig.MaximumTransfer) or 1000000
bankingConfig.HistoryPageSize = tonumber(bankingConfig.HistoryPageSize) or 30
if bankingConfig.AllowCompensatingTransfers == nil then bankingConfig.AllowCompensatingTransfers = false end

function Banking.isEnabled()
    return Config.Server.Banking.Enabled == true
end

function Banking.getBalance(player)
    if not Banking.isEnabled() or not player or not player.source then return nil end
    local value = tonumber(exports.qbcore:getMoney(player.source, Config.Server.Banking.Account))
    if not value then return nil end
    return math.max(0, math.floor(value))
end

function Banking.getOnlinePlayerByCitizenId(citizenId)
    if type(citizenId) ~= 'string' or citizenId == '' then return nil end
    return exports.qbcore:getPlayerByCitizenId(citizenId)
end

function Banking.debit(player, amount, reason)
    if not player or not player.source then return false end
    local ok, result = pcall(function()
        return exports.qbcore:removeMoney(player.source, Config.Server.Banking.Account, amount, reason)
    end)
    return ok and result == true
end

function Banking.credit(player, amount, reason)
    if not player or not player.source then return false end
    local ok, result = pcall(function()
        return exports.qbcore:addMoney(player.source, Config.Server.Banking.Account, amount, reason)
    end)
    return ok and result == true
end

function Banking.canTransfer()
    return Banking.isEnabled() and Config.Server.Banking.AllowCompensatingTransfers == true
end
