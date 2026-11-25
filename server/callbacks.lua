-- Server callback gateway. shared/routes.json is the single source of truth for every phone route:
-- its `server` name, rate bucket and `app` launch gate. Service modules only bind handlers:
--
--     KoraPhone.Routes.handle('getContacts', KoraPhone.Services.Contacts.list)
--
-- The name is the part after `kora_phone:server:`. Handlers are looked up at call time, so load order
-- between modules does not matter; Routes.unbound() lists routes that never got a handler.

KoraPhone.Routes = KoraPhone.Routes or {}
local Routes = KoraPhone.Routes
Routes.handlers = Routes.handlers or {}
Routes.byName = Routes.byName or {}

local PREFIX = 'kora_phone:server:'
local BACKUP_DELAY_MS = 1500
local Errors = PhoneConstants.Errors

-- Server-only callbacks the NUI never calls (the client uses them directly), so they are not in routes.json.
local EXTRA_ROUTES = {
    { server = PREFIX .. 'share:offer', rate = 'shareNumber' },
}

---@class PhoneRouteOptions
---@field async? boolean Handler is `fn(source, payload, reply)` and replies once, possibly later; it is never handset-locked.
---@field lock? boolean Serialise the call per player through Handsets.locked. Defaults to true (ignored when async).

---Binds the handler for a route.
---@param name string Server name without the `kora_phone:server:` prefix.
---@param handler function
---@param options? PhoneRouteOptions
function Routes.handle(name, handler, options)
    assert(type(name) == 'string' and type(handler) == 'function', 'Routes.handle(name, handler)')
    Routes.handlers[name] = { fn = handler, async = options and options.async == true, lock = not options or options.lock ~= false }
end

---Deprecated shim for modules still passing a rate key; the rate now comes from routes.json.
---@param name string
---@param _ string
---@param handler function
function KoraPhone.registerCallback(name, _, handler)
    Routes.handle(name, handler)
end

---@param route table
---@return table|nil denied
local function launchDenied(route)
    if route.app and (Config.Apps or {})[route.app] == false then
        return PhoneError(Errors.FORBIDDEN, 'This app is not part of this release')
    end
end

local function handsets()
    return KoraPhone.Handsets
end

local function runAsync(bound, source, payload, route)
    local response = promise.new()
    local replied = false
    local function reply(result)
        if replied then return end
        replied = true
        response:resolve(result or PhoneError(Errors.INTERNAL, 'Empty service response'))
    end
    local ok, err = xpcall(function() bound.fn(source, payload, reply) end, debug.traceback)
    if not ok then
        Kora.logging.event('phone.callback_failed', source, {
            level = 'error', message = 'Phone callback failed',
            callback = route.name, playerId = source, error = tostring(err),
        })
        reply(PhoneError(Errors.INTERNAL, 'Request failed'))
    end
    return Citizen.Await(response)
end

-- A successful change marks the handset used again and schedules a cloud backup.
local function afterMutation(source)
    local H = handsets()
    local device = H.current(source, false)
    if device then H.clearReset(device.handsetId) end
    KoraPhone.After(BACKUP_DELAY_MS, function()
        if H.selected[source] then H.locked(source, H.backup, {}) end
    end)
end

---Runs one route for a player: rate limit, normalise, app gate, lock, session guard, backup.
---@param route table { name, rate, app }
---@param source integer
---@param payload any
---@return table result PhoneResult or PhoneError
function Routes.invoke(route, source, payload)
    if not KoraPhone.RateLimits.consume(source, route.rate) then
        return PhoneError(Errors.RATE_LIMITED, 'Too many requests')
    end
    payload = type(payload) == 'table' and payload or {}
    local denied = launchDenied(route)
    if denied then return denied end
    local bound = Routes.handlers[route.name]
    if not bound then
        Kora.logging.event('phone.route_unbound', source, {
            level = 'error', message = 'Phone route has no handler',
            callback = route.name, playerId = source,
        })
        return PhoneError(Errors.INTERNAL, 'Request failed')
    end
    if bound.async then return runAsync(bound, source, payload, route) end

    local H = handsets()
    local selected = H and H.selected[source]
    local character = KoraPhone.GetCitizenId(source)
    local isHandsetAction = route.name == 'handsetAction'
    local ok, result = xpcall(function()
        if H and bound.lock and not isHandsetAction then
            return H.locked(source, bound.fn, payload)
        end
        return bound.fn(source, payload)
    end, debug.traceback)
    if not ok then
        Kora.logging.event('phone.callback_failed', source, {
            level = 'error', message = 'Phone callback failed',
            callback = route.name, playerId = source, error = tostring(result),
        })
        return PhoneError(Errors.INTERNAL, 'Request failed')
    end

    local selectionChanged = isHandsetAction and (payload.op == 'select' or payload.op == 'reset')
    local sessionMoved = KoraPhone.GetCitizenId(source) ~= character
        or (not selectionChanged and selected and H.selected[source] ~= selected)
    if sessionMoved then return PhoneError(Errors.FORBIDDEN, 'Handset session changed') end

    local mutating = route.rate == 'mutation' or route.rate == 'sendMessage'
    if result and result.ok and mutating and not isHandsetAction then afterMutation(source) end
    return result or PhoneError(Errors.INTERNAL, 'Empty service response')
