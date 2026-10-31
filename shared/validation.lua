PhoneValidation = {}

local function trim(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or value
end

function PhoneValidation.string(value, field, minimum, maximum, allowEmpty)
    if type(value) ~= 'string' then return nil, field .. ' must be a string' end
    value = trim(value)
    local length = #value
    if not allowEmpty and length == 0 then return nil, field .. ' is required' end
    if minimum and length < minimum then return nil, field .. ' is too short' end
    if maximum and length > maximum then return nil, field .. ' is too long' end
    if value:find('[%z\1-\8\11\12\14-\31]') then return nil, field .. ' contains control characters' end
    return value
end

function PhoneValidation.integer(value, field, minimum, maximum)
    value = tonumber(value)
    if not value or value % 1 ~= 0 then return nil, field .. ' must be an integer' end
    if minimum and value < minimum then return nil, field .. ' is too small' end
    if maximum and value > maximum then return nil, field .. ' is too large' end
    return value
end

function PhoneValidation.phoneNumber(value)
    if type(value) ~= 'string' then return nil, 'phoneNumber must be a string' end
    value = value:gsub('[^%d]', '')
    local expected = #Config.PhoneNumber.Prefix + Config.PhoneNumber.SubscriberDigits
    if #value ~= expected or value:sub(1, #Config.PhoneNumber.Prefix) ~= Config.PhoneNumber.Prefix then
        return nil, 'phoneNumber is invalid'
    end
    return value
end

function PhoneValidation.page(payload)
    payload = type(payload) == 'table' and payload or {}
    local limit, err = PhoneValidation.integer(payload.limit or Config.Limits.PageSizeDefault, 'limit', 1, Config.Limits.PageSizeMaximum)
    if not limit then return nil, err end
    local cursor
    if payload.cursor ~= nil then
        cursor, err = PhoneValidation.integer(payload.cursor, 'cursor', 1)
        if not cursor then return nil, err end
    end
    return { limit = limit, cursor = cursor }
end

function PhoneValidation.enum(value, field, values)
    for _, allowed in ipairs(values) do if value == allowed then return value end end
    return nil, field .. ' is invalid'
end


local SETTINGS_THEMES = { 'light', 'dark', 'ocean', 'forest', 'amethyst', 'ember', 'kora_core' }
local SETTINGS_WALLPAPERS = { 'orbit', 'plain', 'midnight', 'slate', 'ember', 'kora_core', 'custom' }
local SETTINGS_STYLES = { 'classic', 'standard', 'flip', 'fold' }
local SETTINGS_CASES = { 'default', 'nightdrive', 'citypop', 'sakura', 'touge', 'garage', 'kora_core', 'arcade', 'space', 'palms', 'skyline', 'custom' }
local SETTINGS_ICONS = { 'circle', 'squircle', 'outline', 'solid' }

local function boundedNumber(value, field, minimum, maximum)
    if type(value) ~= 'number' or value ~= value then return nil, field .. ' must be a number' end
    if value < minimum or value > maximum then return nil, field .. ' is out of range' end
    return value
end

-- Maps retired appearance ids (Config.Settings.LegacyIds) to their current id; read at use time.
local function currentId(value)
    local settings = Config and Config.Settings
    if type(value) == 'string' and settings and settings.AcceptLegacyIds and type(settings.LegacyIds) == 'table' then
        return settings.LegacyIds[value] or value
    end
    return value
end

-- Whitelists the appearance settings a client may persist. Unknown keys are dropped
-- so the stored JSON can never grow arbitrary client-controlled fields.
function PhoneValidation.settings(payload)
    if type(payload) ~= 'table' then return nil, 'settings must be an object' end
    local out, err = {}
    out.name, err = PhoneValidation.string(payload.name, 'name', 1, 64)
    if not out.name then return nil, err end
    out.theme, err = PhoneValidation.enum(currentId(payload.theme) or 'light', 'theme', SETTINGS_THEMES)
    if not out.theme then return nil, err end
    out.wallpaper, err = PhoneValidation.enum(currentId(payload.wallpaper) or 'kora_core', 'wallpaper', SETTINGS_WALLPAPERS)
    if not out.wallpaper then return nil, err end
    out.phoneStyle, err = PhoneValidation.enum(payload.phoneStyle or 'classic', 'phoneStyle', SETTINGS_STYLES)
    if not out.phoneStyle then return nil, err end
    out.phoneCase, err = PhoneValidation.enum(currentId(payload.phoneCase) or 'default', 'phoneCase', SETTINGS_CASES)
    if not out.phoneCase then return nil, err end
    out.iconStyle, err = PhoneValidation.enum(payload.iconStyle or 'circle', 'iconStyle', SETTINGS_ICONS)
    if not out.iconStyle then return nil, err end
    if payload.dnd ~= nil then
        if type(payload.dnd) ~= 'boolean' then return nil, 'dnd must be a boolean' end
        out.dnd = payload.dnd
    end
    for _, key in ipairs({ 'dndFrom', 'dndTo' }) do
        local value = payload[key]
        if value ~= nil and value ~= '' then
            local hours, minutes
            if type(value) == 'string' then hours, minutes = value:match('^(%d%d):(%d%d)$') end
            if not hours or tonumber(hours) > 23 or tonumber(minutes) > 59 then return nil, key .. ' must be a time like 22:00' end
            out[key] = value
        end
    end
    out.volume, err = boundedNumber(payload.volume == nil and 0.5 or payload.volume, 'volume', 0, 1)
    if not out.volume then return nil, err end
    out.scale, err = boundedNumber(payload.scale == nil and 1 or payload.scale, 'scale', 0.75, 1.15)
    if not out.scale then return nil, err end
    if payload.setupComplete ~= nil then
        if type(payload.setupComplete) ~= 'boolean' then return nil, 'setupComplete must be a boolean' end
        out.setupComplete = payload.setupComplete
    end
    if payload.wallpaperUrl ~= nil and payload.wallpaperUrl ~= '' then
        local url; url, err = PhoneValidation.string(payload.wallpaperUrl, 'wallpaperUrl', 1, 500)
        if not url then return nil, err end
        if url:sub(1, 8) ~= 'https://' then return nil, 'wallpaperUrl must be an https URL' end
        out.wallpaperUrl = url
    end
    if payload.phoneCaseUrl ~= nil and payload.phoneCaseUrl ~= '' then
        local coverUrl; coverUrl, err = PhoneValidation.string(payload.phoneCaseUrl, 'phoneCaseUrl', 1, 500)
        if not coverUrl then return nil, err end
        if coverUrl:sub(1, 8) ~= 'https://' then return nil, 'phoneCaseUrl must be an https URL' end
        out.phoneCaseUrl = coverUrl
    end
    if payload.appOrder ~= nil then
        if type(payload.appOrder) ~= 'table' or #payload.appOrder > 32 then return nil, 'appOrder is invalid' end
        out.appOrder = {}
        for i, id in ipairs(payload.appOrder) do
            if type(id) ~= 'string' or #id > 24 or not id:match('^[a-z]+$') then return nil, 'appOrder is invalid' end
            out.appOrder[i] = id
        end
    end
    if payload.installedApps ~= nil then
        if type(payload.installedApps) ~= 'table' or #payload.installedApps>20 then return nil,'Invalid installed apps' end
        out.installedApps={}
        for _,id in ipairs(payload.installedApps) do
            if not Config.LaunchApps or not Config.LaunchApps[id] then return nil,'App is unavailable' end
            out.installedApps[#out.installedApps+1]=id
        end
    end
    return out
end

-- 4 to 8 digits, matching the web UI. Returned as a string so leading zeros survive.
function PhoneValidation.pin(value, field)
    field = field or 'pin'
    if type(value) ~= 'string' or not value:match('^%d+$') or #value < 4 or #value > 8 then
        return nil, field .. ' must be 4 to 8 digits'
    end
    return value
end

local function clockTime(value)
    local hours, minutes
    if type(value) == 'string' then hours, minutes = value:match('^(%d%d):(%d%d)$') end
    return hours and tonumber(hours) <= 23 and tonumber(minutes) <= 59
end

-- A note, alarm or music station a phone keeps (Config.Server.Items limits how many). Returns a
-- clean copy holding only the known fields, so stored JSON never carries client-chosen extras.
function PhoneValidation.item(kind, item)
    if type(item) ~= 'table' then return nil, 'item must be an object' end
    local id, err = PhoneValidation.string(item.id, 'id', 1, 64)
    if not id then return nil, err end
    if not id:match('^[%w_%-]+$') then return nil, 'id is invalid' end
    if kind == 'note' then
        local title; title, err = PhoneValidation.string(item.title, 'title', 1, 100)
        if not title then return nil, err end
        local body; body, err = PhoneValidation.string(item.body == nil and '' or item.body, 'body', 0, 4000, true)
        if not body then return nil, err end
        return { id = id, title = title, body = body }
    elseif kind == 'alarm' then
        local label; label, err = PhoneValidation.string(item.label == nil and '' or item.label, 'label', 0, 60, true)
        if not label then return nil, err end
        if not clockTime(item.time) then return nil, 'time must look like 07:30' end
        if type(item.enabled) ~= 'boolean' then return nil, 'enabled must be a boolean' end
        local days, seen = {}, {}
        if item.days ~= nil then
            if type(item.days) ~= 'table' or #item.days > 7 then return nil, 'days is invalid' end
            for _, day in ipairs(item.days) do
                local value; value, err = PhoneValidation.integer(day, 'day', 0, 6)
                if not value then return nil, err end
                if not seen[value] then seen[value] = true; days[#days + 1] = value end
            end
            table.sort(days)
        end
        return { id = id, label = label, time = item.time, days = days, enabled = item.enabled }
    elseif kind == 'station' then
        local label; label, err = PhoneValidation.string(item.label, 'label', 1, 60)
        if not label then return nil, err end
        local url; url, err = PhoneValidation.string(item.url, 'url', 1, 500)
        if not url then return nil, err end
        if url:sub(1, 8) ~= 'https://' then return nil, 'url must be an https URL' end
        return { id = id, label = label, url = url }
    end
    return nil, 'kind is invalid'
end
