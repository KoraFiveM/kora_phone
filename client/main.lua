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
    if QB.cache.isDead() then return true end
    local data = SteviePhone.QBCore.Functions.GetPlayerData()
    local metadata = data and data.metadata or {}
    return metadata.isdead == true or metadata.inlaststand == true
end

function SteviePhone.Open(app, payload)
    if SteviePhone.State.open or not SteviePhone.State.playerLoaded or SteviePhone.Unavailable() then return false end
    SteviePhone.State.open = true
    SteviePhone.State.currentApp = type(app) == 'string' and app or nil
    SteviePhone.Animations.Start()
    QB.nui.setFocus(true, true)
    SetNuiFocusKeepInput(false)
    QB.nui.send('phone:open', { app = SteviePhone.State.currentApp, payload = payload, state = SteviePhone.State.Public() })
    return true
end

function SteviePhone.Close(force)
    SteviePhone.Camera.Cleanup()
    SteviePhone.Map.Cleanup()
    TriggerServerEvent('stevie-phone:server:phone:closed')
    SteviePhone.State.open = false
    SteviePhone.State.currentApp = nil
    QB.nui.setFocus(false, false)
    SetNuiFocusKeepInput(false)
    SteviePhone.Animations.Stop()
    QB.nui.send(force and 'phone:reset' or 'phone:close')
end

function SteviePhone.Bootstrap()
    if not SteviePhone.State.playerLoaded then return end
    SteviePhone.ServerCallback('stevie-phone:server:getBootstrap', {}, function(result)
        if result.ok then
            SteviePhone.State.initialData = result.data
            QB.nui.send('bootstrap', result.data)
        else
            QB.nui.send('bootstrap:error', result)
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
    QB.nui.send('player:update', {
        job = playerData and playerData.job or nil,
        money = playerData and playerData.money or nil,
    })
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    QB.nui.send('job:update', job)
end)

RegisterNetEvent('stevie-phone:client:messages:new', function(message)
    QB.nui.send('messages:new', message)
end)

RegisterNetEvent('stevie-phone:client:mail:new', function(mail)
    if type(mail) ~= 'table' or type(mail.sender) ~= 'string' then return end
    QB.nui.send('mail:new', { sender = mail.sender:sub(1, 16), subject = tostring(mail.subject or ''):sub(1, 120) })
end)

RegisterNetEvent('stevie-phone:client:messages:read', function(receipt)
    QB.nui.send('messages:read', receipt)
end)

local function togglePhone()
    if SteviePhone.State.open then
        SteviePhone.Close(false)
    elseif not SteviePhone.Open() and SteviePhone.Unavailable() then
        QB.notify.send({ title = 'Phone', message = 'You cannot use your phone right now', type = 'error', duration = 3000 })
    end
end

RegisterCommand(Config.Client.Command, togglePhone, false)

QB.keybind.add({
    name = 'stevie-phone:open',
    description = 'Open phone',
    defaultKey = Config.Client.Keybind,
    onPressed = togglePhone,
})

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
