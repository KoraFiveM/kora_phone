-- Run from the resource root: lua tests/camera-capture.test.lua
local timer, upload, request, replies, closes, throws
function CreateThread() end
function SetTimeout(ms, callback) assert(ms == 30000); timer = callback end
function GetResourceState() return 'started' end
exports = { ['screenshot-basic'] = { requestScreenshotUpload = function(_, _, _, _, callback)
    if throws then error('provider unavailable') end
    upload = callback
end } }
json = { decode = function() return { receipt = 'receipt' } end }
QBPhone = { State = { cameraMode = true }, ServerCallback = function(name, _, callback)
    request = { name = name, callback = callback }
end }
function AddEventHandler() end
function GetCurrentResourceName() return "kora_phone" end
dofile('client/camera.lua')
QBPhone.Camera.Close = function() closes = closes + 1; QBPhone.State.cameraMode = false end
local function start()
    timer, upload, request, replies, closes, throws = nil, nil, nil, {}, 0, false
    QBPhone.State.cameraMode = true
    QBPhone.Camera.Capture(function(result) replies[#replies + 1] = result end)
end
local function beginUpload()
    request.callback({ ok = true, data = { upload = {
        mode = 'multipart-upload', token = 'token', uploadUrl = 'https://upload.example/photo'
    } } })
end
start()
timer()
assert(#replies == 1 and replies[1].error.code == 'CAPTURE_TIMEOUT' and closes == 1)
beginUpload()
assert(upload == nil, 'late tickets must not start uploads')
start()
beginUpload()
timer()
upload('{}')
assert(#replies == 1 and closes == 1)
assert(request.name == 'qbphone:server:requestMediaUpload', 'late uploads must not be completed')
start()
throws = true
beginUpload()
assert(#replies == 1 and replies[1].error == 'UPLOAD_FAILED' and closes == 1)
timer()
assert(#replies == 1 and closes == 1)
start()
beginUpload()
upload('{}')
assert(request.name == 'qbphone:server:completeMediaUpload')
request.callback({ ok = true, data = { id = 7 } })
timer()
assert(#replies == 1 and replies[1].ok and closes == 0)
print('PASS camera capture: stalled callbacks recover, late callbacks ignored, export errors recover, success preserved')
