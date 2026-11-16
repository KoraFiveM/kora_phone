-- Run outside FiveM with: lua tests/schema.test.lua
-- Tests the startup schema setup against a stubbed Kora.sql.ensureTables, and that server/schema.lua declares every table.

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n")
    else failed = failed + 1; io.stderr:write("FAIL ", name, ": ", tostring(err), "\n") end
end
local function equal(actual, expected) assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual))) end

local script = arg and arg[0] or "tests/schema.test.lua"
local root = script:gsub("[\\/]tests[\\/]schema%.test%.lua$", "")
if root == script then root = "." end

local stub = { calls = 0, spec = nil, reports = {}, err = nil, throw = nil }
local printed = {}
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
Kora = { logging = setmetatable({}, { __index = function(_, level) return function(event, message, fields)
    printed[#printed + 1] = level .. ' ' .. event .. ' ' .. message .. ' ' .. table.concat((function() local t = {} for k, v in pairs(fields or {}) do t[#t + 1] = k .. '=' .. tostring(v) end return t end)(), ' ')
    return true
end end }), sql = { NULL = '\0kora_sql:null\0', ensureTables = function(spec)
    stub.calls = stub.calls + 1; stub.spec = spec
    if stub.throw then error(stub.throw) end
    if stub.err then return nil, stub.err end
    return stub.reports
end } }
Config = { Server = {} }
dofile(root .. "/server/schema.lua")
dofile(root .. "/server/sdk/schema.lua")
dofile(root .. "/server/integrations/schema_setup.lua")
local Setup = KoraPhone.SchemaSetup
local function reset() stub.calls, stub.spec, stub.reports, stub.err, stub.throw, printed = 0, nil, {}, nil, nil, {} end

test("the schema declares all 31 core tables, each once", function()
    equal(#KoraPhoneSchema, 31)
    local seen = {}
    for _, spec in ipairs(KoraPhoneSchema) do assert(not seen[spec.name], 'duplicate ' .. spec.name); seen[spec.name] = true end
    for _, name in ipairs({ 'phone_devices', 'phone_messages', 'phone_calls', 'phone_bank_history', 'phone_social_posts', 'phone_items',
        'phone_mail', 'phone_handsets', 'phone_sims', 'phone_call_hidden', 'phone_system_mail', 'phone_system_activity' }) do
        assert(seen[name], 'missing ' .. name)
    end
end)
test("the SDK schema declares phone_app_storage once", function()
    local count = 0
    for _, spec in ipairs(KoraPhoneSdkSchema) do
        if spec.name == 'phone_app_storage' then count = count + 1 end
    end
    equal(count, 1)
end)
test("no migration or conversion leftovers are declared", function()
    for _, spec in ipairs(KoraPhoneSchema) do
        assert(spec.name ~= 'phone_migration_issues' and spec.name ~= 'phone_legacy_claims', 'leftover table ' .. spec.name)
    end
end)
test("foreign key parents are listed before their children", function()
    local seen = {}
    for _, spec in ipairs(KoraPhoneSchema) do
        seen[spec.name] = true
        for _, fk in ipairs(spec.foreign or {}) do assert(seen[fk.ref_table], spec.name .. ' references ' .. fk.ref_table .. ' before it exists') end
    end
end)
test("the setup passes the schema to ensureTables once", function()
    reset()
    equal(Setup.run(), true); equal(stub.calls, 1)
    -- Core tables first (SDK tables reference phone_devices), then the SDK tables, in one combined call.
    equal(#stub.spec, #KoraPhoneSchema + #KoraPhoneSdkSchema)
    equal(stub.spec[1].name, KoraPhoneSchema[1].name)
    equal(stub.spec[#KoraPhoneSchema + 1].name, KoraPhoneSdkSchema[1].name)
end)
test("created tables are summarised and warnings are logged", function()
    reset(); stub.reports = { { table = 'phone_devices', created = true }, { table = 'phone_mail', warnings = { 'type differs' } } }
    equal(Setup.run(), true)
    local out = table.concat(printed, '\n')
    assert(out:find('info schema.database_ready', 1, true) and out:find('tablesCreated=1', 1, true), out); assert(out:find('warn schema.setup_warning', 1, true), out); assert(out:find('phone_mail', 1, true) and out:find('type differs', 1, true), out)
end)
test("an ensureTables error stops the run with the reason", function()
    reset(); stub.err = 'boom'
    local ok, reason = Setup.run()
    equal(ok, false); assert(reason:find('boom', 1, true), reason)
end)
test("a thrown error is reported, not propagated", function()
    reset(); stub.throw = 'kaput'
    local ok, reason = Setup.run()
    equal(ok, false); assert(reason:find('kaput', 1, true), reason)
end)
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end