KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Client-side registry of apps registered through the client exports (RegisterApp and the
-- lb-phone / sd-phone / 17mov_Phone / yseries / high-phone aliases). These apps have UI and
-- their own resource logic only: they hold no server permissions.
local ClientRegistry = { apps = {} }
KoraPhone.SDK.ClientRegistry = ClientRegistry

-- Job gating is a display filter, same trust level as the rest of this NUI: it decides what
-- the App Store SHOWS, not a security boundary.
local function matchesOne(current, spec)
    if type(spec) == 'string' then return current.name == spec end
    if type(spec) ~= 'table' or current.name ~= spec.name then return false end
    if spec.grade == nil then return true end
    local grade = current.grade
    -- Grades are one-based (kora_core): spec.grade is the minimum one-based grade, same as the server.
    if type(grade) == 'table' then grade = grade.level end
    return type(grade) == 'number' and grade >= spec.grade
end

function ClientRegistry.jobMatches(job)
    if job == nil then return true end
    local player = exports.kora_core:getPlayerData()
    local current = player and player.job
    if not current then return false end
    if type(job) == 'table' and job[1] ~= nil then
        for _, spec in ipairs(job) do
            if matchesOne(current, spec) then return true end
        end
        return false
    end
    return matchesOne(current, job)
end

-- A function handed over through an export arrives as a callable funcref table.
function ClientRegistry.callable(value)
    if type(value) == 'function' then return value end
    if type(value) ~= 'table' then return nil end
    if type(rawget(value, '__cfx_functionReference')) == 'string' then return value end
    local meta = getmetatable(value)
    return type(meta) == 'table' and meta.__call ~= nil and value or nil
end

-- Some ecosystems (High Phone's "@resource/path") fold the resource name into the ui path;
-- the frontend re-qualifies a bare path against `resource`, so a prefix would double up.
local function stripResourcePrefix(ui, resource)
    ui = ui:gsub('^@', '')
    local prefix = resource .. '/'
    if not ui:find('^https?://') and ui:sub(1, #prefix) == prefix then ui = ui:sub(#prefix + 1) end
    return ui
end

local function text(value, fallback)
    return type(value) == 'string' and value ~= '' and value or fallback
end

local function notifyUi()
    SendNUIMessage({ type = 'customRegistry' })
end

function ClientRegistry.register(app, invokingResource)
    if type(app) ~= 'table' or type(app.identifier) ~= 'string' or app.identifier == '' then
        return false, 'INVALID_APP'
    end
    if type(app.ui) ~= 'string' or app.ui == '' then return false, 'INVALID_UI' end
    local resource = text(app.resource, invokingResource or 'unknown')
    ClientRegistry.apps[app.identifier] = {
        identifier = app.identifier,
        name = text(app.name, app.identifier),
        description = type(app.description) == 'string' and app.description or '',
        resource = resource,
        ui = stripResourcePrefix(app.ui, resource),
        icon = type(app.icon) == 'string' and app.icon or nil,
        defaultApp = app.defaultApp == true,
        job = app.job,
        -- Display only: no payment or entitlement flow collects this price.
        price = tonumber(app.price),
        lifecycle = {
            onOpen = ClientRegistry.callable(app.onOpen),
            onClose = ClientRegistry.callable(app.onClose),
            onInstall = ClientRegistry.callable(app.onInstall),
            onDelete = ClientRegistry.callable(app.onDelete),
        },
    }
    notifyUi()
    return true
end

function ClientRegistry.unregister(identifier)
    if type(identifier) == 'table' then identifier = identifier.identifier or identifier.name end
    if type(identifier) ~= 'string' or not ClientRegistry.apps[identifier] then return false, 'NOT_FOUND' end
    ClientRegistry.apps[identifier] = nil
    notifyUi()
    return true
end

function ClientRegistry.removeByResource(resource)
    local removed = false
    for identifier, app in pairs(ClientRegistry.apps) do
        if app.resource == resource then
            ClientRegistry.apps[identifier] = nil
            removed = true
        end
    end
    return removed
end

--- Same data shape as the server `apps:list`, plus the legacy fields (`identifier`, `ui`).
function ClientRegistry.list()
    local result = {}
    for _, app in pairs(ClientRegistry.apps) do
        if ClientRegistry.jobMatches(app.job) then
            result[#result + 1] = {
                id = app.identifier, identifier = app.identifier, name = app.name,
                description = app.description, resource = app.resource, ui = app.ui,
                icon = app.icon, defaultApp = app.defaultApp, defaultInstalled = app.defaultApp,
                price = app.price, permissions = {}, source = 'client',
            }
        end
    end
    table.sort(result, function(a, b) return a.identifier < b.identifier end)
    return result
end

ClientRegistry.MAX_HTML_BYTES = 1024 * 1024

--- The page of a client-registered app, read from its own resource, so the phone can inject the lb-phone
--- compatibility layer ahead of the app's scripts. Nil for apps whose UI is a URL, and for anything unreadable.
function ClientRegistry.html(identifier)
    local app = type(identifier) == 'string' and ClientRegistry.apps[identifier]
    if not app or app.ui:find('^https?://') then return nil end
    local path = app.ui:gsub('^/+', '')
    if path:find('..', 1, true) or not path:match('%.html?$') then return nil end
    local html = LoadResourceFile(app.resource, path)
    if type(html) ~= 'string' or #html > ClientRegistry.MAX_HTML_BYTES then return nil end
    return html
end

function ClientRegistry.sendMessage(identifier, data)
    if type(identifier) ~= 'string' or not ClientRegistry.apps[identifier] then return false, 'NOT_FOUND' end
    SendNUIMessage({ type = 'customMessage', app = identifier, data = data })
    return true
end

--- Runs a lifecycle hook (onOpen, onClose, onInstall, onDelete) of a client-registered app.
function ClientRegistry.fire(identifier, event)
    local app = ClientRegistry.apps[identifier]
    local callback = app and app.lifecycle[event]
    if callback then callback() end
end
