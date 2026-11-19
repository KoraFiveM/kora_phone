KoraPhone = KoraPhone or {}
local Camera = {
    handle = nil,
    previousRadar = true,
    front = false,
    preview = false,
    looking = false,
    fov = nil,
    targetFov = nil,
    zoom = nil,
}

local watchCamera

local function lookSettings()
    local cfg = Config and Config.Camera or {}
    local mode = cfg.lookMode
    if mode ~= 'toggle' and mode ~= 'off' then mode = 'hold' end
    return mode, cfg.lookKey or 'LMENU', cfg.hint ~= false
end

-- Field of view the camera opened at before zoom existed; zoom.maxFov / defaultFov fall back to it.
local DEFAULT_FOV = 60.0

-- Read for the current facing: the selfie camera can narrow the range through zoom.selfie.
local function zoomSettings()
    local cfg = Config and Config.Camera and Config.Camera.zoom
    cfg = type(cfg) == 'table' and cfg or {}
    local lens = Camera.front and type(cfg.selfie) == 'table' and cfg.selfie or cfg
    local minFov = math.max(1.0, tonumber(lens.minFov) or tonumber(cfg.minFov) or 10.0)
    local maxFov = math.min(130.0, math.max(minFov, tonumber(lens.maxFov) or tonumber(cfg.maxFov) or DEFAULT_FOV))
    local fov = tonumber(lens.defaultFov) or tonumber(cfg.defaultFov) or DEFAULT_FOV
    return {
        enabled = cfg.enabled ~= false,
        minFov = minFov,
        maxFov = maxFov,
        fov = math.max(minFov, math.min(maxFov, fov)),
        step = math.abs(tonumber(cfg.step) or 5.0),
        smooth = cfg.smooth ~= false,
        speed = math.max(0.1, tonumber(cfg.smoothSpeed) or 10.0),
    }
end

local function resetZoom()
    Camera.zoom = zoomSettings()
    Camera.fov, Camera.targetFov = Camera.zoom.fov, Camera.zoom.fov
    if Camera.handle then SetCamFov(Camera.handle, Camera.fov) end
end

-- Eases the field of view towards the zoom target; called by the camera loop and a no-op once it gets there.
local function stepZoom()
    local fov, target = Camera.fov, Camera.targetFov
    if not Camera.handle or not fov or not target or fov == target then return end
    fov = fov + (target - fov) * math.min(1.0, GetFrameTime() * Camera.zoom.speed)
    if math.abs(target - fov) < 0.05 then fov = target end
    Camera.fov = fov
    SetCamFov(Camera.handle, fov)
end

local HEAD_BONE = 31086

-- The selfie camera orbits to wherever the player is aiming the gameplay camera.
local function updateSelfieCamera(ped)
    local rot = GetGameplayCamRot(2)
    local pitch = math.rad(math.max(-30.0, math.min(30.0, rot.x)))
    local yaw = math.rad(rot.z)
    local head = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
    local reach = math.cos(pitch) * 0.9
    SetCamCoord(
        Camera.handle,
        head.x - math.sin(yaw) * reach,
        head.y + math.cos(yaw) * reach,
        head.z + math.sin(pitch) * 0.9
    )
    PointCamAtPedBone(Camera.handle, ped, HEAD_BONE, 0.0, 0.0, 0.0, true)
end

local function updateRearCamera(ped)
    StopCamPointing(Camera.handle)
    local at = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.12, 0.03)
    local rot = GetGameplayCamRot(2)
    SetCamCoord(Camera.handle, at.x, at.y, at.z)
    SetCamRot(Camera.handle, rot.x, rot.y, rot.z, 2)
end

local function updateCamera()
    if not Camera.handle then return end
    local ped = PlayerPedId()
    if Camera.front then
        updateSelfieCamera(ped)
    else
        updateRearCamera(ped)
    end
end

