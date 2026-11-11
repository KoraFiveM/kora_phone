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

local placed, hudState, hudCalls, hudResult, radarHidden, radarSet, bigmap, aspect, threads

local function setup(state, result)
    placed, hudCalls, radarSet, bigmap, aspect, threads = {}, 0, nil, {}, 16 / 9, {}
    hudState, hudResult, radarHidden = state, result, false
    _G.KoraPhone = nil
    _G.SetMinimapComponentPosition = function(name, h, v, x, y, w, hh) placed[#placed + 1] = { name = name, v = v, x = x, y = y, w = w, h = hh } end
    _G.GetAspectRatio = function() return aspect end
    _G.SetBigmapActive = function(on) bigmap[#bigmap + 1] = on end
    _G.Wait = function() coroutine.yield() end
    _G.CreateThread = function(fn)
        local co = coroutine.create(fn)
        threads[#threads + 1] = co
        assert(coroutine.resume(co))
    end
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

local function flush()
    for _, co in ipairs(threads) do
        while coroutine.status(co) == "suspended" do assert(coroutine.resume(co)) end
    end
end

local function byName()
    local out = {}
    for _, p in ipairs(placed) do out[p.name] = p end
    return out
end

local function showThenHide()
    KoraPhone.Map.Show(0.1, 0.2, 0.3, 0.4)
    placed = {}
    KoraPhone.Map.Hide()
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
    KoraPhone.Map.Show(0.1, 0.2, 0.3, 0.4)
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

test("the fallback restores the exact vanilla 16:9 rects, left/bottom anchored", function()
    setup("missing", true)
    showThenHide()
    local p = byName()
    local want = {
        minimap = { -0.0045, 0.002, 0.150, 0.188 },
        minimap_mask = { 0.020, 0.032, 0.111, 0.159 },
        minimap_blur = { -0.03, 0.022, 0.266, 0.237 },
    }
    for name, w in pairs(want) do
        equal(p[name].v, "B")
        equal(p[name].x, w[1]); equal(p[name].y, w[2]); equal(p[name].w, w[3]); equal(p[name].h, w[4])
    end
end)

test("the fallback narrows widths on ultrawide and widens them on 4:3", function()
    setup("missing", true)
    aspect = 21 / 9
    showThenHide()
    local wide = byName().minimap
    assert(wide.w < 0.150 and wide.h == 0.188, "21:9 narrower, same height")
    assert(math.abs(wide.w - 0.150 * (16 / 9) / (21 / 9)) < 1e-9)
    setup("missing", true)
    aspect = 4 / 3
    showThenHide()
    assert(byName().minimap.w > 0.150, "4:3 wider fraction")
end)

test("the fallback refreshes the bigmap a frame apart and ends with it off", function()
    setup("missing", true)
    showThenHide()
    equal(#bigmap, 1)
    equal(bigmap[1], true)
    flush()
    equal(#bigmap, 2)
    equal(bigmap[2], false)
end)

test("kora_hud restoring the layout does not toggle the bigmap from the phone", function()
    setup("started", true)
    showThenHide()
    flush()
    equal(#bigmap, 0)
end)

test("Show never touches the bigmap", function()
    setup("missing", true)
    KoraPhone.Map.Show(0.1, 0.2, 0.3, 0.4)
    flush()
    equal(#bigmap, 0)
end)

io.write(("map: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)