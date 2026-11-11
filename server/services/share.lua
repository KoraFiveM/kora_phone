KoraPhone.Services = KoraPhone.Services or {}
local Share = {}
KoraPhone.Services.Share = Share

-- Share your number with a nearby player (third-eye > "Share phone number").
-- The server owns every step: who is sharing, the number shared, who receives it and whether they are close
-- enough all come from the server's own state. Nothing is written to anyone's contacts until the receiver
-- accepts, a request is answered at most once, and it expires after Config.ShareNumber.ExpireSeconds.

Share.pending = {}   -- id -> request
Share.byTarget = {}  -- target source -> id (one open request per receiver)
Share.cooldown = {}  -- 'sharer:target' -> os.time() the pair may share again

local function cfg() return Config.ShareNumber or {} end
local function fail(code, message) return PhoneError(PhoneConstants.Errors[code] or PhoneConstants.Errors.FORBIDDEN, message) end
local function newId() return exports[GetCurrentResourceName()]:randomHex(16) end

local function cellularNumber(device)
    if not device or device.cellular == false then return nil end
    return PhoneValidation.phoneNumber(device.phoneNumber)
end

local function firstName(source)
    local player = KoraPhone.GetPlayer(source)
    local name = player and player.charinfo and player.charinfo.firstname
    name = type(name) == 'string' and PhoneValidation.string(name, 'name', 1, Config.Limits.ContactName) or nil
    return name or 'New contact'
end

-- A label is free text the player typed; it is validated exactly like a contact name.
local function label(value, fallback)
    if value == nil or value == '' then return fallback end
    local name = PhoneValidation.string(value, 'name', 1, Config.Limits.ContactName)
    return name or fallback
end

local function notify(target, title, body)
    TriggerClientEvent('kora_phone:client:notification', target, { app = 'contacts', title = title, body = body, message = body })
end

local function forget(id)
    local request = Share.pending[id]
    if not request then return nil end
    Share.pending[id] = nil
    if Share.byTarget[request.target] == id then Share.byTarget[request.target] = nil end
    return request
end

local function near(a, b, distance)
    return Kora.world.resolveNearbyPlayer(a, b, { maxDistance = distance }) ~= nil
end

-- Saves number under name on deviceId unless that phone already has it. Returns 'saved' or 'exists'.
local function saveContact(deviceId, name, number)
    if KoraPhone.Repositories.Contacts.findByNumber(deviceId, number) then return 'exists' end
    local id = KoraPhone.Repositories.Contacts.upsert(deviceId, { displayName = name, phoneNumber = number, isFavorite = false })
    return id and 'saved' or nil
end

