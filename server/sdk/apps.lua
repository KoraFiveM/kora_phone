KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Server half of Phone.app: registers every definition from apps/<id>/app.lua with the SDK registry
-- (owned by this resource) and gives the handle its server methods.
local SDK = KoraPhone.SDK
local Apps = KoraPhone.Apps
local SELF = GetCurrentResourceName()
local methods = Apps.methods

---Registers every defined folder app. Called once when this file loads (the definitions are shared scripts).
---@return integer registered
function Apps.registerAll()
    local registered = 0
    for _, id in ipairs(Apps.order) do
        -- Config.Apps.<id> = false switches a folder app off (admins edit it with /config).
        local switches = Config and Config.Apps
        if switches and switches[id] == false then goto continue end
        local ok, err = SDK.Registry.register(Apps.manifest(id, Apps.defs[id]), SELF, { files = SDK.Discovery.files })
        if ok then
            registered = registered + 1
        else
            Kora.logging.event('phone.app.rejected', 0, { level = 'error', message = 'Folder app rejected', app = id, error = err })
        end
        ::continue::
    end
    return registered
end

---Registers the server callback `name` for the app. The handler receives (source, payload).
---@param options? { rate?: string } a Config.Server.RateLimits bucket to charge (for example 'bankTransfer')
function methods.callback(id, name, handler, options)
    local ok, err = SDK.Callbacks.register(id, name, handler, SELF, options)
    if not ok then error(('Phone.app(%q).callback(%q): %s'):format(id, tostring(name), tostring(err)), 2) end
end

---Sends an event to the app's open UI for one player. The UI hears it through `phone.on(name, fn)`.
function methods.send(id, source, name, data)
    if type(source) ~= 'number' or source <= 0 or not SDK.Callbacks.validName(name) then return false end
    TriggerClientEvent('kora_phone:client:appEvent', source, id, name, data)
    return true
end

---Shows a notification for one player.
function methods.notify(id, source, title, body)
    local app = SDK.Registry.get(id)
    if not app or type(source) ~= 'number' or source <= 0 or type(title) ~= 'string' or title == '' then return false end
    TriggerClientEvent('kora_phone:client:appNotify', source, id, app.name, title:sub(1, 48), type(body) == 'string' and body:sub(1, 200) or '')
    return true
end

local function deviceOf(source)
    local device = KoraPhone.Permissions.requireDevice(source)
    return device
end

---Per-player storage of the held phone, with the same quotas the UI storage has.
---@return any value, table? err
function methods.getStorage(id, source, key)
    local device = deviceOf(source)
    if not device then return nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'No phone') end
    return SDK.Storage.get(device.id, id, key)
end

function methods.listStorage(id, source, prefix)
    local device = deviceOf(source)
    if not device then return nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'No phone') end
    return SDK.Storage.list(device.id, id, prefix)
end

function methods.setStorage(id, source, key, value)
    local device = deviceOf(source)
    if not device then return nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'No phone') end
    return SDK.Storage.set(device.id, id, key, value)
end

function methods.removeStorage(id, source, key)
    local device = deviceOf(source)
    if not device then return nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'No phone') end
    return SDK.Storage.remove(device.id, id, key)
end

---Turns a service result (PhoneResult or PhoneError) into what an app callback returns: the data on success, and on
---failure the error is raised so the UI receives its code and message.
---@param result table
---@return any data
function Phone.unwrap(result)
    if type(result) ~= 'table' then error(PhoneError(PhoneConstants.Errors.INTERNAL, 'Request failed'), 0) end
    if result.ok == false then error(result, 0) end
    return result.data
end

Apps.registerAll()

-- A phone restart keeps its folder apps: `onResourceStop` for this resource clears the registry by itself.
