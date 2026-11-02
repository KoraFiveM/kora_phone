-- Run from the resource root: lua tests/camera-preview.test.lua
local focus, visible, selfie, destroyed = false, false, false, false
QBPhone = { State = { cameraMode = false, open = true }, SendNui = function(name, data)
    if name == 'phone:visibility' then visible = data end
end }
Kora = { cache = { ped = function() return 1 end } }
local threads = 0
function CreateThread() threads = threads + 1 end
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
local keepInput = false
function SetNuiFocusKeepInput(on) keepInput = on end
function DisplayRadar() end
function ClearFocus() end
function DoesCamExist() return true end
function DestroyCam() destroyed = true end
function AddEventHandler() end
function GetCurrentResourceName() return 'kora_phone' end
dofile('client/camera.lua')
assert(threads == 0, 'no camera loop may run before the camera opens')
assert(QBPhone.Camera.Open({preview=true,front=true}))
assert(focus and visible and selfie and QBPhone.State.cameraMode)
assert(keepInput)
assert(threads == 1, 'opening the camera starts exactly one frame loop')
assert(QBPhone.Camera.SetLooking(true) and not focus and keepInput)
assert(QBPhone.Camera.SetLooking(false) and focus and keepInput)
assert(QBPhone.Camera.SetFacing(false) and not selfie)
assert(QBPhone.Camera.SetFacing(true) and selfie)
assert(not QBPhone.Camera.SetFacing('front'))
QBPhone.Camera.Close()
assert(not keepInput)
assert(destroyed and not QBPhone.State.cameraMode and focus and visible)
assert(not QBPhone.Camera.SetFacing(true))
assert(QBPhone.Camera.Open())
assert(not focus and not visible and not selfie and not keepInput)
assert(not QBPhone.Camera.SetLooking(true))
print('PASS camera preview: visible controls, selfie/rear switching, validation and cleanup')
