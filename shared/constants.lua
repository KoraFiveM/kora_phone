PhoneConstants = {
    Errors = {
        INTERNAL = 'INTERNAL_ERROR', INVALID_INPUT = 'INVALID_INPUT', UNAUTHORIZED = 'UNAUTHORIZED',
        NOT_FOUND = 'NOT_FOUND', RATE_LIMITED = 'RATE_LIMITED', PHONE_REQUIRED = 'PHONE_REQUIRED',
        CONFLICT = 'CONFLICT', FORBIDDEN = 'FORBIDDEN'
    }
}

function PhoneResult(data)
    return { ok = true, data = data }
end

function PhoneError(code, message, details)
    return { ok = false, error = { code = code, message = message, details = details } }
end
