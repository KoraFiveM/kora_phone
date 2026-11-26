-- The viewfinder shows the game's own render (the page draws it from the game texture; client.lua drives the native camera).
-- `record` lets the page open the microphone for clips, `media.write` saves a recorded clip, `camera` takes the photo.
Phone.app('camera', {
    name = 'Camera',
    description = 'Capture what you see.',
    icon = 'icon.svg',
    category = 'system',
    system = true,
    permissions = { 'camera', 'media.write', 'record' },
    defaultInstalled = true,
})
