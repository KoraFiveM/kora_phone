KoraPhone = KoraPhone or {}

-- kora_lib's NUI helpers run in kora_lib's resource VM. This phone owns a different
-- browser frame, so its messages and callback routes must use this resource's natives.
function KoraPhone.SendNui(action, data)
    SendNUIMessage({ action = action, data = data })
end

local callbacks = {
    ['legacy:mailList'] = 'kora_phone:server:legacy:getMail',
    ['legacy:mailRead'] = 'kora_phone:server:legacy:readMail',
    ['legacy:mailDelete'] = 'kora_phone:server:legacy:deleteMail',
    ['legacy:activity'] = 'kora_phone:server:legacy:getActivity',
    ['handset:action'] = 'kora_phone:server:handsetAction',
    ['calls:videoControl'] = 'kora_phone:server:calls:videoControl',
    ['bootstrap'] = 'kora_phone:server:getBootstrap',
    ['settings:save'] = 'kora_phone:server:saveSettings',
    ['security:unlock'] = 'kora_phone:server:unlockPhone',
    ['security:lock'] = 'kora_phone:server:lockPhone',
    ['security:setPin'] = 'kora_phone:server:setPhonePin',
    ['security:removePin'] = 'kora_phone:server:removePhonePin',
    ['contacts:create'] = 'kora_phone:server:saveContact',
    ['contacts:update'] = 'kora_phone:server:saveContact',
    ['contacts:delete'] = 'kora_phone:server:deleteContact',
    ['contacts:list'] = 'kora_phone:server:getContacts',
    ['share:answer'] = 'kora_phone:server:share:answer',
    ['messages:getConversations'] = 'kora_phone:server:getConversations',
    ['messages:startDirect'] = 'kora_phone:server:startDirectConversation',
    ['messages:markRead'] = 'kora_phone:server:markConversationRead',
    ['messages:deleteForSelf'] = 'kora_phone:server:deleteMessageForSelf',
    ['messages:getPage'] = 'kora_phone:server:getMessages',
    ['messages:send'] = 'kora_phone:server:sendMessage',
    ['calls:start'] = 'kora_phone:server:calls:start',
    ['calls:accept'] = 'kora_phone:server:calls:accept',
    ['calls:reject'] = 'kora_phone:server:calls:reject',
    ['calls:hangup'] = 'kora_phone:server:calls:hangup',
    ['calls:history'] = 'kora_phone:server:calls:history',
    ['calls:signal'] = 'kora_phone:server:calls:signal',
    ['gallery:list'] = 'kora_phone:server:getGallery',
    ['media:request'] = 'kora_phone:server:requestMediaUpload',
    ['media:complete'] = 'kora_phone:server:completeMediaUpload',
    ['gallery:delete'] = 'kora_phone:server:deleteMedia',
    ['bank:getData'] = 'kora_phone:server:getBankBalance',
    ['bank:getTransactions'] = 'kora_phone:server:getBankHistory',
    ['bank:transfer'] = 'kora_phone:server:transferBankMoney',
    ['messages:createGroup'] = 'kora_phone:server:createGroup',
    ['messages:leaveGroup'] = 'kora_phone:server:leaveGroup',
    ['messages:addMember'] = 'kora_phone:server:addGroupMember',
    ['blocks:list'] = 'kora_phone:server:getBlocked',
    ['blocks:set'] = 'kora_phone:server:setBlocked',
    ['mail:list'] = 'kora_phone:server:getMail',
    ['mail:send'] = 'kora_phone:server:sendMail',
    ['mail:read'] = 'kora_phone:server:readMail',
    ['mail:delete'] = 'kora_phone:server:deleteMail',
    ['property:list'] = 'kora_phone:server:getProperties',
    ['items:save'] = 'kora_phone:server:saveItem',
    ['items:remove'] = 'kora_phone:server:removeItem',
    ['garage:list'] = 'kora_phone:server:getVehicles',
    ['wallet:get'] = 'kora_phone:server:getWallet',
    ['wallet:show'] = 'kora_phone:server:showWalletId',
    ['jobs:getData'] = 'kora_phone:server:getJob',
    ['jobs:setDuty'] = 'kora_phone:server:setJobDuty',
    ['jobs:runAction'] = 'kora_phone:server:runJobAction',
    ['social:createAccount'] = 'kora_phone:server:social:createAccount',
    ['social:getFeed'] = 'kora_phone:server:social:getFeed',
    ['social:getProfile'] = 'kora_phone:server:social:getProfile',
    ['social:createPost'] = 'kora_phone:server:social:createPost',
    ['social:deletePost'] = 'kora_phone:server:social:deletePost',
    ['social:toggleLike'] = 'kora_phone:server:social:toggleLike',
    ['social:follow'] = 'kora_phone:server:social:follow',
    ['social:unfollow'] = 'kora_phone:server:social:unfollow',
    ['social:createComment'] = 'kora_phone:server:social:createComment',
    ['social:deleteComment'] = 'kora_phone:server:social:deleteComment',
    ['social:getComments'] = 'kora_phone:server:social:getComments',
    ['social:block'] = 'kora_phone:server:social:block',
    ['social:report'] = 'kora_phone:server:social:report',
    ['market:getListings'] = 'kora_phone:server:market:getListings',
    ['market:getListing'] = 'kora_phone:server:market:getListing',
    ['market:createListing'] = 'kora_phone:server:market:createListing',
    ['market:updateListing'] = 'kora_phone:server:market:updateListing',
    ['market:removeListing'] = 'kora_phone:server:market:removeListing',
    ['market:markSold'] = 'kora_phone:server:market:markSold',
    ['market:contactSeller'] = 'kora_phone:server:market:contactSeller',
    ['moderation:getQueue'] = 'kora_phone:server:moderation:getQueue',
    ['moderation:resolve'] = 'kora_phone:server:moderation:resolve',
}

