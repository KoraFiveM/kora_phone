KoraPhone.Repositories = KoraPhone.Repositories or {}
local Db = KoraPhone.Database
local External = {}
KoraPhone.Repositories.External = External

---Reads other resources' tables. There is no kora housing resource to call, so the Property app reads a
---housing script's tables (names from Config.Server.Property). Vehicles come from kora_garages, not SQL.

---Table and column names come from server config, so they are checked before they reach SQL.
---@param name any
---@return boolean
function External.isIdentifier(name)
    return type(name) == 'string' and name:match('^[%w_]+$') ~= nil
end

---@param tableName string
---@param columns string[]
---@return boolean allPresent
local function hasColumns(tableName, columns)
    local marks = {}
    local params = { tableName }
    for index, column in ipairs(columns) do
        marks[index] = '?'
        params[#params + 1] = column
    end
    local count = Db.number(([[
        SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = ? AND column_name IN (%s)
    ]]):format(table.concat(marks, ',')), params)
    return count == #columns
end

---True when every configured housing table and column exists.
---@param cfg table Config.Server.Property
---@return boolean
function External.propertySourceExists(cfg)
    local names = {
        cfg.OwnedTable, cfg.OwnerColumn, cfg.HouseColumn, cfg.LocationsTable,
        cfg.NameColumn, cfg.LabelColumn, cfg.CoordsColumn,
    }
    for _, name in ipairs(names) do
        if not External.isIdentifier(name) then return false end
    end
    return hasColumns(cfg.OwnedTable, { cfg.OwnerColumn, cfg.HouseColumn })
        and hasColumns(cfg.LocationsTable, { cfg.NameColumn, cfg.LabelColumn, cfg.CoordsColumn })
end

---Houses a character owns, read from the configured housing tables.
---@param cfg table Config.Server.Property with validated identifiers.
---@param citizenId string
---@return table[]
function External.ownedProperties(cfg, citizenId)
    return Db.rows(([[
        SELECT l.`%s` AS name, l.`%s` AS label, l.`%s` AS coords
        FROM `%s` o JOIN `%s` l ON l.`%s` = o.`%s`
        WHERE o.`%s` = ? LIMIT 50
    ]]):format(cfg.NameColumn, cfg.LabelColumn, cfg.CoordsColumn, cfg.OwnedTable, cfg.LocationsTable,
        cfg.NameColumn, cfg.HouseColumn, cfg.OwnerColumn), { citizenId })
end
