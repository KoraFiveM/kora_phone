KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- The `apps:*` handler set. The gateway registers each entry of KoraPhone.SDK.routes as
-- `function(source, payload) -> PhoneResult | PhoneError`.
local Permissions = KoraPhone.SDK.Permissions
local errors = PhoneConstants.Errors

local routes = {}

local MAX_TITLE, MAX_BODY, MAX_CONTACT_NAME = 48, 200, 64

local function payloadOf(value)
    return type(value) == 'table' and value or {}
end

local function invalid(message)
    return PhoneError(errors.INVALID_INPUT, message)
end

local function view(app, device)
    return {
        id = app.id, name = app.name, description = app.description, icon = app.icon,
        entry = app.entry, version = app.version, permissions = app.permissions, job = app.job,
        defaultInstalled = app.defaultInstalled, price = app.price, resource = app.resource,
        url = KoraPhone.SDK.Registry.url(app),
        installed = KoraPhone.SDK.Install.isInstalled(device, app),
    }
end

function routes.list(source)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local player = KoraPhone.GetPlayer(source)
    local job = player and player.job
    local apps = {}
    for _, app in ipairs(KoraPhone.SDK.Registry.list()) do
        local entry = view(app, device)
        if entry.installed or KoraPhone.SDK.Registry.jobMatches(app, job) then apps[#apps + 1] = entry end
    end
    return PhoneResult({ apps = apps })
end

local function install(source, payload, installed)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    local app = KoraPhone.SDK.Registry.get(payloadOf(payload).id)
    if not app then return PhoneError(errors.NOT_FOUND, 'App is not registered') end
    if not KoraPhone.SDK.Install.set(device, app.id, installed) then
        return PhoneError(errors.INTERNAL, 'Unable to save install state')
    end
    return PhoneResult({ id = app.id, installed = installed })
end

function routes.install(source, payload) return install(source, payload, true) end
function routes.uninstall(source, payload) return install(source, payload, false) end

function routes.call(source, payload)
    payload = payloadOf(payload)
    return KoraPhone.SDK.Callbacks.invoke(source, payload.app, payload.name, payload.payload)
end

function routes.storageGet(source, payload)
    payload = payloadOf(payload)
    local device, app, err = Permissions.gate(source, payload.app, 'storage')
    if not device then return err end
    local value, storageErr = KoraPhone.SDK.Storage.get(device.id, app.id, payload.key)
    if storageErr then return storageErr end
    return PhoneResult({ value = value })
end

function routes.storageSet(source, payload)
    payload = payloadOf(payload)
    local device, app, err = Permissions.gate(source, payload.app, 'storage')
    if not device then return err end
    local _, storageErr = KoraPhone.SDK.Storage.set(device.id, app.id, payload.key, payload.value)
    if storageErr then return storageErr end
    return PhoneResult({ saved = true })
end

function routes.storageRemove(source, payload)
    payload = payloadOf(payload)
    local device, app, err = Permissions.gate(source, payload.app, 'storage')
    if not device then return err end
    local _, storageErr = KoraPhone.SDK.Storage.remove(device.id, app.id, payload.key)
    if storageErr then return storageErr end
    return PhoneResult({ removed = true })
end

function routes.contactsList(source, payload)
    local device, _, err = Permissions.gate(source, payloadOf(payload).app, 'contacts.read')
    if not device then return err end
    local contacts = {}
    for _, row in ipairs(KoraPhone.Repositories.Contacts.list(device.id)) do
        contacts[#contacts + 1] = { id = row.id, name = row.displayName, number = row.phoneNumber }
    end
    return PhoneResult({ contacts = contacts })
end

function routes.contactsSave(source, payload)
    payload = payloadOf(payload)
    local device, _, err = Permissions.gate(source, payload.app, 'contacts.write')
    if not device then return err end
    local name, number = payload.name, payload.number
    if type(name) ~= 'string' or name == '' or #name > MAX_CONTACT_NAME then return invalid('Invalid contact name') end
    if type(number) ~= 'string' or not number:match('^[%d%+%-%s%(%)]+$') or #number < 3 or #number > 24 then
        return invalid('Invalid contact number')
    end
    local id = payload.id
    if id ~= nil and (type(id) ~= 'number' or id ~= math.floor(id) or id <= 0) then return invalid('Invalid contact id') end
    local saved = KoraPhone.Repositories.Contacts.upsert(device.id, {
        id = id, displayName = name, phoneNumber = number, isFavorite = false,
    })
    if not saved then return PhoneError(errors.NOT_FOUND, 'Contact was not saved') end
    return PhoneResult({ id = saved })
end

function routes.notify(source, payload)
    payload = payloadOf(payload)
    local device, app, err = Permissions.gate(source, payload.app, 'notify')
    if not device then return err end
    local title, body = payload.title, payload.body
    if type(title) ~= 'string' or title == '' or #title > MAX_TITLE then return invalid('Invalid notification title') end
    if body ~= nil and (type(body) ~= 'string' or #body > MAX_BODY) then return invalid('Invalid notification body') end
    TriggerClientEvent('kora_phone:client:appNotify', source, app.id, app.name, title, body or '')
    return PhoneResult({ sent = true })
end

KoraPhone.SDK.routes = {}
-- Route names exactly as the NUI sends them.
KoraPhone.SDK.routes['apps:list'] = routes.list
KoraPhone.SDK.routes['apps:install'] = routes.install
KoraPhone.SDK.routes['apps:uninstall'] = routes.uninstall
KoraPhone.SDK.routes['apps:call'] = routes.call
KoraPhone.SDK.routes['apps:storage:get'] = routes.storageGet
KoraPhone.SDK.routes['apps:storage:set'] = routes.storageSet
KoraPhone.SDK.routes['apps:storage:remove'] = routes.storageRemove
KoraPhone.SDK.routes['apps:contacts:list'] = routes.contactsList
KoraPhone.SDK.routes['apps:contacts:save'] = routes.contactsSave
KoraPhone.SDK.routes['apps:notify'] = routes.notify