local function safeReply(cb, result)
    if type(result) ~= 'table' then result = { ok = false, error = 'INVALID_SERVER_RESPONSE' } end
    cb(result)
end

-- Always answer known-but-unimplemented routes. Leaving an NUI callback open
-- indefinitely locks the browser promise and makes the phone appear frozen.
local unsupportedCallbacks = {}

for _, nuiName in ipairs(unsupportedCallbacks) do
    RegisterNUICallback(nuiName, function(_, cb)
        cb({ ok = false, error = { code = 'NOT_IMPLEMENTED', message = 'This feature is not available yet' } })
    end)
end

for nuiName, serverName in pairs(callbacks) do
    RegisterNUICallback(nuiName, function(data, cb)
        KoraPhone.ServerCallback(serverName, type(data) == 'table' and data or {}, function(result)
            safeReply(cb, result)
        end)
    end)
end

RegisterNUICallback('phone:close', function(data, cb)
    KoraPhone.Close(false)
    -- The UI reports why it could not open (for example no phone item) so the
    -- player gets feedback instead of an invisible phone that holds focus.
    if type(data) == 'table' and type(data.error) == 'string' and data.error ~= '' then
        Kora.notify.send({ title = 'Phone', message = data.error:sub(1, 120), type = 'error', duration = 4000 })
    end
    cb({ ok = true })
end)

RegisterNUICallback('phone:ready', function(_, cb)
    KoraPhone.State.ready = true
    cb({ ok = true, data = KoraPhone.State.Public() })
end)

RegisterNUICallback('route:changed', function(_, cb)
    cb({ ok = true })
end)

RegisterNUICallback('camera:open', function(data, cb)
    local ok, errorCode = KoraPhone.Camera.Open(data)
    cb({ ok = ok == true, error = errorCode, zoom = ok == true and KoraPhone.Camera.ZoomEnabled() or nil, mic = ok == true and KoraPhone.Camera.MicSettings() or nil })
end)

-- The phone cursor owns the mouse wheel while it is up, so the Camera app forwards wheel steps here.
RegisterNUICallback('camera:zoom', function(data, cb)
    cb({ ok = KoraPhone.Camera.Zoom(type(data) == 'table' and tonumber(data.dir) or nil) })
end)

RegisterNUICallback('camera:facing', function(data, cb)
    cb({ ok = KoraPhone.Camera.SetFacing(type(data) == 'table' and data.front) })
end)

-- A video clip with followVoice is recording: report the game's talking state so the UI can open and close the mic.
RegisterNUICallback('camera:recording', function(data, cb)
    cb({ ok = KoraPhone.Camera.SetRecording(type(data) == 'table' and data.active == true) })
end)

RegisterNUICallback('camera:close', function(_, cb)
    KoraPhone.Camera.Close()
    cb({ ok = true })
end)

RegisterNUICallback('camera:capture', function(_, cb)
    KoraPhone.Camera.Capture(function(result) safeReply(cb, result) end)
end)

RegisterNUICallback('customList', function(_, cb)
    cb(KoraPhone.CustomApps.List())
end)

