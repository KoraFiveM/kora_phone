SteviePhone = SteviePhone or {}

-- Lets other resources add installable apps to the phone: a native export, plus
-- alias exports that answer the same calls other FiveM phone scripts use, so an
-- addon app already written for one of them can register here unmodified.
--
-- Verified against each project's own docs/source (lb-phone: docs.lbscripts.com;
-- sd-phone: docs.samueldev.shop; 17mov_Phone: 17movement-net/17mov_Phone_app_boilerplate;
-- YSeries: teamsgg.dev; High Phone: high-phone/app-templates). This reproduces
-- each ecosystem's Lua registration/messaging surface. An addon UI that calls
-- that OTHER phone's own injected JS globals (`fetchNui`, `window.hphone`,
-- `components.*`) can get the data-bridge half of that (fetchNui/onNuiEvent/
-- resourceName/appName/settings) by adding web/public/compat.js as a script
-- tag -- see that file. Full UI component libraries (popups, pickers, maps)
-- are not reproduced; that's a much bigger, phone-specific surface.
local apps = {}

-- Job gating is a display filter, same trust level as the rest of this NUI --
-- it decides what the App Store SHOWS, not a security boundary. Whatever the
-- app actually lets you do once open is still whatever its own resource
-- enforces server-side.
local function jobMatches(job)
    if job == nil then return true end
    local player = SteviePhone.QBCore.Functions.GetPlayerData()
    local current = player and player.job
    if not current then return false end
    local function matchesOne(spec)
        if type(spec) == 'string' then return current.name == spec end
        if type(spec) ~= 'table' then return false end
        if current.name ~= spec.name then return false end
        if spec.grade == nil then return true end
        local grade = type(current.grade) == 'table' and (current.grade.level or current.grade.name) or current.grade
        return type(grade) == 'number' and grade >= spec.grade
    end
    if type(job) == 'table' and job[1] ~= nil then
        for _, spec in ipairs(job) do if matchesOne(spec) then return true end end
        return false
    end
    return matchesOne(job)
end

local function list()
    local result = {}
    for _, app in pairs(apps) do
        if jobMatches(app.job) then
            result[#result + 1] = {
                identifier = app.identifier, name = app.name, description = app.description,
                resource = app.resource, ui = app.ui, icon = app.icon, defaultApp = app.defaultApp,
                price = app.price,
            }
        end
    end
    return result
end