function Share.offer(source, payload)
    local c = cfg()
    if c.Enabled ~= true then return fail('FORBIDDEN', 'Sharing numbers is turned off') end
    local target = tonumber(payload.target)
    if not target or target % 1 ~= 0 or target < 1 or target == source or not GetPlayerName(target) then
        return fail('INVALID_INPUT', 'No one to share with')
    end
    if not KoraPhone.GetCitizenId(target) then return fail('NOT_FOUND', 'They cannot take your number right now') end
    if not near(source, target, c.Distance or 3.0) then return fail('NOT_FOUND', 'Get closer to share your number') end

    local device, err = KoraPhone.Permissions.requireDevice(source, c.AllowWhileLocked == true)
    if not device then return err end
    local number = cellularNumber(device)
    if not number then return fail('FORBIDDEN', 'Your phone has no active SIM') end

    local pair = source .. ':' .. target
    local now = os.time()
    if (Share.cooldown[pair] or 0) > now then return fail('RATE_LIMITED', 'Wait a moment before sharing with them again') end
    if Share.byTarget[target] then return fail('CONFLICT', 'They already have a request open') end
    if not KoraPhone.HasPhone(target) then return fail('NOT_FOUND', 'They cannot take your number right now') end
    local cooldown = math.max(0, tonumber(c.CooldownSeconds) or 20)
    Share.cooldown[pair] = now + cooldown
    SetTimeout((cooldown + 1) * 1000, function()
        if (Share.cooldown[pair] or 0) <= os.time() then Share.cooldown[pair] = nil end
    end)

    local expires = math.max(5, math.min(120, tonumber(c.ExpireSeconds) or 30))
    local id = newId()
    local request = {
        id = id, sharer = source, sharerCitizenId = KoraPhone.GetCitizenId(source), sharerDeviceId = device.id,
        target = target, targetCitizenId = KoraPhone.GetCitizenId(target),
        label = label(payload.label, firstName(source)), number = number, expiresAt = now + expires,
    }

    -- Someone who blocked this number (or is blocked by it) never sees the request; to the sharer it simply
    -- goes unanswered, so a block is not revealed.
    local ok, targetDevice = pcall(KoraPhone.Handsets.current, target, false)
    local blocked = ok and targetDevice and KoraPhone.Repositories.Blocks.isEitherBlocked(targetDevice.id, device.id)

    Share.pending[id] = request
    Share.byTarget[target] = id
    if not blocked then
        TriggerClientEvent('kora_phone:client:share:request', target, {
            id = id, label = request.label, number = number, expiresIn = expires, shareBack = c.AllowShareBack == true,
        })
    end
    SetTimeout((expires + 1) * 1000, function()
        if forget(id) and GetPlayerName(source) then notify(source, 'Number not saved', 'They did not answer in time.') end
    end)
    return PhoneResult({ pending = true, expiresIn = expires })
end

function Share.answer(source, payload)
    local c = cfg()
    local id = type(payload.id) == 'string' and payload.id or nil
    local request = id and Share.pending[id]
    if not request or request.target ~= source then return fail('NOT_FOUND', 'That request expired') end
    forget(id) -- one answer only, accepted or not

    local sharer = request.sharer
    local stillValid = request.expiresAt >= os.time() and c.Enabled == true
        and KoraPhone.GetCitizenId(source) == request.targetCitizenId
        and KoraPhone.GetCitizenId(sharer) == request.sharerCitizenId
    if not stillValid then return fail('NOT_FOUND', 'That request expired') end

    if payload.accept ~= true then
        notify(sharer, 'Number not saved', 'They declined your number.')
        return PhoneResult({ declined = true })
    end
    if not near(source, sharer, c.AnswerDistance or 10.0) then return fail('NOT_FOUND', 'They walked away') end

    local device, err = KoraPhone.Permissions.requireDevice(source, c.AllowWhileLocked == true)
    if not device then return err end
    -- The number must still be live on the sharer's handset (no SIM swap since the offer).
    local sharerDevice = KoraPhone.Repositories.Phones.findByNumber(request.number)
    if not sharerDevice or sharerDevice.id ~= request.sharerDeviceId then return fail('NOT_FOUND', 'That number is no longer active') end
    if sharerDevice.id == device.id then return fail('INVALID_INPUT', 'That is your own number') end

    local name = label(payload.name, request.label)
    local saved = saveContact(device.id, name, request.number)
    if not saved then return fail('INTERNAL', 'Could not save the contact') end

    local sharedBack = false
    local mine = cellularNumber(device)
    if payload.shareBack == true and c.AllowShareBack == true and mine then
        sharedBack = saveContact(sharerDevice.id, label(payload.myLabel, firstName(source)), mine) ~= nil
    end
    notify(sharer, 'Number shared', sharedBack and 'They saved your number and shared theirs back.' or 'They saved your number.')
    return PhoneResult({ saved = saved == 'saved', existing = saved == 'exists', name = name, sharedBack = sharedBack })
end

AddEventHandler('playerDropped', function()
    local src = source
    for id, request in pairs(Share.pending) do
        if request.sharer == src or request.target == src then forget(id) end
    end
    local prefix, suffix = src .. ':', ':' .. src
    for pair in pairs(Share.cooldown) do
        if pair:sub(1, #prefix) == prefix or pair:sub(-#suffix) == suffix then Share.cooldown[pair] = nil end
    end
end)
