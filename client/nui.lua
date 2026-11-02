QBPhone = QBPhone or {}

-- kora_lib's NUI helpers run in kora_lib's resource VM. This phone owns a different
-- browser frame, so its messages and callback routes must use this resource's natives.
function QBPhone.SendNui(action, data)
    SendNUIMessage({ action = action, data = data })
end

local callbacks = {
    ['legacy:mailList'] = 'qbphone:server:legacy:getMail',
    ['legacy:mailRead'] = 'qbphone:server:legacy:readMail',
    ['legacy:mailDelete'] = 'qbphone:server:legacy:deleteMail',
    ['legacy:activity'] = 'qbphone:server:legacy:getActivity',
    ['handset:action'] = 'qbphone:server:handsetAction',
    ['calls:videoControl'] = 'qbphone:server:calls:videoControl',
    ['bootstrap'] = 'qbphone:server:getBootstrap',
    ['settings:save'] = 'qbphone:server:saveSettings',
    ['security:unlock'] = 'qbphone:server:unlockPhone',
    ['security:lock'] = 'qbphone:server:lockPhone',
    ['security:setPin'] = 'qbphone:server:setPhonePin',
    ['security:removePin'] = 'qbphone:server:removePhonePin',
    ['contacts:create'] = 'qbphone:server:saveContact',
    ['contacts:update'] = 'qbphone:server:saveContact',
    ['contacts:delete'] = 'qbphone:server:deleteContact',
    ['contacts:list'] = 'qbphone:server:getContacts',
    ['messages:getConversations'] = 'qbphone:server:getConversations',
    ['messages:startDirect'] = 'qbphone:server:startDirectConversation',
    ['messages:markRead'] = 'qbphone:server:markConversationRead',
    ['messages:deleteForSelf'] = 'qbphone:server:deleteMessageForSelf',
    ['messages:getPage'] = 'qbphone:server:getMessages',
    ['messages:send'] = 'qbphone:server:sendMessage',
    ['calls:start'] = 'qbphone:server:calls:start',
    ['calls:accept'] = 'qbphone:server:calls:accept',
    ['calls:reject'] = 'qbphone:server:calls:reject',
    ['calls:hangup'] = 'qbphone:server:calls:hangup',
    ['calls:history'] = 'qbphone:server:calls:history',
    ['calls:signal'] = 'qbphone:server:calls:signal',
    ['gallery:list'] = 'qbphone:server:getGallery',
    ['media:request'] = 'qbphone:server:requestMediaUpload',
    ['media:complete'] = 'qbphone:server:completeMediaUpload',
    ['gallery:delete'] = 'qbphone:server:deleteMedia',
    ['bank:getData'] = 'qbphone:server:getBankBalance',
    ['bank:getTransactions'] = 'qbphone:server:getBankHistory',
    ['bank:transfer'] = 'qbphone:server:transferBankMoney',
    ['messages:createGroup'] = 'qbphone:server:createGroup',
    ['messages:leaveGroup'] = 'qbphone:server:leaveGroup',
    ['messages:addMember'] = 'qbphone:server:addGroupMember',
    ['blocks:list'] = 'qbphone:server:getBlocked',
    ['blocks:set'] = 'qbphone:server:setBlocked',
    ['mail:list'] = 'qbphone:server:getMail',
    ['mail:send'] = 'qbphone:server:sendMail',
    ['mail:read'] = 'qbphone:server:readMail',
    ['mail:delete'] = 'qbphone:server:deleteMail',
    ['property:list'] = 'qbphone:server:getProperties',
    ['items:save'] = 'qbphone:server:saveItem',
    ['items:remove'] = 'qbphone:server:removeItem',
    ['garage:list'] = 'qbphone:server:getVehicles',
    ['wallet:get'] = 'qbphone:server:getWallet',
    ['wallet:show'] = 'qbphone:server:showWalletId',
    ['jobs:getData'] = 'qbphone:server:getJob',
    ['jobs:setDuty'] = 'qbphone:server:setJobDuty',
    ['jobs:runAction'] = 'qbphone:server:runJobAction',
    ['social:createAccount'] = 'qbphone:server:social:createAccount',
    ['social:getFeed'] = 'qbphone:server:social:getFeed',
    ['social:getProfile'] = 'qbphone:server:social:getProfile',
    ['social:createPost'] = 'qbphone:server:social:createPost',
    ['social:deletePost'] = 'qbphone:server:social:deletePost',
    ['social:toggleLike'] = 'qbphone:server:social:toggleLike',
    ['social:follow'] = 'qbphone:server:social:follow',
    ['social:unfollow'] = 'qbphone:server:social:unfollow',
    ['social:createComment'] = 'qbphone:server:social:createComment',
    ['social:deleteComment'] = 'qbphone:server:social:deleteComment',
    ['social:getComments'] = 'qbphone:server:social:getComments',
    ['social:block'] = 'qbphone:server:social:block',
    ['social:report'] = 'qbphone:server:social:report',
    ['market:getListings'] = 'qbphone:server:market:getListings',
    ['market:getListing'] = 'qbphone:server:market:getListing',
    ['market:createListing'] = 'qbphone:server:market:createListing',
    ['market:updateListing'] = 'qbphone:server:market:updateListing',
    ['market:removeListing'] = 'qbphone:server:market:removeListing',
    ['market:markSold'] = 'qbphone:server:market:markSold',
    ['market:contactSeller'] = 'qbphone:server:market:contactSeller',
    ['moderation:getQueue'] = 'qbphone:server:moderation:getQueue',
    ['moderation:resolve'] = 'qbphone:server:moderation:resolve',
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
        QBPhone.ServerCallback(serverName, type(data) == 'table' and data or {}, function(result)
            safeReply(cb, result)
        end)
    end)
