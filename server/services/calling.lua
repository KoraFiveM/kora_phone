QBPhone.Services = QBPhone.Services or {}
local Calling = {
    activeById = {},
    callByDevice = {},
    nextVoiceChannel = 31000,
}
QBPhone.Services.Calling = Calling

local terminal = { ended = true, rejected = true, missed = true, cancelled = true }
local config = Config.Calls or {}
local ringTimeoutMs = math.max(10000, math.min(120000, tonumber(config.RingTimeoutMs) or 30000))
local channelMinimum = math.max(1, tonumber(config.VoiceChannelMinimum) or 31000)
local channelMaximum = math.max(channelMinimum + 10, tonumber(config.VoiceChannelMaximum) or 60999)
Calling.nextVoiceChannel = channelMinimum

local function publicCall(call, viewerDeviceId)
    local outgoing = viewerDeviceId == call.callerDeviceId
    return {
        id = call.id,
        direction = outgoing and 'outgoing' or 'incoming',
        remoteNumber = outgoing and call.calleeNumber or call.callerNumber,
        status = call.status,
        startedAt = call.startedAt,
        answeredAt = call.answeredAt,
        voiceChannel = call.status == 'active' and call.voiceChannel or nil,
    }
end

local function sourceForDevice(deviceId)
    for source, session in pairs(QBPhone.Sessions.bySource) do
        if session.deviceId == deviceId then return source end
    end
end

local function notify(call, eventName, payload)
    local callerSource = sourceForDevice(call.callerDeviceId)
    local calleeSource = sourceForDevice(call.calleeDeviceId)
    if callerSource then
        TriggerClientEvent(eventName, callerSource, payload or publicCall(call, call.callerDeviceId))
    end
    if calleeSource then
        TriggerClientEvent(eventName, calleeSource, payload or publicCall(call, call.calleeDeviceId))
    end
end

local function allocateChannel()
    local attempts = channelMaximum - channelMinimum + 1
    for _ = 1, attempts do
        local candidate = Calling.nextVoiceChannel
        Calling.nextVoiceChannel = candidate >= channelMaximum and channelMinimum or candidate + 1
        local used = false
        for _, call in pairs(Calling.activeById) do
            if call.voiceChannel == candidate and not terminal[call.status] then used = true; break end
        end
        if not used then return candidate end
    end
end

local function makeId()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return template:gsub('[xy]', function(character)
        local value = character == 'x' and math.random(0, 15) or math.random(8, 11)
        return string.format('%x', value)
    end)
end

local function clear(call)
    if Calling.callByDevice[call.callerDeviceId] == call.id then Calling.callByDevice[call.callerDeviceId] = nil end
    if Calling.callByDevice[call.calleeDeviceId] == call.id then Calling.callByDevice[call.calleeDeviceId] = nil end
    Calling.activeById[call.id] = nil
end

local function finish(call, finalStatus, reason)
    if not call or terminal[call.status] then return false end
    local prior = call.status
    if not QBPhone.Repositories.Calls.transition(call.id, { prior }, finalStatus, reason) then return false end
    if prior == 'active' then
        QBPhone.Integrations.Voice.leave(sourceForDevice(call.callerDeviceId), call.voiceChannel)
        QBPhone.Integrations.Voice.leave(sourceForDevice(call.calleeDeviceId), call.voiceChannel)
    end
    call.status = finalStatus
    call.endedReason = reason
    notify(call, 'qbphone:client:calls:ended', {
        id = call.id, status = finalStatus, reason = reason,
    })
    clear(call)
    return true
end

local function participant(call, deviceId)
    return call and (call.callerDeviceId == deviceId or call.calleeDeviceId == deviceId)
end

local function activeOwnedCall(source, payload)
    local device, err = QBPhone.Permissions.requireDevice(source, true)
    if not device then return nil, nil, err end
    if type(payload) ~= 'table' or type(payload.id) ~= 'string' or #payload.id < 32 or #payload.id > 40 then
        return nil, nil, PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Call id is invalid')
    end
    local call = Calling.activeById[payload.id]
    if not participant(call, device.id) then
        return nil, nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Call was not found')
    end
    return call, device
