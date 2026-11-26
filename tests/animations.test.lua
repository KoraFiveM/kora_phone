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
    _G.GetEntityCoords = function() return { x = 0.0, y = 0.0, z = 0.0 } end
    _G.GetPedBoneIndex = function(_, bone) return bone end
    _G.GetEntityBoneIndexByName = function(_, name) return name end
    _G.SetEntityCollision = function() end
    _G.DetachEntity = function() end
    _G.SetEntityAsMissionEntity = function() end
    -- Objects already in the world when animations.lua loads: { id, script, attached }.
    _G.worldObjects = _G.worldObjects or {}
    _G.PlayerPedId = function() return 1 end
    _G.GetGamePool = function() local ids = {}; for _, o in ipairs(worldObjects) do ids[#ids + 1] = o.id end; return ids end
    _G.IsEntityAttachedToEntity = function(e) for _, o in ipairs(worldObjects) do if o.id == e then return o.attached end end; return false end
    _G.GetEntityScript = function(e) for _, o in ipairs(worldObjects) do if o.id == e then return o.script end end end
    _G.GetEntityModel = function(e) for _, o in ipairs(worldObjects) do if o.id == e then return o.model end end end
    _G.joaat = function(name) return name end
    _G.DeleteEntity = function(e) ent[e] = nil; deleted[#deleted + 1] = e end
    _G.CreateObject = function(hash) local id = 100 + #props + 1; ent[id] = true; props[#props + 1] = { id = id, hash = hash }; return id end
    _G.AttachEntityToEntity = function(e, _, bone, ox, oy, oz) props[#props].bone, props[#props].ox = bone, ox end
    _G.Kora = {
        cache = {
            ped = function() pedReads = pedReads + 1; return 1 end,
            onChange = function(key, fn) if key == "ped" then pedListeners[#pedListeners + 1] = fn end end,
        },
        stream = { loadModel = function(model, cb) cb(model); return true end },
        -- Kora.entities.create loads the model and returns the local entity; the mock keeps CreateObject's bookkeeping.
        entities = { create = function(model) return CreateObject(model) end },
        anim = {
            play = function(entity, dict, clip, opts) played[#played + 1] = { dict = dict, clip = clip, flag = opts.flag }; return { entity = entity, n = #played } end,
            stopHandle = function() stopped = stopped + 1; return true end,
            isPlaying = function() return true end,
        },
    }
    _G.Kora = _G.Kora -- the working tree may use either global name
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

test("the held handset model picks its prop, and a late bootstrap swaps it", function()
    setup({ model = "prop_npc_phone_02" })
    KoraPhone.Animations.Start()
    equal(props[1].hash, "prop_npc_phone_02")
    KoraPhone.State.initialData = { device = { model = "flip" } }
    tick()
    equal(props[2].hash, "kora_phone_flip")
    equal(livingProps(), 1)
    equal(KoraPhone.State.phoneObject, props[2].id)
    KoraPhone.State.initialData = { device = { model = "fold" } }
    tick()
    equal(props[3].hash, "kora_phone_fold")
    KoraPhone.State.initialData = { device = { model = "standard" } }
    tick()
    equal(props[4].hash, "kora_phone_standard")
    equal(livingProps(), 1)
end)

test("closing the phone while the prop model loads leaves no prop behind", function()
    setup({})
    -- Kora.entities.create waits for the model; the phone is put away during that wait.
    Kora.entities.create = function(model) KoraPhone.Animations.Stop(); return CreateObject(model) end
    KoraPhone.Animations.Start()
    equal(livingProps(), 0, 'the prop created during the wait is deleted, not left in the hand')
end)

test("a restart clears a prop the previous instance left in the hand, and only that", function()
    _G.worldObjects = {
        { id = 900, script = nil, attached = true, model = "kora_phone_flip" },           -- orphaned by the old instance
        { id = 901, script = "emotes", attached = true, model = "prop_npc_phone_02" },   -- another resource's phone
        { id = 902, script = nil, attached = false, model = "kora_phone_standard" },    -- not in the hand
        { id = 903, script = nil, attached = true, model = "prop_cs_burger_01" },       -- not a phone
    }
    setup({})
    _G.worldObjects = {}
    equal(table.concat(deleted, ","), "900")
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

-- Attach bone: Config.Animation.bone is text. Digits mean a bone index, anything else a bone name.
local function boneCalls(bone)
    setup({ bone = bone })
    local calls = {}
    _G.GetPedBoneIndex = function(_, index) calls[#calls + 1] = { "index", index }; return "idx:" .. tostring(index) end
    _G.GetEntityBoneIndexByName = function(_, name) calls[#calls + 1] = { "name", name }; return "name:" .. name end
    KoraPhone.Animations.Start()
    return calls, props[1]
end

test("a numeric bone string attaches by index", function()
    local calls, prop = boneCalls("28422")
    equal(#calls, 1)
    equal(calls[1][1], "index")
    equal(calls[1][2], 28422)
    equal(math.type(calls[1][2]), "integer")
    equal(prop.bone, "idx:28422")
end)

test("a numeric bone value attaches by index", function()
    local calls, prop = boneCalls(28422)
    equal(#calls, 1)
    equal(calls[1][1], "index")
    equal(calls[1][2], 28422)
    equal(prop.bone, "idx:28422")
end)

test("a bone name attaches by name", function()
    local calls, prop = boneCalls("PH_R_Hand")
    equal(#calls, 1)
    equal(calls[1][1], "name")
    equal(calls[1][2], "PH_R_Hand")
    equal(prop.bone, "name:PH_R_Hand")
end)

-- Schema: tests/config_shim.lua does NOT validate, so this loads the REAL kora_lib consumer
-- ([pre]/kora_lib/modules/config/consumer.lua) with stubbed natives and runs config/shared.lua through it.
-- The bone field's default is swapped for each candidate; define() asserts on an invalid default.
local koraLibConsumer = root .. "/../../[pre]/kora_lib/modules/config/consumer.lua"
local function haveKoraLib()
    local handle = io.open(koraLibConsumer, "r")
    if handle then handle:close() end
    return handle ~= nil
end

local function defineWithBone(candidate)
    local saved = { Kora = _G.Kora, Config = _G.Config, name = _G.GetCurrentResourceName, dup = _G.IsDuplicityVersion,
        load = _G.LoadResourceFile }
    _G.GetCurrentResourceName = function() return "kora_phone" end
    _G.IsDuplicityVersion = function() return true end
    _G.LoadResourceFile = function() return nil end
    local ok, err = pcall(function()
        local consumer = assert(loadfile(koraLibConsumer))
        local real = consumer()({ config_register = function() return true end })
        local wrapped = setmetatable({}, { __index = real })
        wrapped.string = function(value, options)
            if options and options.label == "Attach bone (index or name)" then value = candidate end
            return real.string(value, options)
        end
        _G.Kora = { config = wrapped }
        dofile(root .. "/config/shared.lua")
        assert(_G.Config.Animation.bone == candidate, "bone default was not applied")
    end)
    _G.Kora, _G.Config, _G.GetCurrentResourceName, _G.IsDuplicityVersion, _G.LoadResourceFile =
        saved.Kora, saved.Config, saved.name, saved.dup, saved.load
    return ok, err
end

test("config schema (real kora_lib validator) accepts '28422' and 'PH_R_Hand'", function()
    if not haveKoraLib() then
        io.write("SKIP real kora_lib validator: " .. koraLibConsumer .. " not found (CI clones kora_lib there)\n")
        return
    end
    local ok, err = defineWithBone("28422")
    assert(ok, tostring(err))
    ok, err = defineWithBone("PH_R_Hand")
    assert(ok, tostring(err))
end)

test("config schema (real kora_lib validator) rejects 'bad bone!'", function()
    if not haveKoraLib() then
        io.write("SKIP real kora_lib validator: " .. koraLibConsumer .. " not found (CI clones kora_lib there)\n")
        return
    end
    local ok, err = defineWithBone("bad bone!")
    assert(not ok, "expected the schema to reject 'bad bone!'")
    assert(tostring(err):find("format", 1, true) or tostring(err):find("nvalid", 1, true), tostring(err))
end)

io.write(("animations: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)