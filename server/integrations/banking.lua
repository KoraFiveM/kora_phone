SteviePhone = SteviePhone or {}
SteviePhone.Integrations = SteviePhone.Integrations or {}

local Banking = {}
SteviePhone.Integrations.Banking = Banking

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

local function moneyFunctions(player)
    return player and player.Functions or nil
end

function Banking.isEnabled()
    return Config.Server.Banking.Enabled == true
end

function Banking.getBalance(player)
    if not Banking.isEnabled() or not player or not player.PlayerData then return nil end
    local money = player.PlayerData.money or {}
    local value = tonumber(money[Config.Server.Banking.Account])
    if not value then return nil end
    return math.max(0, math.floor(value))
end

function Banking.getOnlinePlayerByCitizenId(citizenId)
    if type(citizenId) ~= 'string' or citizenId == '' then return nil end
    return SteviePhone.QB.Functions.GetPlayerByCitizenId(citizenId)
end

function Banking.debit(player, amount, reason)
    local functions = moneyFunctions(player)
    if not functions or type(functions.RemoveMoney) ~= 'function' then return false end
    local ok, result = pcall(function()
        return functions.RemoveMoney(Config.Server.Banking.Account, amount, reason)
    end)
    return ok and result == true
end

function Banking.credit(player, amount, reason)
    local functions = moneyFunctions(player)
    if not functions or type(functions.AddMoney) ~= 'function' then return false end
    local ok, result = pcall(function()
        return functions.AddMoney(Config.Server.Banking.Account, amount, reason)
    end)
    return ok and result == true
end

function Banking.canTransfer()
    return Banking.isEnabled() and Config.Server.Banking.AllowCompensatingTransfers == true
end
