SteviePhone = SteviePhone or {}
local Animations = {}

local dictionary = 'cellphone@'
local animation = 'cellphone_text_read_base'
local model = `prop_npc_phone_02`

local function requestAnimDict(name, timeout)
    RequestAnimDict(name)
    local deadline = GetGameTimer() + (timeout or 3000)
    while not HasAnimDictLoaded(name) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(name)
end

local function requestModel(hash, timeout)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return false end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeout or 3000)
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(hash)
end

function Animations.Start()
    Animations.Stop()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return false end

    if requestAnimDict(dictionary) then
        TaskPlayAnim(ped, dictionary, animation, 3.0, -1.0, -1, 50, 0.0, false, false, false)
    end

    if requestModel(model) then
        local object = CreateObject(model, 1.0, 1.0, 1.0, false, false, false)
        if DoesEntityExist(object) then
            AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0,
                0.0, 0.0, 0.0, true, true, false, true, 1, true)
            SteviePhone.State.phoneObject = object
        end
        SetModelAsNoLongerNeeded(model)
    end
    return true
end

function Animations.Stop()
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        StopAnimTask(ped, dictionary, animation, 2.0)
    end
    local object = SteviePhone.State and SteviePhone.State.phoneObject
    if object and DoesEntityExist(object) then
        DetachEntity(object, true, true)
        DeleteEntity(object)
    end
    if SteviePhone.State then SteviePhone.State.phoneObject = nil end
    RemoveAnimDict(dictionary)
end

SteviePhone.Animations = Animations

