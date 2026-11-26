KoraPhone = KoraPhone or {}
local Share = {}
KoraPhone.Share = Share

-- Share your number with a nearby player. This file only collects answers: the server picks the number,
-- checks the distance and saves the contact (server/services/share.lua).

local function cfg()
    return Config.ShareNumber or {}
end

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

local function notify(titleKey, text, kind, duration)
    Kora.notify.send({ title = Kora.lang(titleKey), message = text, type = kind, duration = duration })
end

local function offer(target)
    local label
    if cfg().AskForName ~= false then
        local result = Kora.nui.openInputDialog({
            {
                id = 'name',
                label = Kora.lang('share.share_as'),
                type = 'text',
                required = true,
                minLength = 1,
                maxLength = Config.Limits.ContactName,
                default = GetResourceKvpString(nameKey()) or '',
            },
        }, Kora.lang('share.dialog_title'), Kora.lang('share.dialog_description'))
        if not result or result.cancelled or type(result.values) ~= 'table' then return end
        label = type(result.values.name) == 'string' and result.values.name:sub(1, Config.Limits.ContactName) or nil
        if label and label ~= '' then SetResourceKvp(nameKey(), label) end
    end
    KoraPhone.ServerCallback('kora_phone:server:share:offer', { target = target, label = label }, function(result)
        if result.ok then
            notify('title.phone', Kora.lang('share.offered'), 'info', 3500)
        else
            notify('title.phone', message(result, Kora.lang('share.offer_failed')), 'error', 3500)
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
            local text
            if data.existing then
                text = Kora.lang('share.already_saved')
            else
                text = Kora.lang('share.saved', tostring(data.name or Kora.lang('share.default_contact')):sub(1, 40))
            end
            if data.sharedBack then text = text .. ' ' .. Kora.lang('share.shared_back') end
            notify('title.contacts', text, 'success', 4000)
        else
            notify('title.contacts', message(result, Kora.lang('share.save_failed')), 'error', 4000)
        end
    end)
end

-- Phone closed: a kora_lib menu. Escape (cancel) declines.
local function popup(request)
    local items = {
        { id = 'accept', label = Kora.lang('share.save_contact'), description = ('%s · %s'):format(request.label, prettyNumber(request.number)) },
    }
    if request.shareBack then items[#items + 1] = { id = 'both', label = Kora.lang('share.save_and_share') } end
    items[#items + 1] = { id = 'decline', label = Kora.lang('share.decline') }
    local choice = Kora.nui.openMenu(items, Kora.lang('share.menu_title', request.label))
    local picked = type(choice) == 'table' and choice.selectedId or nil
    answer(request.id, picked == 'accept' or picked == 'both', picked == 'both')
end

RegisterNetEvent('kora_phone:client:share:request', function(data)
    if type(data) ~= 'table' or type(data.id) ~= 'string' or #data.id > 64 or type(data.number) ~= 'string' then return end
    local request = {
        id = data.id,
        label = (type(data.label) == 'string' and data.label or Kora.lang('share.someone')):sub(1, Config.Limits.ContactName),
        number = data.number:gsub('[^%d]', ''):sub(1, 15),
        expiresIn = math.max(1, math.min(120, tonumber(data.expiresIn) or 30)),
        shareBack = data.shareBack == true,
    }
    -- Down or behind another resource's camera: no prompt, the request simply expires.
    if KoraPhone.Unavailable() or KoraPhone.UiBlocked() then return end
    Kora.sound.playFrontend('Text_Arrive_Tone', 'Phone_SoundSet_Default', { network = true })
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
        label = Kora.lang('share.target_label'),
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
