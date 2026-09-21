SteviePhone.Services = SteviePhone.Services or {}
local BankingService = {}
SteviePhone.Services.Banking = BankingService

local function unavailable(message)
    return PhoneError(PhoneConstants.Errors.CONFLICT, message or 'Banking is unavailable')
end

local function publicTransaction(transaction)
    return {
        id = transaction.id,
        amount = transaction.amount,
        status = transaction.status,
        failureCode = transaction.failureCode,
        createdAt = transaction.createdAt,
        completedAt = transaction.completedAt
    }
end

function BankingService.balance(source)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local player = SteviePhone.GetPlayer(source)
    local balance = SteviePhone.Integrations.Banking.getBalance(player)
    if balance == nil then return unavailable() end
    -- 'account' is the QBCore money type ("bank"); the holder and account number are what a person recognises.
    local pd = player.PlayerData
    local holder = pd.charinfo and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or ''
    return PhoneResult({ balance = balance, account = Config.Server.Banking.Account, holder = holder, number = pd.citizenid })
end

function BankingService.history(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    if not SteviePhone.Integrations.Banking.isEnabled() then return unavailable() end
    local page, validationError = PhoneValidation.page(payload)
    if not page then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local items, nextCursor = SteviePhone.Repositories.Transactions.listForDevice(device.id, page)
    return PhoneResult({ items = items, nextCursor = nextCursor })
end

function BankingService.transfer(source, payload)
    local senderDevice, permissionError = SteviePhone.Permissions.requireDevice(source)
    if not senderDevice then return permissionError end
    if type(payload) ~= 'table' then
        return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'payload must be an object')
    end
    if not SteviePhone.Integrations.Banking.canTransfer() then
        return unavailable('Transfers are disabled because the configured banking API cannot provide atomic transfers')
    end

    local recipientNumber, numberError = PhoneValidation.phoneNumber(payload.to)
    if not recipientNumber then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, numberError) end
    local amount, amountError = PhoneValidation.integer(payload.amount, 'amount', 1, Config.Server.Banking.MaximumTransfer)
    if not amount then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, amountError) end
    local requestId, requestError = PhoneValidation.string(payload.clientRequestId, 'clientRequestId', 8, 64)
    if not requestId then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, requestError) end

    local senderCitizenId = SteviePhone.GetCitizenId(source)
    local recipientDevice = SteviePhone.Repositories.Phones.findByNumber(recipientNumber)
    if not recipientDevice then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Recipient was not found') end
    if recipientDevice.ownerCitizenId == senderCitizenId then
        return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Cannot transfer to your own phone')
    end

    local claimed, transaction = SteviePhone.Repositories.Transactions.claim(
        senderDevice.id, recipientDevice.id, senderCitizenId, recipientDevice.ownerCitizenId, amount, requestId
    )
    if not transaction then return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to create transfer') end
    if not claimed then
        if tonumber(transaction.amount) ~= amount or tonumber(transaction.recipientDeviceId) ~= tonumber(recipientDevice.id) then
            return PhoneError(PhoneConstants.Errors.CONFLICT, 'Transfer request ID was already used for different transfer details')
        end
        if transaction.status == 'completed' then return PhoneResult({ transaction = publicTransaction(transaction), replayed = true }) end
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Transfer request has already been processed', { status = transaction.status })
    end

    local sender = SteviePhone.GetPlayer(source)
    local recipient = SteviePhone.Integrations.Banking.getOnlinePlayerByCitizenId(recipientDevice.ownerCitizenId)
    if not recipient then
        transaction = SteviePhone.Repositories.Transactions.finish(transaction.id, 'rejected', 'RECIPIENT_OFFLINE')
        return unavailable('Recipient must be online for a safe transfer')
    end
    if (SteviePhone.Integrations.Banking.getBalance(sender) or 0) < amount then
        transaction = SteviePhone.Repositories.Transactions.finish(transaction.id, 'rejected', 'INSUFFICIENT_FUNDS')
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Insufficient funds')
    end

    local reason = ('stevie-phone transfer %s'):format(transaction.id)
    if not SteviePhone.Integrations.Banking.debit(sender, amount, reason) then
        SteviePhone.Repositories.Transactions.finish(transaction.id, 'rejected', 'DEBIT_FAILED')
        return unavailable('Transfer debit failed')
    end
    if not SteviePhone.Integrations.Banking.credit(recipient, amount, reason) then
        local rolledBack = SteviePhone.Integrations.Banking.credit(sender, amount, reason .. ' rollback')
        local status = rolledBack and 'rolled_back' or 'manual_review'
        local code = rolledBack and 'CREDIT_FAILED' or 'ROLLBACK_FAILED'
        SteviePhone.Repositories.Transactions.finish(transaction.id, status, code)
        print(('[stevie-phone] transfer %s failed credit; status=%s'):format(transaction.id, status))
        return unavailable(rolledBack and 'Recipient credit failed; sender was refunded' or 'Transfer requires administrator review')
    end

    transaction = SteviePhone.Repositories.Transactions.finish(transaction.id, 'completed', nil)
    return PhoneResult({
        transaction = publicTransaction(transaction),
        balance = SteviePhone.Integrations.Banking.getBalance(sender)
    })
end