-- A couple of ecosystems (e.g. High Phone's "@resource/path" convention) fold
-- the resource name into the ui path itself; our own frontend re-qualifies a
-- bare relative path against `resource` on its own, so a redundant prefix here
-- would double it up.
local function stripResourcePrefix(ui, resource)
    ui = ui:gsub('^@', '')
    local prefix = resource .. '/'
    if not ui:find('^https?://') and ui:sub(1, #prefix) == prefix then ui = ui:sub(#prefix + 1) end
    return ui
end

local function register(app)
    if type(app) ~= 'table' or type(app.identifier) ~= 'string' or app.identifier == '' then
        return false, 'INVALID_APP'
    end
    if type(app.ui) ~= 'string' or app.ui == '' then return false, 'INVALID_UI' end
    local resource = type(app.resource) == 'string' and app.resource ~= '' and app.resource or GetInvokingResource() or 'unknown'
    apps[app.identifier] = {
        identifier = app.identifier,
        name = type(app.name) == 'string' and app.name ~= '' and app.name or app.identifier,
        description = type(app.description) == 'string' and app.description or '',
        resource = resource,
        ui = stripResourcePrefix(app.ui, resource),
        icon = type(app.icon) == 'string' and app.icon or nil,
        defaultApp = app.defaultApp == true,
        job = app.job,
        -- Purchases aren't charged or persisted anywhere -- this is a display-only
        -- price tag until a real payment/entitlement flow is asked for. Skipped
        -- rather than half-built, since a price nobody actually collects is worse
        -- than no price shown at all.
        price = tonumber(app.price),
        lifecycle = {
            onOpen = type(app.onOpen) == 'function' and app.onOpen or nil,
            onClose = type(app.onClose) == 'function' and app.onClose or nil,
            onInstall = type(app.onInstall) == 'function' and app.onInstall or nil,
            onDelete = type(app.onDelete) == 'function' and app.onDelete or nil,
        },
    }
    SendNUIMessage({ type = 'customRegistry' })
    return true
end

local function unregister(identifier)
    if type(identifier) == 'table' then identifier = identifier.identifier or identifier.name end
    if type(identifier) ~= 'string' or not apps[identifier] then return false, 'NOT_FOUND' end
    apps[identifier] = nil
    SendNUIMessage({ type = 'customRegistry' })
    return true
end

local function sendMessage(identifier, data)
    if type(identifier) ~= 'string' or not apps[identifier] then return false, 'NOT_FOUND' end
    SendNUIMessage({ type = 'customMessage', app = identifier, data = data })
    return true
end

local function fire(identifier, event)
    local app = apps[identifier]
    local callback = app and app.lifecycle[event]
    if callback then callback() end
end

-- A few ecosystems also ship a general "send a phone notification" export, separate from
-- the app-registration/messaging contract, that real custom apps call directly (e.g. to
-- alert the player from a server-pushed event). Not aliasing it doesn't just mean it does
-- nothing -- FiveM's export lookup throws in the CALLING resource if nothing answers, so an
-- addon that calls it would error every time. Routed to the same native alert the rest of
-- this phone already uses; it will not appear as a custom-app notification in the shade,
-- since that needs the app's own icon/tap-through, which isn't built.
local function sendNotification(data)
    if type(data) ~= 'table' then return false end
    local title = type(data.title) == 'string' and data.title or 'Notification'
    local body = type(data.content) == 'string' and data.content or (type(data.body) == 'string' and data.body or '')
    return SteviePhone.Notifications.Native(title, body, false)
end

-- Native contract.
exports('RegisterApp', register)
exports('RemoveApp', unregister)
exports('SendAppMessage', sendMessage)

-- FiveM resolves `exports['name']:Fn(...)` through a local event named
-- `__cfx_export_<name>_<Fn>` (see citizenfx/fivem's scheduler.lua), regardless
-- of what the answering resource is actually called. Registering that event
-- ourselves is how another resource's phone script can be swapped for this one
-- without the addon changing a line -- the same trick sd-phone and sky_phone
-- use to inherit the lb-phone app ecosystem.
local function alias(resource, name, handler)
    AddEventHandler(('__cfx_export_%s_%s'):format(resource, name), function(setCB) setCB(handler) end)
end

-- lb-phone (docs.lbscripts.com/phone/exports/client-exports)
alias('lb-phone', 'AddCustomApp', function(app)
    return register(type(app) == 'table' and {
        identifier = app.identifier, name = app.name, description = app.description, ui = app.ui,
        icon = app.icon, defaultApp = app.defaultApp, price = app.price,
        onOpen = app.onOpen, onClose = app.onClose, onInstall = app.onInstall, onDelete = app.onDelete,
    } or nil)
end)
alias('lb-phone', 'RemoveCustomApp', unregister)
alias('lb-phone', 'SendCustomAppMessage', sendMessage)
alias('lb-phone', 'SendNotification', sendNotification)

-- sd-phone (docs.samueldev.shop/resources/phone/custom-apps)
alias('sd-phone', 'addCustomApp', function(app)
    return register(type(app) == 'table' and {
        identifier = app.identifier, name = app.name, description = app.description, ui = app.ui,
        icon = app.icon, defaultApp = app.defaultApp, job = app.job,
        onOpen = app.onOpen, onClose = app.onClose, onDelete = app.onDelete,
    } or nil)
end)
alias('sd-phone', 'removeCustomApp', unregister)
alias('sd-phone', 'sendCustomAppMessage', sendMessage)

-- 17mov_Phone (17movement-net/17mov_Phone_app_boilerplate, client/main.lua)
alias('17mov_Phone', 'AddApplication', function(app)
    return register(type(app) == 'table' and {
        identifier = app.name, name = app.label, description = app.description,
        ui = app.ui, icon = app.icon, defaultApp = app.default == true or app.preInstalled == true,
        resource = app.resourceName, job = app.job,
    } or nil)
end)
alias('17mov_Phone', 'RemoveApplication', unregister)
alias('17mov_Phone', 'SendAppMessage', sendMessage)

-- YSeries (teamsgg.dev/docs/paid-scripts/phone)
alias('yseries', 'AddCustomApp', function(app)
    return register(type(app) == 'table' and {
        identifier = app.key, name = app.name, description = app.description,
        ui = app.ui, icon = app.icon, defaultApp = app.defaultApp,
    } or nil)
end)
alias('yseries', 'RemoveCustomApp', unregister)
alias('yseries', 'SendAppMessage', sendMessage)

-- High Phone (high-phone/app-templates, client/main.lua). Its own docs don't
-- list addApplication/removeApplication, but the official template calls it
-- exactly like this, with the identifier as its own argument and the label/
-- description keyed by locale.
alias('high-phone', 'addApplication', function(identifier, app, locale)
    if type(app) ~= 'table' then return false, 'INVALID_APP' end
    local strings = type(locale) == 'table' and (locale.en or select(2, next(locale) or nil)) or nil
    return register({
        identifier = identifier,
        name = type(strings) == 'table' and strings.label or nil,
        description = type(strings) == 'table' and strings.description or nil,
        ui = app.externalUrl,
        icon = type(app.icon) == 'table' and app.icon.imageUrl or nil,
        defaultApp = app.preAdded == true,
    })
end)
-- Not documented or seen in the template; inferred from addApplication's own
-- naming (camelCase, symmetrical Add/Remove pair). If this guess is wrong it
-- is a harmless no-op -- nothing calls this event name, so nothing breaks.
alias('high-phone', 'removeApplication', unregister)
alias('high-phone', 'sendAppNui', sendMessage)
alias('high-phone', 'sendNotification', sendNotification)

AddEventHandler('onResourceStop', function(resource)
    for identifier, app in pairs(apps) do
        if app.resource == resource then apps[identifier] = nil end
    end
end)

SteviePhone.CustomApps = { List = list, Fire = fire }
