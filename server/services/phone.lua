KoraPhone.Services = KoraPhone.Services or {}
local Phone = {}
KoraPhone.Services.Phone = Phone

local function generateNumber()
    local max = (10 ^ Config.PhoneNumber.SubscriberDigits) - 1
    for _ = 1, 30 do
        local candidate = Config.PhoneNumber.Prefix .. string.format('%0' .. Config.PhoneNumber.SubscriberDigits .. 'd', math.random(0, max))
        if not KoraPhone.Repositories.Phones.numberExists(candidate) then return candidate end
    end
end

function Phone.getOrCreate(citizenId)
    local device = KoraPhone.Repositories.Phones.findByCitizenId(citizenId)
    if device or not Config.Server.AutoProvisionDevice then return device end
    local number = generateNumber()
    if not number then return nil end
    local ok, result = pcall(KoraPhone.Repositories.Phones.create, citizenId, number)
    if ok then return result end
    -- A unique-number race is unlikely; reload in case another request provisioned it.
    return KoraPhone.Repositories.Phones.findByCitizenId(citizenId)
end

local function hasPin(device) return device.hasPin == 1 or device.hasPin == true end

local function pepper() return GetConvar('kora_phone_pin_pepper', '') end

local function crypto() return exports[GetCurrentResourceName()] end

-- Handsets store a KDF hash; PINs set before that kept the salted SHA-256 compared in SQL.
local function pinMatches(deviceId, pin)
    local kdf = KoraPhone.Repositories.Phones.pinKdf(deviceId)
    if kdf then return crypto():pinVerify(pin, kdf) end
    return KoraPhone.Repositories.Phones.legacyPinMatches(deviceId, pepper(), pin)
end

-- Verifies a PIN with attempt limiting. Returns true, or nil plus a client-safe error.
local function checkPin(device, pin)
    local state = KoraPhone.Repositories.Phones.pinState(device.id)
    if not state or not (state.hasPin == 1 or state.hasPin == true) then
        return nil, PhoneError(PhoneConstants.Errors.CONFLICT, 'No PIN is set')
    end
    local now = os.time()
    local lockedUntil = tonumber(state.lockedUntil) or 0
    if lockedUntil > now then
        return nil, PhoneError(PhoneConstants.Errors.RATE_LIMITED, ('Too many attempts. Try again in %d seconds.'):format(lockedUntil - now))
    end
    if pinMatches(device.id, pin) then
        KoraPhone.Repositories.Phones.clearPinFailures(device.id)
        return true
    end
    local cfg = Config.Server.Pin
    KoraPhone.Repositories.Phones.recordPinFailure(device.id, cfg.MaxAttempts, cfg.LockSeconds, now)
    return nil, PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Incorrect PIN')
end

local function characterInfo(player)
    local info = player.charinfo
    local job = player.job
    return {
        firstName = info and info.firstname or '',
        lastName = info and info.lastname or '',
        job = job and {
            name = job.name,
            label = job.label,
            grade = job.grade and job.grade.level or 0,
            onDuty = job.onduty == true,
        } or nil,
    }
end

---Which optional apps and capabilities this server offers, so the UI only shows what works.
local function featureFlags()
    local video = Config.Calls.Video
    return {
        homeReorder = PhoneValidation.homeReorderAllowed(),
        galleryViewer = not Config.Gallery or Config.Gallery.fullscreenViewer ~= false,
        maps = #Config.Server.Maps.Locations > 0,
        garage = KoraPhone.Services.Garage.available(),
        property = KoraPhone.Services.Property.available(),
        media = KoraPhone.Storage.provider() ~= 'disabled',
        transfers = KoraPhone.Integrations.Banking.canTransfer(),
        flash = KoraPhone.Storage.supportsVideo() and {
            maxSeconds = KoraPhone.Storage.Config().MaxVideoSeconds,
            maxBytes = KoraPhone.Storage.Config().MaxVideoBytes,
        } or false,
        video = video and video.Enabled and { iceServers = video.IceServers or {} } or false,
    }
end