local function finishMode()
    RenderScriptCams(false, true, 250, true, true)
    if Camera.handle and DoesCamExist(Camera.handle) then DestroyCam(Camera.handle, false) end
    Camera.handle = nil
    Camera.fov, Camera.targetFov, Camera.zoom = nil, nil, nil
    ClearFocus()
    Camera.looking = false
    SetNuiFocusKeepInput(false)
    DisplayRadar(Camera.previousRadar)
    KoraPhone.State.cameraMode = false
    KoraPhone.SendNui('camera:closed')
end

function Camera.Open(options)
    options = type(options) == 'table' and options or {}
    if KoraPhone.State.cameraMode then return true end
    local ped = Kora.cache.ped()
    if IsEntityDead(ped) then return false, 'PLAYER_DEAD' end
    if KoraPhone.UiBlocked and KoraPhone.UiBlocked() then return false, 'UI_BLOCKED' end
    if KoraPhone.Video and KoraPhone.Video.active then return false, Kora.lang('camera.close_video_first') end
    Camera.previousRadar = not IsRadarHidden()
    KoraPhone.State.cameraMode = true
    Camera.front = options.front == true
    Camera.handle = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not Camera.handle or Camera.handle == 0 then
        Camera.handle = nil
        KoraPhone.State.cameraMode = false
        return false, 'CAMERA_UNAVAILABLE'
    end
    resetZoom()
    updateCamera()
    RenderScriptCams(true, false, 0, true, true)
    Camera.preview = options.preview == true
    Camera.looking = false
    SetNuiFocus(Camera.preview, Camera.preview)
    SetNuiFocusKeepInput(Camera.preview and lookSettings() ~= 'off')
    DisplayRadar(false)
    KoraPhone.SendNui('phone:visibility', options.preview == true)
    watchCamera()
    return true
end

function Camera.SetFacing(front)
    if not KoraPhone.State.cameraMode or type(front) ~= 'boolean' then return false end
    -- Rear and selfie have their own zoom range, so flipping starts the new lens at its default view.
    if front ~= Camera.front then
        Camera.front = front
        resetZoom()
    end
    updateCamera()
    return true
end

-- dir 1 zooms in (narrower field of view), -1 zooms out, one step per call.
function Camera.Zoom(dir)
    if not KoraPhone.State.cameraMode or not Camera.handle or not Camera.zoom then return false end
    if dir ~= 1 and dir ~= -1 then return false end
    local zoom = Camera.zoom
    if not zoom.enabled then return false end
    Camera.targetFov = math.max(zoom.minFov, math.min(zoom.maxFov, (Camera.targetFov or zoom.fov) - dir * zoom.step))
    if not zoom.smooth then
        Camera.fov = Camera.targetFov
        SetCamFov(Camera.handle, Camera.fov)
    end
    return true
end

function Camera.ZoomEnabled()
    return (Camera.zoom or zoomSettings()).enabled
end

-- While the player holds the look key the cursor is released so the mouse aims the camera.
function Camera.SetLooking(on)
    if not KoraPhone.State.cameraMode or not Camera.preview or lookSettings() == 'off' then return false end
    on = on == true
    if on == Camera.looking then return true end
    Camera.looking = on
    -- Keep-input stays on for the whole preview so the key mapping still fires while the phone has focus
    -- (NUI focus without keep-input swallows every key). Releasing the cursor is what hands the mouse to the game.
    SetNuiFocus(not on, not on)
    KoraPhone.SendNui('camera:hint', { text = Camera.Hint() })
    return true
end

function Camera.Close()
    if not KoraPhone.State.cameraMode then return end
    finishMode()
    if KoraPhone.State.open then
        SetNuiFocus(true, true)
        KoraPhone.SendNui('phone:visibility', true)
    end
end

local CAPTURE_TIMEOUT_MS = 30000

