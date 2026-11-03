-- Run from qbphone-stevie: lua5.4 tests/native-integrations.test.lua
local balance, duty, phone, allowDuty = 100, false, true, true
Config = { RequirePhoneItem = true, PhoneItem = 'phone', Handsets = { phone = 'standard' }, Server = {} }
QBPhone = { Permissions = { requireDevice = function() return {} end } }
PhoneConstants = { Errors = { CONFLICT = 'conflict', INVALID_INPUT = 'invalid', NOT_FOUND = 'missing' } }
PhoneError = function(code) return { ok = false, error = code } end
PhoneResult = function(data) return { ok = true, data = data } end
local function player(src)
    if src ~= 12 then return nil end
    return { source = src, citizenid = 'CID', money = { bank = balance },
        job = { name = 'police', grade = { level = 3 }, onduty = duty } }
end
exports = { kora_core = {
    getPlayerData = function(_, src) return player(src) end,
    getPlayerByCitizenId = function(_, citizenid) return citizenid == 'CID' and player(12) or nil end,
    getItemByName = function(_, src, name)
        assert(src == 12 and name == 'phone')
        return phone and {} or nil
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
} }
dofile('server/integrations/qbcore.lua')
dofile('server/integrations/banking.lua')
dofile('server/integrations/jobs.lua')
dofile('server/services/jobs.lua')
assert(QBPhone.GetCitizenId(12) == 'CID' and not QBPhone.GetPlayer('12'))
assert(QBPhone.HasPhone(12) and not QBPhone.HasPhone(99))
phone = false
assert(not QBPhone.HasPhone(12))
local banking, jobs = QBPhone.Integrations.Banking, QBPhone.Integrations.Jobs
local snapshot = QBPhone.GetPlayer(12)
assert(banking.getOnlinePlayerByCitizenId('CID').source == 12)
assert(banking.debit(snapshot, 25) and banking.getBalance(snapshot) == 75)
assert(banking.credit(snapshot, 10) and banking.getBalance(snapshot) == 85)
assert(snapshot.money.bank == 100, 'the balance check must use current money, not a stale snapshot')
assert(not banking.debit(snapshot, 200) and not banking.credit(nil, 1))
assert(jobs.snapshot(snapshot).grade == 2, 'public phone grades remain zero-based')
local result = QBPhone.Services.Jobs.setDuty(12, { onDuty = true })
assert(result.ok and result.data.job.onDuty, 'the duty response must fetch the changed snapshot')
assert(snapshot.job.onduty == false)
allowDuty = false
assert(not QBPhone.Services.Jobs.setDuty(12, { onDuty = false }).ok)
assert(duty == true)
print('qbphone native integrations: fresh balances, phone ownership, legacy grades and duty changes passed')