end

---Registers one Kora callback per distinct server name.
---@param list table[] Entries shaped like routes.json plus extra routes (`nui` optional).
function Routes.register(list)
    for _, entry in ipairs(list) do
        local name = entry.server:sub(#PREFIX + 1)
        local existing = Routes.byName[name]
        if existing then
            assert(existing.rate == entry.rate and existing.app == entry.app,
                ('route %s is listed twice with different rate or app'):format(name))
        else
            local route = { name = name, rate = entry.rate, app = entry.app }
            Routes.byName[name] = route
            Kora.callback.register(entry.server, function(source, payload)
                return Routes.invoke(route, source, payload)
            end)
        end
    end
end

---@return string[] names Registered routes that no module bound a handler to.
function Routes.unbound()
    local missing = {}
    for name in pairs(Routes.byName) do
        if not Routes.handlers[name] then missing[#missing + 1] = name end
    end
    table.sort(missing)
    return missing
end

local function loadRoutes()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'shared/routes.json')
    local list = raw and json.decode(raw)
    assert(type(list) == 'table', 'shared/routes.json is missing or invalid')
    return list
end

Routes.register(loadRoutes())
Routes.register(EXTRA_ROUTES)

-- Core phone routes.
local Services = KoraPhone.Services
local bind = Routes.handle
bind('getBootstrap', Services.Phone.bootstrap)
bind('saveSettings', Services.Phone.saveSettings)
bind('unlockPhone', Services.Phone.unlock)
bind('lockPhone', Services.Phone.lock)
bind('setPhonePin', Services.Phone.setPin)
bind('removePhonePin', Services.Phone.removePin)
bind('getContacts', Services.Contacts.list)
bind('saveContact', Services.Contacts.save)
bind('deleteContact', Services.Contacts.delete)
bind('share:offer', Services.Share.offer)
bind('share:answer', Services.Share.answer)
bind('sendMessage', Services.Messaging.send)
bind('getMessages', Services.Messaging.list)
bind('getConversations', Services.Messaging.listConversations)
bind('startDirectConversation', Services.Messaging.startDirect)
bind('markConversationRead', Services.Messaging.markRead)
bind('createGroup', Services.Messaging.createGroup)
bind('leaveGroup', Services.Messaging.leaveGroup)
bind('addGroupMember', Services.Messaging.addMember)
bind('getBlocked', Services.Blocking.list)
bind('setBlocked', Services.Blocking.set)
bind('getMail', Services.Mail.list)
bind('sendMail', Services.Mail.send)
bind('readMail', Services.Mail.markRead)
bind('deleteMail', Services.Mail.delete)

-- Third-party app SDK (server/sdk/routes.lua). Looked up when
-- called so neither module has to load first. SDK calls can overlap (an app reads several keys on
-- start), so they skip the per-player handset lock.
local function lazy(getTable, key)
    return function(source, payload)
        local handlers = getTable()
        local handler = handlers and handlers[key]
        if not handler then return PhoneError(Errors.INTERNAL, 'Request failed') end
        return handler(source, payload)
    end
end

for _, key in ipairs({
    'apps:list', 'apps:install', 'apps:uninstall', 'apps:call', 'apps:storage:get', 'apps:storage:list',
    'apps:storage:set', 'apps:storage:remove', 'apps:contacts:list', 'apps:contacts:save', 'apps:notify',
}) do
    bind(key, lazy(function() return KoraPhone.SDK and KoraPhone.SDK.routes end, key), { lock = false })
end


-- Lets the client tell a downed player with no phone item apart from one who simply cannot use it right now.
Kora.callback.register(PREFIX .. 'hasPhone', function(source)
    return KoraPhone.HasPhone(source) == true
end)
