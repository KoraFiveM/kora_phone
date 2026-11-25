-- lua tests/sdk-storage.test.lua  (from the resource root)
local H = dofile((arg and arg[0] or 'tests/x'):gsub('[^/\\]+$', '') .. 'sdk-helper.lua')
local test, equal = H.test, H.equal

H.newServer()
local Storage, Repo = KoraPhone.SDK.Storage, KoraPhone.SDK.StorageRepository

-- In-memory stand-in for the SQL layer, keyed by statement shape.
local rows, statements
local function resetSql()
    rows, statements = {}, {}
    local function id(d, a, k) return d .. '|' .. a .. '|' .. k end
    Kora.sql.scalar = function(sql, p)
        statements[#statements + 1] = sql
        local row = rows[id(p[1], p[2], p[3])]
        if sql:find('LENGTH') then return row and #row or nil end
        return row
    end
    Kora.sql.single = function(sql, p)
        statements[#statements + 1] = sql
        local count, bytes = 0, 0
        for key, value in pairs(rows) do
            if key:find('^' .. p[1] .. '|' .. p[2] .. '|') then count, bytes = count + 1, bytes + #value end
        end
        return { keyCount = count, totalBytes = bytes }
    end
    Kora.sql.execute = function(sql, p)
        statements[#statements + 1] = sql
        rows[id(p[1], p[2], p[3])] = p[4]
        return { affectedRows = 1 }
    end
    Kora.sql.update = function(sql, p)
        statements[#statements + 1] = sql
        local existed = rows[id(p[1], p[2], p[3])] ~= nil
        rows[id(p[1], p[2], p[3])] = nil
        return existed and 1 or 0
    end
end

test('set then get round-trips JSON values', function()
    resetSql()
    assert(Storage.set(1, 'app', 'k', { a = 1, list = { 1, 2 } }))
    local value = Storage.get(1, 'app', 'k')
    equal(value.a, 1)
    equal(#value.list, 2)
    equal(Storage.get(1, 'app', 'missing'), nil)
end)

test('storage is isolated per device and per app', function()
    resetSql()
    Storage.set(1, 'app', 'k', 'one')
    equal(Storage.get(2, 'app', 'k'), nil)
    equal(Storage.get(1, 'other', 'k'), nil)
end)

test('keys are validated', function()
    resetSql()
    for _, key in ipairs({ '', ('k'):rep(65), 'has space', 'a/b', 5 }) do
        local ok, err = Storage.set(1, 'app', key, 1)
        equal(ok, nil)
        equal(err.error.code, 'INVALID_INPUT')
    end
    assert(Storage.set(1, 'app', ('k'):rep(64), 1))
    assert(Storage.set(1, 'app', 'a_b.c:d-e', 1))
end)

test('a value over 16 KB is rejected, exactly 16 KB is allowed', function()
    resetSql()
    local ok, err = Storage.set(1, 'app', 'big', ('x'):rep(16 * 1024))
    equal(ok, nil)
    equal(err.error.code, 'INVALID_INPUT')
    assert(Storage.set(1, 'app', 'edge', ('x'):rep(16 * 1024 - 2)))
end)

test('nil and non-JSON values are rejected', function()
    resetSql()
    equal(select(2, Storage.set(1, 'app', 'k', nil)).error.code, 'INVALID_INPUT')
    equal(select(2, Storage.set(1, 'app', 'k', function() end)).error.code, 'INVALID_INPUT')
end)

test('65th key is refused with CONFLICT but overwriting an existing key still works', function()
    resetSql()
    for i = 1, 64 do assert(Storage.set(1, 'app', 'k' .. i, i)) end
    local ok, err = Storage.set(1, 'app', 'k65', 1)
    equal(ok, nil)
    equal(err.error.code, 'CONFLICT')
    assert(Storage.set(1, 'app', 'k1', 'new'))
    equal(Storage.get(1, 'app', 'k1'), 'new')
end)

test('total 128 KB quota counts replaced values only once', function()
    resetSql()
    local chunk = ('x'):rep(16 * 1024 - 2) -- 16382 encoded bytes with quotes
    for i = 1, 8 do assert(Storage.set(1, 'app', 'c' .. i, chunk)) end
    local ok, err = Storage.set(1, 'app', 'c9', chunk)
    equal(ok, nil)
    equal(err.error.code, 'CONFLICT')
    assert(Storage.set(1, 'app', 'c1', chunk)) -- replacing is fine
    assert(Storage.remove(1, 'app', 'c2'))
    assert(Storage.set(1, 'app', 'c9', chunk)) -- freed room
end)

test('remove deletes and is idempotent', function()
    resetSql()
    Storage.set(1, 'app', 'k', 1)
    assert(Storage.remove(1, 'app', 'k'))
    assert(Storage.remove(1, 'app', 'k'))
    equal(Storage.get(1, 'app', 'k'), nil)
end)

test('a failed write is reported as INTERNAL', function()
    resetSql()
    Kora.sql.execute = function() return nil end
    local ok, err = Storage.set(1, 'app', 'k', 1)
    equal(ok, nil)
    equal(err.error.code, 'INTERNAL_ERROR')
end)

test('the repository only issues parameterised statements', function()
    resetSql()
    Storage.set(1, 'app', 'k', 'v')
    Storage.get(1, 'app', 'k')
    Storage.remove(1, 'app', 'k')
    assert(#statements > 0)
    for _, sql in ipairs(statements) do
        assert(sql:find('phone_app_storage'), sql)
        assert(not sql:find("'"), sql)
    end
end)

test('the schema declares phone_app_storage with the contract primary key and cascade', function()
    dofile(H.root .. '/server/sdk/schema.lua')
    local spec = KoraPhoneSdkSchema[1]
    equal(spec.name, 'phone_app_storage')
    equal(table.concat(spec.primary, ','), 'device_id,app_id,key')
    equal(spec.foreign[1].on_delete, 'CASCADE')
end)

test('an app with a raised manifest quota may keep more keys than the default', function()
    resetSql()
    local ok = KoraPhone.SDK.Registry.register(H.manifest({ id = 'bigapp', storage = { keys = 70 } }), 'app_res', {})
    equal(ok, true)
    for i = 1, 70 do equal(select(2, Storage.set(7, 'bigapp', 'k' .. i, i)), nil, 'key ' .. i) end
    local _, err = Storage.set(7, 'bigapp', 'k71', 71)
    equal(err.error.code, 'CONFLICT')
    assert(err.error.message:find('%(70%)'), err.error.message)
    KoraPhone.SDK.Registry.register(H.manifest({ id = 'plainapp' }), 'app_res', {})
    for i = 1, 64 do Storage.set(7, 'plainapp', 'k' .. i, i) end
    equal(select(2, Storage.set(7, 'plainapp', 'k65', 65)).error.code, 'CONFLICT')
end)

test('list escapes LIKE wildcards in the prefix and decodes values', function()
    resetSql()
    local captured
    Kora.sql.query = function(sql, p)
        captured = { sql = sql, params = p }
        return { { key = 'note:1', value = '{"t":"a"}' }, { key = 'note:bad', value = 'not json' } }
    end
    local values = Storage.list(7, 'demo-app', 'note:')
    equal(values['note:1'].t, 'a')
    equal(values['note:bad'], nil)
    equal(captured.params[3], 'note:%')
    Storage.list(7, 'demo-app', nil)
    equal(captured.params[3], '%')
    local _, err = Storage.list(7, 'demo-app', 'a%b')
    equal(err.error.code, 'INVALID_INPUT')
end)

H.finish('sdk-storage')
