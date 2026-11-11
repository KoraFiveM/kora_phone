KoraPhone = KoraPhone or {}

local pendingCallbacks = 0

function KoraPhone.ServerCallback(name, payload, done)
    if type(name) ~= 'string' or type(done) ~= 'function' then return end
    pendingCallbacks = pendingCallbacks + 1
    local generation = KoraPhone.State.generation
    CreateThread(function()
        -- Kora.callback.trigger raises on rejection (timeout, token mismatch, disconnect) rather than
        -- returning an error value; without pcall that kills this thread before done() runs, leaving the
        -- NUI promise that opened the phone unresolved and the UI stuck with focus forever.
        local ok, result = pcall(Kora.callback.trigger, name, payload or {})
        pendingCallbacks = math.max(0, pendingCallbacks - 1)
        if generation ~= KoraPhone.State.generation then
            return done({ ok = false, error = 'SESSION_CHANGED' })
        end
        if not ok then
            return done({ ok = false, error = tostring(result) })
        end
        done(result or { ok = false, error = 'EMPTY_SERVER_RESPONSE' })
    end)
end

-- Config.Client.DisableWhileDead: no phone while dead or in last stand (QBCore's isdead / inlaststand).
function KoraPhone.Unavailable()
    if not Config.Client.DisableWhileDead then return false end
    if Kora.cache.isDead() then return true end
    local data = exports.kora_core:getPlayerData()
    local metadata = data and data.metadata or {}
    return metadata.isdead == true or metadata.inlaststand == true
end

-- Puts the phone away if the player goes down while it is open. Only polls while the phone is open (started from
-- KoraPhone.Open and exits on close), so nothing runs with the phone in the pocket.
local watching = false
local function watchUnavailable()
    if watching then return end
    watching = true
    CreateThread(function()
        while KoraPhone.State.open do
            Wait(500)
            if KoraPhone.State.open and KoraPhone.Unavailable() then KoraPhone.Close(false) end
        end
        watching = false
    end)
end

-- True while another resource holds the phone shut through Config.Client.UiBlockBag.
function KoraPhone.UiBlocked()
    local name = Config.Client.UiBlockBag
    return type(name) == 'string' and name ~= '' and LocalPlayer.state[name] == true
end

-- Put an open phone away as soon as the block starts (state bag handler, no polling). The handler gets the new value
-- in change.value; the bag itself may still hold the old one.
do
    local name = Config.Client.UiBlockBag
    if type(name) == 'string' and name ~= '' then
        Kora.state.onChange(name, nil, function(change)
            if change.value ~= true or not KoraPhone.State.open then return end
            if change.bagName ~= ('player:%d'):format(GetPlayerServerId(PlayerId())) then return end
            KoraPhone.Close(false)
        end)
    end
end

function KoraPhone.Open(app, payload)
    if KoraPhone.State.open or not KoraPhone.State.playerLoaded or KoraPhone.Unavailable() or KoraPhone.UiBlocked() then return false end
    KoraPhone.State.open = true
    watchUnavailable()
    KoraPhone.State.currentApp = type(app) == 'string' and app or nil
    local started, animationError = pcall(KoraPhone.Animations.Start)
    if not started then print(('[kora_phone] phone animation failed: %s'):format(animationError)) end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    KoraPhone.SendNui('phone:open', { app = KoraPhone.State.currentApp, payload = payload, state = KoraPhone.State.Public() })
    return true
end

function KoraPhone.Close(force)
    if KoraPhone.Video then KoraPhone.Video.Cleanup(); KoraPhone.Video.cover=false end
    KoraPhone.Camera.Cleanup()
    TriggerServerEvent('kora_phone:server:phone:closed')
    KoraPhone.State.open = false
    KoraPhone.State.currentApp = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    KoraPhone.Animations.Stop()
    KoraPhone.SendNui(force and 'phone:reset' or 'phone:close')
end

RegisterNetEvent('kora_phone:client:sessionRevoked', function()
    KoraPhone.State.generation=KoraPhone.State.generation+1
    KoraPhone.Close(true)
    KoraPhone.Calls.Cleanup(false)
end)
RegisterNetEvent('kora_phone:client:useHandset',function()
    KoraPhone.Close(true)
    KoraPhone.Open()
end)
RegisterNetEvent('kora_phone:client:contentCleared',function() KoraPhone.SendNui('content:cleared',{}) end)
RegisterNetEvent('kora_phone:client:ready',function() KoraPhone.Bootstrap() end)

function KoraPhone.Bootstrap()
    if not KoraPhone.State.playerLoaded then return end
    KoraPhone.ServerCallback('kora_phone:server:getBootstrap', {}, function(result)
        if result.ok then
            KoraPhone.State.initialData = result.data
            KoraPhone.SendNui('bootstrap', result.data)
        else
            KoraPhone.SendNui('bootstrap:error', result)
        end
    end)
end

local function cleanupCharacter(notifyCallServer)
    KoraPhone.Close(true)
    KoraPhone.Calls.Cleanup(notifyCallServer)
    KoraPhone.State.ResetCharacter()
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    KoraPhone.State.playerLoaded = true
    KoraPhone.Bootstrap()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    cleanupCharacter(true)
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    if not KoraPhone.State.playerLoaded then return end
    KoraPhone.SendNui('player:update', {
        job = playerData and playerData.job or nil,
        money = playerData and playerData.money or nil,
    })
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    KoraPhone.SendNui('job:update', job)
end)

