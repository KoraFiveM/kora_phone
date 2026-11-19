KoraPhone = KoraPhone or {}
local Animations = {}

-- Fallbacks for configs copied from before Config.Animation existed; config/client.lua is the real source.
local DEFAULTS = {
    enabled = true,
    model = 'prop_npc_phone_02',
    bone = 28422, -- PH_R_Hand, a bone index or a bone name
    offset = { x = 0.0, y = 0.0, z = 0.0 },
    rotation = { x = 0.0, y = 0.0, z = 0.0 },
    cancelOnRagdoll = true,
    cancelOnWater = true,
    anims = {
        text = { dict = 'cellphone@', clip = 'cellphone_text_read_base' },
        call = { dict = 'cellphone@', clip = 'cellphone_call_listen_base' },
        vehicleText = { dict = 'anim@cellphone@in_car@ps', clip = 'cellphone_text_read_base' },
        vehicleCall = { dict = 'anim@cellphone@in_car@ps', clip = 'cellphone_call_listen_base' },
    },
}

-- Read at use time so a live config change applies the next time the phone opens.
local function option(key)
    local configured = Config.Animation
    if type(configured) == 'table' and configured[key] ~= nil then return configured[key] end
    return DEFAULTS[key]
end

local function animation(key)
    local configured = Config.Animation and Config.Animation.anims and Config.Animation.anims[key]
    return configured or DEFAULTS.anims[key]
end

local wanted = false
local generation = 0
-- Mirror of Kora.cache.ped() so the 250 ms watcher reads an upvalue instead of making an export call per tick.
local cachedPed
Kora.cache.onChange('ped', function(ped) cachedPed = ped end)
local handle, currentKey, prop, propName

local function removeProp()
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, false)
        DeleteEntity(prop)
    end
    prop, propName = nil, nil
    if KoraPhone.State then KoraPhone.State.phoneObject = nil end
end

local function stopAnimation()
    if handle then Kora.anim.stopHandle(handle, 2.0) end
    handle, currentKey = nil, nil
end

local function release()
    stopAnimation()
    removeProp()
end

-- Dead, cuffed, ragdolling or swimming peds cannot hold the phone up; the watcher puts it back afterwards.
local function blocked(ped)
    if not DoesEntityExist(ped) or IsEntityDead(ped) or IsPedCuffed(ped) then return true end
    if option('cancelOnRagdoll') and IsPedRagdoll(ped) then return true end
    if option('cancelOnWater') and (IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped)) then return true end
    return false
end

local function onCall()
    local call = KoraPhone.State and KoraPhone.State.activeCall
    if not call then return false end
    return call.status == 'active' or (call.status == 'ringing' and call.direction ~= 'incoming')
end

-- Streamed from stream/ (kora_phone_props.ytyp); a handset model without an entry uses the configured prop.
local HANDSET_PROPS = { standard = 'kora_phone_standard', flip = 'kora_phone_flip', fold = 'kora_phone_fold' }

local function propModel()
    local data = KoraPhone.State and KoraPhone.State.initialData
    local handset = type(data) == 'table' and type(data.device) == 'table' and data.device.model
    return HANDSET_PROPS[handset] or option('model')
end

local function createProp(ped)
    -- Config stores the bone as text: digits mean a bone index, anything else is a bone name.
    local bone = option('bone')
    local boneNumber = tonumber(bone)
    local boneIndex = boneNumber and GetPedBoneIndex(ped, boneNumber) or GetEntityBoneIndexByName(ped, bone)
    local offset, rotation = option('offset'), option('rotation')
    local created
    propName = propModel()
    -- loadModel waits for the model; a Stop() during that wait must not leave an untracked prop in the hand.
    local mine = generation
    Kora.stream.loadModel(propName, function(hash)
        if mine ~= generation or not wanted then return end
        created = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
        if created == 0 or not DoesEntityExist(created) then created = nil; return end
        SetEntityCollision(created, false, false)
        AttachEntityToEntity(created, ped, boneIndex, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z,
            true, true, false, true, 1, true)
    end)
    return created
end

local function apply(ped)
    local inVehicle = IsPedInAnyVehicle(ped, false)
    local key = onCall() and (inVehicle and 'vehicleCall' or 'call') or (inVehicle and 'vehicleText' or 'text')
    -- The bootstrap that names the handset can land after the phone opened; swap to the right prop then.
    if prop and propName ~= propModel() then removeProp() end
    if key == currentKey and handle and Kora.anim.isPlaying(ped) and prop then return true end
    local clip = animation(key)
    local started = Kora.anim.play(ped, clip.dict, clip.clip, {
        flag = clip.flag or 50,
        blendInSpeed = 3.0,
        blendOutSpeed = 2.0,
    })
    if not started then return false end
    handle, currentKey = started, key
    if not prop or not DoesEntityExist(prop) then
        prop = createProp(ped)
        if KoraPhone.State then KoraPhone.State.phoneObject = prop end
    end
    return true
end

function Animations.Start()
    Animations.Stop()
    if not option('enabled') then return false end
    local ped = Kora.cache.ped()
    cachedPed = ped
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return false end
    wanted = true
    generation = generation + 1
    local mine = generation
    local played = not blocked(ped) and apply(ped)
    -- Keeps the pose in step with the player: call/vehicle variants, and a cleanup/restore around ragdoll or water.
    CreateThread(function()
        while wanted and mine == generation do
            Wait(250)
            if not wanted or mine ~= generation then break end
            local current = cachedPed
            if blocked(current) then release() else pcall(apply, current) end
        end
    end)
    return played
end

function Animations.Stop()
    wanted = false
    generation = generation + 1
    release()
end

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Animations.Stop() end
end)

-- A restart does not reliably run the stop handler above before the old scripts are torn down, so a phone held at
-- that moment stays in the hand, orphaned (no owning script). A fresh instance owns no prop yet, so one of our prop
-- models attached to the player and owned by no running script (or by us) is stale. Other resources' props are kept.
CreateThread(function()
    local ped, resource = PlayerPedId(), GetCurrentResourceName()
    local ours = { [joaat(option('model'))] = true }
    for _, name in pairs(HANDSET_PROPS) do ours[joaat(name)] = true end
    for _, object in ipairs(GetGamePool('CObject')) do
        local owner = GetEntityScript(object)
        if IsEntityAttachedToEntity(object, ped) and ours[GetEntityModel(object)] and (owner == nil or owner == resource) then
            DetachEntity(object, true, false)
            SetEntityAsMissionEntity(object, true, true)
            DeleteEntity(object)
        end
    end
end)

KoraPhone.Animations = Animations