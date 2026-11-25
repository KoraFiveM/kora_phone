-- Defines the app. Static data only: the phone validates it before any app code runs.
-- The id must equal the folder name. See docs/apps.md for every field.
Phone.app('__ID__', {
    name = '__NAME__',
    description = 'What __NAME__ does, in one sentence',
    icon = 'smile',                 -- a lucide icon name
    category = 'tools',             -- tools | life | social | games | system
    permissions = { 'storage' },    -- what the UI may ask the phone for; request only what you use
    defaultInstalled = false,
})
