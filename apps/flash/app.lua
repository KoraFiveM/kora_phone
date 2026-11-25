-- Flash: the public photo and clip feed. `camera` takes the in-game photo, `record` lets the page use the webcam and microphone for clips,
-- `media.write` saves the clip before it is posted.
Phone.app('flash', {
    name = 'Flash',
    description = 'Little moments. A whole city.',
    icon = 'icon.svg',
    category = 'social',
    permissions = { 'contacts.read', 'media.write', 'camera', 'record' },
    defaultInstalled = false,
})
