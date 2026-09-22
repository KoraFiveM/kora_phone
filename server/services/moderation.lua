QBPhone.Services = QBPhone.Services or {}
local Moderation = {}
QBPhone.Services.Moderation = Moderation

local targetTypes = { 'profile', 'post', 'comment', 'listing' }
local reasons = { 'spam', 'harassment', 'scam', 'illegal', 'other' }

local function invalid(message) return PhoneError(PhoneConstants.Errors.INVALID_INPUT, message) end

local function moderator(source)
    local citizenId = QBPhone.GetCitizenId(source)
    if not citizenId then return nil end
    if IsPlayerAceAllowed(source, 'qbphone.moderate') then return citizenId end
    local hasPermission = QBPhone.QB and QBPhone.QB.Functions and QBPhone.QB.Functions.HasPermission
    if hasPermission and (hasPermission(source, 'admin') or hasPermission(source, 'god')) then return citizenId end
end

local function snapshot(targetType, targetId)
    if targetType == 'profile' then
        local row = QBPhone.Repositories.Social.profileById(targetId)
        if row then return { id = row.id, handle = row.handle, displayName = row.displayName, bio = row.bio } end
    elseif targetType == 'post' then
        local row = QBPhone.Repositories.Social.postInternal(targetId)
        if row then return { id = row.id, body = row.body } end
    elseif targetType == 'comment' then
        local row = QBPhone.Repositories.Social.commentInternal(targetId)
        if row then return { id = row.id, postId = row.postId, body = row.body } end
    elseif targetType == 'listing' then
        local row = QBPhone.Repositories.Marketplace.get(targetId)
        if row then return { id = row.id, title = row.title, description = row.description, category = row.category, price = row.price } end
    end
end

function Moderation.isModerator(source)
    return moderator(source) ~= nil
end

function Moderation.report(source, payload)
    local device, err = QBPhone.Permissions.requireDevice(source)
    if not device then return err end
    payload = type(payload) == 'table' and payload or {}
    local targetType, validationError = PhoneValidation.enum(payload.targetType, 'targetType', targetTypes)
    if not targetType then return invalid(validationError) end
    local targetId; targetId, validationError = PhoneValidation.integer(payload.targetId, 'targetId', 1)
    if not targetId then return invalid(validationError) end
    local reason; reason, validationError = PhoneValidation.enum(payload.reason, 'reason', reasons)
    if not reason then return invalid(validationError) end
    local details; details, validationError = PhoneValidation.string(payload.details or '', 'details', 0, 1000, true)
    if not details then return invalid(validationError) end
    local captured = snapshot(targetType, targetId)
    if not captured then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Reported content was not found') end
    local id, duplicate = QBPhone.Repositories.Reports.create(device.id, {
        targetType = targetType, targetId = targetId, reason = reason, details = details, snapshot = captured,
    })
    if not id then return PhoneError(PhoneConstants.Errors.INTERNAL, 'Unable to create report') end
    return PhoneResult({ id = id, duplicate = duplicate })
end

function Moderation.getQueue(source, payload)
    local device, deviceError = QBPhone.Permissions.requireDevice(source)
    if not device then return deviceError end
    if not moderator(source) then return PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'Moderator permission required') end
    payload = type(payload) == 'table' and payload or {}
    local status, validationError = PhoneValidation.enum(payload.status or 'open', 'status', { 'open', 'reviewing', 'resolved', 'dismissed' })
    if not status then return invalid(validationError) end
    local pagination; pagination, validationError = PhoneValidation.page(payload)
    if not pagination then return invalid(validationError) end
    pagination.limit = math.min(pagination.limit, 50)
    local rows = QBPhone.Repositories.Reports.queue(status, pagination.limit, pagination.cursor)
    for _, row in ipairs(rows) do
        local ok, decoded = pcall(json.decode, row.snapshotJson or '{}')
        row.snapshot = ok and type(decoded) == 'table' and decoded or {}
        row.snapshotJson = nil
    end
    return PhoneResult({ items = rows, nextCursor = #rows == pagination.limit and rows[#rows].id or nil })
end

function Moderation.resolve(source, payload)
    local device, deviceError = QBPhone.Permissions.requireDevice(source)
    if not device then return deviceError end
    local actor = moderator(source)
    if not actor then return PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'Moderator permission required') end
    payload = type(payload) == 'table' and payload or {}
    local reportId, validationError = PhoneValidation.integer(payload.reportId, 'reportId', 1)
    if not reportId then return invalid(validationError) end
    local action; action, validationError = PhoneValidation.enum(payload.action, 'action',
        { 'dismiss', 'remove_content', 'suspend_profile' })
    if not action then return invalid(validationError) end
    local note; note, validationError = PhoneValidation.string(payload.note, 'note', 3, 1000)
    if not note then return invalid(validationError) end
    local report = QBPhone.Repositories.Reports.get(reportId)
    if not report or (report.status ~= 'open' and report.status ~= 'reviewing') then
        return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Open report was not found')
    end
    if not QBPhone.Repositories.Reports.claim(reportId, actor) then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Report is being handled by another moderator')
    end
    local changed = true
    if action == 'remove_content' then
        if report.targetType == 'post' then changed = QBPhone.Repositories.Social.hidePostByModerator(report.targetId)
        elseif report.targetType == 'comment' then changed = QBPhone.Repositories.Social.hideCommentByModerator(report.targetId)
        elseif report.targetType == 'listing' then changed = QBPhone.Repositories.Marketplace.hideByModerator(report.targetId)
        else return invalid('This target cannot be removed') end
    elseif action == 'suspend_profile' then
        if report.targetType ~= 'profile' then return invalid('Only a profile can be suspended') end
        changed = QBPhone.Repositories.Social.setSuspended(report.targetId, true)
    end
    if action ~= 'dismiss' and not changed then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Target was already unavailable') end
    local status = action == 'dismiss' and 'dismissed' or 'resolved'
    if not QBPhone.Repositories.Reports.resolve(reportId, actor, status, note) then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Report was already handled')
    end
    QBPhone.Repositories.Reports.audit(actor, action, report.targetType, report.targetId, note, { reportId = reportId })
    return PhoneResult({ reportId = reportId, status = status, action = action })
end
