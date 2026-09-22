SteviePhone = SteviePhone or {}
SteviePhone.QBCore = exports['qb-core']:GetCoreObject()

local pendingCallbacks = 0

function SteviePhone.ServerCallback(name, payload, done)
    if type(name) ~= 'string' or type(done) ~= 'function' then return end
    pendingCallbacks = pendingCallbacks + 1
    local generation = SteviePhone.State.generation
    SteviePhone.QBCore.Functions.TriggerCallback(name, function(result)
        pendingCallbacks = math.max(0, pendingCallbacks - 1)
        if generation ~= SteviePhone.State.generation then
            return done({ ok = false, error = 'SESSION_CHANGED' })
        end
        done(result or { ok = false, error = 'EMPTY_SERVER_RESPONSE' })
    end, payload or {})
end

-- Config.Client.DisableWhileDead: no phone while dead or in last stand (QBCore's isdead / inlaststand).
function SteviePhone.Unavailable()
    if not Config.Client.DisableWhileDead then return false end
    if IsEntityDead(PlayerPedId()) then return true end
    local data = SteviePhone.QBCore.Functions.GetPlayerData()
    local metadata = data and data.metadata or {}
    return metadata.isdead == true or metadata.inlaststand == true
end

function SteviePhone.Open(app, payload)
    if SteviePhone.State.open or not SteviePhone.State.playerLoaded or SteviePhone.Unavailable() then return false end
    SteviePhone.State.open = true
    SteviePhone.State.currentApp = type(app) == 'string' and app or nil
    SteviePhone.Animations.Start()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'phone:open',
        data = { app = SteviePhone.State.currentApp, payload = payload, state = SteviePhone.State.Public() }
    })
    return true
end

function SteviePhone.Close(force)
    SteviePhone.Camera.Cleanup()
    SteviePhone.Map.Cleanup()
    TriggerServerEvent('stevie-phone:server:phone:closed')
    SteviePhone.State.open = false
    SteviePhone.State.currentApp = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SteviePhone.Animations.Stop()
    SendNUIMessage({ action = force and 'phone:reset' or 'phone:close' })
end

function SteviePhone.Bootstrap()
    if not SteviePhone.State.playerLoaded then return end
    SteviePhone.ServerCallback('stevie-phone:server:getBootstrap', {}, function(result)
        if result.ok then
            SteviePhone.State.initialData = result.data
            SendNUIMessage({ action = 'bootstrap', data = result.data })
        else
            SendNUIMessage({ action = 'bootstrap:error', data = result })
        end
    end)
end

local function cleanupCharacter(notifyCallServer)
    SteviePhone.Close(true)
    SteviePhone.Calls.Cleanup(notifyCallServer)
    SteviePhone.State.ResetCharacter()
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    SteviePhone.State.playerLoaded = true
    SteviePhone.Bootstrap()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    cleanupCharacter(true)
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    if not SteviePhone.State.playerLoaded then return end
    SendNUIMessage({ action = 'player:update', data = {
        job = playerData and playerData.job or nil,
        money = playerData and playerData.money or nil,
    } })
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    SendNUIMessage({ action = 'job:update', data = job })
end)

RegisterNetEvent('stevie-phone:client:messages:new', function(message)
    SendNUIMessage({ action = 'messages:new', data = message })
end)

RegisterNetEvent('stevie-phone:client:mail:new', function(mail)
    if type(mail) ~= 'table' or type(mail.sender) ~= 'string' then return end
    SendNUIMessage({ action = 'mail:new', data = { sender = mail.sender:sub(1, 16), subject = tostring(mail.subject or ''):sub(1, 120) } })
end)

-- Sent by /phonereset: put the phone away and reload it so the setup screen comes back.
RegisterNetEvent('stevie-phone:client:reset', function()
    SteviePhone.Close(true)
    SteviePhone.Bootstrap()
end)

RegisterNetEvent('stevie-phone:client:messages:read', function(receipt)
    SendNUIMessage({ action = 'messages:read', data = receipt })
end)

RegisterCommand(Config.Client.Command, function()
    if SteviePhone.State.open then
        SteviePhone.Close(false)
    elseif not SteviePhone.Open() and SteviePhone.Unavailable() then
        SteviePhone.QBCore.Functions.Notify('You cannot use your phone right now', 'error', 3000)
    end
end, false)
RegisterKeyMapping(Config.Client.Command, 'Open phone', 'keyboard', Config.Client.Keybind)

exports('OpenPhone', SteviePhone.Open)
exports('ClosePhone', function() SteviePhone.Close(false) end)
exports('IsPhoneOpen', function() return SteviePhone.State.open end)
exports('PushNotification', function(notification) return SteviePhone.Notifications.Push(notification) end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SteviePhone.Close(true)
    SteviePhone.Calls.Cleanup(false)
end)

-- If the player goes down with the phone open, put it away instead of leaving it holding the mouse.
CreateThread(function()
    while true do
        Wait(500)
        if SteviePhone.State.open and SteviePhone.Unavailable() then SteviePhone.Close(false) end
    end
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(250) end
    local data = SteviePhone.QBCore.Functions.GetPlayerData()
    if data and data.citizenid then
        SteviePhone.State.playerLoaded = true
        SteviePhone.Bootstrap()
    end
end)
