-- Run outside FiveM with: lua tests/migrations.test.lua
-- Tests the startup migration runner against a fake database: it must run every file once, remember that,
-- run nothing on the next start, resume after a failure, and adopt a database that was imported by hand.

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

-- ---- fake FiveM + oxmysql
local manifest = io.open(root .. "/fxmanifest.lua"):read("*a")
local listed = {}
for path in manifest:gmatch("migration%s+'([^']+)'") do listed[#listed + 1] = path end
function GetCurrentResourceName() return 'kora_phone' end
function GetNumResourceMetadata(_, key) return key == 'migration' and #listed or 0 end
function GetResourceMetadata(_, key, index) return key == 'migration' and listed[index + 1] or nil end
function LoadResourceFile(_, path) local f = io.open(root .. "/" .. path); if not f then return nil end local s = f:read("*a"); f:close(); return s end

local db = { tracked = {}, executed = {}, failOn = nil, alreadyOn = nil, printed = {} }
local function reset() db.tracked, db.executed, db.failOn, db.alreadyOn, db.printed = {}, {}, nil, nil, {} end
_G.print = function(...) db.printed[#db.printed + 1] = table.concat({ ... }, ' ') end
MySQL = { query = { await = function(sql, params)
    if sql:find('CREATE TABLE IF NOT EXISTS `phone_migrations`', 1, true) then return {} end
    if sql:find('SELECT `name`, `step` FROM `phone_migrations`', 1, true) then
        local rows = {}
        for key in pairs(db.tracked) do local name, step = key:match('^(.*):(%d+)$'); rows[#rows + 1] = { name = name, step = tonumber(step) } end
        return rows
    end
    if sql:find('INSERT IGNORE INTO `phone_migrations`', 1, true) then db.tracked[params[1] .. ':' .. params[2]] = true; return {} end
    db.executed[#db.executed + 1] = sql
    if db.failOn and #db.executed == db.failOn then error('ER_PARSE_ERROR: you have an error in your SQL syntax') end
    if db.alreadyOn and sql:find(db.alreadyOn, 1, true) then error("ER_DUP_FIELDNAME: Duplicate column name 'pin_hash'") end
    return {}
end } }

-- Migrations 012 and 013 run through kora_sql's checksum-owned runner; model it with the same fake database:
-- every statement runs once, is remembered, and a failure stops that file and reports the reason.
Kora = { sql = { migrateFiles = function(resource, entries)
    for _, entry in ipairs(entries) do
        local name = ('%03d_%s.sql'):format(entry.version, entry.name)
        for step, statement in ipairs(QBPhone.Migrations.split(LoadResourceFile(resource, entry.file))) do
            if not db.tracked[name .. ':' .. step] then
                db.executed[#db.executed + 1] = statement
                if db.failOn and #db.executed == db.failOn then return false, name .. ' failed' end
                db.tracked[name .. ':' .. step] = true
            end
        end
    end
    return true
end } }

Config = { Server = {} }
dofile(root .. "/server/integrations/migrations.lua")
local Migrations = QBPhone.Migrations

-- ---- the splitter
test("split handles comments, quotes and trailing statements", function()
    local parts = Migrations.split("-- header; not a statement\nCREATE TABLE a (x INT); /* note; */ ALTER TABLE a ADD y VARCHAR(5) DEFAULT 'a;b'\n; -- end\nDROP TABLE `we;ird`;")
    equal(#parts, 3)
    equal(parts[1], "CREATE TABLE a (x INT)")
    equal(parts[2], "ALTER TABLE a ADD y VARCHAR(5) DEFAULT 'a;b'")
    equal(parts[3], "DROP TABLE `we;ird`")
end)
test("split ignores empty input and stray semicolons", function() equal(#Migrations.split(";;\n  ;"), 0); equal(#Migrations.split(""), 0) end)
test("every migration file splits into real statements", function()
    assert(#listed >= 11, 'fxmanifest lists the migrations')
    for _, path in ipairs(listed) do
        local text = assert(LoadResourceFile(nil, path), path .. ' is readable')
        local parts = Migrations.split(text)
        assert(#parts >= 1, path .. ' has statements')
        for _, statement in ipairs(parts) do
            assert(statement:match('^CREATE TABLE') or statement:match('^ALTER TABLE') or statement:match('^CREATE INDEX') or statement:match('^INSERT'), path .. ': unexpected statement start: ' .. statement:sub(1, 40))
            assert(not statement:find(';', 1, true), path .. ': a statement still contains a semicolon')
        end
    end
end)

-- ---- the runner
local function totalStatements()
    local n = 0
    for _, path in ipairs(listed) do n = n + #Migrations.split(LoadResourceFile(nil, path)) end
    return n
end

test("the first start runs every statement, in file order", function()
    reset()
    local ok = Migrations.run()
    equal(ok, true); equal(#db.executed, totalStatements())
    assert(db.executed[1]:find('phone_devices', 1, true), 'the initial schema goes first')
    local newest = Migrations.split(LoadResourceFile(nil, listed[#listed]))
    equal(db.executed[#db.executed], newest[#newest], 'the newest migration goes last')
end)
test("the next start runs nothing at all", function()
    reset(); Migrations.run()
    local first = #db.executed
    db.executed = {}
    equal(Migrations.run(), true); equal(#db.executed, 0)
    assert(first > 0)
end)
test("a new migration file added later runs alone", function()
    reset(); Migrations.run(); db.executed = {}
    -- pretend the last file had not been applied yet
    local last = listed[#listed]:match('([^/]+)$')
    for key in pairs(db.tracked) do if key:find(last, 1, true) == 1 then db.tracked[key] = nil end end
    equal(Migrations.run(), true)
    equal(#db.executed, #Migrations.split(LoadResourceFile(nil, listed[#listed])))
end)
test("a failing statement stops the run and names the file and step", function()
    reset(); db.failOn = 3
    local ok, reason = Migrations.run()
    equal(ok, false); assert(reason:find('001_initial.sql', 1, true) and reason:find('statement 3', 1, true), reason)
    equal(#db.executed, 3)
end)
test("after a failure the next start resumes at the failed statement, not the beginning", function()
    reset(); db.failOn = 3; Migrations.run()
    db.failOn = nil; db.executed = {}
    equal(Migrations.run(), true)
    equal(#db.executed, totalStatements() - 2)          -- steps 1 and 2 were recorded
    assert(db.executed[1] == Migrations.split(LoadResourceFile(nil, listed[1]))[3], 'starts at the statement that failed')
end)
test("a hand-imported database is adopted: 'already exists' errors count as done", function()
    reset(); db.alreadyOn = 'pin_hash'
    equal(Migrations.run(), true)
    db.executed = {}
    equal(Migrations.run(), true); equal(#db.executed, 0)   -- and it is remembered
    assert(table.concat(db.printed, '\n'):find('already present', 1, true), 'the summary says so')
end)
test("AutoMigrate = false leaves the database alone", function()
    reset(); Config.Server.AutoMigrate = false
    equal(Migrations.run(), true); equal(#db.executed, 0); equal(next(db.tracked), nil)
    Config.Server.AutoMigrate = nil
end)
test("a migration listed in the manifest but missing on disk is a clear failure", function()
    reset(); listed[#listed + 1] = 'migrations/999_missing.sql'
    local ok, reason = Migrations.run()
    equal(ok, false); assert(reason:find('999_missing.sql', 1, true), reason)
    listed[#listed] = nil
end)

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
