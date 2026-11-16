-- Cold starts must recover calls only after schema setup finishes, even under load.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function fixture(mode)
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    local state = { handlers = {}, threads = {}, cleanup = 0, messages = {}, stopped = false }
    env.Config = { Calls = {}, Server = { DatabaseReadyTimeoutMs = 10000 } }
    env.KoraPhone = { Repositories = { Calls = { endUnfinished = function()
        state.cleanup = state.cleanup + 1
        check(state.schemaReady, 'cleanup ran before schema setup')
        if mode == 'recovery_failure' then error('controlled SQL failure') end
        return 0
    end } }, Handsets = { start = function() end }, Database = { isReady = function() return true end }, SchemaSetup = { run = function()
        coroutine.yield('schema setup pending')
        state.schemaReady = mode ~= 'schema_failure'
        return state.schemaReady, 'controlled schema failure'
    end } }
    env.CreateThread = function(fn) state.threads[#state.threads + 1] = coroutine.create(fn) end
    env.AddEventHandler = function(name, fn)
        state.handlers[name] = state.handlers[name] or {}
        table.insert(state.handlers[name], fn)
    end
    env.RegisterNetEvent, env.RegisterCommand, env.exports = function() end, function() end, function() end
    env.GetGameTimer = function() return 0 end
    env.GetCurrentResourceName = function() return 'kora_phone-stevie' end
    env.GetResourceMetadata = function() return 'test' end
    state.logs = {}
    env.Kora = { logging = setmetatable({}, { __index = function(_, level) return function(event, message, fields)
        state.logs[#state.logs + 1] = { level = level, event = event, message = message, fields = fields }
        return true
    end end }) }
    env.print = function(message) state.messages[#state.messages + 1] = message end
    env.StopResource = function()
        state.stopped = true
        for _, handler in ipairs(state.handlers.onResourceStop or {}) do handler('kora_phone-stevie') end
    end
    assert(loadfile('server/services/calling.lua', 't', env))()
    assert(loadfile('server/main.lua', 't', env))()
    return state, env
end
for _, mode in ipairs({ 'success', 'schema_failure', 'recovery_failure' }) do
    local state, env = fixture(mode)
    check(#state.threads == 1, 'startup must have one schema-owned recovery path')
    check(not state.handlers.onResourceStart, 'fixed-delay startup recovery remains')
    check(coroutine.resume(state.threads[1]), 'startup coroutine failed')
    check(state.cleanup == 0, 'pending schema setup must not access calls')
    env.KoraPhone.Services.Calling.shutdown('early_stop')
    check(state.cleanup == 0, 'early stop must not access a missing calls table')
    check(coroutine.resume(state.threads[1]), 'startup did not finish')
    check(coroutine.status(state.threads[1]) == 'dead', 'startup remained pending')
    check(state.stopped == (mode ~= 'success'), 'failure did not stop the resource')
    if mode == 'schema_failure' then
        local log = state.logs[1]
        check(log and log.level == 'error' and log.event == 'phone.database_setup_failed', 'setup failure must log error phone.database_setup_failed')
        check(log.fields and tostring(log.fields.error):find('controlled schema failure', 1, true), 'setup failure log must carry the error field')
    end
    check(state.cleanup == (mode == 'schema_failure' and 0 or 1), 'recovery ran the wrong number of times')
    check((env.KoraPhone.Services.Calling.ready == true) == (mode == 'success'), 'readiness published before recovery')
    local ready = false
    for _, log in ipairs(state.logs) do if log.event == 'phone.server_ready' then ready = true end end
    check(ready == (mode == 'success'), 'misleading ready log')
end
-- Boot runs schema setup only: no legacy conversion, import or data preflight is wired in.
local mainSource = assert(io.open('server/main.lua')):read('a')
check(mainSource:find('KoraPhone.SchemaSetup.run()', 1, true) and not mainSource:find('Migrat', 1, true) and not mainSource:find('LegacyMail', 1, true), 'boot must call schema setup and no legacy conversion')
print(('PASS phone schema setup/recovery lifecycle: %d checks'):format(checks))