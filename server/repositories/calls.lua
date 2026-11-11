KoraPhone.Repositories = KoraPhone.Repositories or {}
local Calls = {}
KoraPhone.Repositories.Calls = Calls

function Calls.create(call)
    local inserted = MySQL.update.await([[
        INSERT INTO phone_calls
            (id, caller_device_id, callee_device_id, caller_number_snapshot,
             callee_number_snapshot, status, voice_channel, started_at)
        VALUES (?, ?, ?, ?, ?, 'ringing', ?, CURRENT_TIMESTAMP)
    ]], {
        call.id, call.callerDeviceId, call.calleeDeviceId,
        call.callerNumber, call.calleeNumber, call.voiceChannel,
    })
    return inserted == 1
end

function Calls.transition(callId, fromStatuses, toStatus, reason)
    if type(fromStatuses) ~= 'table' or #fromStatuses == 0 then return false end
    local placeholders = {}
    local params = { toStatus }
    local timestampSql = ''
    if toStatus == 'active' then
        timestampSql = ', answered_at = COALESCE(answered_at, CURRENT_TIMESTAMP)'
    elseif toStatus == 'ended' or toStatus == 'rejected' or toStatus == 'missed' or toStatus == 'cancelled' then
        timestampSql = ', ended_at = COALESCE(ended_at, CURRENT_TIMESTAMP), ended_reason = ?'
        params[#params + 1] = reason
    end
    params[#params + 1] = callId
    for _, status in ipairs(fromStatuses) do
        placeholders[#placeholders + 1] = '?'
        params[#params + 1] = status
    end
    local changed = MySQL.update.await(([[
        UPDATE phone_calls SET status = ? %s
        WHERE id = ? AND status IN (%s)
    ]]):format(timestampSql, table.concat(placeholders, ',')), params)
    return changed and changed > 0
end

function Calls.get(callId)
    return MySQL.single.await([[
        SELECT id, caller_device_id AS callerDeviceId, callee_device_id AS calleeDeviceId,
               caller_number_snapshot AS callerNumber, callee_number_snapshot AS calleeNumber,
               status, voice_channel AS voiceChannel,
               UNIX_TIMESTAMP(started_at) AS startedAt,
               UNIX_TIMESTAMP(answered_at) AS answeredAt,
               UNIX_TIMESTAMP(ended_at) AS endedAt, ended_reason AS endedReason
        FROM phone_calls WHERE id = ? LIMIT 1
    ]], { callId })
end

function Calls.listForDevice(deviceId, limit, cursor)
    local cursorClause = cursor and [[
        AND (
            started_at < (SELECT started_at FROM phone_calls WHERE id = ?)
            OR (started_at = (SELECT started_at FROM phone_calls WHERE id = ?) AND id < ?)
        )
    ]] or ''
    local params = cursor and { deviceId, deviceId, cursor, cursor, cursor, limit } or { deviceId, deviceId, limit }
    return MySQL.query.await(([[
        SELECT id, caller_number_snapshot AS callerNumber, callee_number_snapshot AS calleeNumber,
               status, UNIX_TIMESTAMP(started_at) AS startedAt,
               UNIX_TIMESTAMP(answered_at) AS answeredAt,
               UNIX_TIMESTAMP(ended_at) AS endedAt, ended_reason AS endedReason
        FROM phone_calls
        WHERE (caller_device_id = ? OR callee_device_id = ?)
          AND NOT EXISTS(SELECT 1 FROM phone_call_hidden h WHERE h.call_id=phone_calls.id AND h.device_id=%d) %s
        ORDER BY started_at DESC, id DESC LIMIT ?
    ]]):format(tonumber(deviceId),cursorClause), params) or {}
end

function Calls.endUnfinished(reason)
    return MySQL.update.await([[
        UPDATE phone_calls
        SET status = CASE WHEN status = 'ringing' THEN 'cancelled' ELSE 'ended' END,
            ended_at = COALESCE(ended_at, CURRENT_TIMESTAMP), ended_reason = ?
        WHERE status IN ('ringing', 'active')
    ]], { reason }) or 0
end