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
local fov
function SetCamFov(_, value) fov = value end
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
-- Zoom: defaults (smooth) only move the target; the frame loop eases the field of view towards it.
assert(fov == 60.0 and QBPhone.Camera.ZoomEnabled())
assert(QBPhone.Camera.Zoom(1) and QBPhone.Camera.targetFov == 55.0 and fov == 60.0)
assert(not QBPhone.Camera.Zoom(5) and not QBPhone.Camera.Zoom(nil))
for _ = 1, 20 do QBPhone.Camera.Zoom(1) end
assert(QBPhone.Camera.targetFov == 10.0, 'zoom stops at minFov')
QBPhone.Camera.Close()
Config = { Camera = { zoom = { smooth = false, step = 10.0, selfie = { minFov = 30.0 } } } }
assert(QBPhone.Camera.Open({preview=true,front=true}) and fov == 60.0)
assert(QBPhone.Camera.Zoom(1) and fov == 50.0, 'without smoothing the step applies at once')
for _ = 1, 10 do QBPhone.Camera.Zoom(1) end
assert(fov == 30.0, 'the selfie lens has its own minFov')
assert(QBPhone.Camera.Zoom(-1) and fov == 40.0)
assert(QBPhone.Camera.SetFacing(false) and fov == 60.0, 'flipping resets the zoom')
for _ = 1, 10 do QBPhone.Camera.Zoom(1) end
assert(fov == 10.0, 'the rear lens uses the shared range')
QBPhone.Camera.Close()
assert(QBPhone.Camera.fov == nil and QBPhone.Camera.targetFov == nil and not QBPhone.Camera.Zoom(1))
Config = { Camera = { zoom = { enabled = false } } }
assert(QBPhone.Camera.Open({preview=true,front=true}) and not QBPhone.Camera.ZoomEnabled() and not QBPhone.Camera.Zoom(1))
Config = nil
QBPhone.Camera.Close()
assert(not keepInput)
assert(destroyed and not QBPhone.State.cameraMode and focus and visible)
assert(not QBPhone.Camera.SetFacing(true))
assert(QBPhone.Camera.Open())
assert(not focus and not visible and not selfie and not keepInput)
assert(not QBPhone.Camera.SetLooking(true))
print('PASS camera preview: visible controls, selfie/rear switching, zoom, validation and cleanup')
