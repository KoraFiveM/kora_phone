-- The phone's own settings. `system` apps of this resource may use phone.system(...): settings, PIN, blocked numbers
-- and handset controls (SIM, Wi-Fi, cloud, Face ID, shop services). No other app can.
Phone.app('settings', {
    name = 'Settings',
    description = 'Unmistakably yours.',
    icon = 'icon.svg',
    category = 'system',
    system = true,
    permissions = { 'contacts.read' },
    defaultInstalled = true,
})
