Phone.app('notes', {
    name = 'Notes',
    description = 'A home for your plans, ideas, and little reminders.',
    icon = 'icon.svg',
    category = 'tools',
    permissions = { 'storage' },
    -- Up to 100 notes of 4000 characters each.
    storage = { keys = 128, totalBytes = 512 * 1024 },
    defaultInstalled = true,
})
