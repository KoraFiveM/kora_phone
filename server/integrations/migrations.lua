QBPhone = QBPhone or {}
local Migrations = {}
QBPhone.Migrations = Migrations

-- Applies the .sql files listed in fxmanifest.lua (`migration '...'` lines, in order) when the resource starts,
-- and remembers what it has done in `phone_migrations`, so each statement runs once and a restart runs nothing.
--
--  * A statement is recorded only after it succeeded, so a run that stopped half way resumes at the failed statement.
--  * A database that was set up by hand from these same files is adopted: "already exists" style errors count as done.
--  * Anything else is a real failure: it is printed and the resource stops, rather than running on a half-built schema.
--  * Set Config.Server.AutoMigrate = false to import the files yourself instead.

local TRACK_TABLE = [[
    CREATE TABLE IF NOT EXISTS `phone_migrations` (
      `name` VARCHAR(80) NOT NULL,
      `step` INT UNSIGNED NOT NULL,
      `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`name`, `step`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

-- Error text that means "this was already done" (a hand-imported database, or a step that ran before a crash).
local ALREADY_DONE = {
    'ER_DUP_FIELDNAME', 'ER_DUP_KEYNAME', 'ER_TABLE_EXISTS_ERROR', 'ER_FK_DUP_NAME',
    'Duplicate column name', 'Duplicate key name', 'already exists', 'Duplicate foreign key constraint name', 'errno: 121',
}

local function alreadyDone(err)
    err = tostring(err)
    for _, needle in ipairs(ALREADY_DONE) do if err:find(needle, 1, true) then return true end end
    return false
end

-- Splits a .sql file into statements. Understands -- and /* */ comments and quoted strings (a ; inside quotes
-- does not end a statement).
function Migrations.split(sql)
    local statements, buffer, quote = {}, {}, nil
    local i, n = 1, #sql
    local function flush()
        local statement = table.concat(buffer):match('^%s*(.-)%s*$')
        if statement ~= '' then statements[#statements + 1] = statement end
        buffer = {}
    end
    while i <= n do
        local c = sql:sub(i, i)
        if quote then
            buffer[#buffer + 1] = c
            if c == '\\' and quote ~= '`' then buffer[#buffer + 1] = sql:sub(i + 1, i + 1); i = i + 1
            elseif c == quote then quote = nil end
        elseif c == "'" or c == '"' or c == '`' then
            quote = c; buffer[#buffer + 1] = c
        elseif (c == '-' and sql:sub(i, i + 1) == '--' and (sql:sub(i + 2, i + 2):match('%s') or i + 1 == n)) or c == '#' then
            i = (sql:find('\n', i, true) or n) - 1
            buffer[#buffer + 1] = '\n'
        elseif c == '/' and sql:sub(i, i + 1) == '/*' then
            local finish = sql:find('*/', i + 2, true)
            i = finish and finish + 1 or n
            buffer[#buffer + 1] = ' '
        elseif c == ';' then
            flush()
        else
            buffer[#buffer + 1] = c
        end
        i = i + 1
    end
    flush()
    return statements
end

function Migrations.files()
    local resource, files = GetCurrentResourceName(), {}
    for index = 0, (GetNumResourceMetadata(resource, 'migration') or 0) - 1 do
        files[#files + 1] = GetResourceMetadata(resource, 'migration', index)
    end
    return files
end

-- Returns true when the schema is up to date, or false plus a reason.
function Migrations.run()
    if Config.Server.AutoMigrate == false then return true end
    local resource = GetCurrentResourceName()
    local ok, err = pcall(MySQL.query.await, TRACK_TABLE)
    if not ok then return false, 'could not create phone_migrations: ' .. tostring(err) end
    local done = {}
    for _, row in ipairs(MySQL.query.await('SELECT `name`, `step` FROM `phone_migrations`') or {}) do
        done[row.name .. ':' .. row.step] = true
    end
    local applied, adopted = 0, 0
    for _, path in ipairs(Migrations.files()) do
        local name = path:match('([^/\\]+)$')
        local text = LoadResourceFile(resource, path)
        if not text then return false, ('migration file %s is listed in fxmanifest.lua but cannot be read'):format(path) end
        if name == '012_handsets.sql' or name == '013_legacy_qb_phone.sql' then
            local migrated, reason = QB.sql.migrateFiles(resource,{{version=tonumber(name:sub(1,3)),name=name:sub(5,-5),file=path}})
            if not migrated then return false, tostring(reason) end
            goto continue
        end
        for step, statement in ipairs(Migrations.split(text)) do
            if not done[name .. ':' .. step] then
                local success, message = pcall(MySQL.query.await, statement)
                if success then
                    applied = applied + 1
                elseif alreadyDone(message) then
                    adopted = adopted + 1
                else
                    return false, ('%s, statement %d failed: %s'):format(name, step, tostring(message))
                end
                MySQL.query.await('INSERT IGNORE INTO `phone_migrations` (`name`, `step`) VALUES (?, ?)', { name, step })
            end
        end
        ::continue::
    end
    if applied > 0 or adopted > 0 then
        print(('[qbphone] database ready (%d statements applied, %d already present)'):format(applied, adopted))
    end
    return true
end
