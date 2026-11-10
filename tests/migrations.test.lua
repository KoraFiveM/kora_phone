-- Run outside FiveM with: lua tests/migrations.test.lua
-- Tests the startup schema setup against a stubbed Kora.sql.ensureTables, and that server/schema.lua declares every table.

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n")
    else failed = failed + 1; io.stderr:write("FAIL ", name, ": ", tostring(err), "\n") end
end
local function equal(actual, expected) assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual))) end

local script = arg and arg[0] or "tests/migrations.test.lua"
local root = script:gsub("[\\/]tests[\\/]migrations%.test%.lua$", "")
if root == script then root = "." end

local stub = { calls = 0, spec = nil, reports = {}, err = nil, throw = nil }
local printed = {}
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
Kora = { sql = { NULL = '\0kora_sql:null\0', ensureTables = function(spec)
    stub.calls = stub.calls + 1; stub.spec = spec
    if stub.throw then error(stub.throw) end
    if stub.err then return nil, stub.err end
    return stub.reports
end } }
Config = { Server = {} }
dofile(root .. "/server/schema.lua")
dofile(root .. "/server/integrations/schema_setup.lua")
local Migrations = KoraPhone.SchemaSetup
local function reset() stub.calls, stub.spec, stub.reports, stub.err, stub.throw, printed = 0, nil, {}, nil, nil, {} end

test("the schema declares all 33 tables, each once", function()
    equal(#KoraPhoneSchema, 33)
    local seen = {}
    for _, spec in ipairs(KoraPhoneSchema) do assert(not seen[spec.name], 'duplicate ' .. spec.name); seen[spec.name] = true end
    for _, name in ipairs({ 'phone_devices', 'phone_messages', 'phone_calls', 'phone_economy_audit', 'phone_social_posts', 'phone_items',
        'phone_mail', 'phone_handsets', 'phone_sims', 'phone_call_hidden', 'phone_legacy_mail', 'phone_legacy_transactions' }) do
        assert(seen[name], 'missing ' .. name)
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
    equal(Migrations.run(), true); equal(stub.calls, 1); assert(stub.spec == KoraPhoneSchema)
end)
test("created tables are summarised and warnings are logged", function()
    reset(); stub.reports = { { table = 'phone_devices', created = true }, { table = 'phone_mail', warnings = { 'type differs' } } }
    equal(Migrations.run(), true)
    local out = table.concat(printed, '\n')
    assert(out:find('1 tables created', 1, true), out); assert(out:find('phone_mail', 1, true) and out:find('type differs', 1, true), out)
end)
test("an ensureTables error stops the run with the reason", function()
    reset(); stub.err = 'boom'
    local ok, reason = Migrations.run()
    equal(ok, false); assert(reason:find('boom', 1, true), reason)
end)
test("a thrown error is reported, not propagated", function()
    reset(); stub.throw = 'kaput'
    local ok, reason = Migrations.run()
    equal(ok, false); assert(reason:find('kaput', 1, true), reason)
end)
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end