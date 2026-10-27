QBPhone = QBPhone or {}
local Camera = { handle = nil, previousRadar = true, front=false }
local function updateCamera()
    if not Camera.handle then return end
    local ped=PlayerPedId()
    if Camera.front then
        local p=GetOffsetFromEntityInWorldCoords(ped,0.0,0.9,0.65)
        SetCamCoord(Camera.handle,p.x,p.y,p.z)
        PointCamAtPedBone(Camera.handle,ped,31086,0.0,0.0,0.0,true)
    else
        StopCamPointing(Camera.handle)
        local p=GetPedBoneCoords(ped,31086,0.0,0.12,0.03)
        local rot=GetGameplayCamRot(2)
        SetCamCoord(Camera.handle,p.x,p.y,p.z); SetCamRot(Camera.handle,rot.x,rot.y,rot.z,2)
    end
end

local function finishMode()
    RenderScriptCams(false, true, 250, true, true)
    if Camera.handle and DoesCamExist(Camera.handle) then DestroyCam(Camera.handle, false) end
    Camera.handle = nil
    ClearFocus()
    DisplayRadar(Camera.previousRadar)
    QBPhone.State.cameraMode = false
    QBPhone.SendNui('camera:closed')
end

function Camera.Open()
    if QBPhone.State.cameraMode then return true end
    local ped = QB.cache.ped()
    if IsEntityDead(ped) then return false, 'PLAYER_DEAD' end
    if QBPhone.Video and QBPhone.Video.active then return false,'Close video before opening the camera' end
    Camera.previousRadar = not IsRadarHidden()
    QBPhone.State.cameraMode = true
    Camera.front=false
    Camera.handle=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    if not Camera.handle or Camera.handle==0 then Camera.handle=nil; QBPhone.State.cameraMode=false; return false,'CAMERA_UNAVAILABLE' end
    SetCamFov(Camera.handle,60.0); updateCamera(); RenderScriptCams(true,false,0,true,true)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    DisplayRadar(false)
    QBPhone.SendNui('phone:visibility', false)
    return true
end

function Camera.Close()
    if not QBPhone.State.cameraMode then return end
    finishMode()
    if QBPhone.State.open then
        SetNuiFocus(true, true)
        QBPhone.SendNui('phone:visibility', true)
    end
end

function Camera.Capture(done)
    done = done or function() end
    if not QBPhone.State.cameraMode then return done({ ok = false, error = 'CAMERA_NOT_OPEN' }) end
    if GetResourceState('screenshot-basic') ~= 'started' then
        return done({ ok = false, error = 'SCREENSHOT_PROVIDER_UNAVAILABLE' })
    end
    QBPhone.ServerCallback('qbphone:server:requestMediaUpload', {
        mimeType = 'image/jpeg',
        -- This is only an upper-bound declaration. The provider verifies the actual size.
        byteSize = 8 * 1024 * 1024
    }, function(result)
        if type(result) ~= 'table' or result.ok ~= true then return done(result) end
        local instruction = result.data and result.data.upload
        if type(instruction) ~= 'table' or type(instruction.token) ~= 'string' then
            return done({ ok = false, error = { code = 'INVALID_UPLOAD_INSTRUCTION' } })
        end

        if instruction.mode == 'server-capture' then
            return QBPhone.ServerCallback('qbphone:server:completeMediaUpload', {
                token = instruction.token
            }, done)
        end

        if (instruction.mode ~= 'multipart-upload' and instruction.mode ~= 'direct-upload') or type(instruction.uploadUrl) ~= 'string' then
            return done({ ok = false, error = { code = 'UNSUPPORTED_UPLOAD_MODE' } })
        end

        -- uploadUrl is issued by the server's configured provider. NUI data can
        -- never supply or override it.
        exports['screenshot-basic']:requestScreenshotUpload(
            instruction.uploadUrl,
            type(instruction.field) == 'string' and instruction.field or 'file',
            { encoding = 'jpg', quality = 0.90 },
            function(responseBody)
                local receipt
                if type(responseBody) == 'string' and #responseBody <= 8192 then
                    local ok, response = pcall(json.decode, responseBody)
                    -- A broker answers { receipt }, Fivemanage answers { data = { id } }.
                    if ok and type(response) == 'table' then receipt = response.receipt or (type(response.data) == 'table' and response.data.id or nil) end
                end
                if type(receipt) ~= 'string' then
                    return done({ ok = false, error = { code = 'UPLOAD_FAILED' } })
                end
                QBPhone.ServerCallback('qbphone:server:completeMediaUpload', {
                    token = instruction.token,
                    receipt = receipt
                }, done)
            end
        )
    end)
end

function Camera.Cleanup()
    if QBPhone.State.cameraMode or Camera.handle then finishMode() end
end

CreateThread(function()
    while true do
        if QBPhone.State and QBPhone.State.cameraMode then
            Wait(0)
            updateCamera()
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            HideHudAndRadarThisFrame()
            if IsControlJustReleased(0, 177) then Camera.Close() end
            if IsControlJustReleased(0, 38) then Camera.front=not Camera.front end
        else
            Wait(500)
        end
    end
end)

QBPhone.Camera = Camera
