KoraPhone = KoraPhone or {}
local Share = {}
KoraPhone.Share = Share

-- Share your number with a nearby player. This file only collects answers: the server picks the number,
-- checks the distance and saves the contact (server/services/share.lua).

local function cfg() return Config.ShareNumber or {} end

local function holdsPhone()
    if Config.RequirePhoneItem == false then return true end
    local data = exports.kora_core:getPlayerData() or {}
    for _, item in pairs(data.items or {}) do
        if type(item) == 'table' and Config.Handsets[item.name] then return true end
    end
    return false
end

local function nameKey()
    local data = exports.kora_core:getPlayerData() or {}
    return 'kora_phone:shareName:' .. tostring(data.citizenid or '')
end

local function message(result, fallback)
    local problem = type(result) == 'table' and result.error
    if type(problem) == 'table' and type(problem.message) == 'string' then return problem.message end
    if type(problem) == 'string' and not problem:find('^[%u_]+$') then return problem end
    return fallback
end

local function prettyNumber(number)
    number = tostring(number or '')
    if #number == 10 then return ('%s-%s-%s'):format(number:sub(1, 3), number:sub(4, 6), number:sub(7)) end
    return number
end

local function offer(target)
    local label
    if cfg().AskForName ~= false then
        local result = Kora.nui.openInputDialog({
            { id = 'name', label = 'Share as', type = 'text', required = true, minLength = 1,
              maxLength = Config.Limits.ContactName, default = GetResourceKvpString(nameKey()) or '' },
        }, 'Share your number', 'They see this name and your number, and choose whether to save it.')
        if not result or result.cancelled or type(result.values) ~= 'table' then return end
        label = type(result.values.name) == 'string' and result.values.name:sub(1, Config.Limits.ContactName) or nil
        if label and label ~= '' then SetResourceKvp(nameKey(), label) end
    end
    KoraPhone.ServerCallback('kora_phone:server:share:offer', { target = target, label = label }, function(result)
        if result.ok then
            Kora.notify.send({ title = 'Phone', message = 'Number offered. Waiting for them to accept.', type = 'info', duration = 3500 })
        else
            Kora.notify.send({ title = 'Phone', message = message(result, 'Could not share your number'), type = 'error', duration = 3500 })
        end
    end)
end

local function answer(id, accept, shareBack)
    KoraPhone.ServerCallback('kora_phone:server:share:answer', {
        id = id, accept = accept, shareBack = shareBack, myLabel = GetResourceKvpString(nameKey()),
    }, function(result)
        if not accept then return end
        local data = type(result) == 'table' and result.data or {}
        if result.ok then
            local text = data.existing and 'That number is already in your contacts.' or ('Saved %s to your contacts.'):format(tostring(data.name or 'the contact'):sub(1, 40))
            if data.sharedBack then text = text .. ' Your number was shared back.' end
            Kora.notify.send({ title = 'Contacts', message = text, type = 'success', duration = 4000 })
        else
            Kora.notify.send({ title = 'Contacts', message = message(result, 'Could not save the contact'), type = 'error', duration = 4000 })
        end
    end)
end

-- Phone closed: a kora_lib menu. Escape (cancel) declines.
local function popup(request)
    local items = {
        { id = 'accept', label = 'Save contact', description = ('%s · %s'):format(request.label, prettyNumber(request.number)) },
    }
    if request.shareBack then items[#items + 1] = { id = 'both', label = 'Save and share my number back' } end
    items[#items + 1] = { id = 'decline', label = 'Decline' }
    local choice = Kora.nui.openMenu(items, ('%s wants to share their number'):format(request.label))
    local picked = type(choice) == 'table' and choice.selectedId or nil
    answer(request.id, picked == 'accept' or picked == 'both', picked == 'both')
end

RegisterNetEvent('kora_phone:client:share:request', function(data)
    if type(data) ~= 'table' or type(data.id) ~= 'string' or #data.id > 64 or type(data.number) ~= 'string' then return end
    local request = {
        id = data.id,
        label = (type(data.label) == 'string' and data.label or 'Someone'):sub(1, Config.Limits.ContactName),
        number = data.number:gsub('[^%d]', ''):sub(1, 15),
        expiresIn = math.max(1, math.min(120, tonumber(data.expiresIn) or 30)),
        shareBack = data.shareBack == true,
    }
    -- Down or behind another resource's camera: no prompt, the request simply expires.
    if KoraPhone.Unavailable() or KoraPhone.UiBlocked() then return end
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    if KoraPhone.State.open then
        KoraPhone.SendNui('share:request', request)
    else
        CreateThread(function() popup(request) end)
    end
end)

local function register()
    if cfg().Enabled ~= true or GetResourceState('kora_target') ~= 'started' then return end
    local distance = tonumber(cfg().Distance) or 3.0
    exports.kora_target:addGlobalType('player', { {
        label = 'Share phone number',
        icon = 'Phone',
        distance = distance,
        canInteract = function(entity)
            return NetworkGetPlayerIndexFromPed(entity) ~= -1 and holdsPhone() and not KoraPhone.Unavailable()
        end,
        onSelect = function(entity)
            local index = NetworkGetPlayerIndexFromPed(entity)
            if index == -1 then return end
            offer(GetPlayerServerId(index))
        end,
    } }, distance)
end

CreateThread(register)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_target' then register() end
end)
