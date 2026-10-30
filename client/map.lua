QBPhone = QBPhone or {}
local Map = { active = false, previousRadar = true }

-- ponytail: these are the widely-used vanilla HUD minimap coordinates, restored
-- when the Maps app stops showing the live map. Ceiling: if another resource
-- also repositions the minimap, restoring to these fixed numbers can fight it.
-- Upgrade path: read that resource's own restore call instead of hardcoding this.
local DEFAULT_POSITION = {
    minimap = { 0.0, -0.047, 0.1638, 0.183 },
    minimap_mask = { 0.140, 0.140, 0.145, 0.190 },
    minimap_blur = { 0.0, 0.0, 0.150, 0.190 },
}

local function position(x, y, w, h)
    SetMinimapComponentPosition('minimap', 'L', 'T', x, y, w, h)
    SetMinimapComponentPosition('minimap_mask', 'L', 'T', x, y, w, h)
    SetMinimapComponentPosition('minimap_blur', 'L', 'T', x, y, w, h)
end

-- kora_hud owns the minimap layout when it is running (it fits the map to its
-- border for the player's aspect ratio and safezone), so ask it to put the
-- layout back. Standalone, or if the export is missing or reports the layout
-- as disabled, fall back to DEFAULT_POSITION.
local function restoreFromHud()
    if GetResourceState('kora_hud') ~= 'started' then return false end
    local ok, applied = pcall(function() return exports.kora_hud:applyMinimapLayout() end)
    return ok and applied == true
end

local function restore()
    if restoreFromHud() then return end
    for component, pos in pairs(DEFAULT_POSITION) do
        SetMinimapComponentPosition(component, 'L', 'B', pos[1], pos[2], pos[3], pos[4])
    end
end

-- Resizes and moves the game's own minimap to sit exactly behind the phone's
-- Maps app screen, which the NUI makes transparent at that spot. This is the
-- same live map the pause menu uses, just resized into the app instead of
-- filling the whole screen.
function Map.Show(x, y, w, h)
    if not (type(x) == 'number' and type(y) == 'number' and type(w) == 'number' and type(h) == 'number') then return false end
    if w <= 0 or h <= 0 then return false end
    if not Map.active then Map.previousRadar = not IsRadarHidden() end
    Map.active = true
    DisplayRadar(true)
    position(x, y, w, h)
    return true
end

function Map.Hide()
    if not Map.active then return end
    Map.active = false
    restore()
    DisplayRadar(Map.previousRadar)
end

function Map.Cleanup()
    if Map.active then Map.Hide() end
end

QBPhone.Map = Map
