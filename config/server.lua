-- kora_phone configuration, part 4 of 4 (server only).
-- Everything here uses scope = 'server' and is never sent to a client. Secrets are marked sensitive: they are
-- never shown in /config (put the real value in a convar or config.local.lua, never in a tracked file).

local C = Kora.config

local function bucket(capacity, refill)
    return {
        capacity = capacity,
        refillPerSecond = refill,
    }
end

local function bucketShape()
    return C.object({
        capacity = C.integer(10, { label = 'Burst size', min = 1, max = 1000, description = 'Calls allowed in a burst before the limit applies.' }),
        refillPerSecond = C.number(1, { label = 'Refill per second', min = 0.001, max = 1000, step = 0.001, description = 'Calls restored per second after a burst.' }),
    })
end

local function location(label, x, y)
    return { label = label, x = x, y = y }
end

Kora.config.extend({
    Server = C.object({
        AutoProvisionDevice = C.boolean(true, {
            label = 'Create a device automatically', live = true,
            description = 'Create a device row when a character first needs one.',
        }),
        DatabaseReadyTimeoutMs = C.integer(15000, {
            label = 'Database wait (ms)', min = 1000, max = 120000, advanced = true,
            description = 'How long start-up waits for the database before stopping the resource. Read once when the resource starts.',
        }),

        -- Burst (capacity) and sustained rate (refillPerSecond) per action; enforced as capacity calls per capacity/refill seconds. Unknown actions fall back to mutation.
        RateLimits = C.map({
            bootstrap = bucket(4, 0.5),
            read = bucket(25, 8),
            mutation = bucket(12, 2),
            sendMessage = bucket(8, 1),
            callStart = bucket(4, 0.25),
            -- ICE gathering fires several candidates in a burst when a video call starts.
            videoSignal = bucket(30, 10),
            bankTransfer = bucket(3, 0.05),
            mediaUpload = bucket(4, 0.1),
            jobMutation = bucket(8, 0.5),
            pin = bucket(6, 0.1),
            shareNumber = bucket(3, 0.05),
            -- Third-party app calls; an app may read several keys at once when it starts.
            sdk = bucket(40, 10),
            ['community.read'] = bucket(25, 8),
            ['community.profile'] = bucket(4, 0.25),
            ['community.post'] = bucket(8, 0.5),
            ['community.reaction'] = bucket(20, 4),
            ['community.follow'] = bucket(10, 1),
            ['community.comment'] = bucket(8, 0.5),
            ['community.block'] = bucket(6, 0.5),
            ['community.report'] = bucket(3, 0.1),
            ['community.listing'] = bucket(6, 0.5),
            ['community.contact'] = bucket(5, 0.5),
            ['community.moderation'] = bucket(12, 2),
        }, bucketShape(), {
            label = 'Rate limits', keyType = 'string', requiredKeys = { 'mutation' }, live = true,
            description = 'Limit per action, shared by every route using it. Burst size is how many calls are allowed per window, and the window is burst divided by refill per second (for example 12 and 2 means 12 calls per 6 seconds). Keys: bootstrap, read, mutation, sendMessage, callStart, videoSignal, bankTransfer, mediaUpload, jobMutation, pin, shareNumber, sdk and community.read, .profile, .post, .reaction, .follow, .comment, .block, .report, .listing, .contact, .moderation. An unlisted action falls back to mutation, which cannot be removed.',
        }),

        -- Rate limit for third-party app callbacks (app:<id>:<name>), passed to Kora.callback as rateLimit.
        SdkCallbackRateLimit = C.object({
            max = C.integer(30, { label = 'Calls per window', min = 1, max = 1000, description = 'App callback calls allowed per window and player. Read once when an app registers its callbacks.' }),
            window = C.integer(10000, { label = 'Window (ms)', min = 1000, max = 600000, description = 'Length of the rate limit window in milliseconds.' }),
        }, { advanced = true, description = 'Per-callback limit for sandboxed app callbacks.' }),

        Banking = C.object({
            Enabled = C.boolean(true, { label = 'Banking integration', live = true, description = 'Show balances and history through kora_core. Off disables the integration.' }),
            Account = C.string('bank', { label = 'Bank account', minLength = 1, maxLength = 32, live = true, description = 'kora_core money account the Banking app reads and moves money in.' }),
            MaximumTransfer = C.integer(1000000, { label = 'Largest transfer', min = 1, max = 2000000000, live = true, description = 'Largest amount a single phone transfer may move.' }),
            HistoryPageSize = C.integer(30, { label = 'History page size', min = 5, max = 100, live = true, description = 'Transactions returned per history page (never more than the global page size limit).' }),
        }),

        Jobs = C.object({
            Enabled = C.boolean(true, { label = 'Jobs integration', live = true, description = 'Job and business actions in the phone.' }),
            AllowDutyToggle = C.boolean(true, { label = 'Allow duty toggle', live = true, description = 'Let players go on and off duty from the phone.' }),
            Actions = C.map({}, C.map({}, C.object({
                enabled = C.boolean(false, { label = 'Enabled', description = 'Only enabled actions can run.' }),
                label = C.string('Action', { label = 'Button label', maxLength = 64 }),
                minimumGrade = C.integer(0, { label = 'Minimum grade', min = 0, max = 100 }),
                requireDuty = C.boolean(true, { label = 'Require on duty' }),
                serverEvent = C.string('', { label = 'Server event', maxLength = 128, description = 'Server event called with the verified context table.' }),
            }), { keyType = 'string' }), {
                label = 'Job actions', keyType = 'string', live = true,
                description = 'Allowlisted job actions: job name, then action id, then the action settings (see docs/banking-jobs.md). A handler function cannot be edited here; assign it in Lua after the config loads.',
            }),
        }),

        Pin = C.object({
            MaxAttempts = C.integer(5, { label = 'PIN attempts', min = 1, max = 20, live = true, description = 'Wrong PIN entries before the phone locks.' }),
            LockSeconds = C.integer(300, { label = 'PIN lockout (s)', min = 10, max = 86400, live = true, description = 'How long the phone stays locked after too many wrong PINs.' }),
        }),

        -- With several handsets in the inventory and none selected yet (after a relog or restart), resume the
        -- handset whose Face ID is enrolled for this character instead of the first one found.
        Handsets = C.object({
            ResumeEnrolledHandset = C.boolean(true, {
                label = 'Resume the Face ID handset', live = true,
                description = 'With several handsets in the inventory and none selected yet (after a relog or restart), resume the handset whose Face ID is enrolled for this character instead of the first one found. Off uses the first one found.',
            }),
        }),

        -- The Wallet ID card: licences read from character metadata, shown to the closest player.
        Wallet = C.object({
            ShowDistance = C.number(3.0, { label = 'Show-ID distance (m)', min = 0.5, max = 15.0, step = 0.5, live = true, description = 'How close another player must be to be shown the ID card.' }),
            Licences = C.list({
                { id = 'driver', label = 'Driver licence' },
                { id = 'weapon', label = 'Firearms licence' },
                { id = 'business', label = 'Business licence' },
            }, C.object({
                id = C.string('driver', { label = 'Metadata id', minLength = 1, maxLength = 32, pattern = '^[%w_]+$', description = 'Key read from the character licences metadata.' }),
                label = C.string('Licence', { label = 'Display name', minLength = 1, maxLength = 64 }),
            }), { label = 'Licences', live = true, description = 'Licences listed on the ID card, read from metadata.licences.' }),
        }),

        -- Notes, alarms and music stations each phone may keep.
        Items = C.object({
            alarm = C.integer(20, { label = 'Alarms per phone', min = 1, max = 200, live = true, description = 'How many alarms each phone may keep.' }),
            station = C.integer(30, { label = 'Stations per phone', min = 1, max = 200, live = true, description = 'How many music stations each phone may keep.' }),
        }),

        -- The Maps app lists these places; tapping one sets a waypoint. Add your own.
        Maps = C.object({
            Locations = C.list({
                location('Legion Square', 195.2, -933.8),
                location('Pillbox Medical Center', 298.5, -584.4),
                location('Mission Row Police Station', 425.1, -979.5),
                location('Los Santos Airport', -1037.0, -2737.0),
                location('Vespucci Beach', -1350.0, -1500.0),
                location('Sandy Shores', 1850.0, 3700.0),
                location('Paleto Bay', -150.0, 6300.0),
            }, C.object({
                label = C.string('Place', { label = 'Name', minLength = 1, maxLength = 64 }),
                x = C.number(0.0, { label = 'X', min = -10000.0, max = 10000.0, step = 0.1 }),
                y = C.number(0.0, { label = 'Y', min = -10000.0, max = 10000.0, step = 0.1 }),
            }), {
                label = 'Map places', live = true,
                description = 'Places the Maps app lists; tapping one sets a waypoint. An empty list turns the Maps feature flag off.',
            }),
        }),

        -- The Garage app lists the character's vehicles through exports.kora_garages:getOwnedVehicles.
        Garage = C.object({
            Enabled = C.boolean(true, { label = 'Garage app source', description = 'Off disables the Garage app. Availability is checked once and cached until the resource restarts.' }),
            UseGarageLabels = C.boolean(true, { label = 'Use garage names', description = 'Show the kora_garages garage name instead of its raw id (needs kora_garages running).' }),
        }, { advanced = true }),

        -- The Property app lists the character's homes from a housing script's tables. The app only appears if
        -- every table and column exists. Defaults are qb-houses' names; change them for another script.
        Property = C.object({
            Enabled = C.boolean(true, { label = 'Property app source', advanced = false, description = 'Off disables the Property app. Availability is checked once and cached until the resource restarts.' }),
            OwnedTable = C.string('player_houses', { label = 'Owned houses table', pattern = '^[%w_]+$', maxLength = 64, description = 'Table linking characters to their houses.' }),
            OwnerColumn = C.string('citizenid', { label = 'Owner column', pattern = '^[%w_]+$', maxLength = 64, description = 'Column in the owned houses table holding the character id.' }),
            HouseColumn = C.string('house', { label = 'House column', pattern = '^[%w_]+$', maxLength = 64, description = 'Column in the owned houses table holding the house name.' }),
            LocationsTable = C.string('houselocations', { label = 'House locations table', pattern = '^[%w_]+$', maxLength = 64, description = 'Table holding house names, labels and coordinates.' }),
            NameColumn = C.string('name', { label = 'House name column', pattern = '^[%w_]+$', maxLength = 64, description = 'Column in the locations table matching the house column.' }),
            LabelColumn = C.string('label', { label = 'House label column', pattern = '^[%w_]+$', maxLength = 64, description = 'Column in the locations table holding the display name.' }),
            CoordsColumn = C.string('coords', { label = 'House coords column', pattern = '^[%w_]+$', maxLength = 64, description = 'Column in the locations table holding the coordinates.' }),
        }, { advanced = true }),

        -- Photos and video clips. See docs/media-storage.md. The Fivemanage token goes in the
        -- kora_fivemanage_token convar, which wins over Fivemanage.Token.
        Media = C.object({
            Provider = C.enum('fivemanage', {
                label = 'Media provider',
                options = {
                    { value = 'disabled', label = 'Disabled' },
                    { value = 'local-development', label = 'Local development (photos only)' },
                    { value = 'external', label = 'External broker' },
                    { value = 'fivemanage', label = 'Fivemanage' },
                },
                description = 'Where photos and video clips are stored. See docs/media-storage.md.',
            }),
            TokenTtlSeconds = C.integer(120, { label = 'Upload ticket lifetime (s)', min = 10, max = 3600, live = true, advanced = true, description = 'How long an upload ticket stays valid.' }),
            MaxBytes = C.integer(8 * 1024 * 1024, { label = 'Largest photo (bytes)', min = 1024, max = 100 * 1024 * 1024, live = true, description = 'Photo size ceiling.' }),
            MaxWidth = C.integer(8192, { label = 'Widest photo (px)', min = 16, max = 16384, live = true, advanced = true, description = 'Largest accepted photo width.' }),
            MaxHeight = C.integer(8192, { label = 'Tallest photo (px)', min = 16, max = 16384, live = true, advanced = true, description = 'Largest accepted photo height.' }),
            AllowedMimeTypes = C.list({ 'image/jpeg', 'image/png', 'image/webp' }, C.string('image/jpeg', { maxLength = 64 }), {
                label = 'Photo types', live = true, description = 'Accepted photo MIME types.',
            }),
            AllowedVideoMimeTypes = C.list({ 'video/webm', 'video/mp4' }, C.string('video/webm', { maxLength = 64 }), {
                label = 'Video types', live = true, description = 'Accepted video MIME types.',
            }),
            MaxVideoBytes = C.integer(24 * 1024 * 1024, { label = 'Largest clip (bytes)', min = 1024, max = 500 * 1024 * 1024, live = true, description = 'A 15 second clip is about 3 MB; this is the ceiling.' }),
            MaxVideoSeconds = C.integer(15, { label = 'Longest clip (s)', min = 1, max = 120, live = true, description = 'Longest video clip a phone may record.' }),
            MaxImagesPerDevice = C.integer(300, { label = 'Photos per phone', min = 1, max = 10000, live = true, description = 'Gallery photos a phone may keep (delete some to take more).' }),
            MaxVideosPerDay = C.integer(20, { label = 'Clips per phone per day', min = 1, max = 1000, live = true, description = 'Clips a phone may upload per day.' }),
            AllowedPublicHosts = C.list({}, C.string('cdn.example.com', { maxLength = 255 }), {
                label = 'Allowed public hosts', description = 'Extra HTTPS hosts media URLs may point to.',
            }),
            AllowedProviderHosts = C.list({}, C.string('broker.example.com', { maxLength = 255 }), {
                label = 'Allowed provider hosts', advanced = true,
                description = 'Extra HTTPS hosts the external provider broker, verify and delete endpoints may use. Allowed together with Allowed public hosts.',
            }),
            AllowedUploadHosts = C.list({}, C.string('upload.example.com', { maxLength = 255 }), {
                label = 'Allowed upload hosts', advanced = true,
                description = 'Extra HTTPS hosts the external provider may hand out upload URLs on. Allowed together with Allowed public hosts.',
            }),
            LocalDirectory = C.string('local-media', { label = 'Local media folder', pattern = '^[%w_%-/]+$', maxLength = 128, advanced = true, description = 'Resource folder used by the local-development provider.' }),
            CleanupIntervalMinutes = C.integer(30, { label = 'Cleanup interval (min)', min = 1, max = 1440, live = true, advanced = true, description = 'How often deleted media is purged.' }),
            DeletedRetentionHours = C.integer(24, { label = 'Deleted media retention (h)', min = 0, max = 8760, live = true, advanced = true, description = 'How long deleted media is kept before purging.' }),
            CleanupBatchSize = C.integer(25, { label = 'Cleanup batch size', min = 1, max = 1000, live = true, advanced = true, description = 'Rows purged per cleanup pass.' }),
            External = C.object({
                BrokerUrl = C.string('', { label = 'Broker URL', maxLength = 2048, description = 'HTTPS endpoint issuing upload tickets (external provider).' }),
                VerifyUrl = C.string('', { label = 'Verify URL', maxLength = 2048, description = 'HTTPS endpoint confirming an upload (external provider).' }),
                DeleteUrl = C.string('', { label = 'Delete URL', maxLength = 2048, description = 'HTTPS endpoint deleting an upload (external provider).' }),
                Secret = C.string('', { label = 'Broker secret', maxLength = 512, sensitive = true, description = 'Shared secret for the broker. Never shown in /config; set it in config.local.lua.' }),
            }, { advanced = true }),
            -- Fivemanage's media API. The API token is only ever read on the server; the phone gets a
            -- short-lived presigned upload URL for one file. RequireTag makes the server insist the uploaded
            -- file carries this ticket's tag (only possible for uploads made from the phone UI, not
            -- screenshot-basic photos).
            Fivemanage = C.object({
                Token = C.string('', { label = 'Fivemanage token', maxLength = 512, sensitive = true, description = 'API token. Prefer the kora_fivemanage_token convar, which wins over this. Never shown in /config.' }),
                RequireTag = C.boolean(false, { label = 'Require upload tag', live = true, description = 'Insist the uploaded file carries the ticket tag. Only possible for uploads made from the phone UI.' }),
                ApiBase = C.string('https://api.fivemanage.com', { label = 'API base URL', maxLength = 255, pattern = '^https://', advanced = true, description = 'Fivemanage API endpoint.' }),
                UploadHosts = C.list({ 'api.fivemanage.com', 'fmapi.net' }, C.string('api.fivemanage.com', { maxLength = 255 }), {
                    label = 'Upload hosts', description = 'Hosts presigned upload URLs may use.',
                }),
                PublicHosts = C.list({ 'r2.fivemanage.com' }, C.string('r2.fivemanage.com', { maxLength = 255 }), {
                    label = 'Public hosts', description = 'Hosts uploaded media may be served from.',
                }),
            }, { advanced = true }),
        }),
    }, { scope = 'server' }),

    Calls = C.object({
        RingTimeoutMs = C.integer(30000, { label = 'Ring time (ms)', min = 10000, max = 120000, description = 'How long a call rings before it is missed. Read once when the resource starts.' }),
        VoiceChannelMinimum = C.integer(31000, { label = 'First call voice channel', min = 1, max = 1000000, advanced = true, description = 'Lowest voice channel number used for phone calls. Read once when the resource starts.' }),
        VoiceChannelMaximum = C.integer(60999, { label = 'Last call voice channel', min = 11, max = 1000000, advanced = true, description = 'Highest voice channel number used for phone calls. Read once when the resource starts.' }),
        -- WebRTC video during an active call. STUN alone gets most players connected peer-to-peer; add a TURN
        -- server here too for players behind strict/symmetric NATs who can't otherwise reach each other.
        Video = C.object({
            Enabled = C.boolean(true, { label = 'Video calls', live = true, description = 'Allow WebRTC video during an active call.' }),
            IceServers = C.list({ { urls = 'stun:stun.l.google.com:19302' } }, C.object({
                urls = C.string('stun:stun.l.google.com:19302', { label = 'Server URL', maxLength = 255, description = 'stun: or turn: URL.' }),
                username = C.optional(nil, C.string('', { maxLength = 255 }), { label = 'TURN username', description = 'Only for TURN servers.' }),
                credential = C.optional(nil, C.string('', { maxLength = 255 }), {
                    label = 'TURN credential', sensitive = true,
                    description = 'Only for TURN servers. It is handed to call participants (WebRTC needs it), so use a short-lived credential. Never shown in /config.',
                }),
            }), {
                label = 'ICE servers', live = true,
                description = 'STUN alone gets most players connected peer-to-peer; add a TURN server too for players behind strict or symmetric NATs who cannot otherwise reach each other. Handed to clients when a video call starts.',
            }),
        }, { advanced = true }),
    }, { scope = 'server' }),
}, { scope = 'server' })
