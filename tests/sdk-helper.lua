-- Shared mock environment for tests/sdk-*.test.lua (not a test itself).
-- Provides: a tiny JSON codec, test()/equal() helpers, and `newServer()` which loads the
-- server SDK files against mocked FiveM natives, Kora libs and phone services.
local H = { passed = 0, failed = 0 }

local script = arg and arg[0] or 'tests/x.lua'
H.root = script:gsub('[\\/]tests[\\/][^\\/]+$', '')
if H.root == script then H.root = '.' end

function H.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        H.passed = H.passed + 1
        io.write('PASS ', name, '\n')
    else
        H.failed = H.failed + 1
        io.stderr:write('FAIL ', name, ': ', tostring(err), '\n')
    end
end

function H.equal(actual, expected, label)
    assert(actual == expected, ('%sexpected %s, got %s'):format(label and (label .. ': ') or '', tostring(expected), tostring(actual)))
end

function H.finish(suite)
    io.write(('\n%s: %d passed, %d failed\n'):format(suite, H.passed, H.failed))
    if H.failed > 0 then os.exit(1) end
end

-- Minimal JSON: enough for the SDK (objects, arrays, strings, numbers, booleans, null).
local function encode(value)
    local kind = type(value)
    if kind == 'string' then return '"' .. value:gsub('[%c"\\]', function(c) return ('\\u%04x'):format(c:byte()) end) .. '"' end
    if kind == 'number' or kind == 'boolean' then return tostring(value) end
    if kind == 'nil' then return 'null' end
    if kind ~= 'table' then error('cannot encode ' .. kind) end
    local parts = {}
    if #value > 0 or next(value) == nil then
        for i, item in ipairs(value) do parts[i] = encode(item) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = encode(key) .. ':' .. encode(value[key]) end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function decode(text)
    local pos = 1
    local function skip() pos = text:find('%S', pos) or #text + 1 end
    local parse
    local function str()
        local close = text:find('"', pos + 1, true)
        local value = text:sub(pos + 1, close - 1)
        pos = close + 1
        return (value:gsub('\\u(%x%x%x%x)', function(h) return string.char(tonumber(h, 16)) end))
    end
    function parse()
        skip()
        local c = text:sub(pos, pos)
        if c == '{' then
            local result = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == '}' then pos = pos + 1 return result end
            repeat
                skip()
                local key = str()
                skip()
                pos = pos + 1
                result[key] = parse()
                skip()
                local sep = text:sub(pos, pos)
                pos = pos + 1
            until sep == '}'
            return result
        elseif c == '[' then
            local result = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == ']' then pos = pos + 1 return result end
            repeat
                result[#result + 1] = parse()
                skip()
                local sep = text:sub(pos, pos)
                pos = pos + 1
            until sep == ']'
            return result
        elseif c == '"' then
            return str()
        end
        local literal = text:match('^[%w%.%-%+]+', pos)
        if not literal then error('bad json at ' .. pos) end
        pos = pos + #literal
        if literal == 'true' then return true elseif literal == 'false' then return false elseif literal == 'null' then return nil end
        return assert(tonumber(literal), 'bad json literal')
    end
    local value = parse()
    skip()
    assert(pos > #text, 'trailing json')
    return value
end
_G.json = { encode = encode, decode = decode }

local SDK_FILES = {
    'manifest', 'registry', 'permissions', 'install', 'storage_repository', 'storage', 'callbacks', 'routes',
    'discovery', 'exports',
}

--- Loads shared constants plus the server SDK. Returns an env table of recorders/fixtures.
function H.newServer(opts)
    opts = opts or {}
    local env = {
        exports = {}, handlers = {}, clientEvents = {}, callbacks = {}, logs = {}, resources = {},
        invoking = 'app_res', rows = {}, settingsWrites = {}, limited = false, contacts = {}, upserts = {},
    }
    _G.CreateThread = function(fn) if opts.runThreads then fn() end end
    _G.GetCurrentResourceName = function() return 'kora_phone' end
    _G.GetInvokingResource = function() return env.invoking end
    _G.exports = setmetatable({}, { __call = function(_, name, fn) env.exports[name] = fn end })
    _G.AddEventHandler = function(event, fn) env.handlers[event] = fn end
    _G.TriggerClientEvent = function(event, target, ...)
        env.clientEvents[#env.clientEvents + 1] = { event = event, target = target, args = { ... } }
    end
    _G.GetNumResourceMetadata = function(res, key)
        local meta = env.resources[res] and env.resources[res].meta[key]
        return meta and #meta or 0
    end
    _G.GetResourceMetadata = function(res, key, index) return env.resources[res].meta[key][index + 1] end
    _G.LoadResourceFile = function(res, path) return env.resources[res] and env.resources[res].files[path] end
    _G.GetNumResources = function()
        local n = 0
        for _ in pairs(env.resources) do n = n + 1 end
        return n
    end
    _G.GetResourceByFindIndex = function(index)
        local names = {}
        for name in pairs(env.resources) do names[#names + 1] = name end
        table.sort(names)
        return names[index + 1]
    end
    _G.GetResourceState = function(res) return env.resources[res] and env.resources[res].state or 'missing' end

    local function logEvent(code, source, fields)
        env.logs[#env.logs + 1] = { level = fields.level, code = code, fields = fields, source = source }
    end
    env.removedCallbacks = {}
    _G.Kora = {
        logging = { event = logEvent },
        callback = {
            register = function(name, fn, o) env.callbacks[name] = { fn = fn, opts = o } end,
            unregister = function(name)
                env.callbacks[name] = nil
                env.removedCallbacks[#env.removedCallbacks + 1] = name
            end,
        },
        sql = { NULL = {} },
    }

    dofile(H.root .. '/shared/constants.lua')
    _G.KoraPhone = {
        RateLimits = { consume = function() return not env.limited end },
        GetPlayer = function() return env.player end,
        Repositories = {
            Phones = { updateSettings = function(id, jsonText)
                env.settingsWrites[#env.settingsWrites + 1] = { id = id, json = jsonText }
                env.device.settingsJson = jsonText
                return true
            end },
            Contacts = {
                list = function() return env.contacts end,
                upsert = function(deviceId, contact)
                    env.upserts[#env.upserts + 1] = { deviceId = deviceId, contact = contact }
                    return contact.id or 99
                end,
            },
        },
        Permissions = {
            requireDevice = function()
                if env.deviceError then return nil, env.deviceError end
                return env.device
            end,
            requirePlayer = function() return 'CID1' end,
        },
        Services = { Phone = { getOrCreate = function() return env.device end } },
    }
    env.device = { id = 7, settingsJson = '{}' }
    for _, file in ipairs(SDK_FILES) do dofile(H.root .. '/server/sdk/' .. file .. '.lua') end
    return env
end

function H.manifest(overrides)
    local manifest = {
        id = 'demo-app', name = 'Demo', description = 'A demo', icon = 'star', entry = 'ui/index.html',
        version = '1.0.0', permissions = { 'storage', 'notify' }, defaultInstalled = true,
    }
    for key, value in pairs(overrides or {}) do manifest[key] = value end
    return manifest
end

return H
