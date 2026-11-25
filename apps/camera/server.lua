-- Only the clip limits live on the server; saving a photo or clip is the phone's media service (camera.capture, media.upload).
local app = Phone.app('camera')

app.callback('config', function()
    local video = KoraPhone.Storage.supportsVideo()
    return {
        media = KoraPhone.Storage.provider() ~= 'disabled',
        flash = video and { maxSeconds = KoraPhone.Storage.Config().MaxVideoSeconds, maxBytes = KoraPhone.Storage.Config().MaxVideoBytes } or false,
    }
end, { rate = 'read' })
