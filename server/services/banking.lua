KoraPhone.Services = KoraPhone.Services or {}
local BankingService = {}
KoraPhone.Services.Banking = BankingService

local function unavailable(message)
    return PhoneError(PhoneConstants.Errors.CONFLICT, message or 'Banking is unavailable')
end

function BankingService.balance(source)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local player = KoraPhone.GetPlayer(source)
    local balance = KoraPhone.Integrations.Banking.getBalance(player)
    if balance == nil then return unavailable() end
    local info = player.charinfo
    local holder = info and ('%s %s'):format(info.firstname or '', info.lastname or '') or ''
    return PhoneResult({ balance = balance, account = Config.Server.Banking.Account, holder = holder, number = player.citizenid })
end

function BankingService.history(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    if not KoraPhone.Integrations.Banking.isEnabled() then return unavailable() end
    local page, validationError = PhoneValidation.page(payload)
    if not page then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local items, nextCursor = KoraPhone.Repositories.Transactions.listForDevice(device.id, page)
    return PhoneResult({ items = items, nextCursor = nextCursor })
end

local RETRYABLE = { pending = true, indeterminate = true, unavailable = true }
local MAX_OPERATION_KEY = 128

--- Maps a kora_banking refusal code to a PhoneError. Ambiguous codes are never compensated.
local function refusal(code, message)
    if code == 'insufficient_funds' then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Insufficient funds')
    elseif code == 'conflict' then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Transfer request ID was already used for different transfer details')
    elseif RETRYABLE[code] then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Transfer is still being processed; retry with the same request ID',
            { retryable = true, code = code })
    end
    Kora.logging.error('banking.transfer_refused', 'kora_banking refused a phone transfer',
        { code = tostring(code), message = tostring(message) })
    return PhoneError(PhoneConstants.Errors.INTERNAL, 'Transfer is not available')
end

local function sameTerms(row, recipientDevice, amount)
    return tonumber(row.amount) == amount and tonumber(row.recipientDeviceId) == tonumber(recipientDevice.id)
end

function BankingService.transfer(source, payload)
    local senderDevice, permissionError = KoraPhone.Permissions.requireDevice(source)
    if not senderDevice then return permissionError end
    if type(payload) ~= 'table' then
        return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'payload must be an object')
    end
    if not KoraPhone.Integrations.Banking.canTransfer() then return unavailable('Transfers are unavailable') end

    local recipientNumber, numberError = PhoneValidation.phoneNumber(payload.to)
    if not recipientNumber then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, numberError) end
    local amount, amountError = PhoneValidation.integer(payload.amount, 'amount', 1, Config.Server.Banking.MaximumTransfer)
    if not amount then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, amountError) end
    local requestId, requestError = PhoneValidation.string(payload.clientRequestId, 'clientRequestId', 8, 64)
    if not requestId then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, requestError) end

    local senderCitizenId = KoraPhone.GetCitizenId(source)
    local recipientDevice = KoraPhone.Repositories.Phones.findByNumber(recipientNumber)
    if not recipientDevice then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Recipient was not found') end
    if recipientDevice.ownerCitizenId == senderCitizenId then
        return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Cannot transfer to your own phone')
    end

    -- The key is unique per calling resource inside kora_banking; the recipient is part of the
    -- request terms, so reusing a request ID for a different transfer is a `conflict`.
    local operationKey = ('transfer:%s:%s'):format(senderCitizenId, requestId)
    if #operationKey > MAX_OPERATION_KEY then
        return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'clientRequestId is too long')
    end

    local Transactions = KoraPhone.Repositories.Transactions
    local recorded = Transactions.findByKey(operationKey)
    if recorded then
        if not sameTerms(recorded, recipientDevice, amount) then return refusal('conflict') end
        return PhoneResult({ transaction = Transactions.public(recorded), replayed = true })
    end

    local receipt, code, message = KoraPhone.Integrations.Banking.execute(operationKey, {
        debits = { { citizenid = senderCitizenId, amount = amount } },
        credits = { { citizenid = recipientDevice.ownerCitizenId, amount = amount } },
        reason = 'Phone transfer',
        statements = { Transactions.historyStatement(operationKey, senderDevice.id, recipientDevice.id, amount) },
    })
    if not receipt then return refusal(code, message) end

    local transaction = Transactions.findByKey(operationKey)
    return PhoneResult({
        transaction = transaction and Transactions.public(transaction) or {
            amount = amount, status = 'completed', createdAt = receipt.timestamp, completedAt = receipt.timestamp,
        },
        balance = KoraPhone.Integrations.Banking.getBalance(KoraPhone.GetPlayer(source)),
    })
end