end

local function isCurrentCharacter(source, citizenId, session)
    return QBPhone.GetCitizenId(source) == citizenId
        and (not session or QBPhone.Sessions.bySource[source] == session)
end

function Calling.start(source, payload)
    local callerSession = QBPhone.Sessions.bySource[source]
    local callerCitizenId = QBPhone.GetCitizenId(source)
    local caller, err = QBPhone.Permissions.requireDevice(source)
    if not caller then return err end
    local number, validationError = PhoneValidation.phoneNumber(type(payload) == 'table' and payload.to)
    if not number then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    if number == caller.phoneNumber then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Cannot call your own number') end
    if Calling.callByDevice[caller.id] then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Already in a call') end

    if not isCurrentCharacter(source, callerCitizenId, callerSession) then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call participant is unavailable')
    end

    local callee = QBPhone.Repositories.Phones.findByNumber(number)
    if not callee then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Number was not found') end
    if not isCurrentCharacter(source, callerCitizenId, callerSession) then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call participant is unavailable')
    end
    if QBPhone.Repositories.Blocks.isEitherBlocked(caller.id, callee.id) then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Number was not found')
    end
    if not isCurrentCharacter(source, callerCitizenId, callerSession) then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call participant is unavailable')
    end
    if Calling.callByDevice[caller.id] then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Already in a call') end
    if Calling.callByDevice[callee.id] then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Number is busy') end
    local calleeSource = QBPhone.Sessions.sourceByNumber(number)
    if not calleeSource then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Number is unavailable') end
    local calleeSession = QBPhone.Sessions.bySource[calleeSource]
    local voiceChannel = allocateChannel()
    if not voiceChannel then return PhoneError(PhoneConstants.Errors.INTERNAL, 'No call channel is available') end

    local call = {
        id = makeId(), callerDeviceId = caller.id, calleeDeviceId = callee.id,
        callerNumber = caller.phoneNumber, calleeNumber = callee.phoneNumber,
        status = 'ringing', voiceChannel = voiceChannel, startedAt = os.time(),
    }
    -- Keep both devices busy while the database insert yields.
    Calling.callByDevice[caller.id] = call.id
    Calling.callByDevice[callee.id] = call.id
    local ok, created = pcall(QBPhone.Repositories.Calls.create, call)
    if not ok or not created then
        clear(call)
        if not ok then error(created, 0) end
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to create call')
    end
    if not isCurrentCharacter(source, callerCitizenId, callerSession)
        or not isCurrentCharacter(calleeSource, calleeSession.citizenId, calleeSession) then
        clear(call)
        QBPhone.Repositories.Calls.transition(call.id, { 'ringing' }, 'cancelled', 'participant_unavailable')
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call participant is unavailable')
    end
    Calling.activeById[call.id] = call
    TriggerClientEvent('qbphone:client:calls:outgoing', source, publicCall(call, caller.id))
    TriggerClientEvent('qbphone:client:calls:incoming', calleeSource, publicCall(call, callee.id))

    SetTimeout(ringTimeoutMs, function()
        local current = Calling.activeById[call.id]
        if current and current.status == 'ringing' then finish(current, 'missed', 'ring_timeout') end
    end)
    return PhoneResult(publicCall(call, caller.id))
end

function Calling.accept(source, payload)
    local call, device, err = activeOwnedCall(source, payload)
    if not call then return err end
    if device.id ~= call.calleeDeviceId or call.status ~= 'ringing' then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call cannot be accepted')
    end
    if not QBPhone.Repositories.Calls.transition(call.id, { 'ringing' }, 'active') then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call state changed')
    end
    call.status = 'active'
    local callerSource = sourceForDevice(call.callerDeviceId)
    local calleeSource = sourceForDevice(call.calleeDeviceId)
    if not callerSource or not calleeSource then
        finish(call, 'cancelled', 'participant_unavailable')
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call participant is unavailable')
    end
    if not QBPhone.Integrations.Voice.join(callerSource, calleeSource, call.voiceChannel) then
        finish(call, 'ended', 'voice_unavailable')
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Voice service is unavailable')
    end
    call.answeredAt = os.time()
    notify(call, 'qbphone:client:calls:accepted')
    return PhoneResult(publicCall(call, device.id))
