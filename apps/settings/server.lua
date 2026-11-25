-- Everything that changes the phone goes through phone.system, which runs the validated server routes. The only thing the app
-- asks of this file is the caller's own photos, for choosing a wallpaper or a case photo.
local app = Phone.app('settings')

app.callback('photos', function(source)
    local items = Phone.unwrap(KoraPhone.Services.Media.list(source, { limit = 50 })).items
    local photos = {}
    for _, item in ipairs(items) do
        if not tostring(item.mimeType or ''):find('^video') then photos[#photos + 1] = { id = item.id, url = item.publicUrl } end
    end
    return photos
end, { rate = 'read' })
