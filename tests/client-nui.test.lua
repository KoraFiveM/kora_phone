-- Run from the resource root: lua tests/client-nui.test.lua
-- Covers client/nui.lua: every entry of shared/routes.json becomes one NUI callback that forwards to its server
-- callback, payloads are normalised to tables, and replies are always answered.

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write('PASS ', name, '\n')
    else failed = failed + 1; io.stderr:write('FAIL ', name, ': ', tostring(err), '\n') end
end
local function equal(actual, expected)
    assert(actual == expected, ('expected %s, got %s'):format(tostring(expected), tostring(actual)))
end

local function readFile(path)
    local handle = assert(io.open(path, 'rb'))
    local content = handle:read('a')
    handle:close()
    return content
end

local routesJson = readFile('shared/routes.json')

-- The routes file is a flat array of one-line objects, so a pattern decoder is enough outside FiveM.
local function decode(raw)
    local routes = {}
    for line in raw:gmatch('[^\n]+') do
        local nui, server, rate = line:match('"nui": "([^"]+)", "server": "([^"]+)", "rate": "([^"]+)"')
        if nui then
            local app = line:match('"app": "([^"]+)"')
            routes[#routes + 1] = { nui = nui, server = server, rate = rate, app = app }
        end
    end
    return routes
end

local registered, serverCalls, sent
_G.KoraPhone = nil
_G.json = { decode = decode }
_G.GetCurrentResourceName = function() return 'kora_phone' end
_G.LoadResourceFile = function(_, path) assert(path == 'shared/routes.json'); return routesJson end
_G.RegisterNUICallback = function(name, handler) registered[name] = handler end
_G.SendNUIMessage = function(message) sent[#sent + 1] = message end
_G.Kora = { lang = function(key) return key end, notify = { send = function() end }, cache = {} }

local function load()
    registered, serverCalls, sent = {}, {}, {}
    _G.KoraPhone = {
        State = { open = false, quiet = false, Public = function() return {} end },
        ServerCallback = function(name, payload, done)
            serverCalls[#serverCalls + 1] = { name = name, payload = payload }
            done(KoraPhone.nextResult)
        end,
        Close = function() end,
    }
    dofile('client/nui.lua')
end

local function call(name, data)
    local reply
    registered[name](data, function(result) reply = result end)
    return reply
end

test('one callback is registered per route in routes.json', function()
    load()
    local routes = decode(routesJson)
    assert(#routes > 60, 'routes.json should list the server routes')
    for _, route in ipairs(routes) do assert(registered[route.nui], route.nui) end
    equal(#KoraPhone.Routes, #routes)
end)

test('a server route forwards a table payload and relays the result', function()
    load()
    KoraPhone.nextResult = { ok = true, data = 1 }
    local reply = call('contacts:list', { a = 1 })
    equal(serverCalls[1].name, 'kora_phone:server:getContacts')
    equal(serverCalls[1].payload.a, 1)
    equal(reply.data, 1)
end)

test('a non-table payload becomes an empty table', function()
    load()
    KoraPhone.nextResult = { ok = true }
    call('contacts:list', 'nope')
    equal(type(serverCalls[1].payload), 'table')
end)

test('a malformed server reply is turned into an error instead of hanging', function()
    load()
    KoraPhone.nextResult = nil
    equal(call('contacts:list', {}).error, 'INVALID_SERVER_RESPONSE')
end)

test('the quiet flag is read through the shared guard', function()
    load()
    call('quiet', { quiet = true })
    equal(KoraPhone.State.quiet, true)
    call('quiet', 'garbage')
    equal(KoraPhone.State.quiet, false)
end)

test('waypoint rejects invalid coordinates', function()
    load()
    _G.SetNewWaypoint = function() error('must not be called') end
    local reply = call('waypoint', { x = 'a', y = 1 })
    equal(reply.ok, false)
    equal(reply.error.code, 'INVALID_INPUT')
end)

test('calls:setMuted drives kora_voice setCallMuted and passes the reason through', function()
    load()
    local calls, answer = {}, { true }
    _G.exports = { kora_voice = { setCallMuted = function(_, muted)
        calls[#calls + 1] = muted
        return table.unpack(answer)
    end } }
    _G.Kora.print = { warn = function() end }
    dofile('client/integrations/voice.lua')

    local reply = call('calls:setMuted', { muted = true })
    equal(reply.ok, true)
    equal(calls[1], true)
    equal(KoraPhone.Voice.muted, true)

    answer = { false, 'not_in_call' }
    reply = call('calls:setMuted', { muted = true })
    equal(reply.ok, false)
    equal(reply.error, 'not_in_call')
    equal(KoraPhone.Voice.muted, false)

    _G.exports.kora_voice.setCallMuted = function() error('boom') end
    reply = call('calls:setMuted', { muted = false })
    equal(reply.ok, false)
    equal(reply.error, 'CALL_MUTE_FAILED')
end)

test('calls:setSpeaker is an honest presentation flag', function()
    load()
    _G.exports = { kora_voice = {} }
    dofile('client/integrations/voice.lua')
    local reply = call('calls:setSpeaker', { speaker = true })
    equal(reply.ok, true)
    equal(KoraPhone.Voice.speaker, true)
end)

print(('client-nui: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
