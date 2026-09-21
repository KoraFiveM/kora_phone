SteviePhone = SteviePhone or {}
local Calls = {}

local function validCall(call)
    return type(call) == 'table'
        and type(call.id) == 'string'
        and #call.id == 36
        and type(call.status) == 'string'
end

local function participantEvent(action, call)
    if not validCall(call) then return false end
    SteviePhone.State.activeCall = call
    SendNUIMessage({ action = action, data = call })
    return true
end

RegisterNetEvent('stevie-phone:client:calls:incoming', function(call)
    if SteviePhone.State.activeCall and SteviePhone.State.activeCall.id ~= (call and call.id) then return end
    if participantEvent('calls:incoming', call) and not SteviePhone.State.open then
        if SteviePhone.State.quiet then
            -- Do Not Disturb: leave the phone closed and drop a silent note in the notification shade.
            SendNUIMessage({ action = 'notification:push', data = { title = tostring(call.remoteNumber or 'Unknown'), body = 'Incoming call · Do Not Disturb', app = 'phone' } })
        else
            -- The UI is hidden while the phone is closed, so open it or the call would ring unseen.
            SteviePhone.Open()
        end
    end
end)

RegisterNetEvent('stevie-phone:client:calls:outgoing', function(call)
    if SteviePhone.State.activeCall and SteviePhone.State.activeCall.id ~= (call and call.id) then return end
    participantEvent('calls:outgoing', call)
end)

RegisterNetEvent('stevie-phone:client:calls:accepted', function(call)
    if not validCall(call) or type(call.voiceChannel) ~= 'number' then return end
    local current = SteviePhone.State.activeCall
    if current and current.id ~= call.id then return end
    SteviePhone.State.activeCall = call
    participantEvent('calls:accepted', call)
end)

RegisterNetEvent('stevie-phone:client:calls:ended', function(payload)
    if type(payload) ~= 'table' or type(payload.id) ~= 'string' then return end
    local current = SteviePhone.State.activeCall
    if current and current.id ~= payload.id then return end
    SteviePhone.Voice.Leave()
    SteviePhone.State.activeCall = nil
    SendNUIMessage({ action = 'calls:ended', data = payload })
end)

function Calls.Cleanup(notifyServer)
    local call = SteviePhone.State.activeCall
    SteviePhone.Voice.Leave()
    SteviePhone.State.activeCall = nil
    if notifyServer and call and call.id then
        TriggerServerEvent('stevie-phone:server:calls:hangup', call.id)
    end
end

function Calls.IsActive(callId)
    local call = SteviePhone.State.activeCall
    return call ~= nil and (callId == nil or call.id == callId)
end

SteviePhone.Calls = Calls
