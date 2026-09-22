SteviePhone = SteviePhone or {}

local callbacks = {
    ['bootstrap'] = 'stevie-phone:server:getBootstrap',
    ['settings:save'] = 'stevie-phone:server:saveSettings',
    ['security:unlock'] = 'stevie-phone:server:unlockPhone',
    ['security:lock'] = 'stevie-phone:server:lockPhone',
    ['security:setPin'] = 'stevie-phone:server:setPhonePin',
    ['security:removePin'] = 'stevie-phone:server:removePhonePin',
    ['contacts:create'] = 'stevie-phone:server:saveContact',
    ['contacts:update'] = 'stevie-phone:server:saveContact',
    ['contacts:delete'] = 'stevie-phone:server:deleteContact',
    ['contacts:list'] = 'stevie-phone:server:getContacts',
    ['messages:getConversations'] = 'stevie-phone:server:getConversations',
    ['messages:startDirect'] = 'stevie-phone:server:startDirectConversation',
    ['messages:markRead'] = 'stevie-phone:server:markConversationRead',
    ['messages:deleteForSelf'] = 'stevie-phone:server:deleteMessageForSelf',
    ['messages:getPage'] = 'stevie-phone:server:getMessages',
    ['messages:send'] = 'stevie-phone:server:sendMessage',
    ['calls:start'] = 'stevie-phone:server:calls:start',
    ['calls:accept'] = 'stevie-phone:server:calls:accept',
    ['calls:reject'] = 'stevie-phone:server:calls:reject',
    ['calls:hangup'] = 'stevie-phone:server:calls:hangup',
    ['calls:history'] = 'stevie-phone:server:calls:history',
    ['gallery:list'] = 'stevie-phone:server:getGallery',
    ['media:request'] = 'stevie-phone:server:requestMediaUpload',
    ['media:complete'] = 'stevie-phone:server:completeMediaUpload',
    ['gallery:delete'] = 'stevie-phone:server:deleteMedia',
    ['bank:getData'] = 'stevie-phone:server:getBankBalance',
    ['bank:getTransactions'] = 'stevie-phone:server:getBankHistory',
    ['bank:transfer'] = 'stevie-phone:server:transferBankMoney',
    ['messages:createGroup'] = 'stevie-phone:server:createGroup',
    ['messages:leaveGroup'] = 'stevie-phone:server:leaveGroup',
    ['messages:addMember'] = 'stevie-phone:server:addGroupMember',
    ['blocks:list'] = 'stevie-phone:server:getBlocked',
    ['blocks:set'] = 'stevie-phone:server:setBlocked',
    ['mail:list'] = 'stevie-phone:server:getMail',
    ['mail:send'] = 'stevie-phone:server:sendMail',
    ['mail:read'] = 'stevie-phone:server:readMail',
    ['mail:delete'] = 'stevie-phone:server:deleteMail',
    ['property:list'] = 'stevie-phone:server:getProperties',
    ['items:save'] = 'stevie-phone:server:saveItem',
    ['items:remove'] = 'stevie-phone:server:removeItem',
    ['garage:list'] = 'stevie-phone:server:getVehicles',
    ['wallet:get'] = 'stevie-phone:server:getWallet',
    ['wallet:show'] = 'stevie-phone:server:showWalletId',
    ['jobs:getData'] = 'stevie-phone:server:getJob',
    ['jobs:setDuty'] = 'stevie-phone:server:setJobDuty',
    ['jobs:runAction'] = 'stevie-phone:server:runJobAction',
    ['social:createAccount'] = 'stevie-phone:server:social:createAccount',
    ['social:getFeed'] = 'stevie-phone:server:social:getFeed',
    ['social:getProfile'] = 'stevie-phone:server:social:getProfile',
    ['social:createPost'] = 'stevie-phone:server:social:createPost',
    ['social:deletePost'] = 'stevie-phone:server:social:deletePost',
    ['social:toggleLike'] = 'stevie-phone:server:social:toggleLike',
    ['social:follow'] = 'stevie-phone:server:social:follow',
    ['social:unfollow'] = 'stevie-phone:server:social:unfollow',
    ['social:createComment'] = 'stevie-phone:server:social:createComment',
    ['social:getComments'] = 'stevie-phone:server:social:getComments',
    ['social:block'] = 'stevie-phone:server:social:block',
    ['social:report'] = 'stevie-phone:server:social:report',
    ['market:getListings'] = 'stevie-phone:server:market:getListings',
    ['market:getListing'] = 'stevie-phone:server:market:getListing',
    ['market:createListing'] = 'stevie-phone:server:market:createListing',
    ['market:updateListing'] = 'stevie-phone:server:market:updateListing',
    ['market:removeListing'] = 'stevie-phone:server:market:removeListing',
    ['market:markSold'] = 'stevie-phone:server:market:markSold',
    ['market:contactSeller'] = 'stevie-phone:server:market:contactSeller',
    ['moderation:getQueue'] = 'stevie-phone:server:moderation:getQueue',
    ['moderation:resolve'] = 'stevie-phone:server:moderation:resolve',
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
        SteviePhone.ServerCallback(serverName, type(data) == 'table' and data or {}, function(result)
            safeReply(cb, result)
        end)
    end)
