SteviePhone.Repositories = SteviePhone.Repositories or {}
local Reports = {}
SteviePhone.Repositories.Reports = Reports

function Reports.create(reporterDeviceId, report)
    local ok, id = pcall(MySQL.insert.await, [[INSERT INTO phone_reports
        (reporter_device_id, target_type, target_id, reason, details, snapshot_json)
        VALUES (?, ?, ?, ?, ?, ?)]], { reporterDeviceId, report.targetType, report.targetId,
        report.reason, report.details, json.encode(report.snapshot) })
    if ok then return id, false end
    local existing = MySQL.scalar.await([[SELECT id FROM phone_reports WHERE reporter_device_id = ?
        AND target_type = ? AND target_id = ? LIMIT 1]], { reporterDeviceId, report.targetType, report.targetId })
    return existing, existing ~= nil
end

function Reports.queue(status, limit, cursor)
    local sql = [[SELECT id, target_type AS targetType, target_id AS targetId, reason, details,
        status, assigned_citizenid AS assignedCitizenId, snapshot_json AS snapshotJson,
        UNIX_TIMESTAMP(created_at) AS createdAt
        FROM phone_reports WHERE status = ?]]
    local params = { status }
    if cursor then sql = sql .. ' AND id < ?'; params[#params + 1] = cursor end
    sql = sql .. ' ORDER BY id DESC LIMIT ?'; params[#params + 1] = limit
    return MySQL.query.await(sql, params) or {}
end

function Reports.get(id)
    return MySQL.single.await([[SELECT id, reporter_device_id AS reporterDeviceId, target_type AS targetType,
        target_id AS targetId, reason, details, snapshot_json AS snapshotJson, status,
        assigned_citizenid AS assignedCitizenId, resolution_note AS resolutionNote,
        UNIX_TIMESTAMP(created_at) AS createdAt FROM phone_reports WHERE id = ?]], { id })
end

function Reports.claim(id, actorCitizenId)
    local changed = MySQL.update.await([[UPDATE phone_reports SET status = 'reviewing', assigned_citizenid = ?
        WHERE id = ? AND status = 'open']], { actorCitizenId, id })
    if changed and changed > 0 then return true end
    return MySQL.scalar.await([[SELECT EXISTS(SELECT 1 FROM phone_reports
        WHERE id = ? AND status = 'reviewing' AND assigned_citizenid = ?)]], { id, actorCitizenId }) == 1
end

function Reports.resolve(id, actorCitizenId, status, note)
    return MySQL.update.await([[UPDATE phone_reports SET status = ?, assigned_citizenid = ?,
        resolution_note = ? WHERE id = ? AND status IN ('open','reviewing')]],
        { status, actorCitizenId, note, id }) > 0
end

function Reports.audit(actorCitizenId, action, targetType, targetId, reason, metadata)
    return MySQL.insert.await([[INSERT INTO phone_moderation_audit
        (actor_citizenid, action, target_type, target_id, reason, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?)]], { actorCitizenId, action, targetType, targetId,
        reason, json.encode(metadata or {}) })
end
