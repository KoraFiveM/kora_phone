KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Per-app server callbacks. Each one is exposed twice, through the same gate:
--   * `apps:call` {app, name, payload} from the phone UI
--   * `Kora.callback` name `app:<id>:<name>` (rate limited) for callers that use kora_lib
-- The handler belongs to the app's resource, so it is dropped when the app is removed.
local Callbacks = { handlers = {} }
KoraPhone.SDK.Callbacks = Callbacks

Callbacks.NAME_PATTERN = '^[a-zA-Z0-9_:.-]+$'
Callbacks.MAX_NAME = 48
Callbacks.MAX_RESULT_BYTES = 64 * 1024
Callbacks.DEFAULT_RATE_LIMIT = { max = 30, window = 10000 }

-- A function passed through an export arrives as a callable funcref table.
function Callbacks.isCallable(value)
    if type(value) == 'function' then return true end
    if type(value) ~= 'table' then return false end
    if type(rawget(value, '__cfx_functionReference')) == 'string' then return true end
    local meta = getmetatable(value)
    return type(meta) == 'table' and meta.__call ~= nil
end

function Callbacks.validName(name)
    return type(name) == 'string' and #name >= 1 and #name <= Callbacks.MAX_NAME and name:match(Callbacks.NAME_PATTERN) ~= nil
end

function Callbacks.fullName(appId, name)
    return ('app:%s:%s'):format(appId, name)
end

local function rateLimit()
    local configured = Config and Config.Server and Config.Server.SdkCallbackRateLimit
    return configured or Callbacks.DEFAULT_RATE_LIMIT
end

--- Runs a registered callback after the full gate. Returns a PhoneResult or PhoneError.
function Callbacks.invoke(source, appId, name, payload)
    local errors = PhoneConstants.Errors
    if not Callbacks.validName(name) then return PhoneError(errors.INVALID_INPUT, 'Invalid callback name') end
    local device, app, err = KoraPhone.SDK.Permissions.gate(source, appId)
    if not device then return err end
    local entry = Callbacks.handlers[app.id] and Callbacks.handlers[app.id][name]
    if not entry then return PhoneError(errors.NOT_FOUND, 'Callback is not registered') end

    local ok, result = pcall(entry.handler, source, payload)
    if not ok then
        Kora.logging.error('phone.sdk.callback_failed', 'App callback failed', {
            app = app.id, callback = name, error = tostring(result),
        })
        return PhoneError(errors.INTERNAL, 'App callback failed')
    end
    local encodedOk, encoded = pcall(json.encode, result)
    if not encodedOk or type(encoded) ~= 'string' or #encoded > Callbacks.MAX_RESULT_BYTES then
        return PhoneError(errors.INTERNAL, 'App callback returned an invalid result')
    end
    return PhoneResult(result)
end

---@param resource string must own the app
---@return boolean ok
---@return string? err
function Callbacks.register(appId, name, handler, resource)
    local app = KoraPhone.SDK.Registry.get(appId)
    if not app then return false, 'NOT_FOUND: app is not registered' end
    if app.resource ~= resource then return false, 'FORBIDDEN: app belongs to another resource' end
    if not Callbacks.validName(name) then return false, 'INVALID_INPUT: callback name is invalid' end
    if not Callbacks.isCallable(handler) then return false, 'INVALID_INPUT: handler must be a function' end

    Callbacks.handlers[appId] = Callbacks.handlers[appId] or {}
    local replaced = Callbacks.handlers[appId][name] ~= nil
    Callbacks.handlers[appId][name] = { handler = handler, resource = resource }
    if not replaced then
        Kora.callback.register(Callbacks.fullName(appId, name), function(source, payload)
            return Callbacks.invoke(source, appId, name, payload)
        end, { rateLimit = rateLimit() })
    end
    return true
end

function Callbacks.removeApp(appId)
    for name in pairs(Callbacks.handlers[appId] or {}) do
        Kora.callback.unregister(Callbacks.fullName(appId, name))
    end
    Callbacks.handlers[appId] = nil
end

KoraPhone.SDK.Registry.onRemove(Callbacks.removeApp)
