SteviePhone.Services = SteviePhone.Services or {}
local Phone = {}
SteviePhone.Services.Phone = Phone

local function generateNumber()
    local max = (10 ^ Config.PhoneNumber.SubscriberDigits) - 1
    for _ = 1, 30 do
        local candidate = Config.PhoneNumber.Prefix .. string.format('%0' .. Config.PhoneNumber.SubscriberDigits .. 'd', math.random(0, max))
        if not SteviePhone.Repositories.Phones.numberExists(candidate) then return candidate end
    end
end

function Phone.getOrCreate(citizenId)
    local device = SteviePhone.Repositories.Phones.findByCitizenId(citizenId)
    if device or not Config.Server.AutoProvisionDevice then return device end
    local number = generateNumber()
    if not number then return nil end
    local ok, result = pcall(SteviePhone.Repositories.Phones.create, citizenId, number)
    if ok then return result end
    -- A unique-number race is unlikely; reload in case another request provisioned it.
    return SteviePhone.Repositories.Phones.findByCitizenId(citizenId)
end

local function hasPin(device) return device.hasPin == 1 or device.hasPin == true end

local function pepper() return GetConvar('stevie_phone_pin_pepper', '') end

local function newSalt()
    local parts = {}
    for i = 1, 4 do parts[i] = string.format('%08x', math.random(0, 0x7fffffff)) end
    return table.concat(parts)
end

-- Verifies a PIN with attempt limiting. Returns true, or nil plus a client-safe error.
local function checkPin(device, pin)
    local state = SteviePhone.Repositories.Phones.pinState(device.id)
    if not state or not (state.hasPin == 1 or state.hasPin == true) then
        return nil, PhoneError(PhoneConstants.Errors.CONFLICT, 'No PIN is set')
    end
    local now = os.time()
    local lockedUntil = tonumber(state.lockedUntil) or 0
    if lockedUntil > now then
        return nil, PhoneError(PhoneConstants.Errors.RATE_LIMITED, ('Too many attempts. Try again in %d seconds.'):format(lockedUntil - now))
    end
    if SteviePhone.Repositories.Phones.pinMatches(device.id, pepper(), pin) then
        SteviePhone.Repositories.Phones.clearPinFailures(device.id)
        return true
    end
    local cfg = Config.Server.Pin
    SteviePhone.Repositories.Phones.recordPinFailure(device.id, cfg.MaxAttempts, cfg.LockSeconds, now)
    return nil, PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Incorrect PIN')
end

function Phone.bootstrap(source)
    local citizenId, err = SteviePhone.Permissions.requirePlayer(source)
    if not citizenId then return err end
    local device = Phone.getOrCreate(citizenId)
    if not device then return PhoneError(PhoneConstants.Errors.INTERNAL, 'No active phone is available') end
    local session = SteviePhone.Sessions.ensure(source, device)
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
    local pd = SteviePhone.GetPlayer(source).PlayerData
    return PhoneResult({
        device = deviceInfo,
        security = { hasPin = hasPin(device), locked = false },
        locale = Config.Locale,
        moderator = SteviePhone.Services.Moderation.isModerator(source),
        -- Same permission as moderator: lets the feed's own delete buttons remove someone
        -- else's post/comment directly, instead of only through a filed report.
        admin = SteviePhone.Services.Moderation.isModerator(source),
        character = {
            firstName = pd.charinfo and pd.charinfo.firstname or '',
            lastName = pd.charinfo and pd.charinfo.lastname or '',
            job = pd.job and { name = pd.job.name, label = pd.job.label, grade = pd.job.grade and pd.job.grade.level or 0, onDuty = pd.job.onduty == true } or nil
        },
        features = { maps = #Config.Server.Maps.Locations > 0, garage = SteviePhone.Services.Garage.available(), property = SteviePhone.Services.Property.available(), media = SteviePhone.Storage.provider() ~= 'disabled', transfers = SteviePhone.Integrations.Banking.canTransfer(),
            flash = SteviePhone.Storage.supportsVideo() and { maxSeconds = SteviePhone.Storage.Config().MaxVideoSeconds, maxBytes = SteviePhone.Storage.Config().MaxVideoBytes } or false,
            video = Config.Calls.Video and Config.Calls.Video.Enabled and { iceServers = Config.Calls.Video.IceServers or {} } or false },
        locations = Config.Server.Maps.Locations,
        items = SteviePhone.Services.Items.forDevice(device.id),
        contacts = SteviePhone.Repositories.Contacts.list(device.id),
        conversations = SteviePhone.Repositories.Messages.listConversations(device.id, Config.Limits.PageSizeDefault)
    })
end

function Phone.unlock(source, payload)
    local citizenId, err = SteviePhone.Permissions.requirePlayer(source)
    if not citizenId then return err end
    local device = Phone.getOrCreate(citizenId)
    if not device then return PhoneError(PhoneConstants.Errors.INTERNAL, 'No active phone is available') end
    local session = SteviePhone.Sessions.ensure(source, device)
    if not hasPin(device) then session.unlocked = true; return PhoneResult({ unlocked = true }) end
    local pin, pinError = PhoneValidation.pin(type(payload) == 'table' and payload.pin)
    if not pin then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, pinError) end
    local ok, checkError = checkPin(device, pin)
    if not ok then return checkError end
    session.unlocked = true
    return PhoneResult({ unlocked = true })
end

function Phone.lock(source)
    local session = SteviePhone.Sessions.bySource[source]
    if session then session.unlocked = false end
    return PhoneResult({ locked = true })
end

function Phone.setPin(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
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
    if not SteviePhone.Repositories.Phones.setPin(device.id, newSalt(), pepper(), pin) then
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to save PIN')
    end
    local session = SteviePhone.Sessions.bySource[source]
    if session then session.unlocked = true end
    return PhoneResult({ hasPin = true })
end

-- Removing a PIN needs the current PIN, with the same attempt limiting as unlocking.
function Phone.removePin(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    if not hasPin(device) then return PhoneResult({ hasPin = false }) end
    local current, currentError = PhoneValidation.pin(type(payload) == 'table' and payload.currentPin, 'currentPin')
    if not current then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, currentError) end
    local ok, checkError = checkPin(device, current)
    if not ok then return checkError end
    if not SteviePhone.Repositories.Phones.clearPin(device.id) then
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to remove PIN')
    end
    return PhoneResult({ hasPin = false })
end

function Phone.saveSettings(source, payload)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    local settings, validationError = PhoneValidation.settings(payload)
    if not settings then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    if not SteviePhone.Repositories.Phones.updateSettings(device.id, json.encode(settings)) then
        return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to save settings')
    end
    return PhoneResult(settings)
end
