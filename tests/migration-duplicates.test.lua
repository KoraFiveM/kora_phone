-- Run from the resource root: lua tests/migration-duplicates.test.lua
Config = { Server = {} }
local recorded, attempts, failure = {}, 0, nil
function GetCurrentResourceName() return 'kora_phone-stevie' end
function GetNumResourceMetadata() return 1 end
function GetResourceMetadata() return 'migrations/004_media.sql' end
function LoadResourceFile(_, path)
    local file = assert(io.open(path))
    local text = file:read('*a'); file:close(); return text
end
MySQL = { query = { await = function(sql, params)
    if sql:find('CREATE TABLE IF NOT EXISTS `phone_migrations`', 1, true) then return {} end
    if sql:find('SELECT `name`, `step`', 1, true) then
        local rows = {}
        for step in pairs(recorded) do rows[#rows + 1] = { name = '004_media.sql', step = step } end
        return rows
    end
    if sql:find('INSERT IGNORE INTO `phone_migrations`', 1, true) then
        recorded[params[2]] = true; return {}
    end
    attempts = attempts + 1
    if sql:find('ADD CONSTRAINT', 1, true) and failure then error(failure) end
    return {}
end } }
dofile('server/integrations/migrations.lua')
for _, message in ipairs({
    "Duplicate FOREIGN KEY constraint name ''",
    "Duplicate foreign key constraint name 'fk_phone_contacts_avatar_media'",
    'ER_FK_DUP_NAME',
}) do
    recorded, attempts, failure = {}, 0, message
    assert(QBPhone.Migrations.run())
    assert(recorded[1] and recorded[2] and recorded[3])
    assert(attempts == 3)
    attempts = 0
    assert(QBPhone.Migrations.run())
    assert(attempts == 0, 'adopted statements must not run again')
end
recorded, attempts, failure = {}, 0, 'ER_PARSE_ERROR: invalid SQL'
local ok, reason = QBPhone.Migrations.run()
assert(not ok and reason:find('004_media.sql, statement 2 failed', 1, true))
assert(recorded[1] and not recorded[2] and not recorded[3])
print('PASS migration duplicates: case variants adopted, restarts skip, real errors stop')
