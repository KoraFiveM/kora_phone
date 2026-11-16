KoraPhone.Services = KoraPhone.Services or {}
local Garage = {}
KoraPhone.Services.Garage = Garage

local STATE_CODES = { out = 0, garaged = 1, impounded = 2 }

---The Garage app lists the character's vehicles through kora_garages' `getOwnedVehicles` export.
function Garage.available()
    return Config.Server.Garage.Enabled == true and GetResourceState('kora_garages') == 'started'
end

---One vehicle in the shape the Vehicles screen reads: vehicle, plate, garage, state (0 out, 1 garaged,
---2 impounded) and fuel. `row` is a kora_garages owned-vehicle entry.
---@param row table
---@param useLabels boolean show the garage name instead of its raw id
---@return table
local function publicVehicle(row, useLabels)
    local garage = useLabels and row.garageLabel or row.garage
    return {
        vehicle = tostring(row.label or row.model or ''),
        plate = tostring(row.plate or ''),
        garage = tostring(garage or ''),
        state = STATE_CODES[row.state] or 0,
        fuel = tonumber(row.fuel) or 0,
    }
end

---Yields: kora_garages reads the character's vehicles from the database.
function Garage.list(source)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    if not Garage.available() then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Garage is not available') end
    local owned = exports.kora_garages:getOwnedVehicles(device.ownerCitizenId)
    if type(owned) ~= 'table' then return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to load vehicles') end
    local useLabels = Config.Server.Garage.UseGarageLabels == true
    local vehicles = {}
    for index, row in ipairs(owned) do
        vehicles[index] = publicVehicle(row, useLabels)
    end
    return PhoneResult(vehicles)
end
