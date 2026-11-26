-- kora_phone configuration, part 1 of 4 (shared realm).
--
-- This is the only file that calls Kora.config.define. config/handsets.lua (shared) and config/server.lua
-- (server only) add their branches with Kora.config.extend, so one `Config` table keeps every access path
-- (Config.Camera.zoom.step, Config.Server.RateLimits.read, ...) exactly as the code reads it.
--
-- Scopes used across the config files:
--   shared (default)  validated and synced to every client; client code reads these.
--   client            validated and saved by the server, synced to clients, never run through server handlers.
--   server            never sent to a client (rate limits, media provider, secrets, rules only the server uses).
-- Admins edit values in-game with /config (needs the kora_lib.config.edit ACE); changes are written to
-- config.local.lua, never to these files. See docs/configuration.md.
--
-- Client-only settings (Client, Camera, Animation) are declared here, not in config/client.lua, because the
-- server has to know the schema to validate and persist them.

local C = Kora.config

local function offset(label)
    return C.object({
        x = C.number(0.0, { label = label .. ' X', min = -5.0, max = 5.0, step = 0.001, live = true }),
        y = C.number(0.0, { label = label .. ' Y', min = -5.0, max = 5.0, step = 0.001, live = true }),
        z = C.number(0.0, { label = label .. ' Z', min = -5.0, max = 5.0, step = 0.001, live = true }),
    }, { advanced = true })
end

local function animation(dict, clip, label)
    return C.object({
        dict = C.string(dict, { label = label .. ' animation dictionary', maxLength = 128, live = true }),
        clip = C.string(clip, { label = label .. ' animation clip', maxLength = 128, live = true }),
    }, { advanced = true })
end

