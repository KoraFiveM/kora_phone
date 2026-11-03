Config = Config or {}

Config.Debug = false
Config.PhoneItem = 'phone'
Config.RequirePhoneItem = true
Config.PhoneNumber = {
    Prefix = '555',
    SubscriberDigits = 7
}

Config.Limits = {
    ContactName = 64,
    MessageBody = 2000,
    ConversationTitle = 80,
    PageSizeDefault = 30,
    PageSizeMaximum = 100
}

-- Appearance ids that older web bundles / saved handsets used. When true, the server maps them to the
-- current id (e.g. the old default "qbcore" -> "kora_core") instead of rejecting the settings save,
-- which is what made setup fail with "wallpaper is invalid". Unknown ids are still rejected.
-- Set false to require the current ids only.
Config.Settings = Config.Settings or {}
Config.Settings.AcceptLegacyIds = true
Config.Settings.LegacyIds = { qbcore = "kora_core" }

-- Home screen. allowReorder lets players press-and-hold (or use the arrange button) and drag app icons on
-- the home grid and dock; the order is saved per phone. Set false to keep the fixed default order: the
-- arrange controls are hidden, the server ignores order changes and any order already saved is kept.
Config.HomeScreen = Config.HomeScreen or {}
Config.HomeScreen.allowReorder = true

-- Gallery. fullscreenViewer opens a photo or video in a large full-screen viewer (click the picture, Esc or
-- click outside to close). Set false to keep the small in-phone view with the plain video controls.
Config.Gallery = Config.Gallery or {}
Config.Gallery.fullscreenViewer = true

-- Compatibility with resources written for the legacy kora_phone resource (kora_housing, kora_police, ...).
-- koraPhoneExports: also answer exports.kora_phone:sendMailToOffline / sendMail / sendMessage / getNumber /
-- getNumberByCitizenId / hasPhone (server) and open / close / isOpen (client). Needs a restart to apply.
-- Never run this resource alongside the legacy kora_phone: both provide the same names.
Config.compat = Config.compat or {}
Config.compat.koraPhoneExports = { enabled = true }
