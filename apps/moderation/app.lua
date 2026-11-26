-- Staff tools for the Pulse, Flash and Market reports. Off by default: set Config.Apps.moderation = true.
-- `staff` makes the phone show and serve this app to moderators only, checked on the server.
Phone.app('moderation', {
    name = 'Moderation',
    description = 'Keep the city civil.',
    icon = 'icon.svg',
    category = 'system',
    system = true,
    staff = true,
    defaultInstalled = true,
})
