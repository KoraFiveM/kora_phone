-- Shared FiveM / Kora mocks for the plain-Lua tests (not a test itself).
-- Usage:  local mocks = dofile(root .. '/tests/helpers/fivem_mocks.lua').install({ resources = { kora_core = 'started' } })
-- Installs `exports`, `Kora` (callback, config shim, sql, logging, lang, cache, timers), `GetResourceState`,
-- `LoadResourceFile` and `GetCurrentResourceName`, and returns a recorder so tests can inspect what was called.
local M = {}

---@param options? { resources?: table<string,string>, root?: string, files?: table<string,string> }
function M.install(options)
    options = options or {}
    local root = options.root or '.'
    local mock = { logs = {}, callbacks = {}, timers = {}, exports = {}, cacheListeners = {} }

    -- Kora.config shim (typed descriptors collapse to their authored defaults).
    dofile(root .. '/tests/config_shim.lua')
    Kora = Kora or {}

    local function log(level)
        return function(event, message, fields)
            mock.logs[#mock.logs + 1] = { level = level, event = event, message = message, fields = fields }
            return true
        end
    end
    Kora.logging = setmetatable({}, { __index = function(_, level) return log(level) end })

    Kora.callback = Kora.callback or {
        register = function(name, handler, opts) mock.callbacks[name] = { handler = handler, opts = opts } end,
        await = function() return nil end,
    }
    Kora.sql = Kora.sql or {
        NULL = '\0kora_sql:null\0',
        ensureTables = function() return {} end,
        query = function() return {} end,
        single = function() return nil end,
        scalar = function() return nil end,
        insert = function() return 0 end,
        update = function() return 0 end,
        execute = function() return 0 end,
    }
    Kora.lang = Kora.lang or { t = function(key) return key end, get = function(key) return key end }
    Kora.cache = Kora.cache or {
        onChange = function(key, handler)
            mock.cacheListeners[key] = handler
            return function() mock.cacheListeners[key] = nil end
        end,
    }
    Kora.timers = Kora.timers or {
        setTimeout = function(ms, fn) mock.timers[#mock.timers + 1] = { ms = ms, fn = fn } return #mock.timers end,
        clear = function(id) mock.timers[id] = nil end,
    }

    -- `exports.res:fn(...)` resolves to a recorder returning whatever the test registered via mock.exports.
    local states = options.resources or {}
    exports = setmetatable({}, { __index = function(_, resource)
        return setmetatable({}, { __index = function(_, name)
            return function(_, ...)
                local handler = mock.exports[resource .. ':' .. name]
                if handler then return handler(...) end
                return nil
            end
        end })
    end })
    GetResourceState = function(resource) return states[resource] or 'missing' end
    GetCurrentResourceName = function() return 'kora_phone' end
    LoadResourceFile = function(_, path)
        local content = options.files and options.files[path]
        if content then return content end
        local handle = io.open(root .. '/' .. path, 'rb')
        if not handle then return nil end
        content = handle:read('a')
        handle:close()
        return content
    end
    return mock
end

return M
