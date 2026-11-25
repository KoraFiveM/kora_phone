-- kora_phone configuration, part 2 of 4 (shared realm): handsets, SIMs, launchable apps and phone shops.
-- Adds its branches to the Config table defined in config/shared.lua. Do not put secrets here: this file is
-- downloaded by every client.

local C = Kora.config

local function shopItem()
    return C.object({
        label = C.string('Circuit Mobile', { label = 'Shop name', maxLength = 64, description = 'Name shown on the counter prompt and in the shop list.' }),
        coords = C.object({
            x = C.number(0.0, { label = 'X', min = -10000.0, max = 10000.0, step = 0.01 }),
            y = C.number(0.0, { label = 'Y', min = -10000.0, max = 10000.0, step = 0.01 }),
            z = C.number(0.0, { label = 'Z', min = -1000.0, max = 3000.0, step = 0.01 }),
        }, { description = 'World position of the counter.' }),
        distance = C.number(2.0, {
            label = 'Interaction radius (m)', min = 0.5, max = 10.0, step = 0.1,
            description = 'Interaction radius in metres; keep it small (2.0).',
        }),
        bucket = C.integer(0, { label = 'Routing bucket', min = 0, max = 65535, description = 'Routing bucket the counter exists in.' }),
        job = C.optional(nil, C.string('mechanic', { maxLength = 64 }), {
            label = 'Required job', description = 'Business counter: only this job can use it. Leave unset for a public counter.',
        }),
        grade = C.optional(nil, C.integer(0, { min = 0, max = 100 }), {
            label = 'Required job grade', description = 'Minimum job grade for a business counter.',
        }),
        recoveryFee = C.integer(500, { label = 'Recovery fee', min = 0, max = 1000000, description = 'Price to recover a lost handset.' }),
        replacementFee = C.integer(100, { label = 'Replacement fee', min = 0, max = 1000000, description = 'Price to replace a handset.' }),
        resalePercent = C.integer(50, { label = 'Resale percent', min = 0, max = 100, description = 'Share of the item price paid out when a handset is sold back.' }),
        prices = C.map({}, C.integer(0, { min = 0, max = 10000000 }), {
            label = 'Prices', keyType = 'string',
            description = 'Item name (key) mapped to its price. Only listed items are sold at this counter.',
        }),
    })
end

local function standardShop(label, x, y, z)
    return {
        label = label, coords = { x = x, y = y, z = z }, distance = 2.0,
        bucket = 0, recoveryFee = 500, replacementFee = 100, resalePercent = 50,
        prices = { phone_standard = 1200, phone_flip = 1800, phone_fold = 2400, phone_sim = 100 },
    }
end

local technician = standardShop('Mobile Workshop', -40.1, -1090.7, 26.4)
technician.job = 'mechanic'
technician.grade = 0

local function apps(defaults)
    local fields = {}
    for id, enabled in pairs(defaults) do
        fields[id] = C.boolean(enabled, { label = id .. ' allowed', description = 'Whether the server accepts the ' .. id .. ' app in saved settings.' })
    end
    return fields
end