-- A broker answers { receipt }, Fivemanage answers { data = { id } }.
local function receiptFrom(responseBody)
    if type(responseBody) ~= 'string' or #responseBody > 8192 then return nil end
    local ok, response = pcall(json.decode, responseBody)
    if not ok or type(response) ~= 'table' then return nil end
    local receipt = response.receipt or (type(response.data) == 'table' and response.data.id or nil)
    return type(receipt) == 'string' and receipt or nil
end

function Camera.Capture(done)
    done = done or function() end
    if not KoraPhone.State.cameraMode then return done({ ok = false, error = 'CAMERA_NOT_OPEN' }) end
    local reply, finished = done, false
    done = function(result)
        if finished then return end
        finished = true
        reply(result)
    end
    Kora.timers.setTimeout(function()
        if finished then return end
        Camera.Close()
        done({ ok = false, error = { code = 'CAPTURE_TIMEOUT', message = Kora.lang('camera.capture_timeout') } })
    end, CAPTURE_TIMEOUT_MS)
    KoraPhone.ServerCallback('kora_phone:server:requestMediaUpload', {
        mimeType = 'image/jpeg',
        -- This is only an upper-bound declaration. The provider verifies the actual size.
        byteSize = 8 * 1024 * 1024,
    }, function(result)
        if finished then return end
        if type(result) ~= 'table' or result.ok ~= true then return done(result) end
        local instruction = result.data and result.data.upload
        if type(instruction) ~= 'table' or type(instruction.token) ~= 'string' then
            return done({ ok = false, error = { code = 'INVALID_UPLOAD_INSTRUCTION' } })
        end

        if instruction.mode == 'server-capture' then
            return KoraPhone.ServerCallback('kora_phone:server:completeMediaUpload', {
                token = instruction.token,
            }, done)
        end

        local uploads = instruction.mode == 'multipart-upload' or instruction.mode == 'direct-upload'
        if not uploads or type(instruction.uploadUrl) ~= 'string' then
            return done({ ok = false, error = { code = 'UNSUPPORTED_UPLOAD_MODE' } })
        end

        -- uploadUrl is issued by the server's configured provider. NUI data can
        -- never supply or override it.
        local started = pcall(Kora.screenshot.requestScreenshotUpload,
            instruction.uploadUrl,
            type(instruction.field) == 'string' and instruction.field or 'file',
            { encoding = 'jpg', quality = 0.90 },
            function(responseBody)
                if finished then return end
                local receipt = receiptFrom(responseBody)
                if not receipt then
                    return done({ ok = false, error = { code = 'UPLOAD_FAILED' } })
                end
                KoraPhone.ServerCallback('kora_phone:server:completeMediaUpload', {
                    token = instruction.token,
                    receipt = receipt,
                }, done)
            end
        )
        if not started then
            Camera.Close()
            done({ ok = false, error = 'UPLOAD_FAILED' })
        end
    end)
end

function Camera.Cleanup()
    if KoraPhone.State.cameraMode or Camera.handle then finishMode() end
end

function Camera.MicSettings()
    local mic = type(Config.Camera.micAudio) == 'table' and Config.Camera.micAudio or {}
    return { enabled = mic.enabled == true, followVoice = mic.followVoice ~= false }
end

-- While a clip records, tell the UI when the player starts or stops talking (native voice state, the same one
-- kora_voice and the HUD use). Polls every 100 ms only while recording with the camera open.
local TALK_POLL_MS = 100

local function stopTalkWatch()
    Camera.recording = false
    if Camera.talkTimer then Kora.timers.clearInterval(Camera.talkTimer) end
    Camera.talkTimer = nil
end

function Camera.SetRecording(active)
    Camera.recording = active == true and KoraPhone.State.cameraMode == true
    if not Camera.recording then
        stopTalkWatch()
        return false
    end
    if Camera.talkTimer then return true end
    local last
    Camera.talkTimer = Kora.timers.setInterval(function()
        if not Camera.recording or not KoraPhone.State.cameraMode then return stopTalkWatch() end
        local talking = NetworkIsPlayerTalking(PlayerId()) == true
        if talking ~= last then
            last = talking
            KoraPhone.SendNui('camera:talking', { talking = talking })
        end
    end, TALK_POLL_MS)
    return true
