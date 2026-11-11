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
-- current id (e.g. the old default "kora_core" -> "kora_core") instead of rejecting the settings save,
-- which is what made setup fail with "wallpaper is invalid". Unknown ids are still rejected.
-- Set false to require the current ids only.
Config.Settings = Config.Settings or {}
Config.Settings.AcceptLegacyIds = true
Config.Settings.LegacyIds = { qbcore = "kora_core" }

-- Share your number: third-eye (kora_target) a nearby player and pick "Share phone number". They get an
-- accept/decline prompt (in the phone if it is open, otherwise a kora_lib popup); nothing is saved until they
-- accept. The server re-checks every value here; the shareNumber rate limit is in config/server.lua.
-- Enabled = false removes the third-eye option and the server refuses every request.
Config.ShareNumber = {
    Enabled = true,
    Distance = 3.0,          -- metres; the server measures it from its own ped positions
    AnswerDistance = 10.0,   -- they must still be this close when they accept
    ExpireSeconds = 30,      -- an unanswered request expires (5 to 120)
    CooldownSeconds = 20,    -- per sharer and receiver pair
    AskForName = true,       -- the sharer types the name they share as (otherwise their character's first name)
    AllowShareBack = true,   -- the receiver may also share their own number back (mutual exchange)
    -- A PIN keeps a phone's content private; it does not hide the phone's own number from whoever holds it.
    -- true lets a PIN-locked (closed) phone share and accept numbers. false needs an unlocked phone, which
    -- with a PIN set means the phone must be open.
    AllowWhileLocked = true
}

-- Home screen. allowReorder lets players press-and-hold (or use the arrange button) and drag app icons on
-- the home grid and dock; the order is saved per phone. Set false to keep the fixed default order: the
-- arrange controls are hidden, the server ignores order changes and any order already saved is kept.
Config.HomeScreen = Config.HomeScreen or {}
Config.HomeScreen.allowReorder = true

-- Gallery. fullscreenViewer opens a photo or video in a large full-screen viewer (click the picture, Esc or
-- click outside to close). Set false to keep the small in-phone view with the plain video controls.
Config.Gallery = Config.Gallery or {}
Config.Gallery.fullscreenViewer = true

-- App Store. Set false to hide the App Store icon from the home screen entirely.
Config.AppStore = true

-- Toggle individual apps on or off. Apps set to false won't appear in the App Store or on
-- the home screen, and their server callbacks will be blocked. The server still checks extra
-- requirements for some apps (media provider for camera, housing tables for property, etc.),
-- so an app set to true here may still show "Unavailable on this server" in the Store if those
-- requirements aren't met.
Config.Apps = {
    banking     = true,
    social      = true,
    classifieds = true,
    services    = true,
    property    = true,
    vehicles    = true,
    flash       = true,
    moderation  = false,
    gps         = true,
    notes       = true,
    mail        = true,
    weather     = true,
    calculator  = true,
    clock       = true,
    music       = true,
}
