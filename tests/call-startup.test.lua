-- Cold starts must recover calls only after migrations finish, even under load.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function fixture(mode)
    local env = {}; for key, value in pairs(_G) do env[key] = value end
    local state = { handlers = {}, threads = {}, cleanup = 0, messages = {}, stopped = false }
    env.Config = { Calls = {}, Server = { DatabaseReadyTimeoutMs = 10000 } }
    env.QBPhone = { Repositories = { Calls = { endUnfinished = function()
        state.cleanup = state.cleanup + 1
        check(state.migrated, 'cleanup ran before migrations')
        if mode == 'recovery_failure' then error('controlled SQL failure') end
        return 0
    end } }, Database = { isReady = function() return true end }, Migrations = { run = function()
        coroutine.yield('migration pending')
        state.migrated = mode ~= 'migration_failure'
        return state.migrated, 'controlled migration failure'
    end } }
    env.CreateThread = function(fn) state.threads[#state.threads + 1] = coroutine.create(fn) end
    env.AddEventHandler = function(name, fn)
        state.handlers[name] = state.handlers[name] or {}
        table.insert(state.handlers[name], fn)
    end
    env.RegisterNetEvent, env.RegisterCommand, env.exports = function() end, function() end, function() end
    env.GetGameTimer = function() return 0 end
    env.GetCurrentResourceName = function() return 'qbphone-stevie' end
    env.GetResourceMetadata = function() return 'test' end
    env.print = function(message) state.messages[#state.messages + 1] = message end
    env.StopResource = function()
        state.stopped = true
        for _, handler in ipairs(state.handlers.onResourceStop or {}) do handler('qbphone-stevie') end
    end
    assert(loadfile('server/services/calling.lua', 't', env))()
    assert(loadfile('server/main.lua', 't', env))()
    return state, env
end
for _, mode in ipairs({ 'success', 'migration_failure', 'recovery_failure' }) do
    local state, env = fixture(mode)
    check(#state.threads == 1, 'startup must have one migration-owned recovery path')
    check(not state.handlers.onResourceStart, 'fixed-delay startup recovery remains')
    check(coroutine.resume(state.threads[1]), 'startup coroutine failed')
    check(state.cleanup == 0, 'pending migration must not access calls')
    env.QBPhone.Services.Calling.shutdown('early_stop')
    check(state.cleanup == 0, 'early stop must not access a missing calls table')
    check(coroutine.resume(state.threads[1]), 'startup did not finish')
    check(coroutine.status(state.threads[1]) == 'dead', 'startup remained pending')
    check(state.stopped == (mode ~= 'success'), 'failure did not stop the resource')
    check(state.cleanup == (mode == 'migration_failure' and 0 or 1), 'recovery ran the wrong number of times')
    check((env.QBPhone.Services.Calling.ready == true) == (mode == 'success'), 'readiness published before recovery')
    local ready = table.concat(state.messages, '\n'):find('foundation ready', 1, true) ~= nil
    check(ready == (mode == 'success'), 'misleading ready log')
end
print(('PASS phone migration/recovery lifecycle: %d checks'):format(checks))
