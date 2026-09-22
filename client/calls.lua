QBPhone = QBPhone or {}
local Calls = {}

local function validCall(call)
    return type(call) == 'table'
        and type(call.id) == 'string'
        and #call.id == 36
        and type(call.status) == 'string'
end

local function participantEvent(action, call)
    if not validCall(call) then return false end
    QBPhone.State.activeCall = call
    SendNUIMessage({ action = action, data = call })
    return true
end

RegisterNetEvent('qbphone:client:calls:incoming', function(call)
    if QBPhone.State.activeCall and QBPhone.State.activeCall.id ~= (call and call.id) then return end
    if participantEvent('calls:incoming', call) and not QBPhone.State.open then
        if QBPhone.State.quiet then
            -- Do Not Disturb: leave the phone closed and drop a silent note in the notification shade.
            SendNUIMessage({ action = 'notification:push', data = { title = tostring(call.remoteNumber or 'Unknown'), body = 'Incoming call · Do Not Disturb', app = 'phone' } })
        else
            -- The UI is hidden while the phone is closed, so open it or the call would ring unseen.
            QBPhone.Open()
        end
    end
end)

RegisterNetEvent('qbphone:client:calls:outgoing', function(call)
    if QBPhone.State.activeCall and QBPhone.State.activeCall.id ~= (call and call.id) then return end
    participantEvent('calls:outgoing', call)
end)

RegisterNetEvent('qbphone:client:calls:accepted', function(call)
    if not validCall(call) or type(call.voiceChannel) ~= 'number' then return end
    local current = QBPhone.State.activeCall
    if current and current.id ~= call.id then return end
    QBPhone.State.activeCall = call
    participantEvent('calls:accepted', call)
end)

-- A WebRTC offer/answer/ICE candidate from the other side of the call, passed straight to the NUI's own peer connection.
RegisterNetEvent('qbphone:client:calls:signal', function(signal)
    if type(signal) ~= 'table' then return end
    SendNUIMessage({ type = 'videoSignal', data = signal })
end)

RegisterNetEvent('qbphone:client:calls:ended', function(payload)
    if type(payload) ~= 'table' or type(payload.id) ~= 'string' then return end
    local current = QBPhone.State.activeCall
    if current and current.id ~= payload.id then return end
    QBPhone.Voice.Leave()
    QBPhone.State.activeCall = nil
    SendNUIMessage({ action = 'calls:ended', data = payload })
end)

function Calls.Cleanup(notifyServer)
    local call = QBPhone.State.activeCall
    QBPhone.Voice.Leave()
    QBPhone.State.activeCall = nil
    if notifyServer and call and call.id then
        TriggerServerEvent('qbphone:server:calls:hangup', call.id)
    end
end

function Calls.IsActive(callId)
    local call = QBPhone.State.activeCall
    return call ~= nil and (callId == nil or call.id == callId)
end

QBPhone.Calls = Calls
