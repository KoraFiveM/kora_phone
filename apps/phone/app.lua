-- The dialer and the recent calls. The call itself (ringing, answer, hang up, video) belongs to the phone's call
-- service and call screen: this app only starts one with phone.call(number).
Phone.app('phone', {
    name = 'Phone',
    description = 'A voice on the other end.',
    icon = 'icon.svg',
    category = 'system',
    system = true,
    permissions = { 'contacts.read' },
    defaultInstalled = true,
})
