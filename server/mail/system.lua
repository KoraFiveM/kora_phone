-- System mail: trusted server resources deliver mail and activity notes to a character.
-- Mail belongs to the character, not to a handset. Players cannot create it.
KoraPhone.SystemMail = KoraPhone.SystemMail or {}
local SystemMail = KoraPhone.SystemMail
local Repo = KoraPhone.Repositories.SystemMail

local LIMITS = { sender = 100, subject = 120, message = 16000, event = 200, data = 16000, citizenId = 64,
    title = 100, note = 1000 }

-- A button may only trigger a client event of another resource, never one of the core stack.
local EVENT_PATTERN = '^[%w_%-]+:client:[%w_:%-]+$'
local RESERVED_PREFIXES = { 'kora_phone:', 'kora_core:', 'kora_lib:', 'kora_sql:', 'kora_inventory:', 'kora_voice:' }

---@param value any
---@param maximum integer
---@return string|nil
local function text(value, maximum)
    return type(value) == 'string' and #value > 0 and #value <= maximum and value or nil
end

---@param event any
---@return boolean
function SystemMail.isAllowedEvent(event)
    if not text(event, LIMITS.event) or not event:match(EVENT_PATTERN) then return false end
    for _, prefix in ipairs(RESERVED_PREFIXES) do
        if event:sub(1, #prefix) == prefix then return false end
    end
    return true
end

---@param value string
---@return string
local function stripHtml(value)
    return (value:gsub('<[bB][rR]%s*/?>', '\n'):gsub('</[pP]>', '\n'):gsub('<[^>]*>', ''))
end

---Validates and sanitises a mail table.
---@param data any
---@return table|nil mail
---@return string|nil err
function SystemMail.sanitize(data)
    if type(data) ~= 'table' then return nil, 'mail must be a table' end
    local sender = text(data.sender, LIMITS.sender)
    local subject = text(data.subject, LIMITS.subject)
    local message = text(data.message, LIMITS.message)
    if not sender or not subject or not message then return nil, 'invalid sender, subject or message' end
    local button
    local raw = data.button
    if type(raw) == 'table' and raw.enabled ~= false and raw.event ~= nil then
        if not SystemMail.isAllowedEvent(raw.event) then return nil, 'button event not allowed' end
        local ok, encoded = pcall(json.encode, raw.data)
        if not ok or (encoded and #encoded > LIMITS.data) then return nil, 'button data too large' end
        button = { event = raw.event, data = raw.data }
    end
    return { sender = sender, subject = subject, message = stripHtml(message), button = button }
end

---@param citizenId string
---@param mail table
---@return integer|nil id
---@return string|nil err
function SystemMail.send(citizenId, mail)
    if not text(citizenId, LIMITS.citizenId) then return nil, 'invalid citizen id' end
    local clean, err = SystemMail.sanitize(mail)
    if not clean then return nil, err end
    local id = Repo.insert(citizenId, clean)
    if not id or id <= 0 then return nil, 'mail not stored' end
    local player = exports.kora_core:getPlayerByCitizenId(citizenId)
    if player and player.source then
        local device = KoraPhone.Handsets.current(player.source, false)
        TriggerClientEvent('kora_phone:client:mail:new', player.source, {
            id = id, citizenId = citizenId, deviceId = device and tostring(device.id),
            sender = clean.sender, subject = clean.subject,
        })
    end
    return id
end

---Informational note shown in Mail > Activity. Never changes a balance.
---@param citizenId string
---@param title string
---@param message string
---@return integer|nil id
---@return string|nil err
function SystemMail.addActivity(citizenId, title, message)
    if not text(citizenId, LIMITS.citizenId) or not text(title, LIMITS.title) or not text(message, LIMITS.note) then
        return nil, 'invalid activity'
    end
    local id = Repo.addActivity(citizenId, title, message)
    if not id or id <= 0 then return nil, 'activity not stored' end
    -- Let an online player's open Mail > Activity list refresh itself.
    local player = exports.kora_core:getPlayerByCitizenId(citizenId)
    if player and player.source then
        TriggerClientEvent('kora_phone:client:activity:new', player.source, { citizenId = citizenId })
    end
    return id
end

exports('SendSystemMail', function(citizenId, mail)
    local id = SystemMail.send(citizenId, mail)
    return id ~= nil, id
end)

exports('AddSystemActivity', function(citizenId, title, message)
    return SystemMail.addActivity(citizenId, title, message) ~= nil
end)

---@param src integer
---@param payload any
---@return string|nil citizenId
---@return integer|nil id
---@return table|nil err
local function access(src, payload)
    local device, err = KoraPhone.Permissions.requireDevice(src)
    if not device then return nil, nil, err end
    local citizenId = KoraPhone.GetCitizenId(src)
    if not citizenId or device.holderCitizenId ~= citizenId then
        return nil, nil, PhoneError(PhoneConstants.Errors.FORBIDDEN, 'Handset session changed')
    end
    return citizenId, PhoneValidation.integer(type(payload) == 'table' and payload.id, 'id', 1)
end

local function list(src, payload, activity)
    local citizenId, _, err = access(src, payload)
    if not citizenId then return err end
    local page, validationError = PhoneValidation.page(payload)
    if not page then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local rows = (activity and Repo.activity or Repo.list)(citizenId, page.limit, page.cursor)
    return PhoneResult({ items = rows, nextCursor = #rows == page.limit and rows[#rows].id or nil })
end

local function mutate(src, payload, operation, onDone)
    local citizenId, id, err = access(src, payload)
    if not citizenId then return err end
    if not id then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'Invalid mail') end
    local result = operation(citizenId, id)
    if result == nil or result == false then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Mail action is no longer available')
    end
    if onDone then onDone(result) end
    return PhoneResult(result)
end

---Consumes the Accept button once, then the server fires the nominated client event itself.
local function accept(src, payload)
    local fired
    local result = mutate(src, payload, Repo.takeButton, function(button)
        if not SystemMail.isAllowedEvent(button.event) then return end
        TriggerClientEvent(button.event, src, button.data)
        fired = true
    end)
    if result.ok then return PhoneResult({ accepted = true, dispatched = fired == true }) end
    return result
end

SystemMail.routes = {
    ['mail:system:list'] = function(src, payload) return list(src, payload, false) end,
    ['mail:system:activity'] = function(src, payload) return list(src, payload, true) end,
    ['mail:system:read'] = function(src, payload) return mutate(src, payload, Repo.markRead) end,
    ['mail:system:delete'] = function(src, payload) return mutate(src, payload, Repo.delete) end,
    ['mail:system:accept'] = accept,
}
