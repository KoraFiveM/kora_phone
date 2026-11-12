KoraPhone = KoraPhone or {}
KoraPhone.Integrations = KoraPhone.Integrations or {}

local Jobs = {}
KoraPhone.Integrations.Jobs = Jobs

Config.Server.Jobs = Config.Server.Jobs or {}
local jobsConfig = Config.Server.Jobs
if jobsConfig.Enabled == nil then jobsConfig.Enabled = true end
if jobsConfig.AllowDutyToggle == nil then jobsConfig.AllowDutyToggle = true end
jobsConfig.Actions = type(jobsConfig.Actions) == 'table' and jobsConfig.Actions or {}

local function gradeLevel(job)
    if type(job) ~= 'table' then return 0 end
    if type(job.grade) == 'table' then return tonumber(job.grade.level) or 0 end
    return tonumber(job.grade) or 0
end

function Jobs.snapshot(player)
    local job = player and player.job
    if type(job) ~= 'table' or type(job.name) ~= 'string' then return nil end
    return {
        name = job.name,
        label = tostring(job.label or job.name),
        grade = math.max(0, gradeLevel(job) - 1),
        gradeName = type(job.grade) == 'table' and tostring(job.grade.name or '') or '',
        gradeLabel = type(job.grade) == 'table' and tostring(job.grade.label or '') or '',
        onDuty = job.onduty == true,
        isBoss = job.isboss == true or (type(job.grade) == 'table' and job.grade.isboss == true)
    }
end

function Jobs.setDuty(player, onDuty)
    if not Config.Server.Jobs.Enabled or not Config.Server.Jobs.AllowDutyToggle then return false end
    if not player or not player.source then return false end
    local ok, changed = pcall(function() return exports.kora_core:setJobDuty(player.source, onDuty == true) end)
    return ok and changed == true
end

function Jobs.getAction(jobName, actionName)
    local jobs = Config.Server.Jobs.Actions
    local actions = type(jobs) == 'table' and jobs[jobName] or nil
    local action = type(actions) == 'table' and actions[actionName] or nil
    if type(action) ~= 'table' or action.enabled ~= true then return nil end
    return action
end