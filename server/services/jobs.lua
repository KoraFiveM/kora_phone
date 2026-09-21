SteviePhone.Services = SteviePhone.Services or {}
local JobsService = {}
SteviePhone.Services.Jobs = JobsService

local function requireJobPlayer(source)
    local _, err = SteviePhone.Permissions.requireDevice(source)
    if err then return nil, nil, err end
    if not Config.Server.Jobs.Enabled then
        return nil, nil, PhoneError(PhoneConstants.Errors.CONFLICT, 'Jobs app is disabled')
    end
    local player = SteviePhone.GetPlayer(source)
    local snapshot = SteviePhone.Integrations.Jobs.snapshot(player)
    if not snapshot then return nil, nil, PhoneError(PhoneConstants.Errors.NOT_FOUND, 'No current job') end
    return player, snapshot
end

local function actionsFor(snapshot)
    local configured = Config.Server.Jobs.Actions[snapshot.name]
    local output = {}
    if type(configured) ~= 'table' then return output end
    for key, action in pairs(configured) do
        if type(action) == 'table' and action.enabled == true
            and snapshot.grade >= (tonumber(action.minimumGrade) or 0)
            and (action.requireDuty ~= true or snapshot.onDuty) then
            output[#output + 1] = { id = key, label = tostring(action.label or key):sub(1, 64) }
        end
    end
    table.sort(output, function(a, b) return a.id < b.id end)
    return output
end

function JobsService.get(source)
    local _, snapshot, err = requireJobPlayer(source)
    if not snapshot then return err end
    return PhoneResult({ job = snapshot, actions = actionsFor(snapshot) })
end

function JobsService.setDuty(source, payload)
    local player, before, err = requireJobPlayer(source)
    if not player then return err end
    if type(payload) ~= 'table' or type(payload.onDuty) ~= 'boolean' then
        return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'onDuty must be a boolean')
    end
    if not SteviePhone.Integrations.Jobs.setDuty(player, payload.onDuty) then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Duty state could not be changed')
    end
    local after = SteviePhone.Integrations.Jobs.snapshot(player)
    if not after or after.name ~= before.name then
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Job changed while duty state was being updated')
    end
    return PhoneResult({ job = after, actions = actionsFor(after) })
end

function JobsService.runAction(source, payload)
    local player, snapshot, err = requireJobPlayer(source)
    if not player then return err end
    if type(payload) ~= 'table' then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, 'payload must be an object') end
    local actionName, validationError = PhoneValidation.string(payload.action, 'action', 1, 48)
    if not actionName then return PhoneError(PhoneConstants.Errors.INVALID_INPUT, validationError) end
    local action = SteviePhone.Integrations.Jobs.getAction(snapshot.name, actionName)
    if not action then return PhoneError(PhoneConstants.Errors.NOT_FOUND, 'Job action is unavailable') end
    if snapshot.grade < (tonumber(action.minimumGrade) or 0) then
        return PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'Job grade is not permitted')
    end
    if action.requireDuty == true and not snapshot.onDuty then
        return PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'You must be on duty')
    end

    local context = {
        source = source,
        citizenId = player.PlayerData.citizenid,
        job = snapshot.name,
        grade = snapshot.grade,
        action = actionName
    }
    local ok, result
    if type(action.handler) == 'function' then
        ok, result = pcall(action.handler, context)
    elseif type(action.serverEvent) == 'string' and action.serverEvent ~= '' then
        ok = pcall(TriggerEvent, action.serverEvent, context)
        result = ok
    else
        return PhoneError(PhoneConstants.Errors.CONFLICT, 'Job action is not configured correctly')
    end
    if not ok or result == false then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Job action failed') end
    return PhoneResult({ action = actionName, completed = true })
end

