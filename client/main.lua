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

-- Puts the phone away when the player goes down while it is open. Event driven: the cache fires on death and
-- kora_core's mirror fires when the last-stand / dead metadata flags change, so nothing polls.
local function closeIfUnavailable()
    if KoraPhone.State.open and KoraPhone.Unavailable() then KoraPhone.Close(false) end
end

Kora.cache.onChange('isDead', function(dead)
    if dead then closeIfUnavailable() end
end)

exports.kora_core:onPlayerDataChange({ 'metadata' }, function()
    closeIfUnavailable()
end)

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
    if KoraPhone.State.open or not KoraPhone.State.playerLoaded then return false end
    if KoraPhone.Unavailable() or KoraPhone.UiBlocked() then return false end
    KoraPhone.State.open = true
    KoraPhone.State.currentApp = type(app) == 'string' and app or nil
    local started, animationError = pcall(KoraPhone.Animations.Start)
    if not started then
        Kora.logging.error('phone.animation_failed', 'Phone animation failed', { error = tostring(animationError) })
    end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    KoraPhone.SendNui('phone:open', {
        app = KoraPhone.State.currentApp,
        payload = payload,
        state = KoraPhone.State.Public(),
    })
    return true
end

function KoraPhone.Close(force)
    if KoraPhone.Video then
        KoraPhone.Video.Cleanup()
        KoraPhone.Video.cover = false
    end
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
    KoraPhone.State.generation = KoraPhone.State.generation + 1
    KoraPhone.Close(true)
    KoraPhone.Calls.Cleanup(false)
end)

RegisterNetEvent('kora_phone:client:useHandset', function()
    KoraPhone.Close(true)
    KoraPhone.Open()
end)

RegisterNetEvent('kora_phone:client:contentCleared', function()
    KoraPhone.SendNui('content:cleared', {})
end)

RegisterNetEvent('kora_phone:client:ready', function()
    KoraPhone.Bootstrap()
end)

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

-- kora_core raises this locally for every snapshot, including a resync of the same character, so only a
-- different character (or none loaded yet) starts a session.
local function startSession(playerData)
    local citizenId = type(playerData) == 'table' and playerData.citizenid or nil
    if not citizenId or (KoraPhone.State.playerLoaded and KoraPhone.State.citizenId == citizenId) then return end
    KoraPhone.State.playerLoaded = true
    KoraPhone.State.citizenId = citizenId
    KoraPhone.Bootstrap()
end

AddEventHandler('kora_core:client:playerLoaded', startSession)

AddEventHandler('kora_core:client:playerLoggedOut', function()
    cleanupCharacter(true)
end)

-- Job and money changes arrive as one mirror op each; coalesce a burst into a single UI update.
local pushPlayerUpdate = Kora.timers.debounce(function()
    if not KoraPhone.State.playerLoaded then return end
    local data = exports.kora_core:getPlayerData() or {}
    KoraPhone.SendNui('player:update', { job = data.job, money = data.money })
end, 50)

local pushJobUpdate = Kora.timers.debounce(function()
    if not KoraPhone.State.playerLoaded then return end
    local data = exports.kora_core:getPlayerData() or {}
    KoraPhone.SendNui('job:update', data.job)
end, 50)

exports.kora_core:onPlayerDataChange({ 'job' }, function()
    pushJobUpdate.run()
    pushPlayerUpdate.run()
end)

exports.kora_core:onPlayerDataChange({ 'money' }, function()
    pushPlayerUpdate.run()
end)

RegisterNetEvent('kora_phone:client:messages:new', function(message)
    KoraPhone.SendNui('messages:new', message)
    if KoraPhone.State.open or type(message) ~= 'table' or message.isMine then return end
    KoraPhone.SendNui('phone:peek', {
        title = tostring(message.senderNumber or Kora.lang('notify.new_message')),
        body = tostring(message.body or ''):sub(1, 120),
    })
end)

RegisterNetEvent('kora_phone:client:mail:new', function(mail)
    if type(mail) ~= 'table' or type(mail.sender) ~= 'string' then return end
    local player = exports.kora_core:getPlayerData()
    if mail.citizenId and (not player or mail.citizenId ~= player.citizenid) then return end
    KoraPhone.SendNui('mail:new', {
        deviceId = mail.deviceId,
        sender = mail.sender:sub(1, 100),
        subject = tostring(mail.subject or ''):sub(1, 120),
    })
end)

-- A system activity note was stored for this character: tell the Mail app to refresh its Activity list.
RegisterNetEvent('kora_phone:client:activity:new', function(data)
    local player = exports.kora_core:getPlayerData()
    if type(data) ~= 'table' or not player or data.citizenId ~= player.citizenid then return end
    KoraPhone.SendNui('mail:activity')
end)

-- Sent by /phonereset: put the phone away and reload it so the setup screen comes back.
RegisterNetEvent('kora_phone:client:reset', function()
    KoraPhone.Close(true)
    KoraPhone.Bootstrap()
end)

RegisterNetEvent('kora_phone:client:messages:read', function(receipt)
    KoraPhone.SendNui('messages:read', receipt)
end)

local function unavailableMessage()
    if Config.Client.NoPhoneNoticeWhileDown then
        local ok, hasPhone = pcall(Kora.callback.trigger, 'kora_phone:server:hasPhone', {})
        if ok and hasPhone == false then return Kora.lang('notify.no_phone') end
    end
    return Kora.lang('notify.phone_unavailable')
end

local function togglePhone()
    if KoraPhone.State.open then
        KoraPhone.Close(false)
    elseif not KoraPhone.Open() and KoraPhone.Unavailable() then
        Kora.notify.send({
            title = Kora.lang('title.phone'),
            message = unavailableMessage(),
            type = 'error',
            duration = 3000,
        })
    end
end

-- /phone stays a typed command (Kora.commands is server-side and would add a round trip to open the phone);
-- the key goes through Kora.keybind so it is rebindable in the game's key settings.
RegisterCommand(Config.Client.Command, togglePhone, false)

Kora.keybind.add({
    name = 'kora_phone_toggle',
    description = Kora.lang('keybind.open_phone'),
    defaultKey = Config.Client.Keybind,
    onPressed = togglePhone,
})

exports('OpenPhone', KoraPhone.Open)
exports('ClosePhone', function() KoraPhone.Close(false) end)
exports('IsPhoneOpen', function() return KoraPhone.State.open end)
exports('PushNotification', function(notification) return KoraPhone.Notifications.Push(notification) end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    KoraPhone.Close(true)
    KoraPhone.Calls.Cleanup(false)
end)

-- A restart of this resource while a character is already in the world: the mirror exists, no event will come.
CreateThread(function()
    startSession(exports.kora_core:getPlayerData())
end)