end

RegisterNUICallback('phone:close', function(data, cb)
    SteviePhone.Close(false)
    -- The UI reports why it could not open (for example no phone item) so the
    -- player gets feedback instead of an invisible phone that holds focus.
    if type(data) == 'table' and type(data.error) == 'string' and data.error ~= '' then
        SteviePhone.QBCore.Functions.Notify(data.error:sub(1, 120), 'error', 4000)
    end
    cb({ ok = true })
end)

RegisterNUICallback('phone:ready', function(_, cb)
    SteviePhone.State.ready = true
    cb({ ok = true, data = SteviePhone.State.Public() })
end)

RegisterNUICallback('route:changed', function(_, cb)
    cb({ ok = true })
end)

RegisterNUICallback('camera:open', function(_, cb)
    local ok, errorCode = SteviePhone.Camera.Open()
    cb({ ok = ok == true, error = errorCode })
end)

RegisterNUICallback('camera:close', function(_, cb)
    SteviePhone.Camera.Close()
    cb({ ok = true })
end)

RegisterNUICallback('camera:capture', function(_, cb)
    SteviePhone.Camera.Capture(function(result) safeReply(cb, result) end)
end)

RegisterNUICallback('customList', function(_, cb)
    cb(SteviePhone.CustomApps.List())
end)

RegisterNUICallback('customLifecycle', function(data, cb)
    if type(data) == 'table' and type(data.app) == 'string' and type(data.event) == 'string' then
        SteviePhone.CustomApps.Fire(data.app, data.event)
    end
    cb({ ok = true })
end)

RegisterNUICallback('map:open', function(data, cb)
    data = type(data) == 'table' and data or {}
    cb({ ok = SteviePhone.Map.Show(tonumber(data.x), tonumber(data.y), tonumber(data.w), tonumber(data.h)) == true })
end)

RegisterNUICallback('map:close', function(_, cb)
    SteviePhone.Map.Hide()
    cb({ ok = true })
end)

-- Location sharing: the UI asks where the player is and, on the receiving side, sets a waypoint.
RegisterNUICallback('location:mine', function(_, cb)
    local at = GetEntityCoords(PlayerPedId())
    local street = GetStreetNameFromHashKey((GetStreetNameAtCoord(at.x, at.y, at.z)))
    local zone = GetLabelText(GetNameOfZone(at.x, at.y, at.z))
    local label = (street ~= '' and zone ~= 'NULL' and (street .. ', ' .. zone)) or (street ~= '' and street) or (zone ~= 'NULL' and zone) or 'Shared location'
    cb({ ok = true, data = { x = math.floor(at.x * 10 + 0.5) / 10, y = math.floor(at.y * 10 + 0.5) / 10, label = label:gsub('[%[%]|]', ''):sub(1, 60) } })
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
    if type(data.title) == 'string' and not SteviePhone.State.open then
        SteviePhone.Notifications.Native(data.title:sub(1, 60), type(data.body) == 'string' and data.body:sub(1, 120) or '', data.urgent == true)
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
    if not SteviePhone.State.open then
        local label = type(data) == 'table' and type(data.label) == 'string' and data.label:sub(1, 60) or ''
        SteviePhone.QBCore.Functions.Notify('Alarm: ' .. (label ~= '' and label or 'Untitled'), 'primary', 8000)
        PlaySoundFrontend(-1, 'Beep_Green', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    end
    cb({ ok = true })
end)

-- Do Not Disturb: the UI owns the setting and schedule and tells the client whether it is quiet now.
RegisterNUICallback('quiet', function(data, cb)
    SteviePhone.State.quiet = type(data) == 'table' and data.quiet == true
    cb({ ok = true })
end)

RegisterNUICallback('calls:setMuted', function(data, cb)
    cb({ ok = SteviePhone.Voice.SetMuted(type(data) == 'table' and data.muted == true) })
end)

RegisterNUICallback('calls:setSpeaker', function(data, cb)
    cb({ ok = SteviePhone.Voice.SetSpeaker(type(data) == 'table' and data.speaker == true) })
end)
