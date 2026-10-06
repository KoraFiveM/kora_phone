-- Run outside FiveM with: lua tests/customapps.test.lua
-- Stubs the FiveM natives client/customapps.lua touches, then exercises the
-- native export and each phone's alias mapping (field renames, resource
-- resolution, the "@resource/" path prefix High Phone uses).

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write("PASS ", name, "\n")
    else
        failed = failed + 1
        io.stderr:write("FAIL ", name, ": ", tostring(err), "\n")
    end
end

local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local sent, exportsTable, handlers

local script = arg and arg[0] or "tests/customapps.test.lua"
local root = script:gsub("[\\/]tests[\\/]customapps%.test%.lua$", "")
if root == script then root = "." end

local playerJob, natives

local function loadCustomApps()
    sent, exportsTable, handlers, natives = {}, {}, {}, {}
    _G.SendNUIMessage = function(msg) sent[#sent + 1] = msg end
    _G.GetInvokingResource = function() return 'addon-resource' end
    _G.exports = setmetatable({ qbcore = { getPlayerData = function()
        local job = playerJob and { name = playerJob.name, grade = playerJob.grade }
        if job and type(job.grade) == 'table' then
            job.grade = { level = job.grade.level + 1 }
        end
        return { job = job }
    end } }, { __call = function(_, name, fn) exportsTable[name] = fn end })
    _G.AddEventHandler = function(event, fn) handlers[event] = fn end
    _G.QBPhone = {
        Notifications = { Native = function(title, body, urgent) natives[#natives + 1] = { title = title, body = body, urgent = urgent }; return true end },
    }
    dofile(root .. "/client/customapps.lua")
end

local function findApp(identifier)
    for _, app in ipairs(QBPhone.CustomApps.List()) do
        if app.identifier == identifier then return app end
    end
end

local function alias(event, ...)
    local captured
    handlers[event](function(fn) captured = fn end)
    return captured(...)
end

loadCustomApps()

test("native RegisterApp defaults resource to the invoking resource", function()
    equal(exportsTable['RegisterApp']({ identifier = 'native-app', name = 'Native', ui = 'ui/index.html' }), true)
    equal(findApp('native-app').resource, 'addon-resource')
end)

test("lb-phone AddCustomApp registers with its own identifier field", function()
    equal(alias('__cfx_export_lb-phone_AddCustomApp', { identifier = 'lb-app', name = 'LB App', ui = 'ui/index.html' }), true)
    equal(findApp('lb-app').name, 'LB App')
end)

test("17mov_Phone AddApplication maps name/label/resourceName and preInstalled", function()
    alias('__cfx_export_17mov_Phone_AddApplication', { name = 'mov-app', label = 'Movement App', ui = 'ui/index.html', resourceName = 'mov-resource', preInstalled = true })
    local app = findApp('mov-app')
    equal(app.name, 'Movement App')
    equal(app.resource, 'mov-resource')
    equal(app.defaultApp, true)
end)

test("High Phone addApplication takes the identifier as its own argument, name/description from a locale table, and strips \"@resource/\"", function()
    alias('__cfx_export_high-phone_addApplication', 'high-app', { preAdded = true, externalUrl = '@addon-resource/ui/dist/index.html' }, { en = { label = 'High App', description = 'A High Phone app' } })
    local app = findApp('high-app')
    equal(app.name, 'High App')
    equal(app.description, 'A High Phone app')
    equal(app.ui, 'ui/dist/index.html')
    equal(app.defaultApp, true)
end)

test("YSeries AddCustomApp/RemoveCustomApp key off `key`, not `identifier`", function()
    alias('__cfx_export_yseries_AddCustomApp', { key = 'ys-app', name = 'YSeries App', ui = 'ui/dist/index.html' })
    equal(findApp('ys-app') ~= nil, true)
    equal(alias('__cfx_export_yseries_RemoveCustomApp', 'ys-app'), true)
    equal(findApp('ys-app'), nil)
end)

test("lb-phone SendNotification and High Phone sendNotification route to a native alert instead of throwing", function()
    equal(alias('__cfx_export_lb-phone_SendNotification', { title = 'noted_crimeapp', content = 'A robbery was reported nearby' }), true)
    equal(natives[#natives].title, 'noted_crimeapp')
    equal(natives[#natives].body, 'A robbery was reported nearby')
    equal(alias('__cfx_export_high-phone_sendNotification', { title = 'High App', content = 'Hello' }), true)
    equal(natives[#natives].title, 'High App')
end)

test("onResourceStop removes only that resource's apps", function()
    handlers['onResourceStop']('mov-resource')
    equal(findApp('mov-app'), nil)
    equal(findApp('lb-app') ~= nil, true)
end)

test("High Phone removeApplication is a plausible, harmless alias", function()
    alias('__cfx_export_high-phone_addApplication', 'high-remove-me', { externalUrl = 'ui/index.html' }, {})
    equal(findApp('high-remove-me') ~= nil, true)
    equal(alias('__cfx_export_high-phone_removeApplication', 'high-remove-me'), true)
    equal(findApp('high-remove-me'), nil)
end)

test("lb-phone AddCustomApp carries price through to the listing", function()
    alias('__cfx_export_lb-phone_AddCustomApp', { identifier = 'priced-app', ui = 'ui/index.html', price = 500 })
    equal(findApp('priced-app').price, 500)
end)

test("a job-gated app is hidden from a player without that job", function()
    playerJob = { name = 'ambulance', grade = 0 }
    alias('__cfx_export_sd-phone_addCustomApp', { identifier = 'police-app', ui = 'ui/index.html', job = 'police' })
    equal(findApp('police-app'), nil)
    playerJob = { name = 'police', grade = 0 }
    equal(findApp('police-app') ~= nil, true)
    playerJob = nil
end)

test("a job-gated app respects a minimum grade", function()
    alias('__cfx_export_17mov_Phone_AddApplication', { name = 'chief-app', ui = 'ui/index.html', job = { name = 'police', grade = 3 } })
    playerJob = { name = 'police', grade = 1 }
    equal(findApp('chief-app'), nil)
    playerJob = { name = 'police', grade = 3 }
    equal(findApp('chief-app') ~= nil, true)
    playerJob = nil
end)

io.write(("\n%d passed, %d failed (%d NUI messages sent)\n"):format(passed, failed, #sent))
if failed > 0 then os.exit(1) end