end

-- The help line shown on the Camera screen (nil when it is turned off); sent with camera:open and on every aim change.
local KEY_NAMES = { LMENU = 'Left Alt', RMENU = 'Right Alt', LSHIFT = 'Left Shift', RSHIFT = 'Right Shift', LCONTROL = 'Left Ctrl', RCONTROL = 'Right Ctrl' }

function Camera.Hint()
    local mode, key, hint = lookSettings()
    if not hint or not Camera.preview or mode == 'off' then return nil end
    key = KEY_NAMES[key] or key
    local text = Camera.looking and Kora.lang('camera.hint_aiming', key) or Kora.lang('camera.hint_hold', key)
    if Camera.zoom and Camera.zoom.enabled then text = text .. Kora.lang('camera.hint_zoom') end
    return text
end

-- Aiming key: held (or toggled) to release the cursor so the mouse aims the camera. Kora.keybind makes it rebindable.
do
    local mode, key = lookSettings()
    if mode ~= 'off' then
        Kora.keybind.add({
            name = 'kora_phone_camera_look',
            description = Kora.lang('keybind.camera_look'),
            defaultKey = key,
            onPressed = function()
                Camera.SetLooking(mode == 'toggle' and not Camera.looking or true)
            end,
            onReleased = function()
                if mode == 'hold' then Camera.SetLooking(false) end
            end,
        })
    end
end

-- The per-frame loop only exists while the camera is open: Camera.Open starts it and it ends itself once
-- cameraMode is cleared (finishMode / character reset).
local watching = false
-- Every control bound to the mouse wheel (weapon wheel, weapon select on foot and in vehicles, cursor scroll).
-- Weapon wheel, attack, aim, cover: nothing but the camera should react while it is up.
local blockedControls = { 19, 24, 25, 37, 44 }
local wheelControls = { 14, 15, 16, 17, 99, 100, 241, 242, 261, 262 }
local WHEEL_UP = { 241, 15, 17 }
local WHEEL_DOWN = { 242, 14, 16 }

local function wheelPressed(controls)
    for i = 1, #controls do
        if IsDisabledControlJustPressed(0, controls[i]) then return true end
    end
    return false
end

local function wheelDirection()
    if wheelPressed(WHEEL_UP) then return 1 end
    if wheelPressed(WHEEL_DOWN) then return -1 end
end
function watchCamera()
    if watching then return end
    watching = true
    CreateThread(function()
        while KoraPhone.State and KoraPhone.State.cameraMode do
            Wait(0)
            updateCamera()
            stepZoom()
            -- The wheel zooms instead of cycling weapons. While the phone cursor is up the NUI receives the wheel
            -- and forwards it (camera:zoom), so the game-side wheel is only read while the game has the mouse.
            for i = 1, #wheelControls do DisableControlAction(0, wheelControls[i], true) end
            if not Camera.preview or Camera.looking then
                local dir = wheelDirection()
                if dir then Camera.Zoom(dir) end
            end
            -- With the phone cursor up the view is frozen: keep-input would otherwise let the mouse rotate the
            -- camera while the player is trying to reach the capture button. Only the look key unfreezes it.
            if Camera.preview and not Camera.looking then
                for control = 1, 6 do DisableControlAction(0, control, true) end
            end
            for i = 1, #blockedControls do DisableControlAction(0, blockedControls[i], true) end
            HideHudAndRadarThisFrame()
            if IsControlJustReleased(0, 177) then Camera.Close() end
        end
        watching = false
    end)
end

-- NUI focus is released by the engine on stop; this also drops the scripted camera and keep-input flag.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if KoraPhone.State.cameraMode or Camera.handle then
        finishMode()
        SetNuiFocus(false, false)
    end
end)

KoraPhone.Camera = Camera