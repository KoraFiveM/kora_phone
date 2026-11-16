-- Test shim for Kora.config. Tests run without FiveM and without kora_lib, so this stands in for the config
-- handler: `define` and `extend` return the authored defaults as a plain table, exactly the shape the real
-- handler hands the code (Config.Camera.zoom.step, Config.Server.RateLimits.read, ...).
-- It does not validate or persist anything; schema validation is covered by running the real kora_lib
-- consumer (see docs/configuration.md, "Checking a change").
--
-- Usage in a test, before loading config/*.lua:
--     dofile(root .. '/tests/config_shim.lua')

Kora = Kora or {}

local shim = {}
local DESCRIPTOR = {}

local function descriptor(kind)
    return function(value, ...)
        local field = { [DESCRIPTOR] = true, kind = kind, value = value }
        if kind == 'optional' then field.inner = (...) end
        return field
    end
end

for _, kind in ipairs({
    'boolean', 'string', 'integer', 'number', 'enum', 'color',
    'vector2', 'vector3', 'vector4', 'object', 'list', 'map', 'optional',
}) do
    shim[kind] = descriptor(kind)
end

local function resolve(node)
    if type(node) ~= 'table' then return node end
    if node[DESCRIPTOR] then
        return resolve(node.value)
    end
    local out = {}
    for key, child in pairs(node) do
        out[key] = resolve(child)
    end
    return out
end

local current

function shim.define(values)
    current = resolve(values)
    return current
end

shim.register = shim.define

function shim.extend(values)
    assert(current, 'Kora.config.extend requires Kora.config.define first.')
    for key, child in pairs(resolve(values)) do
        current[key] = child
    end
    return current
end

function shim.onChange() end
function shim.onValidate() end
function shim.onApply() end

Kora.config = shim
