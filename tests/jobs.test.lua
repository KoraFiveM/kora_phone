-- Run from kora_phone: lua5.4 tests/jobs.test.lua
-- Covers the jobs:setDuty path: kora_multijob owns the duty rules, the phone only maps the result.
local duty, multijobState, locked, multijobReply = false, 'started', false, nil
local setDutyCalls = 0

Config = { Server = { Jobs = { Enabled = true, AllowDutyToggle = true, Actions = {} } } }
KoraPhone = { Permissions = { requireDevice = function() return {} end }, GetPlayer = function() return {} end }
PhoneConstants = { Errors = { CONFLICT = 'CONFLICT', INVALID_INPUT = 'INVALID_INPUT', NOT_FOUND = 'NOT_FOUND' } }
PhoneError = function(code, message) return { ok = false, error = { code = code, message = message } } end
PhoneResult = function(data) return { ok = true, data = data } end
PhoneValidation = {}

GetResourceState = function(name)
    assert(name == 'kora_multijob')
    return multijobState
end

exports = {
    kora_core = {
        getJob = function(_, src)
            assert(src == 7)
            return { name = 'police', label = 'Police', onduty = duty, grade = { name = 'Officer', level = 2 } }
        end,
        setJobDuty = function() error('the phone must not call kora_core setJobDuty directly') end,
    },
    kora_multijob = {
        setDuty = function(_, src, onDuty)
            assert(src == 7 and type(onDuty) == 'boolean')
            setDutyCalls = setDutyCalls + 1
            if multijobReply then return false, multijobReply end
            if locked then return false, 'duty_change_disabled' end
            duty = onDuty
            return true
        end,
        getRoster = function()
            return { jobs = { { name = 'police', dutyLocked = locked } }, active = { name = 'police', onDuty = duty } }
        end,
    },
}

dofile('server/integrations/jobs.lua')
dofile('server/services/jobs.lua')
local Service = KoraPhone.Services.Jobs

local result = Service.setDuty(7, { onDuty = true })
assert(result.ok, 'an unlocked job can change duty')
assert(result.data.job.onDuty == true and result.data.job.name == 'police', 'the response keeps the job snapshot shape')
assert(result.data.job.dutyLocked == false and type(result.data.actions) == 'table', 'the response keeps dutyLocked and actions')
assert(setDutyCalls == 1, 'the change goes through exports.kora_multijob:setDuty once')

locked = true
local refused = Service.setDuty(7, { onDuty = false })
assert(not refused.ok and refused.error.code == 'CONFLICT', 'a locked job is refused')
assert(refused.error.message == 'This job cannot change duty from the phone', 'the lock reason is explained')
assert(duty == true, 'a refused change leaves duty untouched')
assert(Service.get(7).data.job.dutyLocked == true, 'the roster lock is still exposed for the UI')
locked = false

multijobReply = 'duty_change_failed'
local failed = Service.setDuty(7, { onDuty = false })
assert(not failed.ok and failed.error.message == 'Duty state could not be changed', 'other refusals are generic')
multijobReply = nil

multijobState = 'stopped'
local calls = setDutyCalls
local unavailable = Service.setDuty(7, { onDuty = false })
assert(not unavailable.ok and unavailable.error.code == 'CONFLICT', 'a stopped kora_multijob is a PhoneError')
assert(unavailable.error.message == 'Duty management is currently unavailable', 'the unavailable reason is clear')
assert(setDutyCalls == calls and duty == true, 'nothing is changed while kora_multijob is stopped')
assert(Service.get(7).data.job.dutyLocked == false, 'reading the lock flag tolerates a stopped kora_multijob')
multijobState = 'started'

local invalid = Service.setDuty(7, { onDuty = 'yes' })
assert(not invalid.ok and invalid.error.code == 'INVALID_INPUT', 'onDuty must be a boolean')

Config.Server.Jobs.AllowDutyToggle = false
assert(not Service.setDuty(7, { onDuty = false }).ok, 'AllowDutyToggle = false refuses duty changes')

print('kora_phone jobs: duty toggle via kora_multijob, lock refusal, unavailable resource passed')
