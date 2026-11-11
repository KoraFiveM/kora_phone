-- Run with lua tests/map-blips.test.lua (or a Lua 5.4 embedding).
KoraPhone = nil
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
GetStreetNameFromHashKey = function(id) assert(id == 42); return 'Job Street' end
blips = {
    [1] = {sprite=1}, [2] = {sprite=280}, [3] = {sprite=280,display=0},
    [4] = {sprite=280,display=1}, [5] = {sprite=280,display=7},
    [6] = {sprite=280,alpha=0}, [7] = {sprite=8}, [8] = {sprite=6},
    [9] = {sprite=280,x=0/0}, [10] = {sprite=280,x=20001},
    [11] = {sprite=1023,display=3}, [12] = {sprite=280,display=5},
    [99] = {sprite=1}
}
local found = KoraPhone.Map.Blips()
assert(#found == 4, 'only visible, valid blips, including map/minimap-only')
assert(found[1].id == 1 and found[2].id == 2 and found[3].id == 12 and found[4].id == 11)
assert(found[2].colour == '#5db6e5' and found[2].label == 'Job Street')
blips[2].x = 500
assert(KoraPhone.Map.Blips()[2].x == 500, 'moving blips refresh')
blips[2] = nil
assert(#KoraPhone.Map.Blips() == 3, 'removed blips disappear')
blips = {}
assert(#KoraPhone.Map.Blips() == 0, 'resource cleanup leaves no stale markers')
blips[1] = {sprite=280}
GetNextBlipInfoId = function() return 1 end
assert(#KoraPhone.Map.Blips() == 1, 'repeated native handle cannot loop forever')
print('map-blips: all checks passed')