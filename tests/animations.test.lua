-- Run outside FiveM with: lua tests/animations.test.lua
-- Covers client/animations.lua: phone prop + pose while the phone is open.

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n")
    else failed = failed + 1; io.stderr:write("FAIL ", name, ": ", tostring(err), "\n") end
end
local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local script = arg and arg[0] or "tests/animations.test.lua"
local root = script:gsub("[\\/]tests[\\/]animations%.test%.lua$", "")
if root == script then root = "." end

local ped, ent, played, props, deleted, threads, stopped, handlers
local flags -- toggles the stubbed ped state
local pedListeners, pedReads -- cache.onChange("ped") handlers and Kora.cache.ped() export calls

local function setup(config)
    played, props, deleted, threads, stopped, handlers = {}, {}, {}, {}, 0, {}
    pedListeners, pedReads = {}, 0
    flags = { dead = false, cuffed = false, ragdoll = false, swimming = false, vehicle = false }
    ent = {}
    _G.KoraPhone = { State = { activeCall = nil } }
    _G.Config = { Animation = config }
    _G.joaat = nil
    _G.Wait = function() coroutine.yield() end
    _G.CreateThread = function(fn) local co = coroutine.create(fn); threads[#threads + 1] = co; assert(coroutine.resume(co)) end
    _G.AddEventHandler = function(name, fn) handlers[name] = fn end
    _G.GetCurrentResourceName = function() return "kora_phone-stevie" end
    _G.DoesEntityExist = function(e) return e == 1 or (ent[e] == true) end
    _G.IsEntityDead = function() return flags.dead end
    _G.IsPedCuffed = function() return flags.cuffed end
    _G.IsPedRagdoll = function() return flags.ragdoll end
    _G.IsPedSwimming = function() return flags.swimming end
    _G.IsPedSwimmingUnderWater = function() return false end
    _G.IsPedInAnyVehicle = function() return flags.vehicle end
    _G.GetPedBoneIndex = function(_, bone) return bone end
    _G.GetEntityBoneIndexByName = function(_, name) return name end
    _G.SetEntityCollision = function() end
    _G.DetachEntity = function() end
    _G.DeleteEntity = function(e) ent[e] = nil; deleted[#deleted + 1] = e end
    _G.CreateObject = function(hash) local id = 100 + #props + 1; ent[id] = true; props[#props + 1] = { id = id, hash = hash }; return id end
    _G.AttachEntityToEntity = function(e, _, bone, ox, oy, oz) props[#props].bone, props[#props].ox = bone, ox end
    _G.QB = {
        cache = {
            ped = function() pedReads = pedReads + 1; return 1 end,
            onChange = function(key, fn) if key == "ped" then pedListeners[#pedListeners + 1] = fn end end,
        },
        stream = { loadModel = function(model, cb) cb(model); return true end },
        anim = {
            play = function(entity, dict, clip, opts) played[#played + 1] = { dict = dict, clip = clip, flag = opts.flag }; return { entity = entity, n = #played } end,
            stopHandle = function() stopped = stopped + 1; return true end,
            isPlaying = function() return true end,
        },
    }
    _G.Kora = _G.QB -- the working tree may use either global name
    dofile(root .. "/client/animations.lua")
end

local function tick() for _, co in ipairs(threads) do if coroutine.status(co) == "suspended" then assert(coroutine.resume(co)) end end end
local function livingProps() local n = 0; for _, p in ipairs(props) do if ent[p.id] then n = n + 1 end end; return n end

test("start holds the phone prop and plays the text pose", function()
    setup({ enabled = true, model = "prop_npc_phone_02", bone = 28422, offset = { x = 0.1, y = 0, z = 0 }, rotation = { x = 0, y = 0, z = 0 } })
    equal(KoraPhone.Animations.Start(), true)
    equal(played[1].dict, "cellphone@")
    equal(played[1].clip, "cellphone_text_read_base")
    equal(played[1].flag, 50)
    equal(props[1].hash, "prop_npc_phone_02")
    equal(props[1].bone, 28422)
    equal(props[1].ox, 0.1)
    equal(KoraPhone.State.phoneObject, props[1].id)
end)

test("the watcher follows the mirrored ped instead of calling the cache export every tick", function()
    setup({})
    KoraPhone.Animations.Start()
    equal(pedReads, 1)
    tick(); tick(); tick()
    equal(pedReads, 1)
    equal(#pedListeners, 1)
    pedListeners[1](2) -- ped 2 does not exist: the prop is put away
    tick()
    equal(livingProps(), 0)
    pedListeners[1](1)
    tick()
    equal(livingProps(), 1)
end)

test("stop removes the prop and the pose, and the watcher ends", function()
    setup({})
    KoraPhone.Animations.Start()
    KoraPhone.Animations.Stop()
    equal(livingProps(), 0)
    equal(stopped, 1)
    equal(KoraPhone.State.phoneObject, nil)
    tick()
    equal(coroutine.status(threads[1]), "dead")
end)

test("the in-vehicle pose is used when seated", function()
    setup({})
    flags.vehicle = true
    KoraPhone.Animations.Start()
    equal(played[1].dict, "anim@cellphone@in_car@ps")
end)

test("an active call switches to the call pose without a second prop", function()
    setup({})
    KoraPhone.Animations.Start()
    KoraPhone.State.activeCall = { id = "x", status = "active" }
    tick()
    equal(played[2].clip, "cellphone_call_listen_base")
    equal(#props, 1)
    KoraPhone.State.activeCall = nil
    tick()
    equal(played[3].clip, "cellphone_text_read_base")
end)

test("an incoming ringing call keeps the text pose", function()
    setup({})
    KoraPhone.Animations.Start()
    KoraPhone.State.activeCall = { id = "x", status = "ringing", direction = "incoming" }
    tick()
    equal(#played, 1)
end)

test("ragdoll removes the prop and it returns afterwards", function()
    setup({})
    KoraPhone.Animations.Start()
    flags.ragdoll = true; tick()
    equal(livingProps(), 0)
    flags.ragdoll = false; tick()
    equal(livingProps(), 1)
end)

test("swimming removes the prop, unless cancelOnWater is off", function()
    setup({})
    KoraPhone.Animations.Start()
    flags.swimming = true; tick()
    equal(livingProps(), 0)
    setup({ cancelOnWater = false })
    KoraPhone.Animations.Start()
    flags.swimming = true; tick()
    equal(livingProps(), 1)
end)

test("death and cuffs remove the prop; starting while dead plays nothing", function()
    setup({})
    KoraPhone.Animations.Start()
    flags.dead = true; tick()
    equal(livingProps(), 0)
    setup({})
    flags.cuffed = true
    equal(KoraPhone.Animations.Start(), false)
    equal(#played, 0)
    equal(#props, 0)
    setup({})
    flags.dead = true
    equal(KoraPhone.Animations.Start(), false)
    equal(#played, 0)
end)

test("Config.Animation.enabled = false does nothing", function()
    setup({ enabled = false })
    equal(KoraPhone.Animations.Start(), false)
    equal(#played, 0)
    equal(#props, 0)
end)

test("a missing Config.Animation falls back to the defaults", function()
    setup(nil)
    equal(KoraPhone.Animations.Start(), true)
    equal(props[1].hash, "prop_npc_phone_02")
end)

test("resource stop cleans up", function()
    setup({})
    KoraPhone.Animations.Start()
    handlers.onClientResourceStop("some_other_resource")
    equal(livingProps(), 1)
    handlers.onClientResourceStop("kora_phone-stevie")
    equal(livingProps(), 0)
end)

io.write(("animations: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)