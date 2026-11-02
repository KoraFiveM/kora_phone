QBPhone = QBPhone or {}
local Camera = { handle = nil, previousRadar = true, front=false, preview=false, looking=false }

local watchCamera

local function lookSettings()
    local cfg = Config and Config.Camera or {}
    local mode = cfg.lookMode
    if mode ~= 'toggle' and mode ~= 'off' then mode = 'hold' end
    return mode, cfg.lookKey or 'LMENU', cfg.hint ~= false
end

local function updateCamera()
    if not Camera.handle then return end
    local ped=PlayerPedId()
    if Camera.front then
        -- The selfie camera orbits to wherever the player is aiming the gameplay camera.
        local rot=GetGameplayCamRot(2)
        local pitch,yaw=math.rad(math.max(-30.0,math.min(30.0,rot.x))),math.rad(rot.z)
        local head=GetPedBoneCoords(ped,31086,0.0,0.0,0.0)
        SetCamCoord(Camera.handle,head.x-math.sin(yaw)*math.cos(pitch)*0.9,head.y+math.cos(yaw)*math.cos(pitch)*0.9,head.z+math.sin(pitch)*0.9)
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
    Camera.looking = false
    SetNuiFocusKeepInput(false)
    DisplayRadar(Camera.previousRadar)
    QBPhone.State.cameraMode = false
    QBPhone.SendNui('camera:closed')
end

function Camera.Open(options)
    options = type(options) == 'table' and options or {}
    if QBPhone.State.cameraMode then return true end
    local ped = Kora.cache.ped()
    if IsEntityDead(ped) then return false, 'PLAYER_DEAD' end
    if QBPhone.Video and QBPhone.Video.active then return false,'Close video before opening the camera' end
    Camera.previousRadar = not IsRadarHidden()
    QBPhone.State.cameraMode = true
    Camera.front=options.front == true
    Camera.handle=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    if not Camera.handle or Camera.handle==0 then Camera.handle=nil; QBPhone.State.cameraMode=false; return false,'CAMERA_UNAVAILABLE' end
    SetCamFov(Camera.handle,60.0); updateCamera(); RenderScriptCams(true,false,0,true,true)
    Camera.preview = options.preview == true
    Camera.looking = false
    SetNuiFocus(Camera.preview, Camera.preview)
    SetNuiFocusKeepInput(Camera.preview and lookSettings() ~= 'off')
    DisplayRadar(false)
    QBPhone.SendNui('phone:visibility', options.preview == true)
    watchCamera()
    return true
end

function Camera.SetFacing(front)
    if not QBPhone.State.cameraMode or type(front) ~= 'boolean' then return false end
    Camera.front = front
    updateCamera()
    return true
end

-- While the player holds the look key the cursor is released so the mouse aims the camera.
function Camera.SetLooking(on)
    if not QBPhone.State.cameraMode or not Camera.preview or lookSettings() == 'off' then return false end
    on = on == true
    if on == Camera.looking then return true end
    Camera.looking = on
    SetNuiFocus(not on, not on)
    SetNuiFocusKeepInput(not on)
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
    local reply, finished = done, false
    done = function(result)
        if finished then return end
        finished = true
        reply(result)
    end
    SetTimeout(30000, function()
        if finished then return end
        Camera.Close()
        done({ ok = false, error = { code = 'CAPTURE_TIMEOUT', message = 'Taking the photo timed out. Please try again.' } })
    end)
    QBPhone.ServerCallback('qbphone:server:requestMediaUpload', {
        mimeType = 'image/jpeg',
        -- This is only an upper-bound declaration. The provider verifies the actual size.
        byteSize = 8 * 1024 * 1024
    }, function(result)
        if finished then return end
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
        local started = pcall(function() exports['screenshot-basic']:requestScreenshotUpload(
            instruction.uploadUrl,
            type(instruction.field) == 'string' and instruction.field or 'file',
            { encoding = 'jpg', quality = 0.90 },
            function(responseBody)
                if finished then return end
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
        ) end)
        if not started then
            Camera.Close()
            done({ ok = false, error = 'UPLOAD_FAILED' })
        end
    end)
end

function Camera.Cleanup()
    if QBPhone.State.cameraMode or Camera.handle then finishMode() end
end

local function lookHint()
    local _, key = lookSettings()
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(Camera.looking and ('Aiming the camera. Release ' .. key .. ' to use the phone.') or ('Hold ' .. key .. ' and move the mouse to aim the camera.'))
    EndTextCommandDisplayHelp(0, false, false, -1)
end

do
    local mode, key = lookSettings()
    if mode ~= 'off' and RegisterCommand and RegisterKeyMapping then
        RegisterCommand('+kora_phone_camera_look', function()
            Camera.SetLooking(mode == 'toggle' and not Camera.looking or true)
        end, false)
        RegisterCommand('-kora_phone_camera_look', function()
            if mode == 'hold' then Camera.SetLooking(false) end
        end, false)
        RegisterKeyMapping('+kora_phone_camera_look', 'Phone camera: aim the camera', 'keyboard', key)
    end
end

-- The per-frame loop only exists while the camera is open: Camera.Open starts it and it ends itself once
-- cameraMode is cleared (finishMode / character reset).
local watching = false
function watchCamera()
    if watching then return end
    watching = true
    CreateThread(function()
        while QBPhone.State and QBPhone.State.cameraMode do
            Wait(0)
            updateCamera()
            local mode, _, hint = lookSettings()
            if hint and Camera.preview and mode ~= 'off' then lookHint() end
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            HideHudAndRadarThisFrame()
            if IsControlJustReleased(0, 177) then Camera.Close() end
        end
        watching = false
    end)
end

QBPhone.Camera = Camera
