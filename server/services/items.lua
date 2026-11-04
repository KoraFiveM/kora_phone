KoraPhone.Services = KoraPhone.Services or {}
local Items = {}
KoraPhone.Services.Items = Items

local GROUP = { note = 'notes', alarm = 'alarms', station = 'stations' }

local function invalid(message) return PhoneError(PhoneConstants.Errors.INVALID_INPUT, message) end

-- Everything a phone keeps, grouped for the bootstrap: { notes = {}, alarms = {}, stations = {} }.
function Items.forDevice(deviceId)
    local out = { notes = {}, alarms = {}, stations = {} }
    for _, row in ipairs(KoraPhone.Repositories.Items.list(deviceId)) do
        local ok, decoded = pcall(json.decode, row.payload)
        local group = out[GROUP[row.kind]]
        if ok and type(decoded) == 'table' and group then group[#group + 1] = decoded end
    end
    return out
end

function Items.save(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    payload = type(payload) == 'table' and payload or {}
    local kind = payload.kind
    if not GROUP[kind] then return invalid('kind is invalid') end
    local item, validationError = PhoneValidation.item(kind, payload.item)
    if not item then return invalid(validationError) end
    local repo = KoraPhone.Repositories.Items
    if not repo.exists(device.id, kind, item.id) and repo.count(device.id, kind) >= Config.Server.Items[kind] then
        return PhoneError(PhoneConstants.Errors.CONFLICT, ('You can keep up to %d %s'):format(Config.Server.Items[kind], GROUP[kind]))
    end
    if not repo.upsert(device.id, kind, item.id, json.encode(item)) then
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to save')
    end
    return PhoneResult(item)
end

function Items.remove(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    payload = type(payload) == 'table' and payload or {}
    if not GROUP[payload.kind] then return invalid('kind is invalid') end
    local id, validationError = PhoneValidation.string(payload.id, 'id', 1, 64)
    if not id then return invalid(validationError) end
    KoraPhone.Repositories.Items.remove(device.id, payload.kind, id)
    return PhoneResult({ id = id })
end