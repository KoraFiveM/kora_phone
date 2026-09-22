-- This module intentionally owns its callback names so banking/jobs can be
-- added without weakening the central callback router. Ensure it is loaded
-- after integrations, repositories and services.
local function register(name, rateKey, handler)
    QBPhone.QB.Functions.CreateCallback('qbphone:server:' .. name, function(source, cb, payload)
        if not QBPhone.RateLimits.consume(source, rateKey) then
            cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
            return
        end
        local ok, result = xpcall(function() return handler(source, payload) end, debug.traceback)
        if not ok then
            print(('[qbphone] economy callback %s failed for source %s: %s'):format(name, source, result))
            cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
            return
        end
        cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
    end)
end

register('getBankBalance', 'read', QBPhone.Services.Banking.balance)
register('getBankHistory', 'read', QBPhone.Services.Banking.history)
register('transferBankMoney', 'bankTransfer', QBPhone.Services.Banking.transfer)
register('getWallet', 'read', QBPhone.Services.Wallet.get)
register('showWalletId', 'mutation', QBPhone.Services.Wallet.show)
register('getJob', 'read', QBPhone.Services.Jobs.get)
register('setJobDuty', 'jobMutation', QBPhone.Services.Jobs.setDuty)
register('runJobAction', 'jobMutation', QBPhone.Services.Jobs.runAction)
