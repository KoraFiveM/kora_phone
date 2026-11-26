KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Server-side gate every `apps:*` call and every app callback goes through. Permissions are
-- always read from the REGISTERED manifest, never from anything the client sent.
local Permissions = {}
KoraPhone.SDK.Permissions = Permissions

---@param source integer
---@param appId any
---@param permission? string manifest permission the call needs
---@return table? device
---@return table? app
---@return table? err PhoneError
function Permissions.gate(source, appId, permission)
    local errors = PhoneConstants.Errors
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return nil, nil, err end
    local app = KoraPhone.SDK.Registry.get(appId)
    if not app then return nil, nil, PhoneError(errors.NOT_FOUND, 'App is not registered') end
    if not KoraPhone.SDK.Registry.visibleTo(app, source) then
        return nil, nil, PhoneError(errors.FORBIDDEN, 'App is not available')
    end
    if not KoraPhone.SDK.Install.isInstalled(device, app) then
        return nil, nil, PhoneError(errors.FORBIDDEN, 'App is not installed')
    end
    if permission and not Kora.util.tableContains(app.permissions or {}, permission) then
        return nil, nil, PhoneError(errors.FORBIDDEN, ('App lacks the %s permission'):format(permission))
    end
    return device, app
end
