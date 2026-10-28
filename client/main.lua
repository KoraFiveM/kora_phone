QBPhone = QBPhone or {}

local pendingCallbacks = 0

function QBPhone.ServerCallback(name, payload, done)
    if type(name) ~= 'string' or type(done) ~= 'function' then return end
    pendingCallbacks = pendingCallbacks + 1
    local generation = QBPhone.State.generation
    CreateThread(function()
        local result = QB.callback.trigger(name, payload or {})
        pendingCallbacks = math.max(0, pendingCallbacks - 1)
        if generation ~= QBPhone.State.generation then
            return done({ ok = false, error = 'SESSION_CHANGED' })
        end
        done(result or { ok = false, error = 'EMPTY_SERVER_RESPONSE' })
    end)
end

-- Config.Client.DisableWhileDead: no phone while dead or in last stand (QBCore's isdead / inlaststand).
function QBPhone.Unavailable()
    if not Config.Client.DisableWhileDead then return false end
    if QB.cache.isDead() then return true end
    local data = exports.kora_core:getPlayerData()
    local metadata = data and data.metadata or {}
    return metadata.isdead == true or metadata.inlaststand == true
end

function QBPhone.Open(app, payload)
    if QBPhone.State.open or not QBPhone.State.playerLoaded or QBPhone.Unavailable() then return false end
    QBPhone.State.open = true
    QBPhone.State.currentApp = type(app) == 'string' and app or nil
    local started, animationError = pcall(QBPhone.Animations.Start)
    if not started then print(('[qbphone] phone animation failed: %s'):format(animationError)) end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    QBPhone.SendNui('phone:open', { app = QBPhone.State.currentApp, payload = payload, state = QBPhone.State.Public() })
    return true
end

function QBPhone.Close(force)
    if QBPhone.Video then QBPhone.Video.Cleanup(); QBPhone.Video.cover=false end
    QBPhone.Camera.Cleanup()
    TriggerServerEvent('qbphone:server:phone:closed')
    QBPhone.State.open = false
    QBPhone.State.currentApp = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    QBPhone.Animations.Stop()
    QBPhone.SendNui(force and 'phone:reset' or 'phone:close')
end

RegisterNetEvent('qbphone:client:sessionRevoked', function()
    QBPhone.State.generation=QBPhone.State.generation+1
    QBPhone.Close(true)
    QBPhone.Calls.Cleanup(false)
end)
RegisterNetEvent('qbphone:client:useHandset',function()
    QBPhone.Close(true)
    QBPhone.Open()
end)
RegisterNetEvent('qbphone:client:contentCleared',function() QBPhone.SendNui('content:cleared',{}) end)
RegisterNetEvent('qbphone:client:ready',function() QBPhone.Bootstrap() end)

function QBPhone.Bootstrap()
    if not QBPhone.State.playerLoaded then return end
    QBPhone.ServerCallback('qbphone:server:getBootstrap', {}, function(result)
        if result.ok then
            QBPhone.State.initialData = result.data
            QBPhone.SendNui('bootstrap', result.data)
        else
            QBPhone.SendNui('bootstrap:error', result)
        end
    end)
end

local function cleanupCharacter(notifyCallServer)
    QBPhone.Close(true)
    QBPhone.Calls.Cleanup(notifyCallServer)
    QBPhone.State.ResetCharacter()
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    QBPhone.State.playerLoaded = true
    QBPhone.Bootstrap()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    cleanupCharacter(true)
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    if not QBPhone.State.playerLoaded then return end
    QBPhone.SendNui('player:update', {
        job = playerData and playerData.job or nil,
        money = playerData and playerData.money or nil,
    })
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    QBPhone.SendNui('job:update', job)
end)

RegisterNetEvent('qbphone:client:messages:new', function(message)
    QBPhone.SendNui('messages:new', message)
end)

RegisterNetEvent('qbphone:client:mail:new', function(mail)
    if type(mail) ~= 'table' or type(mail.sender) ~= 'string' then return end
    local player=exports.kora_core:getPlayerData()
    if mail.citizenId and (not player or mail.citizenId~=player.citizenid) then return end
    QBPhone.SendNui('mail:new', { deviceId=mail.deviceId, sender = mail.sender:sub(1, 100), subject = tostring(mail.subject or ''):sub(1, 120) })
end)

-- Sent by /phonereset: put the phone away and reload it so the setup screen comes back.
RegisterNetEvent('qbphone:client:reset', function()
    QBPhone.Close(true)
    QBPhone.Bootstrap()
end)

RegisterNetEvent('qbphone:client:messages:read', function(receipt)
    QBPhone.SendNui('messages:read', receipt)
end)

local function togglePhone()
    if QBPhone.State.open then
        QBPhone.Close(false)
    elseif not QBPhone.Open() and QBPhone.Unavailable() then
        QB.notify.send({ title = 'Phone', message = 'You cannot use your phone right now', type = 'error', duration = 3000 })
    end
end

RegisterCommand(Config.Client.Command, togglePhone, false)
RegisterKeyMapping(Config.Client.Command, 'Open phone', 'keyboard', Config.Client.Keybind)

exports('OpenPhone', QBPhone.Open)
exports('ClosePhone', function() QBPhone.Close(false) end)
exports('IsPhoneOpen', function() return QBPhone.State.open end)
exports('PushNotification', function(notification) return QBPhone.Notifications.Push(notification) end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    QBPhone.Close(true)
    QBPhone.Calls.Cleanup(false)
end)

-- If the player goes down with the phone open, put it away instead of leaving it holding the mouse.
CreateThread(function()
    while true do
        Wait(500)
        if QBPhone.State.open and QBPhone.Unavailable() then QBPhone.Close(false) end
    end
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(250) end
    local data = exports.kora_core:getPlayerData()
    if data and data.citizenid then
        QBPhone.State.playerLoaded = true
        QBPhone.Bootstrap()
    end
end)
