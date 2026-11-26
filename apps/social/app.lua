-- Pulse: chats and groups. `record` lets this app's page use the webcam and microphone for short clips, `media.write` saves the
-- clip to the gallery before it is sent.
Phone.app('social', {
    name = 'Pulse',
    description = 'Message your people, one-on-one or in a group.',
    icon = 'icon.svg',
    category = 'social',
    permissions = { 'contacts.read', 'contacts.write', 'media.write', 'record' },
    defaultInstalled = false,
})