end

function Calling.reject(source, payload)
    local call, device, err = activeOwnedCall(source, payload)
    if not call then return err end
    if device.id ~= call.calleeDeviceId or call.status ~= 'ringing' then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call cannot be rejected')
    end
    finish(call, 'rejected', 'declined')
    return PhoneResult({ id = call.id, status = 'rejected' })
end

function Calling.hangup(source, payload)
    local call, _, err = activeOwnedCall(source, payload)
    if not call then return err end
    local finalStatus = call.status == 'ringing' and 'cancelled' or 'ended'
    finish(call, finalStatus, 'hangup')
    return PhoneResult({ id = call.id, status = finalStatus })
end

function Calling.history(source, payload)
    local device, err = QBPhone.Permissions.requireDevice(source)
    if not device then return err end
    payload = type(payload) == 'table' and payload or {}
    local limit, validationError = PhoneValidation.integer(
        payload.limit or Config.Limits.PageSizeDefault, 'limit', 1, Config.Limits.PageSizeMaximum
    )
    if not limit then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local cursor = payload.cursor
    if cursor ~= nil and (type(cursor) ~= 'string' or not cursor:match('^[0-9a-fA-F%-]+$') or #cursor ~= 36) then
        return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'cursor is invalid')
    end
    local rows = QBPhone.Repositories.Calls.listForDevice(device.id, limit, cursor)
    return PhoneResult({ items = rows, nextCursor = #rows == limit and rows[#rows].id or nil })
end

-- Relays a WebRTC offer/answer/ICE candidate to the other side of an active call.
-- Opaque to the server: the browsers on both ends are the ones that parse and
-- validate it as SDP/ICE, this just checks shape and bounds the size.
function Calling.videoSignal(source, payload)
    local call, device, err = activeOwnedCall(source, payload)
    if not call then return err end
    if call.status ~= 'active' then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Call is not active') end
    local signal, validationError = PhoneContracts.callSignal(payload)
    if not signal then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local targetDeviceId = device.id == call.callerDeviceId and call.calleeDeviceId or call.callerDeviceId
    local targetSource = sourceForDevice(targetDeviceId)
    if not targetSource then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'The other participant is unavailable') end
    TriggerClientEvent('qbphone:client:calls:signal', targetSource, { kind = signal.kind, sdp = signal.sdp, candidate = signal.candidate })
    return PhoneResult(true)
end

function Calling.voiceFailure(source, callId)
    local session = QBPhone.Sessions.bySource[source]
    local call = type(callId) == 'string' and Calling.activeById[callId] or nil
    if not session or not participant(call, session.deviceId) or call.status ~= 'active' then return end
    finish(call, 'ended', 'voice_unavailable')
end

function Calling.disconnect(source, reason)
    local session = QBPhone.Sessions.bySource[source]
    if not session then return end
    local callId = Calling.callByDevice[session.deviceId]
    local call = callId and Calling.activeById[callId]
    if call then finish(call, call.status == 'ringing' and 'cancelled' or 'ended', reason or 'disconnected') end
end

function Calling.shutdown(reason)
    local ids = {}
    for id in pairs(Calling.activeById) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local call = Calling.activeById[id]
        if call then finish(call, call.status == 'ringing' and 'cancelled' or 'ended', reason or 'resource_restart') end
    end
    QBPhone.Repositories.Calls.endUnfinished(reason or 'resource_restart')
end

AddEventHandler('playerDropped', function()
    Calling.disconnect(source, 'disconnected')
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    Calling.disconnect(source, 'character_unload')
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1000)
        pcall(QBPhone.Repositories.Calls.endUnfinished, 'resource_restart')
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Calling.shutdown('resource_restart') end
end)
