KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Client half of Phone.app: handle methods for apps/<id>/client.lua and the `apps:client` NUI route
-- the UI uses (`phone.client(name, payload)`) to reach them.
local Apps = KoraPhone.Apps
local methods = Apps.methods

local clientHandlers = {}
local eventHandlers = {}

---Registers a client-side callback. The UI calls it with `phone.client(name, payload)`; the return value is the reply.
function methods.client(id, name, handler)
    if type(name) ~= 'string' or name == '' or type(handler) ~= 'function' then
        error(('Phone.app(%q).client(name, handler): name must be a string and handler a function'):format(id), 2)
    end
    clientHandlers[id] = clientHandlers[id] or {}
    clientHandlers[id][name] = handler
end

---Runs `handler(data)` when the server sends the event `name` for this app (handle.send on the server).
function methods.on(id, name, handler)
    if type(name) ~= 'string' or name == '' or type(handler) ~= 'function' then
        error(('Phone.app(%q).on(name, handler): name must be a string and handler a function'):format(id), 2)
    end
    eventHandlers[id] = eventHandlers[id] or {}
    eventHandlers[id][name] = handler
end

---Pushes an event to this app's open UI.
function methods.push(id, name, data)
    return KoraPhone.SDK.Events.deliver(id, name, data)
end

---Runs a client callback for the NUI route. Returns `{ ok = true, data = ... }` or `{ ok = false, error = ... }`.
function Apps.invokeClient(id, name, payload)
    local handler = type(id) == 'string' and type(name) == 'string' and clientHandlers[id] and clientHandlers[id][name]
    if not handler then return { ok = false, error = 'NOT_FOUND' } end
    local ok, result = pcall(handler, payload)
    if not ok then
        Kora.logging.event('phone.app.client_failed', 0, { level = 'error', message = 'App client callback failed', app = id, callback = name, error = tostring(result) })
        return { ok = false, error = 'INTERNAL' }
    end
    return { ok = true, data = result }
end

RegisterNetEvent('kora_phone:client:appEvent', function(appId, name, data)
    local handler = eventHandlers[appId] and eventHandlers[appId][name]
    if handler then handler(data) end
end)
