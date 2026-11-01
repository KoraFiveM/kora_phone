-- Installing a SIM must consume exactly one SIM item; removing it must hand the same SIM back.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function auto() return setmetatable({}, { __index = function(t, k) local v = auto(); rawset(t, k, v); return v end }) end
local function fixture()
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    local state = { items = {}, removed = 0, added = {}, removeOk = true, addOk = true }
    env.Config = { SimItem = 'phone_sim', Handsets = {} }
    env.QBPhone = auto()
    env.QBPhone.GetPlayer = function() return { items = state.items } end
    env.PhoneError, env.PhoneResult, env.PhoneConstants = function() end, function() end, { Errors = {} }
    env.MySQL = auto()
    env.exports = setmetatable({}, { __call = function() end, __index = function(_, resource)
        return setmetatable({}, { __index = function(_, name) return function(_, ...)
            local a = { ... }
            if name == 'getItemBySlot' then return state.items[a[2]] end
            if resource == 'kora_inventory' and name == 'RemoveItem' then
                if not state.removeOk then return false, 'blocked' end
                state.items[a[4]] = nil; state.removed = state.removed + 1; return true
            end
            if resource == 'kora_inventory' and name == 'AddItem' then
                if not state.addOk then return false, 'full' end
                state.added[#state.added + 1] = a[5]; state.items[9] = { name = 'phone_sim', amount = 1, info = a[5] }; return true
            end
        end end })
    end })
    env.AddEventHandler, env.RegisterNetEvent, env.RegisterCommand, env.CreateThread = function() end, function() end, function() end, function() end
    env.print = function() end
    assert(loadfile('server/handsets.lua', 't', env))()
    return state, env.QBPhone.Handsets
end
local sim = string.rep('a', 32)
local request = { simSlot = 7, simId = sim }

-- Gateway already consumed the SIM: nothing more is removed (exactly one item leaves).
local state, H = fixture()
check(H.settleSimItem(1, 'insertSim', request), 'install settles')
check(state.removed == 0, 'no second removal after the gateway consumed the SIM')

-- Older gateway left the SIM loose: it is consumed once.
state, H = fixture()
state.items[7] = { name = 'phone_sim', amount = 1, slot = 7, info = { simId = sim } }
check(H.settleSimItem(1, 'insertSim', request), 'loose SIM is consumed')
check(state.removed == 1 and state.items[7] == nil, 'exactly one SIM removed')
check(H.settleSimItem(1, 'insertSim', request) and state.removed == 1, 'repeat does not remove again')

-- A different SIM in that slot is never touched.
state, H = fixture()
state.items[7] = { name = 'phone_sim', amount = 1, slot = 7, info = { simId = string.rep('b', 32) } }
check(H.settleSimItem(1, 'insertSim', request) and state.removed == 0, 'other SIM left alone')

-- A removal failure is reported, not hidden.
state, H = fixture()
state.items[7] = { name = 'phone_sim', amount = 1, slot = 7, info = { simId = sim } }
state.removeOk = false
check(H.settleSimItem(1, 'insertSim', request) == false, 'failed consume is an error')

-- Removal: gateway returned the SIM, so nothing is added again (no duplication).
state, H = fixture()
state.items[4] = { name = 'phone_sim', amount = 1, slot = 4, info = { simId = sim } }
check(H.settleSimItem(1, 'removeSim', request, { simId = sim }) and #state.added == 0, 'no duplicate on removal')

-- Removal: SIM missing from the inventory is returned with its metadata.
state, H = fixture()
check(H.settleSimItem(1, 'removeSim', request, { simId = sim, number = '555' }), 'missing SIM returned')
check(#state.added == 1 and state.added[1].simId == sim and state.added[1].number == '555', 'same SIM metadata returned')

-- Removal without trustworthy metadata or with a full inventory fails.
state, H = fixture()
check(H.settleSimItem(1, 'removeSim', request, nil) == false, 'no metadata, no new SIM')
state, H = fixture(); state.addOk = false
check(H.settleSimItem(1, 'removeSim', request, { simId = sim }) == false, 'full inventory is an error')

print(('sim-install.test.lua: %d checks passed'):format(checks))