end

RegisterNUICallback('phone:close', function(data, cb)
    QBPhone.Close(false)
    -- The UI reports why it could not open (for example no phone item) so the
    -- player gets feedback instead of an invisible phone that holds focus.
    if type(data) == 'table' and type(data.error) == 'string' and data.error ~= '' then
        Kora.notify.send({ title = 'Phone', message = data.error:sub(1, 120), type = 'error', duration = 4000 })
    end
    cb({ ok = true })
end)

RegisterNUICallback('phone:ready', function(_, cb)
    QBPhone.State.ready = true
    cb({ ok = true, data = QBPhone.State.Public() })
end)

RegisterNUICallback('route:changed', function(_, cb)
    cb({ ok = true })
end)

RegisterNUICallback('camera:open', function(data, cb)
    local ok, errorCode = QBPhone.Camera.Open(data)
    cb({ ok = ok == true, error = errorCode, zoom = ok == true and QBPhone.Camera.ZoomEnabled() or nil })
end)

-- The phone cursor owns the mouse wheel while it is up, so the Camera app forwards wheel steps here.
RegisterNUICallback('camera:zoom', function(data, cb)
    cb({ ok = QBPhone.Camera.Zoom(type(data) == 'table' and tonumber(data.dir) or nil) })
end)

RegisterNUICallback('camera:facing', function(data, cb)
    cb({ ok = QBPhone.Camera.SetFacing(type(data) == 'table' and data.front) })
end)

RegisterNUICallback('camera:close', function(_, cb)
    QBPhone.Camera.Close()
    cb({ ok = true })
end)

RegisterNUICallback('camera:capture', function(_, cb)
    QBPhone.Camera.Capture(function(result) safeReply(cb, result) end)
end)

RegisterNUICallback('customList', function(_, cb)
    cb(QBPhone.CustomApps.List())
end)

RegisterNUICallback('customLifecycle', function(data, cb)
    if type(data) == 'table' and type(data.app) == 'string' and type(data.event) == 'string' then
        QBPhone.CustomApps.Fire(data.app, data.event)
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
    if type(data.title) == 'string' and not QBPhone.State.open then
        QBPhone.Notifications.Native(data.title:sub(1, 60), type(data.body) == 'string' and data.body:sub(1, 120) or '', data.urgent == true)
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
    if not QBPhone.State.open then
        local label = type(data) == 'table' and type(data.label) == 'string' and data.label:sub(1, 60) or ''
        Kora.notify.send({ title = 'Alarm', message = label ~= '' and label or 'Untitled', type = 'info', duration = 8000 })
        PlaySoundFrontend(-1, 'Beep_Green', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    end
    cb({ ok = true })
end)

-- Do Not Disturb: the UI owns the setting and schedule and tells the client whether it is quiet now.
RegisterNUICallback('quiet', function(data, cb)
    QBPhone.State.quiet = type(data) == 'table' and data.quiet == true
    cb({ ok = true })
end)

RegisterNUICallback('calls:setMuted', function(data, cb)
    cb({ ok = QBPhone.Voice.SetMuted(type(data) == 'table' and data.muted == true) })
end)

RegisterNUICallback('calls:setSpeaker', function(data, cb)
    cb({ ok = QBPhone.Voice.SetSpeaker(type(data) == 'table' and data.speaker == true) })
end)

RegisterNUICallback('map:blips', function(_, cb)
    cb({ ok = true, data = QBPhone.Map.Blips() })
end)
