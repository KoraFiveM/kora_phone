QBPhone.Services = QBPhone.Services or {}
local Property = {}
QBPhone.Services.Property = Property

local available

local function ident(value) return type(value) == 'string' and value:match('^[%w_]+$') ~= nil end

local function hasColumns(tableName, columns)
    local marks = {}
    for i = 1, #columns do marks[i] = '?' end
    local params = { tableName }
    for _, column in ipairs(columns) do params[#params + 1] = column end
    local count = MySQL.scalar.await(('SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name IN (%s)'):format(table.concat(marks, ',')), params)
    return (tonumber(count) or 0) == #columns
end

-- The Property app reads a housing script's tables (QBCore's qb-houses layout by default, changeable in
-- Config.Server.Property). It only appears when every configured table and column exists.
function Property.available()
    if available ~= nil then return available end
    local cfg = Config.Server.Property
    available = false
    if not cfg.Enabled then return false end
    for _, name in ipairs({ cfg.OwnedTable, cfg.OwnerColumn, cfg.HouseColumn, cfg.LocationsTable, cfg.NameColumn, cfg.LabelColumn, cfg.CoordsColumn }) do
        if not ident(name) then return false end
    end
    local ok, result = pcall(function()
        return hasColumns(cfg.OwnedTable, { cfg.OwnerColumn, cfg.HouseColumn }) and hasColumns(cfg.LocationsTable, { cfg.NameColumn, cfg.LabelColumn, cfg.CoordsColumn })
    end)
    available = ok and result == true
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
    local device, err = QBPhone.Permissions.requireDevice(source)
    if not device then return err end
    if not Property.available() then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Property is not available') end
    local cfg = Config.Server.Property
    local sql = 'SELECT l.`%s` AS name, l.`%s` AS label, l.`%s` AS coords FROM `%s` o JOIN `%s` l ON l.`%s` = o.`%s` WHERE o.`%s` = ? LIMIT 50'
    local rows = MySQL.query.await(sql:format(cfg.NameColumn, cfg.LabelColumn, cfg.CoordsColumn, cfg.OwnedTable, cfg.LocationsTable,
        cfg.NameColumn, cfg.HouseColumn, cfg.OwnerColumn), { device.ownerCitizenId }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = { name = tostring(row.name), label = tostring(row.label or row.name), coords = point(row.coords) }
    end
    return PhoneResult(out)
end
