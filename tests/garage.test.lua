-- Run outside FiveM with: lua5.4 tests/garage.test.lua
local script = arg and arg[0] or 'tests/garage.test.lua'
local root = script:gsub('[\\/]tests[\\/]garage%.test%.lua$', '')
if root == script then root = '.' end

local passed = 0
local function check(value, message) assert(value, message) passed = passed + 1 end

local state = { resource = 'started', owned = nil, device = { ownerCitizenId = 'CID1' }, queried = {} }
KoraPhone = { Services = {}, Permissions = {} }
Config = { Server = { Garage = { Enabled = true, UseGarageLabels = true } } }
PhoneConstants = { Errors = { CONFLICT = 'CONFLICT', INTERNAL = 'INTERNAL_ERROR' } }
function PhoneError(code, message) return { ok = false, code = code, message = message } end
function PhoneResult(data) return { ok = true, data = data } end
function GetResourceState() return state.resource end
function KoraPhone.Permissions.requireDevice() return state.device, nil end
exports = { kora_garages = { getOwnedVehicles = function(_, citizenid)
    state.queried[#state.queried + 1] = citizenid
    return state.owned
end } }

dofile(root .. '/server/services/garage.lua')
local Garage = KoraPhone.Services.Garage

state.owned = {
    { plate = 'A1', model = 'blista', label = 'Dinka Blista', garage = 'legion', garageLabel = 'Legion Square',
        state = 'garaged', fuel = 80, engine = 900, body = 900 },
    { plate = 'B2', model = 'mystery', label = 'mystery', garage = 'house_x', garageLabel = 'House', state = 'out', fuel = 10 },
    { plate = 'C3', model = 'x', label = 'X', garage = '', garageLabel = 'None', state = 'impounded', fuel = 0 },
}
local result = Garage.list(1)
check(result.ok and #result.data == 3, 'three vehicles')
check(state.queried[1] == 'CID1', 'owner comes from the device, not the client')
local first = result.data[1]
check(first.vehicle == 'Dinka Blista' and first.plate == 'A1' and first.garage == 'Legion Square', 'shape and labels')
check(first.state == 1 and first.fuel == 80 and first.engine == nil, 'garaged is 1, only the screen fields')
check(result.data[2].state == 0 and result.data[2].garage == 'House', 'out is 0')
check(result.data[3].state == 2 and result.data[3].garage == 'None', 'impounded is 2')

Config.Server.Garage.UseGarageLabels = false
check(Garage.list(1).data[1].garage == 'legion', 'raw garage id when labels are off')
Config.Server.Garage.UseGarageLabels = true

state.owned = { { plate = 'Z', state = 'bogus' } }
local odd = Garage.list(1).data[1]
check(odd.state == 0 and odd.vehicle == '' and odd.fuel == 0, 'unexpected values stay safe')

state.owned = false
check(Garage.list(1).ok == false, 'export failure is an error result')
state.owned = {}
check(#Garage.list(1).data == 0, 'empty list')

state.resource = 'stopped'
check(Garage.list(1).code == 'CONFLICT', 'unavailable without kora_garages')
state.resource = 'started'
Config.Server.Garage.Enabled = false
check(Garage.list(1).code == 'CONFLICT', 'unavailable when disabled')
Config.Server.Garage.Enabled = true

print(string.format('garage: %d passed, 0 failed', passed))
