SteviePhone = SteviePhone or {}
local Camera = { handle = nil, previousRadar = true }

local function finishMode()
    RenderScriptCams(false, true, 250, true, true)
    if Camera.handle and DoesCamExist(Camera.handle) then DestroyCam(Camera.handle, false) end
    Camera.handle = nil
    ClearFocus()
    DisplayRadar(Camera.previousRadar)
    SteviePhone.State.cameraMode = false
    QB.nui.send('camera:closed')
end

function Camera.Open()
    if SteviePhone.State.cameraMode then return true end
    local ped = QB.cache.ped()
    if IsEntityDead(ped) then return false, 'PLAYER_DEAD' end
    Camera.previousRadar = not IsRadarHidden()
    SteviePhone.State.cameraMode = true
    QB.nui.setFocus(false, false)
    SetNuiFocusKeepInput(false)
    DisplayRadar(false)
    QB.nui.send('phone:visibility', false)
    return true
end

function Camera.Close()
    if not SteviePhone.State.cameraMode then return end
    finishMode()
    if SteviePhone.State.open then
        QB.nui.setFocus(true, true)
        QB.nui.send('phone:visibility', true)
    end
end

function Camera.Capture(done)
    done = done or function() end
    if not SteviePhone.State.cameraMode then return done({ ok = false, error = 'CAMERA_NOT_OPEN' }) end
    if GetResourceState('screenshot-basic') ~= 'started' then
        return done({ ok = false, error = 'SCREENSHOT_PROVIDER_UNAVAILABLE' })
    end
    SteviePhone.ServerCallback('stevie-phone:server:requestMediaUpload', {
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
            return SteviePhone.ServerCallback('stevie-phone:server:completeMediaUpload', {
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
                SteviePhone.ServerCallback('stevie-phone:server:completeMediaUpload', {
                    token = instruction.token,
                    receipt = receipt
                }, done)
            end
        )
    end)
end

function Camera.Cleanup()
    if SteviePhone.State.cameraMode or Camera.handle then finishMode() end
end

CreateThread(function()
    while true do
        if SteviePhone.State and SteviePhone.State.cameraMode then
            Wait(0)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            HideHudAndRadarThisFrame()
            if IsControlJustReleased(0, 177) then Camera.Close() end
        else
            Wait(500)
        end
    end
end)

SteviePhone.Camera = Camera
