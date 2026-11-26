-- Contacts sits in the dock. The phone keeps its own copy of the contact list for Phone and Messages, so every
-- change here ends with phone.refresh().
Phone.app('contacts', {
    name = 'Contacts',
    description = 'Good people. One place.',
    icon = 'icon.svg',
    category = 'system',
    system = true,
    defaultInstalled = true,
})
