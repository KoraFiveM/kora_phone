KoraPhone.Services = KoraPhone.Services or {}
local Property = {}
KoraPhone.Services.Property = Property
local External = KoraPhone.Repositories.External

local available

-- There is no Kora housing resource, so the app reads a housing script's tables (qb-houses layout by default,
-- names in Config.Server.Property). It only appears when every configured table and column exists; the check
-- runs once and is cached until the resource restarts.
function Property.available()
    if available == nil then
        local cfg = Config.Server.Property
        available = cfg.Enabled == true and External.propertySourceExists(cfg)
    end
    return available
end

local function point(raw)
    if type(raw) ~= 'string' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil end
    local at = type(decoded.enter) == 'table' and decoded.enter or decoded
    local x, y = tonumber(at.x), tonumber(at.y)
    if x and y then return { x = x, y = y } end
end

function Property.list(source)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    if not Property.available() then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Property is not available') end
    local cfg = Config.Server.Property
    local rows = External.ownedProperties(cfg, device.ownerCitizenId)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = { name = tostring(row.name), label = tostring(row.label or row.name), coords = point(row.coords) }
    end
    return PhoneResult(out)
end