-- Run from the resource root: lua5.4 tests/system-mail.test.lua
local nativeExports, sent, rows, nextId = {}, {}, {}, 0
local device, citizen, money = { id = 5, holderCitizenId = 'CID' }, 'CID', 100
local activity, moneyTouched = {}, false

local function encode(v)
    if type(v) == 'table' then
        local out = {}
        for k, x in pairs(v) do out[#out + 1] = tostring(k) .. '=' .. tostring(x) end
        table.sort(out); return '{' .. table.concat(out, ',') .. '}'
    end
    return tostring(v)
end
json = { encode = encode }
exports = setmetatable({ kora_core = {
    getPlayerByCitizenId = function(_, id) return id == 'CID' and { source = 12 } or nil end,
} }, { __call = function(_, name, fn) nativeExports[name] = fn end })
function TriggerClientEvent(name, target, payload) sent[#sent + 1] = { name, target, payload } end
PhoneConstants = { Errors = { NOT_FOUND = 'missing', INVALID_INPUT = 'invalid', FORBIDDEN = 'forbidden' } }
PhoneError = function(code) return { ok = false, error = code } end
PhoneResult = function(data) return { ok = true, data = data } end
PhoneValidation = {
    integer = function(v) return type(v) == 'number' and v > 0 and v % 1 == 0 and v or nil end,
    page = function() return { limit = 50 } end,
}
local Repo = {
    insert = function(cid, mail)
        nextId = nextId + 1; rows[nextId] = { cid = cid, mail = mail, deleted = false }; return nextId
    end,
    list = function(cid) local o = {}; for id, r in pairs(rows) do if r.cid == cid and not r.deleted then o[#o + 1] = { id = id } end end; return o end,
    markRead = function(cid, id) return rows[id] and rows[id].cid == cid and 1 or nil end,
    delete = function(cid, id)
        local r = rows[id]; if not r or r.cid ~= cid or r.deleted then return false end
        r.deleted = true; r.mail.button = nil; return true
    end,
    takeButton = function(cid, id)
        local r = rows[id]; if not r or r.cid ~= cid or r.deleted or not r.mail.button then return nil end
        local b = r.mail.button; r.mail.button = nil; return b
    end,
    activity = function(cid) return activity end,
    addActivity = function(cid, title, message) activity[#activity + 1] = { cid, title, message }; return #activity end,
}
KoraPhone = {
    GetCitizenId = function() return citizen end,
    Permissions = { requireDevice = function() if device then return device end return nil, PhoneError('locked') end },
    Handsets = { current = function() return device end },
    Repositories = { SystemMail = Repo },
}
dofile('server/mail/system.lua')
local SM, routes = KoraPhone.SystemMail, KoraPhone.SystemMail.routes
local pass = 0
local function check(cond, label) assert(cond, label); pass = pass + 1 end

-- Sanitisation
local ok = nativeExports.SendSystemMail('OFFLINE', { sender = 'Job', subject = 'Hi', message = '<b>Go</b><br>there<p>x</p>' })
check(ok and rows[1].mail.message == 'Go\nthere' .. 'x\n', 'html stripped')
check(not nativeExports.SendSystemMail('CID', { sender = 'a', subject = 'b', message = {} }), 'non-string message rejected')
check(not nativeExports.SendSystemMail('CID', { sender = ('x'):rep(101), subject = 'b', message = 'm' }), 'sender cap')
check(not nativeExports.SendSystemMail('CID', { sender = 'a', subject = ('x'):rep(121), message = 'm' }), 'subject cap')
check(not nativeExports.SendSystemMail('CID', { sender = 'a', subject = 'b', message = ('x'):rep(16001) }), 'message cap')
check(not nativeExports.SendSystemMail(nil, { sender = 'a', subject = 'b', message = 'm' }), 'citizen id required')
check(not nativeExports.SendSystemMail('CID', { sender = 'a', subject = 'b', message = 'm',
    button = { event = 'job:client:' .. ('x'):rep(200), data = 1 } }), 'button event cap')
check(not nativeExports.SendSystemMail('CID', { sender = 'a', subject = 'b', message = 'm',
    button = { event = 'job:client:go', data = ('x'):rep(16001) } }), 'button data cap')
check(not nativeExports.SendSystemMail('CID', { sender = 'a', subject = 'b', message = 'm',
    button = { event = 'kora_core:client:anything' } }), 'reserved prefix rejected')
check(not nativeExports.SendSystemMail('CID', { sender = 'a', subject = 'b', message = 'm',
    button = { event = 'nocolon' } }), 'non client event rejected')

-- Offline delivery sends no notification; online delivery does
sent = {}
check(nativeExports.SendSystemMail('OFFLINE', { sender = 'a', subject = 'b', message = 'm' }) and #sent == 0, 'offline stored silently')
local id = select(2, nativeExports.SendSystemMail('CID', { sender = 'Job', subject = 'Offer', message = 'm',
    button = { event = 'job:client:accept', data = { mission = 7 } } }))
check(#sent == 1 and sent[1][1] == 'kora_phone:client:mail:new' and sent[1][2] == 12 and sent[1][3].id == id, 'online notification')

-- One-use button: the server triggers the client event itself
sent = {}
local r = routes['mail:system:accept'](12, { id = id })
check(r.ok and r.data.dispatched and sent[1][1] == 'job:client:accept' and sent[1][2] == 12 and sent[1][3].mission == 7, 'accept dispatches')
check(not routes['mail:system:accept'](12, { id = id }).ok and #sent == 1, 'button is one-use')
check(not routes['mail:system:accept'](12, { id = 999 }).ok, 'unknown mail')
check(not routes['mail:system:accept'](12, { id = 'x' }).ok, 'invalid id')

-- Ownership and lock
local foreign = select(2, nativeExports.SendSystemMail('OFFLINE', { sender = 'a', subject = 'b', message = 'm',
    button = { event = 'job:client:accept' } }))
sent = {}
check(not routes['mail:system:accept'](12, { id = foreign }).ok and #sent == 0, 'foreign mail not acceptable')
check(not routes['mail:system:delete'](12, { id = foreign }).ok, 'foreign mail not deletable')
check(routes['mail:system:read'](12, { id = id }).ok, 'own mail readable')
check(routes['mail:system:delete'](12, { id = id }).ok and not routes['mail:system:delete'](12, { id = id }).ok, 'delete once')
device.holderCitizenId = 'OTHER'
check(not routes['mail:system:list'](12, {}).ok, 'handset holder mismatch refused')
device.holderCitizenId = 'CID'
local savedDevice = device; device = nil
check(not routes['mail:system:list'](12, {}).ok, 'locked handset refused')
device = savedDevice
nativeExports.SendSystemMail('CID', { sender = 'a', subject = 'b', message = 'm' })
local items = routes['mail:system:list'](12, {}).data.items
check(#items >= 1, 'list own mail')
for _, item in ipairs(items) do check(rows[item.id].cid == 'CID', 'list only own mail') end

-- Activity never touches money
check(nativeExports.AddSystemActivity('CID', 'Credit', 'Received 5 BTC') and #activity == 1 and money == 100, 'activity stored, money untouched')
check(not nativeExports.AddSystemActivity('CID', 'Credit', {}) and #activity == 1, 'invalid activity rejected')
check(not nativeExports.AddSystemActivity('CID', ('x'):rep(101), 'm'), 'title cap')
check(routes['mail:system:activity'](12, {}).ok, 'activity list route')
print(('PASS system mail: %d checks'):format(pass))
