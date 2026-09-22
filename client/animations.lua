SteviePhone = SteviePhone or {}
local Animations = {}

local dictionary = 'cellphone@'
local animation = 'cellphone_text_read_base'
local model = `prop_npc_phone_02`
local animationHandle

function Animations.Start()
    Animations.Stop()
    local ped = QB.cache.ped()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return false end

    animationHandle = QB.anim.play(ped, dictionary, animation, { flag = 50, blendInSpeed = 3.0, blendOutSpeed = 2.0 })
    if not animationHandle then return false end

    local object = QB.anim.attachProp(ped, model, 'SKEL_R_Hand', nil, nil, { softPin = true, collision = true })
    if object then SteviePhone.State.phoneObject = object end
    return true
end

function Animations.Stop()
    if animationHandle then QB.anim.stopHandle(animationHandle, 2.0) end
    animationHandle = nil
    local object = SteviePhone.State and SteviePhone.State.phoneObject
    if object then QB.anim.detachProp(object) end
    if SteviePhone.State then SteviePhone.State.phoneObject = nil end
end

SteviePhone.Animations = Animations
