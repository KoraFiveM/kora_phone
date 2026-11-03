QBPhone = QBPhone or {}
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
    Video.cover=false
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
-- the QBPhone.Unavailable() check (cache + player-data exports) runs every 250 ms.
local watching = false
local function watchVideo()
    if watching then return end
    watching = true
    CreateThread(function()
        local nextUnavailableCheck = 0
        while Video.active do
            local call = QBPhone.State and QBPhone.State.activeCall
            local now = GetGameTimer()
            local unavailable = false
            if QBPhone.Unavailable and now >= nextUnavailableCheck then
                nextUnavailableCheck = now + 250
                unavailable = QBPhone.Unavailable()
            end
            if not QBPhone.State or not QBPhone.State.open or (not Video.cover and (not call or call.status ~= 'active'))
                or IsEntityDead(PlayerPedId()) or unavailable then
                Video.Cleanup()
                QBPhone.SendNui('video:stopped', { reason = 'Camera session ended' })
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

RegisterNUICallback('camera:videoStart', function(data, cb)
    if type(data) ~= 'table' or type(data.token) ~= 'string' or #data.token > 64 or #data.token < 1 then
        cb({ ok = false, error = 'Invalid camera session' })
        return
    end
    local call = QBPhone.State and QBPhone.State.activeCall
    if not QBPhone.State or not QBPhone.State.open or not call or call.status ~= 'active' then
        cb({ ok = false, error = 'An active call is required' })
        return
    end
    if IsEntityDead(PlayerPedId()) or (QBPhone.Unavailable and QBPhone.Unavailable()) then
        cb({ ok = false, error = 'PLAYER_DEAD' })
        return
    end
    if QBPhone.State.cameraMode then
        cb({ ok = false, error = 'Close the camera app before starting video' })
        return
    end
    if Video.active and Video.token ~= data.token then Video.Cleanup() end
    if not Video.active then
        Video.token = data.token
        Video.previousRadar = not IsRadarHidden()
        Video.front = true
        Video.camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        if not Video.camera or Video.camera == 0 then
            Video.camera = nil
            cb({ ok = false, error = 'Game camera could not start' })
            return
        end
        Video.active = true
        watchVideo()
        updateCamera()
        RenderScriptCams(true, false, 0, true, true)
        DisplayRadar(false)
    end
    cb({ ok = true })
end)

RegisterNUICallback('camera:videoStop', function(data, cb)
    if type(data) == 'table' and data.token == Video.token then Video.Cleanup() end
    cb({ ok = true })
end)

RegisterNUICallback('camera:videoFacing', function(data, cb)
    if not Video.active or type(data) ~= 'table' or data.token ~= Video.token or type(data.front) ~= 'boolean' then
        cb({ ok = false, error = 'Game camera is not active' })
        return
    end
    Video.front = data.front
    updateCamera()
    cb({ ok = true })
end)

RegisterNUICallback('camera:coverStart',function(data,cb)
    if type(data)~='table' then return cb({ok=false}) end
    if not data.active then
        if Video.cover then Video.Cleanup(); Video.cover=false end
        return cb({ok=true})
    end
    if not QBPhone.State.open or QBPhone.Unavailable() or QBPhone.State.cameraMode or Video.active then
        return cb({ok=false,error='Close the other camera first'})
    end
    Video.previousRadar=not IsRadarHidden(); Video.front=true; Video.cover=true
    Video.camera=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    if not Video.camera or Video.camera==0 then Video.camera=nil; Video.cover=false; return cb({ok=false,error='Camera unavailable'}) end
    Video.active=true; Video.token='cover'; watchVideo(); updateCamera()
    RenderScriptCams(true,false,0,true,true); DisplayRadar(false)
    cb({ok=true})
end)

RegisterNetEvent('qbphone:client:calls:ended', function() Video.Cleanup() end)
RegisterNetEvent('qbphone:client:reset', function() Video.Cleanup() end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() Video.Cleanup() end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Video.Cleanup() end
end)

QBPhone.Video = Video
