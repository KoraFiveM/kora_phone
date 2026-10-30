-- Run outside FiveM with: lua tests/map.test.lua
-- Covers client/map.lua restoring the minimap layout: through kora_hud when it
-- is running and exposes applyMinimapLayout, otherwise the built-in defaults.

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write("PASS ", name, "\n")
    else
        failed = failed + 1
        io.stderr:write("FAIL ", name, ": ", tostring(err), "\n")
    end
end

local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local script = arg and arg[0] or "tests/map.test.lua"
local root = script:gsub("[\\/]tests[\\/]map%.test%.lua$", "")
if root == script then root = "." end

local placed, hudState, hudCalls, hudResult, radarHidden, radarSet

local function setup(state, result)
    placed, hudCalls, radarSet = {}, 0, nil
    hudState, hudResult, radarHidden = state, result, false
    _G.QBPhone = nil
    _G.SetMinimapComponentPosition = function(name, h, v, x, y, w, hh) placed[#placed + 1] = { name = name, v = v, x = x, y = y, w = w, h = hh } end
    _G.IsRadarHidden = function() return radarHidden end
    _G.DisplayRadar = function(v) radarSet = v end
    _G.GetResourceState = function(name) assert(name == "kora_hud"); return hudState end
    _G.exports = { kora_hud = { applyMinimapLayout = function()
        hudCalls = hudCalls + 1
        if hudResult == "error" then error("export failed") end
        return hudResult
    end } }
    dofile(root .. "/client/map.lua")
end

local function showThenHide()
    QBPhone.Map.Show(0.1, 0.2, 0.3, 0.4)
    placed = {}
    QBPhone.Map.Hide()
end

test("closing the map asks kora_hud to restore its layout", function()
    setup("started", true)
    showThenHide()
    equal(hudCalls, 1)
    equal(#placed, 0)
    equal(radarSet, true)
end)

test("Show still positions all three components itself", function()
    setup("started", true)
    QBPhone.Map.Show(0.1, 0.2, 0.3, 0.4)
    equal(#placed, 3)
    equal(hudCalls, 0)
end)

test("without kora_hud the built-in defaults are restored", function()
    setup("missing", true)
    showThenHide()
    equal(hudCalls, 0)
    equal(#placed, 3)
end)

test("a disabled kora_hud layout falls back to the defaults", function()
    setup("started", false)
    showThenHide()
    equal(hudCalls, 1)
    equal(#placed, 3)
end)

test("a failing export falls back to the defaults", function()
    setup("started", "error")
    showThenHide()
    equal(#placed, 3)
    equal(radarSet, true)
end)

io.write(("map: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
