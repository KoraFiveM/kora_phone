-- Run from the resource root: lua5.4 tests/manifest.test.lua
-- 1. fxmanifest.lua lists (or globs) every client/server/shared/config Lua file (orphan check) and lists nothing missing.
-- 2. No Lua file references the removed stacks: MySQL.*, QBCore:*, pma-voice, qb-* exports.
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 io.write('PASS ', name, '\n')
    else failed = failed + 1 io.stderr:write('FAIL ', name, ': ', tostring(err), '\n') end
end

local function read(path)
    local handle = assert(io.open(path, 'rb'), 'cannot open ' .. path)
    local content = handle:read('a')
    handle:close()
    return content
end

local function listLua(dir)
    local files = {}
    local pipe = io.popen(('find %s -type f -name "*.lua" 2>/dev/null | sort'):format(dir))
    for line in pipe:lines() do files[#files + 1] = (line:gsub('^%./', '')) end
    pipe:close()
    return files
end

-- Every quoted entry inside the *_scripts blocks / single-entry forms, comments stripped.
local function manifestEntries()
    local source = read('fxmanifest.lua'):gsub('%-%-[^\n]*', '')
    local entries = {}
    for _, kind in ipairs({ 'client', 'server', 'shared' }) do
        for body in source:gmatch(kind .. '_scripts%s*(%b{})') do
            for entry in body:gmatch("'([^']+)'") do entries[#entries + 1] = entry end
        end
        for entry in source:gmatch(kind .. "_script%s+'([^']+)'") do entries[#entries + 1] = entry end
    end
    return entries
end

local function globToPattern(glob)
    local escaped = glob:gsub('[%^%$%(%)%%%.%[%]%+%-%?]', '%%%0')
    escaped = escaped:gsub('%*%*', '\1'):gsub('%*', '[^/]*'):gsub('\1', '.*')
    return '^' .. escaped .. '$'
end

local entries = manifestEntries()

test('the manifest lists scripts', function() assert(#entries > 20, 'only ' .. #entries .. ' entries parsed') end)

test('every manifest entry exists on disk (globs match at least one file)', function()
    for _, entry in ipairs(entries) do
        if entry:sub(1, 1) ~= '@' and entry:match('%.lua$') then
            if entry:find('*', 1, true) then
                local pattern, found = globToPattern(entry), false
                for _, file in ipairs(listLua(entry:match('^(.-)/[^/]*$') or '.')) do
                    if file:match(pattern) then found = true break end
                end
                assert(found, 'glob matches nothing: ' .. entry)
            else
                local handle = io.open(entry, 'rb')
                assert(handle, 'missing file: ' .. entry)
                handle:close()
            end
        end
    end
end)

test('no client/server/shared/config Lua file is orphaned from the manifest', function()
    local patterns, orphans = {}, {}
    for _, entry in ipairs(entries) do
        if entry:sub(1, 1) ~= '@' then patterns[#patterns + 1] = globToPattern(entry) end
    end
    for _, dir in ipairs({ 'client', 'server', 'shared', 'config' }) do
        for _, file in ipairs(listLua(dir)) do
            local listed = false
            for _, pattern in ipairs(patterns) do
                if file:match(pattern) then listed = true break end
            end
            if not listed then orphans[#orphans + 1] = file end
        end
    end
    assert(#orphans == 0, 'not in fxmanifest.lua: ' .. table.concat(orphans, ', '))
end)

-- Custom-app alias files keep their lb-phone/qb-style names on purpose.
local FORBIDDEN_ALLOWLIST = { ['client/customapps.lua'] = true }
local FORBIDDEN = {
    { 'MySQL.', 'oxmysql-style MySQL.* (use Kora.sql.*)' },
    { 'QBCore:', 'QBCore: events (use kora_core native events)' },
    { 'pma-voice', 'pma-voice (use kora_voice)' },
    { "exports['qb-", "exports['qb-*'] (use Kora resources)" },
    { 'exports["qb-', 'exports["qb-*"] (use Kora resources)' },
    { 'qb-core', 'qb-core (use kora_core)' },
}

test('no Lua file references MySQL., QBCore:, pma-voice or qb-* exports', function()
    local hits = {}
    for _, dir in ipairs({ 'client', 'server', 'shared', 'config' }) do
        for _, file in ipairs(listLua(dir)) do
            if not FORBIDDEN_ALLOWLIST[file] then
                local number = 0
                for line in read(file):gmatch('([^\n]*)\n?') do
                    number = number + 1
                    local code = line:gsub('%-%-.*$', '')
                    for _, rule in ipairs(FORBIDDEN) do
                        if code:find(rule[1], 1, true) then hits[#hits + 1] = ('%s:%d %s'):format(file, number, rule[2]) end
                    end
                end
            end
        end
    end
    assert(#hits == 0, table.concat(hits, '; '))
end)

io.write(('\n%d passed, %d failed\n'):format(passed, failed))
if failed > 0 then os.exit(1) end
