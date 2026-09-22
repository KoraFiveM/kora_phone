Config.Server = {
    -- Create and upgrade the database tables when the resource starts (each .sql file in fxmanifest.lua runs once).
    -- Set to false to import the files in migrations/ yourself.
    AutoMigrate = true,
    AutoProvisionDevice = true,
    DatabaseReadyTimeoutMs = 15000,
    MessageBatchLimit = 100,
    RateLimits = {
        bootstrap = { capacity = 4, refillPerSecond = 0.5 },
        read = { capacity = 25, refillPerSecond = 8 },
        mutation = { capacity = 12, refillPerSecond = 2 },
        sendMessage = { capacity = 8, refillPerSecond = 1 },
        callStart = { capacity = 4, refillPerSecond = 0.25 },
        -- ICE gathering fires several candidates in a burst when a video call starts.
        videoSignal = { capacity = 30, refillPerSecond = 10 },
        bankTransfer = { capacity = 3, refillPerSecond = 0.05 },
        mediaUpload = { capacity = 4, refillPerSecond = 0.1 },
        jobMutation = { capacity = 8, refillPerSecond = 0.5 },
        pin = { capacity = 6, refillPerSecond = 0.1 },
        ['community.read'] = { capacity = 25, refillPerSecond = 8 },
        ['community.profile'] = { capacity = 4, refillPerSecond = 0.25 },
        ['community.post'] = { capacity = 8, refillPerSecond = 0.5 },
        ['community.reaction'] = { capacity = 20, refillPerSecond = 4 },
        ['community.follow'] = { capacity = 10, refillPerSecond = 1 },
        ['community.comment'] = { capacity = 8, refillPerSecond = 0.5 },
        ['community.block'] = { capacity = 6, refillPerSecond = 0.5 },
        ['community.report'] = { capacity = 3, refillPerSecond = 0.1 },
        ['community.listing'] = { capacity = 6, refillPerSecond = 0.5 },
        ['community.contact'] = { capacity = 5, refillPerSecond = 0.5 },
        ['community.moderation'] = { capacity = 12, refillPerSecond = 2 }
    },
    Banking = { Enabled = true, Account = 'bank', MaximumTransfer = 1000000, AllowCompensatingTransfers = false },
    Jobs = { Enabled = true, AllowDutyToggle = true, Actions = {} },
    Pin = { MaxAttempts = 5, LockSeconds = 300 },
    -- The Wallet ID card: licences read from QBCore character metadata, shown to the closest player.
    Wallet = {
        ShowDistance = 3.0,
        Licences = {
            { id = 'driver', label = 'Driver licence' },
            { id = 'weapon', label = 'Firearms licence' },
            { id = 'business', label = 'Business licence' }
        }
    },
    -- Notes, alarms and music stations each phone may keep.
    Items = { note = 100, alarm = 20, station = 30 },
    -- The Maps app lists these places; tapping one sets a waypoint. Add your own.
    Maps = {
        Locations = {
            { label = 'Legion Square', x = 195.2, y = -933.8 },
            { label = 'Pillbox Medical Center', x = 298.5, y = -584.4 },
            { label = 'Mission Row Police Station', x = 425.1, y = -979.5 },
            { label = 'Los Santos Airport', x = -1037.0, y = -2737.0 },
            { label = 'Vespucci Beach', x = -1350.0, y = -1500.0 },
            { label = 'Sandy Shores', x = 1850.0, y = 3700.0 },
            { label = 'Paleto Bay', x = -150.0, y = 6300.0 }
        }
    },
    -- The Garage app lists the character's vehicles from QBCore's owned-vehicles table.
    Garage = { Enabled = true, Table = 'player_vehicles' },
    -- The Property app lists the character's homes from a housing script's tables. These are qb-houses' names;
    -- change them for another script. The app only appears if every table and column exists.
    Property = {
        Enabled = true,
        OwnedTable = 'player_houses', OwnerColumn = 'citizenid', HouseColumn = 'house',
        LocationsTable = 'houselocations', NameColumn = 'name', LabelColumn = 'label', CoordsColumn = 'coords'
    },
    -- Photos and video clips. Provider: disabled | local-development (photos only) | external (your own
    -- broker) | fivemanage (see docs/media-storage.md; the token goes in the qbphone_fivemanage_token convar).
    Media = {
        Provider = 'disabled',
        MaxVideoBytes = 24 * 1024 * 1024, -- a 15 second clip is about 3 MB; this is the ceiling
        MaxVideoSeconds = 15,
        MaxImagesPerDevice = 300,         -- gallery photos a phone may keep (delete some to take more)
        MaxVideosPerDay = 20,             -- clips a phone may upload per day
        Fivemanage = { RequireTag = false }
    }
}

Config.Calls = {
    RingTimeoutMs = 30000,
    VoiceChannelMinimum = 31000,
    VoiceChannelMaximum = 60999,
    -- WebRTC video during an active call. STUN alone gets most players connected
    -- peer-to-peer; add a TURN server here too for players behind strict/symmetric
    -- NATs who can't otherwise reach each other.
    Video = {
        Enabled = true,
        IceServers = { { urls = 'stun:stun.l.google.com:19302' } }
    }
}
