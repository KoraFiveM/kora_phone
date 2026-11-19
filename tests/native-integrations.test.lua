-- Run from kora_phone: lua5.4 tests/native-integrations.test.lua
local balance, duty, phone, allowDuty, dutyLocked = 100, false, true, true, false
Config = { RequirePhoneItem = true, PhoneItem = 'phone', Handsets = { phone = 'standard' }, Server = {} }
KoraPhone = { Permissions = { requireDevice = function() return {} end } }
PhoneConstants = { Errors = { CONFLICT = 'conflict', INVALID_INPUT = 'invalid', NOT_FOUND = 'missing' } }
PhoneError = function(code) return { ok = false, error = code } end
PhoneResult = function(data) return { ok = true, data = data } end
local function player(src)
    if src ~= 12 then return nil end
    return { source = src, citizenid = 'CID', money = { bank = balance },
        job = { name = 'police', grade = { level = 3 }, onduty = duty } }
end
exports = { kora_core = {
    getPlayer = function(_, src) return player(src) end,
    -- Mirrors kora_core: path is an array of keys; a plain string path finds nothing.
    getPlayerData = function(_, src, path)
        local node = player(src)
        if not path then return nil end
        for i = 1, #path do
            if type(node) ~= 'table' then return nil end
            node = node[path[i]]
        end
        return node
    end,
    getPlayerByCitizenId = function(_, citizenid) return citizenid == 'CID' and player(12) or nil end,
    getJob = function(_, src)
        local data = player(src)
        if not data then return nil end
        return { name = data.job.name, label = 'Police', onduty = data.job.onduty,
            isboss = false, grade = { name = 'Sergeant', level = data.job.grade.level } }
    end,
    hasItem = function(_, src, name, count)
        assert(src == 12 and name == 'phone' and count == 1)
        return phone
    end,
    getMoney = function(_, src, account) assert(src == 12 and account == 'bank'); return balance end,
    addMoney = function(_, src, account, amount)
        assert(src == 12 and account == 'bank'); balance = balance + amount; return true
    end,
    removeMoney = function(_, src, account, amount)
        assert(src == 12 and account == 'bank')
        if amount > balance then return false end
        balance = balance - amount; return true
    end,
    setJobDuty = function(_, src, value)
        assert(src == 12)
        if not allowDuty then return false end
        duty = value; return true
    end,
}, kora_multijob = {
    setDuty = function(_, src, value)
        assert(src == 12)
        if dutyLocked then return false, 'duty_change_disabled' end
        if not allowDuty then return false, 'duty_change_failed' end
        duty = value
        return true
    end,
    getRoster = function(_, src)
        assert(src == 12)
        return { jobs = { { name = 'police', dutyLocked = dutyLocked } }, active = { name = 'police', onDuty = duty } }
    end,
} }
GetResourceState = function() return 'started' end
Config.Server.Jobs = { Enabled = true, AllowDutyToggle = true, Actions = {} }
Config.Server.Banking = { Enabled = true, Account = 'bank' }
dofile('server/integrations/kora_core.lua')
dofile('server/integrations/banking.lua')
dofile('server/integrations/jobs.lua')
dofile('server/services/jobs.lua')
assert(KoraPhone.GetCitizenId(12) == 'CID' and not KoraPhone.GetPlayer('12'))
assert(KoraPhone.HasPhone(12) and not KoraPhone.HasPhone(99))
phone = false
assert(not KoraPhone.HasPhone(12))
local banking, jobs = KoraPhone.Integrations.Banking, KoraPhone.Integrations.Jobs
local snapshot = KoraPhone.GetPlayer(12)
assert(banking.getBalance(snapshot) == 100, 'balance is read from kora_core')
local job = jobs.snapshot(12)
assert(job.grade == 3 and job.gradeLabel == 'Sergeant', 'grades are kora_core native one-based levels')
assert(jobs.onDutyAt(12, 'police', 3) == false, 'off duty never satisfies a counter')
local result = KoraPhone.Services.Jobs.setDuty(12, { onDuty = true })
assert(result.ok and result.data.job.onDuty, 'the duty response must fetch the changed snapshot')
assert(snapshot.job.onduty == false)
assert(jobs.onDutyAt(12, 'police', 3) and not jobs.onDutyAt(12, 'police', 4) and not jobs.onDutyAt(12, 'fire', 0))
dutyLocked = true
local locked = KoraPhone.Services.Jobs.setDuty(12, { onDuty = false })
assert(not locked.ok and duty == true, 'multijob duty lock must be honoured')
dutyLocked = false
allowDuty = false
assert(not KoraPhone.Services.Jobs.setDuty(12, { onDuty = false }).ok)
assert(duty == true)
print('kora_phone native integrations: fresh balances, phone ownership, one-based grades, duty lock and duty changes passed')