Kora.config.extend({
    Handsets = C.map({
        phone = 'standard', -- legacy item: converted once, never stacked
        phone_standard = 'standard',
        phone_flip = 'flip',
        phone_fold = 'fold',
    }, C.enum('standard', { options = { 'standard', 'flip', 'fold' } }), {
        label = 'Handset items', keyType = 'string', requiredKeys = { 'phone_standard' }, scope = 'shared',
        description = 'Inventory item name (key) mapped to the handset model (value). The legacy phone item is treated as Standard. Removing an entry disables that model. Read once when the resource starts.',
    }),

    SimItem = C.string('phone_sim', {
        label = 'SIM item', minLength = 1, maxLength = 64, scope = 'server',
        description = 'Inventory item name of the SIM card. Read once when the resource starts.',
    }),
    SimSwap = C.enum('both', {
        label = 'Who may swap SIMs', scope = 'server', live = true, options = { 'player', 'shop', 'both' },
        description = 'player lets players swap their own SIM, shop only at a phone shop counter, both allows either.',
    }),
    -- Inserting a SIM moves its item into the phone (exactly one item leaves the inventory); removing it
    -- returns the same item with its number. The inventory gateway does this; the phone re-checks it.
    ConsumeSimOnInstall = C.boolean(true, {
        label = 'Re-check SIM item removal', scope = 'server', live = true,
        description = 'Inserting a SIM moves its item into the phone (exactly one item leaves the inventory); removing it returns the same item with its number. The inventory gateway does this and the phone re-checks it. Off skips the re-check.',
    }),

    LaunchApps = C.object(apps({
        phone = true, contacts = true, messages = true, camera = true, gallery = true, gps = true,
        settings = true, mail = true, clock = true, music = true,
        store = true, social = true, classifieds = true,
        flash = true, moderation = true,
    }), {
        live = true, advanced = true,
        description = 'Which apps the server accepts in saved settings (installedApps, home order). An id set to false or missing is rejected or dropped. Use Apps to hide an app from players.',
    }),

    PhoneServices = C.object({
        -- Replace coordinates and business job names for your server. Place each shop where no other
        -- interaction (bank teller/ATM, inventory shop, job point) sits within a few metres, or both prompts
        -- open together. The default Circuit Mobile spot is on the Alta St pavement near Legion Square, about
        -- 25 m from the Legion Fleeca teller (149.05, -1041.3). Digital Den doors (Vinewood, Mirror Park,
        -- Sinner St) each get a Circuit Mobile counter. Add more entries with the same shape for other
        -- stores; every entry is registered as a target zone and a kora_inventory shop automatically.
        shops = C.map({
            legion = standardShop('Circuit Mobile', 127.4, -1029.2, 29.4),
            digitalDenVinewood = standardShop('Circuit Mobile', -509.49, 278.57, 83.32),
            digitalDenMirrorPark = standardShop('Circuit Mobile', 1137.82, -470.77, 66.67),
            digitalDenSinnerSt = standardShop('Circuit Mobile', 392.61, -831.76, 29.29),
            technician = technician,
        }, shopItem(), {
            label = 'Phone shops', keyType = 'string', requiredKeys = {},
            description = 'Phone service counters keyed by an id. Each entry becomes a circle zone and a kora_inventory shop named kora_phone: plus the key. Keep each counter several metres away from other interactions. Read once when the resource starts.',
        }),
        wifi = C.map({
            legion = { label = 'Legion Public Wi-Fi', coords = { x = 215.8, y = -810.1, z = 30.7 }, radius = 70, bucket = 0 },
            workshop = {
                label = 'Workshop Private', coords = { x = -40.1, y = -1090.7, z = 26.4 }, radius = 25, bucket = 0,
                passwordConvar = 'kora_phone_workshop_wifi_password', ownerJob = 'mechanic',
            },
        }, C.object({
            label = C.string('Wi-Fi', { label = 'Network name', maxLength = 64 }),
            coords = C.object({
                x = C.number(0.0, { label = 'X', min = -10000.0, max = 10000.0, step = 0.01 }),
                y = C.number(0.0, { label = 'Y', min = -10000.0, max = 10000.0, step = 0.01 }),
                z = C.number(0.0, { label = 'Z', min = -1000.0, max = 3000.0, step = 0.01 }),
            }),
            radius = C.number(50, { label = 'Range (m)', min = 1, max = 1000, description = 'Players inside this distance can join the hotspot.' }),
            bucket = C.integer(0, { label = 'Routing bucket', min = 0, max = 65535 }),
            passwordConvar = C.optional(nil, C.string('', { maxLength = 128 }), {
                label = 'Password convar name',
                description = 'Name of the server convar holding the password (the password itself is never stored here). Unset means an open network.',
            }),
            ownerJob = C.optional(nil, C.string('', { maxLength = 64 }), {
                label = 'Owner job', description = 'Job allowed to manage this private hotspot.',
            }),
        }), {
            label = 'Wi-Fi hotspots', keyType = 'string', scope = 'server', live = true,
            description = 'Wi-Fi hotspots keyed by an id, with position, range and an optional password convar.',
        }),
    }, { advanced = true }),
})
