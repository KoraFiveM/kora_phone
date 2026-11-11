KoraPhone = KoraPhone or {}
local Map = { active = false, previousRadar = true }

-- Vanilla 16:9 minimap rects (the widely used community reference values),
-- left/bottom anchored, restored when the Maps app stops showing the live map
-- and kora_hud is not managing the layout. Widths and x are scaled by
-- (16/9)/aspect for other aspect ratios so the map is not stretched; 16:9 is
-- exactly these numbers. Ceiling: if another resource also repositions the
-- minimap, restoring to these numbers can fight it.
local DEFAULT_POSITION = {
    minimap = { -0.0045, 0.002, 0.150, 0.188 },
    minimap_mask = { 0.020, 0.032, 0.111, 0.159 },
    minimap_blur = { -0.03, 0.022, 0.266, 0.237 },
}

local function position(x, y, w, h)
    SetMinimapComponentPosition('minimap', 'L', 'T', x, y, w, h)
    SetMinimapComponentPosition('minimap_mask', 'L', 'T', x, y, w, h)
    SetMinimapComponentPosition('minimap_blur', 'L', 'T', x, y, w, h)
end

-- kora_hud owns the minimap layout when it is running (it fits the map to its
-- border for the player's aspect ratio and safezone), so ask it to put the
-- layout back. Standalone, or if the export is missing or reports the layout
-- as disabled, fall back to the vanilla DEFAULT_POSITION.
local function restoreFromHud()
    if GetResourceState('kora_hud') ~= 'started' then return false end
    local ok, applied = pcall(function() return exports.kora_hud:applyMinimapLayout() end)
    return ok and applied == true
end

local function restore()
    if restoreFromHud() then return end
    local aspect = GetAspectRatio(false)
    local widthFactor = (type(aspect) == 'number' and aspect > 0) and (16 / 9) / aspect or 1.0
    for component, pos in pairs(DEFAULT_POSITION) do
        SetMinimapComponentPosition(component, 'L', 'B', pos[1] * widthFactor, pos[2], pos[3] * widthFactor, pos[4])
    end
    -- The engine only re-reads component positions on a bigmap toggle, with a
    -- frame between the two calls; leaving it on would show the big radar.
    CreateThread(function()
        SetBigmapActive(true, false)
        Wait(0)
        SetBigmapActive(false, false)
    end)
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

local registered = {}

local function changed()
    SendNUIMessage({ type = 'mapBlipsChanged' })
end

exports('RegisterMapBlip', function(handle, title)
    local owner = GetInvokingResource()
    if not owner or type(handle) ~= 'number' or math.tointeger(handle) == nil or not DoesBlipExist(handle) then return false end
    if type(title) ~= 'string' or #title > 160 or not title:find('%S') then return false end
    if registered[handle] and registered[handle].owner ~= owner then return false end
    registered[handle] = { owner = owner, title = title }
    changed()
    return true
end)

exports('UnregisterMapBlip', function(handle)
    local record = registered[handle]
    if not record or record.owner ~= GetInvokingResource() then return false end
    registered[handle] = nil
    changed()
    return true
end)

AddEventHandler('kora_lib:blips:changed', changed)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_lib' then changed() end
end)

AddEventHandler('onClientResourceStop', function(resource)
    local removed = false
    for handle, record in pairs(registered) do
        if record.owner == resource then
            registered[handle] = nil
            removed = true
        end
    end
    if removed or resource == 'kora_lib' then changed() end
end)

function Map.Blips()
    local result, titles = {}, {}
    if GetResourceState('kora_lib') == 'started' then
        local ok, records = pcall(function() return Kora.blips.getRegistered() end)
        if ok and type(records) == 'table' then
            for _, record in ipairs(records) do
                titles[record.handle] = record.label ~= '' and record.label or record.name
            end
        end
    end
    for handle, record in pairs(registered) do
        if DoesBlipExist(handle) then titles[handle] = record.title
        else registered[handle] = nil end
    end
    for handle, title in pairs(titles) do
        if DoesBlipExist(handle) then
            local display = GetBlipInfoIdDisplay(handle)
            local at = GetBlipInfoIdCoord(handle)
            if display >= 2 and display ~= 7 and GetBlipAlpha(handle) > 0
                and math.abs(at.x) <= 20000 and math.abs(at.y) <= 20000 then
                local r, g, b = GetHudColour(GetBlipHudColour(handle))
                local street = GetStreetNameFromHashKey((GetStreetNameAtCoord(at.x, at.y, at.z)))
                local zone = GetLabelText(GetNameOfZone(at.x, at.y, at.z))
                result[#result + 1] = {
                    id = handle, x = at.x, y = at.y, sprite = GetBlipSprite(handle),
                    label = title, street = street ~= '' and street or nil,
                    zone = zone ~= 'NULL' and zone or nil,
                    colour = ('#%02x%02x%02x'):format(r, g, b)
                }
            end
        end
    end
    return result
end

KoraPhone.Map = Map
