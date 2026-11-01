-- Run from the resource root: lua tests/camera-preview.test.lua
local focus, visible, selfie, destroyed = false, false, false, false
QBPhone = { State = { cameraMode = false, open = true }, SendNui = function(name, data)
    if name == 'phone:visibility' then visible = data end
end }
Kora = { cache = { ped = function() return 1 end } }
function CreateThread() end
function IsEntityDead() return false end
function IsRadarHidden() return false end
function CreateCam() return 10 end
function PlayerPedId() return 1 end
function GetOffsetFromEntityInWorldCoords() return {x=0,y=1,z=1} end
function GetPedBoneCoords() return {x=0,y=0,z=1} end
function GetGameplayCamRot() return {x=0,y=0,z=0} end
function PointCamAtPedBone() selfie = true end
function StopCamPointing() selfie = false end
function SetCamCoord() end
function SetCamRot() end
function SetCamFov() end
function RenderScriptCams() end
function SetNuiFocus(mouse, keyboard) focus = mouse and keyboard end
function SetNuiFocusKeepInput() end
function DisplayRadar() end
function ClearFocus() end
function DoesCamExist() return true end
function DestroyCam() destroyed = true end
dofile('client/camera.lua')
assert(QBPhone.Camera.Open({preview=true,front=true}))
assert(focus and visible and selfie and QBPhone.State.cameraMode)
assert(QBPhone.Camera.SetFacing(false) and not selfie)
assert(QBPhone.Camera.SetFacing(true) and selfie)
assert(not QBPhone.Camera.SetFacing('front'))
QBPhone.Camera.Close()
assert(destroyed and not QBPhone.State.cameraMode and focus and visible)
assert(not QBPhone.Camera.SetFacing(true))
assert(QBPhone.Camera.Open())
assert(not focus and not visible and not selfie)
print('PASS camera preview: visible controls, selfie/rear switching, validation and cleanup')
