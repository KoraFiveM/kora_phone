SteviePhone.Services = SteviePhone.Services or {}
local Garage = {}
SteviePhone.Services.Garage = Garage

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

function Garage.list(source)
    local device, err = SteviePhone.Permissions.requireDevice(source)
    if not device then return err end
    if not Garage.available() then return PhoneError(PhoneConstants.Errors.CONFLICT, 'Garage is not available') end
    local rows = MySQL.query.await(('SELECT vehicle, plate, garage, state, fuel FROM `%s` WHERE citizenid = ? ORDER BY plate LIMIT 100'):format(Config.Server.Garage.Table), { device.ownerCitizenId }) or {}
    for _, row in ipairs(rows) do row.state = tonumber(row.state) or 0; row.fuel = tonumber(row.fuel) or 0; row.garage = row.garage or '' end
    return PhoneResult(rows)
end
