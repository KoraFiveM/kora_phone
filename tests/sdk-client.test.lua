-- lua tests/sdk-client.test.lua  (from the resource root): client registry + app:event delivery
local H = dofile((arg and arg[0] or 'tests/x'):gsub('[^/\\]+$', '') .. 'sdk-helper.lua')
local test, equal = H.test, H.equal

local sent, netHandlers, natives
_G.SendNUIMessage = function(message) sent[#sent + 1] = message end
_G.RegisterNetEvent = function(name, fn) netHandlers[name] = fn end
_G.exports = { kora_core = { getPlayerData = function() return { job = { name = 'police', grade = { level = 4 } } } end } }

local function load()
    sent, netHandlers, natives = {}, {}, {}
    _G.KoraPhone = { Notifications = { Native = function(t, b, u) natives[#natives + 1] = { t, b, u } return true end } }
    dofile(H.root .. '/client/sdk/registry.lua')
    dofile(H.root .. '/client/sdk/events.lua')
end
load()
local Registry, Events = KoraPhone.SDK.ClientRegistry, KoraPhone.SDK.Events

test('server events become app:event NUI messages', function()
    netHandlers['kora_phone:client:appEvent']('demo-app', 'tick', { n = 1 })
    local message = sent[#sent]
    equal(message.type, 'app:event')
    equal(message.app, 'demo-app')
    equal(message.name, 'tick')
    equal(message.data.n, 1)
end)

test('malformed events are dropped', function()
    local before = #sent
    equal(Events.deliver(5, 'tick'), false)
    equal(Events.deliver('a', 'bad name'), false)
    equal(Events.deliver('a', ('n'):rep(49)), false)
    equal(Events.deliver('a', nil), false)
    equal(#sent, before)
end)

test('appNotify shows a native phone alert', function()
    netHandlers['kora_phone:client:appNotify']('demo-app', 'Demo', 'Title', 'Body')
    equal(natives[1][1], 'Title')
    equal(natives[1][2], 'Body')
    equal(Events.notify('a', 'A', 5, 'b'), false)
end)

test('registry validates, lists in SDK shape and notifies the UI', function()
    equal(select(2, Registry.register({ identifier = '' }, 'r')), 'INVALID_APP')
    equal(select(2, Registry.register({ identifier = 'x' }, 'r')), 'INVALID_UI')
    equal(Registry.register({ identifier = 'b-app', ui = '@res/ui/index.html', resource = 'res' }, 'r'), true)
    Registry.register({ identifier = 'a-app', ui = 'ui/index.html' }, 'inv')
    local list = Registry.list()
    equal(list[1].id, 'a-app')
    equal(list[1].resource, 'inv')
    equal(list[2].ui, 'ui/index.html')
    equal(sent[#sent].type, 'customRegistry')
end)

test('hooks, sendMessage, unregister and removeByResource', function()
    local opened = 0
    Registry.register({ identifier = 'h-app', ui = 'a.html', resource = 'hres', onOpen = function() opened = opened + 1 end }, 'x')
    Registry.fire('h-app', 'onOpen')
    Registry.fire('h-app', 'onClose')
    Registry.fire('ghost', 'onOpen')
    equal(opened, 1)
    equal(Registry.sendMessage('h-app', 'hi'), true)
    equal(sent[#sent].type, 'customMessage')
    equal(Registry.removeByResource('hres'), true)
    equal(Registry.removeByResource('hres'), false)
    equal(select(2, Registry.unregister('h-app')), 'NOT_FOUND')
    equal(Registry.unregister({ identifier = 'a-app' }), true)
end)

test('job filter supports arrays and grades', function()
    -- one-based grades: the player is grade level 4, spec.grade is the minimum
    equal(Registry.jobMatches({ name = 'police', grade = 4 }), true)
    equal(Registry.jobMatches({ name = 'police', grade = 5 }), false)
    equal(Registry.jobMatches({ 'ems', 'police' }), true)
    equal(Registry.jobMatches('ems'), false)
    equal(Registry.jobMatches(nil), true)
end)

test('html() reads the registered page from its own resource and nothing else', function()
    local files = { ['ui/index.html'] = '<html></html>', ['ui/big.html'] = string.rep('x', Registry.MAX_HTML_BYTES + 1) }
    _G.LoadResourceFile = function(resource, path) return resource == 'lb_res' and files[path] or nil end
    local function add(id, ui) Registry.register({ identifier = id, name = id, ui = ui, resource = 'lb_res' }, 'lb_res') end
    add('page', 'lb_res/ui/index.html'); add('url', 'https://example.com/x.html'); add('up', '../secret.html')
    add('big', 'ui/big.html'); add('script', 'ui/app.js')
    equal(Registry.html('page'), '<html></html>')
    equal(Registry.html('url'), nil)
    equal(Registry.html('up'), nil)
    equal(Registry.html('big'), nil)
    equal(Registry.html('script'), nil)
    equal(Registry.html('ghost'), nil)
    equal(Registry.html({ identifier = 'page' }), nil)
end)

H.finish('sdk-client')
