SteviePhone.Services = SteviePhone.Services or {}
local Media = { tickets = {} }
SteviePhone.Services.Media = Media

local function newToken()
    local parts = {}
    for i = 1, 5 do parts[i] = string.format('%08x', math.random(0, 0x7fffffff)) end
    return table.concat(parts)
end

local function takeTicket(source, token)
    if type(token) ~= 'string' or #token ~= 40 then return nil, 'INVALID_UPLOAD_TOKEN' end
    local ticket = Media.tickets[token]
    if not ticket or ticket.source ~= source then return nil, 'INVALID_UPLOAD_TOKEN' end
    Media.tickets[token] = nil -- One attempt only, including failed verification.
    if ticket.expiresAt < os.time() then return nil, 'UPLOAD_TOKEN_EXPIRED' end
    return ticket
end

function Media.requestUpload(source, payload, callback)
    local device, permissionError = SteviePhone.Permissions.requireDevice(source)
    if not device then return callback(permissionError) end
    payload = type(payload) == 'table' and payload or {}
    local mimeType = tostring(payload.mimeType or ''):lower()
    local requestedBytes = tonumber(payload.byteSize)
    local byteSize = requestedBytes and math.min(requestedBytes, SteviePhone.Storage.maxBytesFor(mimeType)) or nil
    local valid, validationError = SteviePhone.Storage.validateRequest(mimeType, byteSize)
    if not valid then return callback(PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError)) end
    -- Storage limits per phone: photos must be deleted to make room, clips have a daily allowance.
    local limits = SteviePhone.Storage.Config()
    if SteviePhone.Storage.isVideo(mimeType) then
        if SteviePhone.Repositories.Media.countRecentVideos(device.id) >= limits.MaxVideosPerDay then
            return callback(PhoneError(PhoneConstants.Errors.RATE_LIMITED, 'You have posted enough clips for today'))
        end
    elseif SteviePhone.Repositories.Media.countImages(device.id) >= limits.MaxImagesPerDevice then
        return callback(PhoneError(PhoneConstants.Errors.CONFLICT, 'Your gallery is full. Delete a photo to make room.'))
    end
    local token = newToken()
    local ticket = {
        token = token, source = source, deviceId = device.id, mimeType = mimeType,
        byteSize = byteSize, expiresAt = os.time() + SteviePhone.Storage.Config().TokenTtlSeconds
    }
    Media.tickets[token] = ticket
    SteviePhone.Storage.begin(ticket, function(ok, instruction, providerError, providerData)
        if not ok then Media.tickets[token] = nil; return callback(PhoneError(PhoneConstants.Errors.INTERNAL, providerError)) end
        ticket.providerData = providerData or {}
        callback(PhoneResult({ upload = instruction, expiresAt = ticket.expiresAt }))
    end)
end

function Media.completeUpload(source, payload, callback)
    payload = type(payload) == 'table' and payload or {}
    local ticket, ticketError = takeTicket(source, payload.token)
    if not ticket then return callback(PhoneError(PhoneConstants.Errors.UNAUTHORIZED, ticketError)) end
    local device, permissionError = SteviePhone.Permissions.requireDevice(source)
    if not device or device.id ~= ticket.deviceId then return callback(permissionError or PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'Device changed')) end

    local function persist(ok, record, providerError)
        if not ok then return callback(PhoneError(PhoneConstants.Errors.INVALID_INPUT, providerError)) end
        record.ownerDeviceId = device.id
        local saved = SteviePhone.Repositories.Media.create(record)
        if not saved then
            SteviePhone.Storage.delete(record, function() end)
            return callback(PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to save media'))
        end
        callback(PhoneResult(saved))
    end

    if SteviePhone.Storage.provider() == 'local-development' then
        return SteviePhone.Storage.completeLocal(source, ticket, persist)
    end
    if SteviePhone.Storage.provider() == 'external' then
        return SteviePhone.Storage.completeExternal(ticket, payload.receipt, persist)
    end
    if SteviePhone.Storage.provider() == 'fivemanage' then
        return SteviePhone.Storage.completeFivemanage(ticket, payload.receipt, persist)
    end
    callback(PhoneError(PhoneConstants.Errors.INTERNAL, 'MEDIA_DISABLED'))
end

function Media.list(source, payload)
    local device, permissionError = SteviePhone.Permissions.requireDevice(source)
    if not device then return permissionError end
    local page, validationError = PhoneValidation.page(payload)
    if not page then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local rows = SteviePhone.Repositories.Media.listOwned(device.id, page.limit, page.cursor)
    return PhoneResult({ items = rows, nextCursor = #rows == page.limit and rows[#rows].id or nil })
end

function Media.delete(source, payload, callback)
    local device, permissionError = SteviePhone.Permissions.requireDevice(source)
    if not device then return callback(permissionError) end
    local mediaId, validationError = PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
    if not mediaId then return callback(PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError)) end
    local record = SteviePhone.Repositories.Media.findOwned(device.id, mediaId)
    if not record then return callback(PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Media was not found')) end
    if SteviePhone.Repositories.Media.referenceCount(mediaId) > 0 then
        return callback(PhoneError(PhoneConstants.Errors.CONFLICT, 'Media is still in use'))
    end
    if not SteviePhone.Repositories.Media.softDelete(device.id, mediaId) then
        return callback(PhoneError(PhoneConstants.Errors.CONFLICT, 'Media could not be deleted'))
    end
    SteviePhone.Storage.delete(record, function(deleted)
        if deleted then SteviePhone.Repositories.Media.hardDelete(mediaId) end
        callback(PhoneResult({ id = mediaId, storageDeleted = deleted == true }))
    end)
end

CreateThread(function()
    local cleanupTicks = 0
    while true do
        Wait(60000)
        local now = os.time()
        for token, ticket in pairs(Media.tickets) do
            if ticket.expiresAt < now then Media.tickets[token] = nil end
        end
        cleanupTicks = cleanupTicks + 1
        local storageConfig = SteviePhone.Storage.Config()
        if cleanupTicks >= storageConfig.CleanupIntervalMinutes then
            cleanupTicks = 0
            local tombstones = SteviePhone.Repositories.Media.expiredDeleted(
                storageConfig.DeletedRetentionHours,
                storageConfig.CleanupBatchSize
            )
            for _, record in ipairs(tombstones) do
                SteviePhone.Storage.delete(record, function(deleted)
                    if deleted then SteviePhone.Repositories.Media.hardDelete(record.id) end
                end)
            end
        end
    end
end)
