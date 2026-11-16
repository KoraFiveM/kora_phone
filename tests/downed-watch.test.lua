-- Run outside FiveM with: lua tests/downed-watch.test.lua
-- Covers client/main.lua: the phone is put away when the player goes down, driven by
-- Kora.cache.onChange('isDead') and the kora_core metadata mirror (no polling thread).

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n")
    else failed = failed + 1; io.stderr:write("FAIL ", name, ": ", tostring(err), "\n") end
end
local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local script = arg and arg[0] or "tests/downed-watch.test.lua"
local root = script:gsub("[\\/]tests[\\/]downed%-watch%.test%.lua$", "")
if root == script then root = "." end

local threads, flags, closes, cacheHandlers, mirrorHandlers

local function setup()
    threads, closes, cacheHandlers, mirrorHandlers = {}, 0, {}, {}
    flags = { dead = false, metadata = {} }
    _G.Config = { Client = { DisableWhileDead = true, UiBlockBag = "koraUiBlocked", Command = "phone", Keybind = "M" } }
    _G.KoraPhone = {
        State = { open = false, playerLoaded = true, generation = 0, Public = function() return {} end },
        Animations = { Start = function() end, Stop = function() end },
        Camera = { Cleanup = function() end },
        SendNui = function(name) if name == "phone:close" then closes = closes + 1 end end,
    }
    _G.Wait = function() coroutine.yield() end
    _G.CreateThread = function(fn) local co = coroutine.create(fn); threads[#threads + 1] = co; assert(coroutine.resume(co)) end
    _G.RegisterNetEvent = function() end
    _G.AddEventHandler = function() end
    _G.RegisterCommand = function() end
    _G.TriggerServerEvent = function() end
    _G.SetNuiFocus = function() end
    _G.SetNuiFocusKeepInput = function() end
    _G.exports = setmetatable({
        kora_core = {
            getPlayerData = function() return { metadata = flags.metadata } end,
            onPlayerDataChange = function(_, path, handler) mirrorHandlers[path[1]] = handler end,
        },
    }, { __call = function() end })
    _G.LocalPlayer = { state = {} }
    _G.GetPlayerServerId = function() return 7 end
    _G.PlayerId = function() return 0 end
    _G.Kora = {
        cache = {
            isDead = function() return flags.dead end,
            onChange = function(key, handler) cacheHandlers[key] = handler end,
        },
        notify = { send = function() end },
        lang = function(key) return key end,
        keybind = { add = function(options) flags.keybind = options end },
        timers = { debounce = function(fn) return { run = fn } end },
        state = { onChange = function(key, bag, handler) flags.stateKey, flags.stateHandler = key, handler end },
    }
    dofile(root .. "/client/main.lua")
end

local function live() local n = 0; for _, co in ipairs(threads) do if coroutine.status(co) == "suspended" then n = n + 1 end end; return n end

test("no polling thread exists, open or closed", function()
    setup()
    local base = live()
    assert(KoraPhone.Open())
    equal(live(), base)
    KoraPhone.Close(false)
    equal(live(), base)
end)

test("closes the phone when the cache reports death while it is open", function()
    setup()
    assert(KoraPhone.Open())
    cacheHandlers.isDead(false, true)
    equal(KoraPhone.State.open, true)
    flags.dead = true
    cacheHandlers.isDead(true, false)
    equal(KoraPhone.State.open, false)
    equal(closes, 1)
end)

test("a death while the phone is closed does nothing", function()
    setup()
    flags.dead = true
    cacheHandlers.isDead(true, false)
    equal(closes, 0)
end)

test("last-stand metadata changes from kora_core close the phone", function()
    setup()
    assert(KoraPhone.Open())
    flags.metadata = { inlaststand = true }
    mirrorHandlers.metadata({ "metadata", "inlaststand" }, true)
    equal(KoraPhone.State.open, false)
end)

test("DisableWhileDead = false keeps the phone open", function()
    setup()
    Config.Client.DisableWhileDead = false
    assert(KoraPhone.Open())
    flags.dead = true
    cacheHandlers.isDead(true, false)
    equal(KoraPhone.State.open, true)
end)

test("the phone key is registered through Kora.keybind", function()
    setup()
    equal(flags.keybind.name, "kora_phone_toggle")
    equal(flags.keybind.defaultKey, "M")
end)

test("a blocked phone does not open, and opens again once the block clears", function()
    setup()
    equal(flags.stateKey, "koraUiBlocked")
    LocalPlayer.state.koraUiBlocked = true
    equal(KoraPhone.Open(), false)
    equal(KoraPhone.State.open, false)
    LocalPlayer.state.koraUiBlocked = nil
    equal(KoraPhone.Open(), true)
end)

test("the bag turning true closes an open phone; other players and false values do not", function()
    setup()
    assert(KoraPhone.Open())
    flags.stateHandler({ value = true, bagName = "player:9" })
    equal(KoraPhone.State.open, true)
    flags.stateHandler({ value = false, bagName = "player:7" })
    equal(KoraPhone.State.open, true)
    flags.stateHandler({ value = true, bagName = "player:7" })
    equal(KoraPhone.State.open, false)
    equal(closes, 1)
end)

test("UiBlockBag = false turns the block off", function()
    setup()
    Config.Client.UiBlockBag = false
    dofile(root .. "/client/main.lua")
    LocalPlayer.state.koraUiBlocked = true
    equal(KoraPhone.Open(), true)
end)

print(("downed-watch: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end