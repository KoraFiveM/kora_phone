-- Run outside FiveM with: lua tests/downed-watch.test.lua
-- Covers client/main.lua: the "put the phone away when downed" watcher only
-- runs while the phone is open, and never runs twice.

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

local threads, flags, closes

local function setup()
    threads, closes = {}, 0
    flags = { dead = false, metadata = {} }
    _G.Config = { Client = { DisableWhileDead = true, Command = "phone", Keybind = "M" } }
    _G.QBPhone = {
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
    _G.RegisterKeyMapping = function() end
    _G.TriggerServerEvent = function() end
    _G.SetNuiFocus = function() end
    _G.SetNuiFocusKeepInput = function() end
    _G.NetworkIsSessionStarted = function() return false end
    _G.exports = setmetatable({
        kora_core = { getPlayerData = function() return { metadata = flags.metadata } end },
    }, { __call = function() end })
    _G.Kora = { cache = { isDead = function() return flags.dead end }, notify = { send = function() end } }
    dofile(root .. "/client/main.lua")
end

local function tick() for _, co in ipairs(threads) do if coroutine.status(co) == "suspended" then assert(coroutine.resume(co)) end end end
local function live() local n = 0; for _, co in ipairs(threads) do if coroutine.status(co) == "suspended" then n = n + 1 end end; return n end

test("no watcher thread while the phone is closed", function()
    setup()
    local base = live() -- the startup session wait
    tick(); tick()
    equal(live(), base)
end)

test("closes the phone when the player dies while it is open, then the watcher exits", function()
    setup()
    local base = live()
    assert(QBPhone.Open())
    equal(live(), base + 1)
    tick()
    equal(QBPhone.State.open, true)
    flags.dead = true
    tick()
    equal(QBPhone.State.open, false)
    equal(closes, 1)
    tick()
    equal(live(), base)
end)

test("last-stand metadata (no cache key) still closes the phone", function()
    setup()
    assert(QBPhone.Open())
    flags.metadata = { inlaststand = true }
    tick()
    equal(QBPhone.State.open, false)
end)

test("reopening never starts a second watcher", function()
    setup()
    local base = live()
    assert(QBPhone.Open())
    QBPhone.Close(false)
    assert(QBPhone.Open())
    equal(live(), base + 1)
    QBPhone.Close(false)
    tick()
    equal(live(), base)
end)

print(("downed-watch: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
