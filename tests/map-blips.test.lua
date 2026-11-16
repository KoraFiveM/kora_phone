-- Run with lua tests/map-blips.test.lua (or a Lua 5.4 embedding).
KoraPhone = nil
-- Minimal runtime: exports is callable (registration), events are no-ops, kora_lib reports no registered blips.
exports = setmetatable({}, { __call = function() end })
AddEventHandler = function() end
GetInvokingResource = function() return 'test' end
GetResourceState = function() return 'started' end
local registry = {}
Kora = { blips = { getRegistered = function() return registry end } }
dofile('client/map.lua')
local blips, cursors = {}, {}
PlayerPedId = function() return 99 end
GetBlipFromEntity = function() return 99 end
GetFirstBlipInfoId = function(sprite)
    cursors[sprite] = 0
    return GetNextBlipInfoId(sprite)
end
GetNextBlipInfoId = function(sprite)
    for id = cursors[sprite] + 1, 100 do
        if blips[id] and blips[id].sprite == sprite then cursors[sprite] = id; return id end
    end
    return 0
end
DoesBlipExist = function(id) return blips[id] ~= nil end
GetBlipInfoIdDisplay = function(id) return blips[id].display or 2 end
GetBlipAlpha = function(id) return blips[id].alpha or 255 end
GetBlipInfoIdCoord = function(id) return { x = blips[id].x or 10, y = 20, z = 0 } end
GetBlipHudColour = function() return 9 end
GetHudColour = function(id) assert(id == 9); return 93, 182, 229, 255 end
GetStreetNameAtCoord = function() return 42, 0 end
GetNameOfZone = function() return 'ZONE' end
GetLabelText = function() return 'NULL' end
GetBlipSprite = function(id) return blips[id].sprite end
GetStreetNameFromHashKey = function(id) assert(id == 42); return 'Job Street' end
blips = {
    [1] = {sprite=1}, [2] = {sprite=280}, [3] = {sprite=280,display=0},
    [4] = {sprite=280,display=1}, [5] = {sprite=280,display=7},
    [6] = {sprite=280,alpha=0}, [7] = {sprite=8}, [8] = {sprite=6},
    [9] = {sprite=280,x=0/0}, [10] = {sprite=280,x=20001},
    [11] = {sprite=1023,display=3}, [12] = {sprite=280,display=5},
    [99] = {sprite=1}
}
local function register(...)
    registry = {}
    for _, id in ipairs({ ... }) do registry[#registry + 1] = { handle = id, label = 'Blip ' .. id, name = 'raw' } end
end
local function sorted()
    local result = KoraPhone.Map.Blips()
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

register(1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 77)
local found = sorted()
assert(#found == 4, 'only visible, valid registered blips, including map/minimap-only')
assert(found[1].id == 1 and found[2].id == 2 and found[3].id == 11 and found[4].id == 12)
assert(found[2].colour == '#5db6e5' and found[2].street == 'Job Street' and found[2].label == 'Blip 2')
blips[2].x = 500
assert(sorted()[2].x == 500, 'moving blips refresh')
blips[2] = nil
assert(#sorted() == 3, 'removed blips disappear')
blips = {}
assert(#sorted() == 0, 'resource cleanup leaves no stale markers')
register()
blips[1] = { sprite = 280 }
assert(#KoraPhone.Map.Blips() == 0, 'unregistered blips are never listed')
print('map-blips: all checks passed')