Config = C.define({
    RequirePhoneItem = C.boolean(true, {
        label = 'Require a phone item',
        description = 'Require a handset item (any name in Handsets) to use the phone. Turn off to let everyone use the phone without owning one.',
        live = true,
    }),

    PhoneNumber = C.object({
        Prefix = C.string('555', {
            label = 'Phone number prefix', minLength = 1, maxLength = 6, pattern = '^%d+$',
            description = 'Digits every generated phone number starts with. Changing it after launch does not rewrite numbers already issued.',
        }),
        SubscriberDigits = C.integer(7, {
            label = 'Random digits after the prefix', min = 4, max = 10,
            description = 'How many zero-padded random digits follow the prefix. Prefix length plus this value is the full number length.',
        }),
    }, { advanced = true }),

    Limits = C.object({
        ContactName = C.integer(64, { label = 'Contact name length', min = 8, max = 128, description = 'Longest contact or shared-name text, in characters.' }),
        MessageBody = C.integer(2000, { label = 'Message length', min = 100, max = 10000, description = 'Longest single message, in characters.' }),
        ConversationTitle = C.integer(80, { label = 'Conversation title length', min = 8, max = 200, description = 'Longest group conversation title, in characters.' }),
        PageSizeDefault = C.integer(30, { label = 'Default page size', min = 5, max = 100, description = 'Rows returned by a list request that does not ask for a size.' }),
        PageSizeMaximum = C.integer(100, { label = 'Maximum page size', min = 10, max = 500, description = 'Largest page a client may request from any list.' }),
    }, { advanced = true }),

    -- Appearance ids that older web bundles / saved handsets used. When true, the server maps them to the
    -- current id instead of rejecting the settings save, which is what made setup fail with
    -- "wallpaper is invalid". Unknown ids are still rejected.
    Settings = C.object({
        AcceptLegacyIds = C.boolean(true, {
            label = 'Accept retired appearance ids', live = true,
            description = 'Map appearance ids used by older saved phones to their current id instead of rejecting the settings save. Unknown ids are still rejected. Turn off to require current ids only.',
        }),
        LegacyIds = C.map({ qbcore = 'kora_core' }, C.string('kora_core', { maxLength = 64 }), {
            label = 'Retired appearance ids', live = true,
            description = 'Old appearance id (key) mapped to its current id (value). Only used while Accept retired appearance ids is on.',
        }),
    }, { advanced = true }),

    -- Share your number: third-eye (kora_target) a nearby player and pick "Share phone number". They get an
    -- accept/decline prompt (in the phone if it is open, otherwise a kora_lib popup); nothing is saved until
    -- they accept. The server re-checks every value here; the shareNumber rate limit is in Server.RateLimits.
    ShareNumber = C.object({
        Enabled = C.boolean(true, {
            label = 'Enable number sharing', live = true,
            description = 'Off removes the third-eye option and the server refuses every share request.',
        }),
        Distance = C.number(3.0, {
            label = 'Share distance (m)', min = 1.0, max = 15.0, step = 0.5, live = true,
            description = 'How close the two players must be to start a share. The server measures it from its own ped positions.',
        }),
        AnswerDistance = C.number(10.0, {
            label = 'Answer distance (m)', min = 1.0, max = 50.0, step = 0.5, live = true,
            description = 'The receiver must still be this close to the sharer when they accept.',
        }),
        ExpireSeconds = C.integer(30, {
            label = 'Request expiry (s)', min = 5, max = 120, live = true,
            description = 'An unanswered request expires after this long.',
        }),
        CooldownSeconds = C.integer(20, {
            label = 'Cooldown per pair (s)', min = 0, max = 600, live = true,
            description = 'Minimum wait before the same sharer and receiver can exchange another request.',
        }),
        AskForName = C.boolean(true, {
            label = 'Sharer types a name', live = true,
            description = 'The sharer types the name they share as. Off uses their character first name.',
        }),
        AllowShareBack = C.boolean(true, {
            label = 'Allow sharing back', live = true,
            description = 'The receiver may also share their own number back (mutual exchange).',
        }),
        AllowWhileLocked = C.boolean(true, {
            label = 'Allow while PIN-locked', live = true,
            description = 'A PIN keeps a phone content private; it does not hide the phone own number from whoever holds it. On lets a PIN-locked (closed) phone share and accept numbers. Off needs an unlocked phone, which with a PIN set means the phone must be open.',
        }),
    }),

    -- Home screen. allowReorder lets players press-and-hold (or use the arrange button) and drag app icons on
    -- the home grid and dock; the order is saved per phone.
    HomeScreen = C.object({
        allowReorder = C.boolean(true, {
            label = 'Players can rearrange icons', live = true,
            description = 'Lets players press-and-hold (or use the arrange button) and drag app icons on the home grid and dock; the order is saved per phone. Off keeps the fixed default order: the arrange controls are hidden, the server ignores order changes and any order already saved is kept.',
        }),
    }),

    -- Gallery. fullscreenViewer opens a photo or video in a large full-screen viewer.
    Gallery = C.object({
        fullscreenViewer = C.boolean(true, {
            label = 'Full-screen media viewer', scope = 'server', live = true,
            description = 'Open a photo or video in a large full-screen viewer (click the picture; Esc or click outside closes). Off keeps the small in-phone view with the plain video controls.',
        }),
    }),

    AppStore = C.boolean(true, {
        label = 'Show the App Store', scope = 'server', live = true,
        description = 'Off hides the App Store icon from the home screen entirely.',
    }),

    -- Toggle individual apps on or off. Apps set to false do not appear in the App Store or on the home
    -- screen, and their server callbacks are blocked. The server still checks extra requirements for some
    -- apps (media provider for camera, housing tables for property, ...), so an app set to true here may
    -- still show "Unavailable on this server" in the Store if those requirements are not met.
    Apps = C.object({
        banking = C.boolean(true, { label = 'Banking app', description = 'Off also blocks bank transfers from the phone.' }),
        social = C.boolean(true, { label = 'Social app', description = 'Off also refuses every social callback on the server.' }),
        classifieds = C.boolean(true, { label = 'Classifieds app', description = 'Off also refuses every market callback on the server.' }),
        services = C.boolean(true, { label = 'Services app', description = 'Job and business directory. Only changes what the UI offers.' }),
        property = C.boolean(true, { label = 'Property app', description = 'Still needs the housing tables in Server.Property to exist.' }),
        vehicles = C.boolean(true, { label = 'Vehicles app', description = 'Garage listing. Only changes what the UI offers.' }),
        flash = C.boolean(true, { label = 'Flash app', description = 'Short video clips. Only changes what the UI offers.' }),
        moderation = C.boolean(false, { label = 'Moderation app', description = 'Staff moderation tools. Off also refuses every moderation callback on the server.' }),
        gps = C.boolean(true, { label = 'GPS app', description = 'Only changes what the UI offers.' }),
        notes = C.boolean(true, { label = 'Notes app', description = 'Off removes the Notes app from the phone.' }),
        mail = C.boolean(true, { label = 'Mail app', description = 'Only changes what the UI offers.' }),
        weather = C.boolean(true, { label = 'Weather app', description = 'Off removes the Weather app and the home-screen weather shortcut.' }),
        calculator = C.boolean(true, { label = 'Calculator app', description = 'Off removes the Calculator app from the phone.' }),
        clock = C.boolean(true, { label = 'Clock app', description = 'Only changes what the UI offers.' }),
        music = C.boolean(true, { label = 'Music app', description = 'Only changes what the UI offers.' }),
    }, { scope = 'server', live = true }),

    -- ---------------------------------------------------------------- client-only settings

    Client = C.object({
        Command = C.string('phone', {
            label = 'Toggle command', minLength = 1, maxLength = 32, pattern = '^[%w_%-]+$',
            description = 'Chat command that opens and closes the phone. Read once when the resource starts.',
        }),
        Keybind = C.string('M', {
            label = 'Default key', minLength = 1, maxLength = 32,
            description = 'Default key mapping for the toggle command. Players can rebind it in their key settings. Read once when the resource starts.',
        }),
        DisableWhileDead = C.boolean(true, {
            label = 'Block while dead', live = true,
            description = 'No phone while dead or in last stand; an open phone closes.',
        }),
        NoPhoneNoticeWhileDown = C.boolean(true, {
            label = 'Say "no phone" while down', live = true,
            description = 'Downed without a phone item: say "You do not have a phone" instead of "cannot use your phone right now".',
        }),
        NotificationSound = C.boolean(true, {
            label = 'Notification sound', live = true,
            description = 'Play the game own text-message tone for notifications while the phone is closed.',
        }),
        -- Another resource sets this state bag while its own camera or editor is up (kora_emotemenu's Emote
        -- Maker freecam does); kora_inventory honours the same bag.
        UiBlockBag = C.string('koraUiBlocked', {
            label = 'UI block state bag', maxLength = 64, advanced = true,
            description = 'Player state bag that keeps the phone shut while it is true. Another resource sets it while its own camera or editor is up (the Emote Maker freecam does); the phone then refuses to open (key, item, export, camera app) and closes if it was open. kora_inventory honours the same bag. Empty turns this off. Read once when the resource starts.',
        }),
    }, { scope = 'client' }),

    -- Camera app. The live preview needs the mouse for the phone UI, so aiming works through a key.
    Camera = C.object({
        lookMode = C.enum('hold', {
            label = 'Aiming mode',
            options = {
                { value = 'hold', label = 'Hold the look key' },
                { value = 'toggle', label = 'Toggle with the look key' },
                { value = 'off', label = 'Fixed to where the player faces' },
            },
            description = 'How the camera is aimed while the phone cursor is up. Hold aims while the look key is held, toggle switches aiming on and off with it, off keeps the camera fixed to where the player faces. Read once when the resource starts.',
        }),
        lookKey = C.string('LMENU', {
            label = 'Look key', minLength = 1, maxLength = 32,
            description = 'Keyboard key name for aiming (LMENU is left Alt). A default only: players can rebind it in their key settings. Read once when the resource starts.',
        }),
        hint = C.boolean(true, { label = 'Show on-screen help', live = true, description = 'Show the on-screen help line while the camera is open.' }),
        -- The mouse wheel zooms the rear and selfie cameras, with the phone cursor up and while aiming.
        zoom = C.object({
            enabled = C.boolean(true, { label = 'Mouse wheel zoom', description = 'Zoom the rear and selfie cameras with the mouse wheel, both with the phone cursor up and while aiming.' }),
            minFov = C.number(10.0, { label = 'Closest zoom (FOV)', min = 1.0, max = 120.0, step = 1.0, description = 'Smallest field of view in degrees (lower is closer).' }),
            maxFov = C.number(60.0, { label = 'Widest zoom (FOV)', min = 1.0, max = 120.0, step = 1.0, description = 'Largest field of view in degrees.' }),
            defaultFov = C.number(60.0, { label = 'Starting zoom (FOV)', min = 1.0, max = 120.0, step = 1.0, description = 'The camera opens at this field of view and returns to it when it closes or flips between rear and selfie.' }),
            step = C.number(5.0, { label = 'Zoom per wheel notch (degrees)', min = 0.5, max = 30.0, step = 0.5, description = 'Field of view change for each mouse wheel notch.' }),
            smooth = C.boolean(true, { label = 'Smooth zoom', description = 'Ease to each zoom step instead of jumping.' }),
            smoothSpeed = C.number(10.0, { label = 'Smooth zoom speed', min = 1.0, max = 50.0, step = 0.5, description = 'Higher eases to each step quicker. Only used when smooth zoom is on.' }),
            selfie = C.object({
                minFov = C.number(30.0, { label = 'Selfie closest zoom (FOV)', min = 1.0, max = 120.0, step = 1.0, description = 'Overrides the closest zoom for the selfie camera held at arm length.' }),
                maxFov = C.number(60.0, { label = 'Selfie widest zoom (FOV)', min = 1.0, max = 120.0, step = 1.0, description = 'Overrides the widest zoom for the selfie camera held at arm length.' }),
            }),
        }, { live = true }),
        -- Sound in Camera video clips: the player's OWN microphone, recorded by the phone's browser (FiveM
        -- asks the player once for microphone access and always uses their Windows default input). Other
        -- players' voices and game sound cannot be recorded (docs/features.md).
        micAudio = C.object({
            enabled = C.boolean(true, { label = 'Record microphone in clips', description = 'Video clips contain the player own microphone, recorded by the phone browser (FiveM asks once for access and uses the Windows default input). Other players voices and game sound cannot be recorded. Off makes clips silent.' }),
            followVoice = C.boolean(true, { label = 'Only while talking', description = 'The microphone is only live while the game says the player is talking (push-to-talk or voice activity), so a clip holds what nearby players actually heard.' }),
        }, { live = true }),
    }, { scope = 'client' }),

    -- Phone prop and animation while the phone is open. The player holds a phone and plays the texting pose
    -- (the in-car pose when seated, the call pose during a call). The prop and pose go away when the phone
    -- closes or the player dies, is cuffed, ragdolls or swims, and come back when that clears.
    Animation = C.object({
        enabled = C.boolean(true, { label = 'Phone prop and animation', description = 'Off means no prop and no animation; the phone just opens.' }),
        model = C.string('prop_npc_phone_02', { label = 'Phone prop model', minLength = 1, maxLength = 64, description = 'Prop model held in the hand.' }),
        bone = C.string('28422', {
            label = 'Attach bone (index or name)', minLength = 1, maxLength = 64, pattern = '^[%w_]+$',
            description = 'Bone the prop attaches to: a numeric bone index (28422 is PH_R_Hand) or a bone name such as PH_R_Hand. Digits are read as an index.',
        }),
        offset = offset('Prop offset'),
        rotation = offset('Prop rotation'),
        cancelOnRagdoll = C.boolean(true, { label = 'Drop pose while ragdolling', description = 'Drop the pose while ragdolling or falling over.' }),
        cancelOnWater = C.boolean(true, { label = 'Drop pose while swimming', description = 'Drop the pose while swimming.' }),
        -- flag defaults to 50 (upper body only, so the player can still move)
        anims = C.object({
            text = animation('cellphone@', 'cellphone_text_read_base', 'Texting'),
            call = animation('cellphone@', 'cellphone_call_listen_base', 'Call'),
            vehicleText = animation('anim@cellphone@in_car@ps', 'cellphone_text_read_base', 'In-car texting'),
            vehicleCall = animation('anim@cellphone@in_car@ps', 'cellphone_call_listen_base', 'In-car call'),
        }, { advanced = true, description = 'Animation clips used while the phone is open. Played with flag 50 (upper body only, so the player can still move).' }),
    }, { scope = 'client', live = true }),
})
