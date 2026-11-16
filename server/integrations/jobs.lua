KoraPhone = KoraPhone or {}
KoraPhone.Integrations = KoraPhone.Integrations or {}

---Job reads through kora_core and duty changes through kora_multijob. Config defaults come from
---the Config.Server.Jobs schema, so nothing is defaulted here.
local Jobs = {}
KoraPhone.Integrations.Jobs = Jobs

---@class PhoneJobSnapshot
---@field name string
---@field label string
---@field grade integer kora_core's one-based grade level (the same scale as shop `grade` and `minimumGrade`).
---@field gradeName string
---@field gradeLabel string Same as `gradeName`: kora_core jobs carry no separate grade label.
---@field onDuty boolean
---@field isBoss boolean

---The player's current job in the phone's shape, or nil when it cannot be read.
---@param src integer
---@return PhoneJobSnapshot|nil
function Jobs.snapshot(src)
    local job = exports.kora_core:getJob(src)
    if type(job) ~= 'table' or type(job.name) ~= 'string' then return nil end
    local grade = type(job.grade) == 'table' and job.grade or {}
    local gradeName = tostring(grade.name or '')
    return {
        name = job.name,
        label = tostring(job.label or job.name),
        grade = tonumber(grade.level) or 0,
        gradeName = gradeName,
        gradeLabel = gradeName,
        onDuty = job.onduty == true,
        isBoss = job.isboss == true,
    }
end

---True when the player is on duty in `jobName` at `minimumGrade` or above (one-based, like kora_core).
---Used by both the Jobs app and the business shop counters.
---@param src integer
---@param jobName string
---@param minimumGrade? integer
---@return boolean
function Jobs.onDutyAt(src, jobName, minimumGrade)
    local snapshot = Jobs.snapshot(src)
    return snapshot ~= nil
        and snapshot.name == jobName
        and snapshot.onDuty
        and snapshot.grade >= (tonumber(minimumGrade) or 0)
end

---Display-only: whether kora_multijob's roster marks `jobName` as duty-locked (`Config.disabledDuty`), so the
---Jobs app can hide its duty switch. Enforcement lives in `exports.kora_multijob:setDuty`, not here.
---@param src integer
---@param jobName string
---@return boolean
function Jobs.dutyLocked(src, jobName)
    if GetResourceState('kora_multijob') ~= 'started' then return false end
    local roster = exports.kora_multijob:getRoster(src)
    for _, entry in ipairs(type(roster) == 'table' and roster.jobs or {}) do
        if entry.name == jobName then return entry.dutyLocked == true end
    end
    return false
end

---Changes the player's duty state through `exports.kora_multijob:setDuty`, which owns the duty-lock rules
---and calls kora_core's `setJobDuty`.
---@param src integer
---@param onDuty boolean
---@return boolean changed
---@return string|nil reason 'disabled', 'no_job', 'multijob_unavailable', 'duty_locked' or 'rejected'
function Jobs.setDuty(src, onDuty)
    if not Config.Server.Jobs.Enabled or not Config.Server.Jobs.AllowDutyToggle then
        return false, 'disabled'
    end
    if not Jobs.snapshot(src) then return false, 'no_job' end
    if GetResourceState('kora_multijob') ~= 'started' then return false, 'multijob_unavailable' end
    local changed, reason = exports.kora_multijob:setDuty(src, onDuty == true)
    if changed == true then return true end
    return false, reason == 'duty_change_disabled' and 'duty_locked' or 'rejected'
end

---@param jobName string
---@param actionName string
---@return table|nil
function Jobs.getAction(jobName, actionName)
    local actions = Config.Server.Jobs.Actions[jobName]
    local action = type(actions) == 'table' and actions[actionName] or nil
    if type(action) ~= 'table' or action.enabled ~= true then return nil end
    return action
end
