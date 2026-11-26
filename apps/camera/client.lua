-- The native camera. The page asks for it to open, aim, zoom and close; the game answers with its settings and pushes the aiming
-- hint and the talking state back (client/camera.lua).
local app = Phone.app('camera')

local function payloadOf(payload) return type(payload) == 'table' and payload or {} end

app.client('open', function(payload)
    local opened, errorCode = KoraPhone.Camera.Open({ preview = true, front = payloadOf(payload).front == true })
    return {
        ok = opened == true,
        error = errorCode,
        zoom = opened == true and KoraPhone.Camera.ZoomEnabled() or nil,
        mic = opened == true and KoraPhone.Camera.MicSettings() or nil,
        hint = opened == true and KoraPhone.Camera.Hint() or nil,
    }
end)
app.client('zoom', function(payload) return { ok = KoraPhone.Camera.Zoom(tonumber(payloadOf(payload).dir)) } end)
app.client('facing', function(payload) return { ok = KoraPhone.Camera.SetFacing(payloadOf(payload).front == true) } end)
app.client('recording', function(payload) return { ok = KoraPhone.Camera.SetRecording(payloadOf(payload).active == true) } end)
app.client('close', function() KoraPhone.Camera.Close() return { ok = true } end)