RegisterNUICallback('customLifecycle', function(data, cb)
    if type(data) == 'table' and type(data.app) == 'string' and type(data.event) == 'string' then
        KoraPhone.CustomApps.Fire(data.app, data.event)
    end
    cb({ ok = true })
end)

-- Location sharing: the UI asks where the player is and, on the receiving side, sets a waypoint.
RegisterNUICallback('location:mine', function(_, cb)
    local at = Kora.cache.coords()
    local street = GetStreetNameFromHashKey((GetStreetNameAtCoord(at.x, at.y, at.z)))
    local zone = GetLabelText(GetNameOfZone(at.x, at.y, at.z))
    local label = (street ~= '' and zone ~= 'NULL' and (street .. ', ' .. zone)) or (street ~= '' and street) or (zone ~= 'NULL' and zone) or 'Shared location'
    -- heading and the game's current waypoint (blip sprite 8) feed the Maps app's arrow and pin
    local blip, waypoint = GetFirstBlipInfoId(8), nil
    if DoesBlipExist(blip) then local w = GetBlipInfoIdCoord(blip); waypoint = { x = math.floor(w.x + 0.5), y = math.floor(w.y + 0.5) } end
    cb({ ok = true, data = { x = math.floor(at.x * 10 + 0.5) / 10, y = math.floor(at.y * 10 + 0.5) / 10, label = label:gsub('[%[%]|]', ''):sub(1, 60), heading = math.floor(GetEntityHeading(Kora.cache.ped()) + 0.5), waypoint = waypoint } })
end)

RegisterNUICallback('waypoint', function(data, cb)
    local x, y = type(data) == 'table' and tonumber(data.x), type(data) == 'table' and tonumber(data.y)
    if not x or not y or math.abs(x) > 20000 or math.abs(y) > 20000 then
        return cb({ ok = false, error = { code = 'INVALID_INPUT', message = 'That location is invalid' } })
    end
    SetNewWaypoint(x + 0.0, y + 0.0)
    cb({ ok = true, data = true })
end)

-- The UI asks for a game notification when something arrives (a text, mail, a missed call) and the phone is closed.
RegisterNUICallback('notify', function(data, cb)
    data = type(data) == 'table' and data or {}
    if type(data.title) == 'string' and not KoraPhone.State.open then
        KoraPhone.Notifications.Native(data.title:sub(1, 60), type(data.body) == 'string' and data.body:sub(1, 120) or '', data.urgent == true)
    end
    cb({ ok = true })
end)

-- Weather comes straight from the game, so it matches whatever weather script the server runs.
local WEATHER = { 'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'SMOG', 'FOGGY', 'OVERCAST', 'RAIN', 'THUNDER', 'CLEARING', 'NEUTRAL', 'SNOW', 'BLIZZARD', 'SNOWLIGHT', 'XMAS', 'HALLOWEEN' }
RegisterNUICallback('weather:get', function(_, cb)
    local current = GetPrevWeatherTypeHashName() & 0xFFFFFFFF
    local condition = 'CLEAR'
    for _, name in ipairs(WEATHER) do
        if (GetHashKey(name) & 0xFFFFFFFF) == current then condition = name; break end
    end
    cb({ ok = true, data = { condition = condition, hour = GetClockHours(), minute = GetClockMinutes(), rain = math.max(0.0, GetRainLevel() + 0.0) } })
end)

-- An alarm went off in the UI. With the phone closed the player still needs to notice it.
RegisterNUICallback('alarm', function(data, cb)
    if not KoraPhone.State.open then
        local label = type(data) == 'table' and type(data.label) == 'string' and data.label:sub(1, 60) or ''
        Kora.notify.send({ title = 'Alarm', message = label ~= '' and label or 'Untitled', type = 'info', duration = 8000 })
        PlaySoundFrontend(-1, 'Beep_Green', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    end
    cb({ ok = true })
end)

-- Do Not Disturb: the UI owns the setting and schedule and tells the client whether it is quiet now.
RegisterNUICallback('quiet', function(data, cb)
    KoraPhone.State.quiet = type(data) == 'table' and data.quiet == true
    cb({ ok = true })
end)

RegisterNUICallback('calls:setMuted', function(data, cb)
    cb({ ok = KoraPhone.Voice.SetMuted(type(data) == 'table' and data.muted == true) })
end)

RegisterNUICallback('calls:setSpeaker', function(data, cb)
    cb({ ok = KoraPhone.Voice.SetSpeaker(type(data) == 'table' and data.speaker == true) })
end)

RegisterNUICallback('map:blips', function(_, cb)
    cb({ ok = true, data = KoraPhone.Map.Blips() })
end)