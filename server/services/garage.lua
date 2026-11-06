KoraPhone.Services = KoraPhone.Services or {}
local Garage = {}
KoraPhone.Services.Garage = Garage

local available

-- The Garage app needs QBCore's owned-vehicles table. Checked once, so a server without it
-- simply doesn't offer the app instead of failing on every open.
function Garage.available()
    if available ~= nil then return available end
    local cfg = Config.Server.Garage
    available = false
    if cfg.Enabled and cfg.Table:match('^[%w_]+$') then
        local ok, count = pcall(MySQL.scalar.await, 'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { cfg.Table })
        available = ok and (tonumber(count) or 0) > 0
    end
    return available
end

local stateCodes = { out = 0, garaged = 1, impounded = 2 }
local hasGarageId

-- kora_core stores the garage in `garage_id` (mirrored into `garage`) and the state as text;
-- stock QBCore tables have neither a `garage_id` column nor text states.
local function garageIdColumn()
    if hasGarageId ~= nil then return hasGarageId end
    local ok, count = pcall(MySQL.scalar.await, 'SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?', { Config.Server.Garage.Table, 'garage_id' })
    hasGarageId = ok and (tonumber(count) or 0) > 0
    return hasGarageId
end

local function garageLabels()
    local labels = {}
    if not Config.Server.Garage.UseGarageLabels then return labels end
    local ok, list = pcall(function() return exports.kora_garages:getAllGarages() end)
    if ok and type(list) == 'table' then
        for _, g in ipairs(list) do if g.name and g.label then labels[g.name] = g.label end end
    end
    return labels
end

function Garage.list(source)
    local device, err = KoraPhone.Permissions.requireDevice(source)
    if not device then return err end
    if not Garage.available() then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Garage is not available') end
    local column = garageIdColumn() and "COALESCE(NULLIF(garage, ''), garage_id)" or 'garage'
    local rows = MySQL.query.await(('SELECT vehicle, plate, %s AS garage, state, fuel FROM `%s` WHERE citizenid = ? ORDER BY plate LIMIT 100'):format(column, Config.Server.Garage.Table), { device.ownerCitizenId }) or {}
    local labels = garageLabels()
    for _, row in ipairs(rows) do
        row.state = tonumber(row.state) or stateCodes[row.state] or 0; row.fuel = tonumber(row.fuel) or 0
        row.garage = row.garage and (labels[row.garage] or row.garage) or ''
    end
    return PhoneResult(rows)
end