function Phone.bootstrap(source)
    local citizenId, err = KoraPhone.Permissions.requirePlayer(source)
    if not citizenId then return err end
    local device = Phone.getOrCreate(citizenId)
    if not device then return PhoneError(PhoneConstants.Errors.INTERNAL, 'No active phone is available') end
    local session = KoraPhone.Sessions.ensure(source, device)
    local locked = hasPin(device) and not session.unlocked
    local settings = {}
    if device.settingsJson and device.settingsJson ~= '' then
        local ok, decoded = pcall(json.decode, device.settingsJson)
        if ok and type(decoded) == 'table' then settings = decoded end
    end
    local deviceInfo = { id = device.id, phoneNumber = device.phoneNumber, label = device.label, settings = settings }
    -- A locked phone only reveals what the lock screen needs.
    if locked then
        return PhoneResult({ device = deviceInfo, security = { hasPin = true, locked = true } })
    end
    local player = KoraPhone.GetPlayer(source)
    local isModerator = KoraPhone.Services.Moderation.isModerator(source)
    return PhoneResult({
        device = deviceInfo,
        security = { hasPin = hasPin(device), locked = false },
        moderator = isModerator,
        -- Same permission as moderator: lets the feed's own delete buttons remove someone
        -- else's post/comment directly, instead of only through a filed report.
        admin = isModerator,
        character = characterInfo(player),
        apps = Config.Apps or {},
        appStore = Config.AppStore ~= false,
        features = featureFlags(),
        locations = Config.Server.Maps.Locations,
        items = KoraPhone.Services.Items.forDevice(device.id),
        contacts = KoraPhone.Repositories.Contacts.list(device.id),
        -- Conversations are loaded through the handset mailbox service, never legacy memberships.
    })
end

function Phone.unlock(source, payload)
    local citizenId, err = KoraPhone.Permissions.requirePlayer(source)
    if not citizenId then return err end
    local device = Phone.getOrCreate(citizenId)
    if not device then return PhoneError(PhoneConstants.Errors.INTERNAL, 'No active phone is available') end
    local session = KoraPhone.Sessions.ensure(source, device)
    if not hasPin(device) then session.unlocked = true; return PhoneResult({ unlocked = true }) end
    local pin, pinError = PhoneValidation.pin(type(payload) == 'table' and payload.pin)
    if not pin then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, pinError) end
    local ok, checkError = checkPin(device, pin)
    if not ok then return checkError end
    session.unlocked = true
    return PhoneResult({ unlocked = true })
end

function Phone.lock(source)
    local session = KoraPhone.Sessions.bySource[source]
    if session then session.unlocked = false end
    return PhoneResult({ locked = true })
end

function Phone.setPin(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    payload = type(payload) == 'table' and payload or {}
    local pin, pinError = PhoneValidation.pin(payload.pin)
    if not pin then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, pinError) end
    if hasPin(device) then
        local current, currentError = PhoneValidation.pin(payload.currentPin, 'currentPin')
        if not current then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, currentError) end
        local ok, checkError = checkPin(device, current)
        if not ok then return checkError end
    end
    if not KoraPhone.Repositories.Phones.setPinKdf(device.id, crypto():pinHash(pin)) then
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to save PIN')
    end
    local session = KoraPhone.Sessions.bySource[source]
    if session then session.unlocked = true end
    return PhoneResult({ hasPin = true })
end

-- Removing a PIN needs the current PIN, with the same attempt limiting as unlocking.
function Phone.removePin(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    if not hasPin(device) then return PhoneResult({ hasPin = false }) end
    local current, currentError = PhoneValidation.pin(type(payload) == 'table' and payload.currentPin, 'currentPin')
    if not current then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, currentError) end
    local ok, checkError = checkPin(device, current)
    if not ok then return checkError end
    if not KoraPhone.Repositories.Phones.clearPin(device.id) then
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to remove PIN')
    end
    return PhoneResult({ hasPin = false })
end

function Phone.saveSettings(source, payload)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    if type(payload)=='table' and payload.expectedDeviceId~=nil and tostring(payload.expectedDeviceId)~=tostring(device.id) then
        return PhoneError(PhoneConstants.Errors.CONFLICT,'Handset changed before these settings were saved')
    end
    local settings, validationError = PhoneValidation.settings(payload)
    if not settings then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    if not PhoneValidation.homeReorderAllowed() and device.settingsJson and device.settingsJson ~= '' then
        -- Arranging is switched off: keep whatever order the player saved earlier instead of wiping it.
        local ok, previous = pcall(json.decode, device.settingsJson)
        if ok and type(previous) == 'table' then settings.appOrder, settings.dockOrder = previous.appOrder, previous.dockOrder end
    end
    -- Third-party app install state is server-owned: never let a settings save drop or rewrite it.
    settings.sdkApps = nil
    KoraPhone.SDK.Install.preserve(device.settingsJson, settings)
    if not KoraPhone.Repositories.Phones.updateSettings(device.id, json.encode(settings)) then
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to save settings')
    end
    return PhoneResult(settings)
end