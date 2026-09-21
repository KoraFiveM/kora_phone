-- This module intentionally owns its callback names so banking/jobs can be
-- added without weakening the central callback router. Ensure it is loaded
-- after integrations, repositories and services.
local function register(name, rateKey, handler)
    SteviePhone.QB.Functions.CreateCallback('stevie-phone:server:' .. name, function(source, cb, payload)
        if not SteviePhone.RateLimits.consume(source, rateKey) then
            cb(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'Too many requests'))
            return
        end
        local ok, result = xpcall(function() return handler(source, payload) end, debug.traceback)
        if not ok then
            print(('[stevie-phone] economy callback %s failed for source %s: %s'):format(name, source, result))
            cb(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'))
            return
        end
        cb(result or PhoneError(PhoneConstants.Errors.INTERNAL, 'Empty service response'))
    end)
end

register('getBankBalance', 'read', SteviePhone.Services.Banking.balance)
register('getBankHistory', 'read', SteviePhone.Services.Banking.history)
register('transferBankMoney', 'bankTransfer', SteviePhone.Services.Banking.transfer)
register('getWallet', 'read', SteviePhone.Services.Wallet.get)
register('showWalletId', 'mutation', SteviePhone.Services.Wallet.show)
register('getJob', 'read', SteviePhone.Services.Jobs.get)
register('setJobDuty', 'jobMutation', SteviePhone.Services.Jobs.setDuty)
register('runJobAction', 'jobMutation', SteviePhone.Services.Jobs.runAction)
