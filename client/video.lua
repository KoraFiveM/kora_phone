KoraPhone = KoraPhone or {}
local Video = { active = false, camera = nil, front = true, previousRadar = true }

local function updateCamera()
    if not Video.camera then return end
    local ped = PlayerPedId()
    if Video.front then
        local position = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.9, 0.65)
        SetCamCoord(Video.camera, position.x, position.y, position.z)
        PointCamAtPedBone(Video.camera, ped, 31086, 0.0, 0.0, 0.0, true)
        SetCamFov(Video.camera, 48.0)
    else
        StopCamPointing(Video.camera)
        local position = GetPedBoneCoords(ped, 31086, 0.0, 0.12, 0.03)
        SetCamCoord(Video.camera, position.x, position.y, position.z)
        local rotation = GetGameplayCamRot(2)
        SetCamRot(Video.camera, rotation.x, rotation.y, rotation.z, 2)
        SetCamFov(Video.camera, 60.0)
    end
end

function Video.Cleanup()
    Video.cover = false
    if not Video.active and not Video.camera then return end
    Video.active = false
    if Video.camera then
        RenderScriptCams(false, false, 0, true, true)
        if DoesCamExist(Video.camera) then DestroyCam(Video.camera, false) end
    end
    Video.camera = nil
    Video.token = nil
    ClearFocus()
    DisplayRadar(Video.previousRadar)
end

-- The per-frame loop only exists while a video call camera (or cover) is active; it is started from the two places
-- that set Video.active and ends itself once Video.Cleanup() clears it. The death check stays per frame (a native),
-- the KoraPhone.Unavailable() check (cache + player-data exports) runs every 250 ms.
local watching = false
local function watchVideo()
    if watching then return end
    watching = true
    CreateThread(function()
        local nextUnavailableCheck = 0
        while Video.active do
            local call = KoraPhone.State and KoraPhone.State.activeCall
            local now = GetGameTimer()
            local unavailable = false
            if KoraPhone.Unavailable and now >= nextUnavailableCheck then
                nextUnavailableCheck = now + 250
                unavailable = KoraPhone.Unavailable()
            end
            if not KoraPhone.State or not KoraPhone.State.open or (not Video.cover and (not call or call.status ~= 'active'))
                or IsEntityDead(PlayerPedId()) or unavailable then
                Video.Cleanup()
                KoraPhone.SendNui('video:stopped', { reason = Kora.lang('video.session_ended') })
            else
                updateCamera()
                HideHudAndRadarThisFrame()
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 37, true)
            end
            Wait(0)
        end
        watching = false
    end)
end

local function validToken(token)
    return type(token) == 'string' and #token >= 1 and #token <= 64
end

local function startCamera()
    local handle = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not handle or handle == 0 then return false end
    Video.camera = handle
    Video.active = true
    watchVideo()
    updateCamera()
    RenderScriptCams(true, false, 0, true, true)
    DisplayRadar(false)
    return true
end

local function failure(message)
    return { ok = false, error = message }
end

KoraPhone.RegisterNui('camera:videoStart', function(data, reply)
    if not validToken(data.token) then return reply(failure(Kora.lang('video.invalid_session'))) end
    local call = KoraPhone.State and KoraPhone.State.activeCall
    if not KoraPhone.State or not KoraPhone.State.open or not call or call.status ~= 'active' then
        return reply(failure(Kora.lang('video.call_required')))
    end
    if IsEntityDead(PlayerPedId()) or (KoraPhone.Unavailable and KoraPhone.Unavailable()) then
        return reply(failure('PLAYER_DEAD'))
    end
    if KoraPhone.State.cameraMode then return reply(failure(Kora.lang('camera.close_camera_first'))) end
    if Video.active and Video.token ~= data.token then Video.Cleanup() end
    if not Video.active then
        Video.token = data.token
        Video.previousRadar = not IsRadarHidden()
        Video.front = true
        if not startCamera() then
            Video.camera = nil
            return reply(failure(Kora.lang('video.game_camera_failed')))
        end
    end
    reply({ ok = true })
end)

KoraPhone.RegisterNui('camera:videoStop', function(data, reply)
    if data.token == Video.token then Video.Cleanup() end
    reply({ ok = true })
end)

KoraPhone.RegisterNui('camera:videoFacing', function(data, reply)
    if not Video.active or data.token ~= Video.token or type(data.front) ~= 'boolean' then
        return reply(failure(Kora.lang('video.game_camera_inactive')))
    end
    Video.front = data.front
    updateCamera()
    reply({ ok = true })
end)

KoraPhone.RegisterNui('camera:coverStart', function(data, reply)
    if not data.active then
        if Video.cover then Video.Cleanup() end
        return reply({ ok = true })
    end
    if not KoraPhone.State.open or KoraPhone.Unavailable() or KoraPhone.State.cameraMode or Video.active then
        return reply(failure(Kora.lang('camera.close_other_camera')))
    end
    Video.previousRadar = not IsRadarHidden()
    Video.front = true
    Video.cover = true
    Video.token = 'cover'
    if not startCamera() then
        Video.camera = nil
        Video.cover = false
        Video.token = nil
        return reply(failure(Kora.lang('camera.camera_unavailable')))
    end
    reply({ ok = true })
end)

RegisterNetEvent('kora_phone:client:calls:ended', function() Video.Cleanup() end)
RegisterNetEvent('kora_phone:client:reset', function() Video.Cleanup() end)
AddEventHandler('kora_core:client:playerLoggedOut', function() Video.Cleanup() end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Video.Cleanup() end
end)

KoraPhone.Video = Video
