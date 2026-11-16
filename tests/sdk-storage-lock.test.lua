-- lua tests/sdk-storage-lock.test.lua  (from the resource root)
-- Covers the per (device, app) lock in server/sdk/storage.lua: overlapping Storage.set calls must not both
-- pass the quota check. A tiny cooperative scheduler stands in for FiveM's promise / Citizen.Await.
local H = dofile((arg and arg[0] or 'tests/x'):gsub('[^/\\]+$', '') .. 'sdk-helper.lua')
local test, equal = H.test, H.equal

H.newServer()
local Storage = KoraPhone.SDK.Storage

-- Cooperative scheduler: Await yields the running coroutine until the promise resolves.
local function installScheduler()
    _G.promise = {
        new = function()
            local p = { resolved = false }
            function p:resolve() self.resolved = true end
            return p
        end,
    }
    _G.Citizen = {
        Await = function(p)
            while not p.resolved do coroutine.yield() end
        end,
    }
end

local function removeScheduler()
    _G.promise, _G.Citizen = nil, nil
end

local function runAll(tasks)
    local alive = #tasks
    local guard = 0
    while alive > 0 do
        guard = guard + 1
        assert(guard < 10000, 'scheduler did not settle (deadlock?)')
        for _, task in ipairs(tasks) do
            if coroutine.status(task.co) == 'suspended' then
                task.ok, task.err = coroutine.resume(task.co)
                if coroutine.status(task.co) == 'dead' then alive = alive - 1 end
            end
        end
    end
end

local function spawn(tasks, fn)
    local task = { results = {} }
    task.co = coroutine.create(function() task.results = table.pack(fn()) end)
    tasks[#tasks + 1] = task
    return task
end

-- Repository stub whose every call yields once, like a real database round trip.
local rows
local inCritical, maxInCritical, failNext
local function installRepo()
    rows = {}
    inCritical, maxInCritical, failNext = 0, 0, false
    local function id(d, a, k) return d .. '|' .. a .. '|' .. k end
    local function pause() if _G.Citizen then coroutine.yield() end end
    KoraPhone.SDK.StorageRepository = {
        usage = function(d, a)
            pause()
            local count, bytes = 0, 0
            for key, value in pairs(rows) do
                if key:find('^' .. d .. '|' .. a .. '|') then count, bytes = count + 1, bytes + #value end
            end
            return { keys = count, bytes = bytes }
        end,
        size = function(d, a, k)
            pause()
            local row = rows[id(d, a, k)]
            return row and #row or nil
        end,
        set = function(d, a, k, encoded)
            pause()
            if failNext then
                failNext = false
                error('database exploded')
            end
            rows[id(d, a, k)] = encoded
            return true
        end,
        get = function(d, a, k) return rows[id(d, a, k)] end,
        remove = function(d, a, k) rows[id(d, a, k)] = nil end,
    }
end

local chunk = ('x'):rep(16 * 1024 - 2) -- 16382 encoded bytes with quotes
local function fillSevenChunks()
    for i = 1, 7 do rows['1|app|c' .. i] = '"' .. chunk .. '"' end
end

test('two overlapping sets that each fit alone: exactly one wins, the other gets CONFLICT', function()
    installScheduler()
    installRepo()
    fillSevenChunks() -- 7 x 16382 = 114674 of 131072; one more chunk fits, two do not
    local tasks = {}
    local a = spawn(tasks, function() return Storage.set(1, 'app', 'new_a', chunk) end)
    local b = spawn(tasks, function() return Storage.set(1, 'app', 'new_b', chunk) end)
    runAll(tasks)
    equal(a.ok, true, tostring(a.err))
    equal(b.ok, true, tostring(b.err))
    local wins, conflicts = 0, 0
    for _, task in ipairs({ a, b }) do
        if task.results[1] == true then
            wins = wins + 1
        else
            equal(task.results[1], nil)
            equal(task.results[2].error.code, 'CONFLICT')
            conflicts = conflicts + 1
        end
    end
    equal(wins, 1, 'wins')
    equal(conflicts, 1, 'conflicts')
    local total = 0
    for _, value in pairs(rows) do total = total + #value end
    assert(total <= Storage.LIMITS.totalBytes, 'stored bytes exceed the quota: ' .. total)
    removeScheduler()
end)

test('without the lock the same race would overshoot (guards the test itself)', function()
    removeScheduler() -- no promise: the fallback path has no lock, but the stubs then do not yield either
    installRepo()
    fillSevenChunks()
    -- Emulate the unlocked interleaving by hand: both read usage first, then both write.
    local repo = KoraPhone.SDK.StorageRepository
    local usageA, usageB = repo.usage(1, 'app'), repo.usage(1, 'app')
    assert(usageA.bytes + #chunk + 2 <= Storage.LIMITS.totalBytes)
    assert(usageB.bytes + #chunk + 2 <= Storage.LIMITS.totalBytes)
    assert(usageA.bytes + 2 * (#chunk + 2) > Storage.LIMITS.totalBytes)
end)

test('the 64-key limit is also serialised', function()
    installScheduler()
    installRepo()
    for i = 1, 63 do rows['1|app|k' .. i] = '1' end
    local tasks = {}
    local a = spawn(tasks, function() return Storage.set(1, 'app', 'last_a', 1) end)
    local b = spawn(tasks, function() return Storage.set(1, 'app', 'last_b', 1) end)
    runAll(tasks)
    local wins = 0
    for _, task in ipairs({ a, b }) do
        if task.results[1] == true then
            wins = wins + 1
        else
            equal(task.results[2].error.code, 'CONFLICT')
        end
    end
    equal(wins, 1)
    removeScheduler()
end)

test('different apps do not block each other', function()
    installScheduler()
    installRepo()
    local tasks = {}
    local a = spawn(tasks, function() return Storage.set(1, 'app_one', 'k', 1) end)
    local b = spawn(tasks, function() return Storage.set(1, 'app_two', 'k', 1) end)
    runAll(tasks)
    equal(a.results[1], true)
    equal(b.results[1], true)
    removeScheduler()
end)

test('the lock is released after an error thrown inside the critical section', function()
    installScheduler()
    installRepo()
    failNext = true
    local tasks = {}
    local first = spawn(tasks, function() return pcall(Storage.set, 1, 'app', 'boom', 'v') end)
    local second = spawn(tasks, function() return Storage.set(1, 'app', 'after', 'v') end)
    runAll(tasks)
    equal(first.ok, true, tostring(first.err))
    equal(first.results[1], false) -- the error propagated out of set
    assert(tostring(first.results[2]):find('database exploded', 1, true), tostring(first.results[2]))
    equal(second.ok, true, tostring(second.err))
    equal(second.results[1], true) -- the waiter got the lock and finished
    assert(rows['1|app|after'], 'second write was not stored')
    -- and a later call is not blocked either
    local later = {}
    local third = spawn(later, function() return Storage.set(1, 'app', 'again', 'v') end)
    runAll(later)
    equal(third.results[1], true)
    removeScheduler()
end)

test('without promise / Citizen.Await the unlocked fallback still works', function()
    removeScheduler()
    installRepo()
    assert(Storage.set(1, 'app', 'k', { a = 1 }))
    equal(Storage.get(1, 'app', 'k').a, 1)
    for i = 1, 7 do assert(Storage.set(1, 'app', 'c' .. i, chunk)) end
    local ok, err = Storage.set(1, 'app', 'c8', ('y'):rep(16 * 1024 - 2))
    equal(ok, nil)
    equal(err.error.code, 'CONFLICT')
end)

H.finish('sdk-storage-lock')