RegisterNetEvent('kora_phone:client:messages:new', function(message)
    KoraPhone.SendNui('messages:new', message)
    if not KoraPhone.State.open and type(message) == 'table' and not message.isMine then
        KoraPhone.SendNui('phone:peek', { title = tostring(message.senderNumber or 'New message'), body = tostring(message.body or ''):sub(1, 120) })
    end
end)

RegisterNetEvent('kora_phone:client:mail:new', function(mail)
    if type(mail) ~= 'table' or type(mail.sender) ~= 'string' then return end
    local player=exports.kora_core:getPlayerData()
    if mail.citizenId and (not player or mail.citizenId~=player.citizenid) then return end
    KoraPhone.SendNui('mail:new', { deviceId=mail.deviceId, sender = mail.sender:sub(1, 100), subject = tostring(mail.subject or ''):sub(1, 120) })
end)

-- Sent by /phonereset: put the phone away and reload it so the setup screen comes back.
RegisterNetEvent('kora_phone:client:reset', function()
    KoraPhone.Close(true)
    KoraPhone.Bootstrap()
end)

RegisterNetEvent('kora_phone:client:messages:read', function(receipt)
    KoraPhone.SendNui('messages:read', receipt)
end)

local function togglePhone()
    if KoraPhone.State.open then
        KoraPhone.Close(false)
    elseif not KoraPhone.Open() and KoraPhone.Unavailable() then
        local message = 'You cannot use your phone right now'
        if Config.Client.NoPhoneNoticeWhileDown then
            local ok, result = pcall(Kora.callback.trigger, 'kora_phone:server:hasPhone', {})
            if ok and result == false then message = "You don't have a phone" end
        end
        Kora.notify.send({ title = 'Phone', message = message, type = 'error', duration = 3000 })
    end
end

RegisterCommand(Config.Client.Command, togglePhone, false)
RegisterKeyMapping(Config.Client.Command, 'Open phone', 'keyboard', Config.Client.Keybind)

exports('OpenPhone', KoraPhone.Open)
exports('ClosePhone', function() KoraPhone.Close(false) end)
exports('IsPhoneOpen', function() return KoraPhone.State.open end)
exports('PushNotification', function(notification) return KoraPhone.Notifications.Push(notification) end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    KoraPhone.Close(true)
    KoraPhone.Calls.Cleanup(false)
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(250) end
    local data = exports.kora_core:getPlayerData()
    if data and data.citizenid then
        KoraPhone.State.playerLoaded = true
        KoraPhone.Bootstrap()
    end
end)