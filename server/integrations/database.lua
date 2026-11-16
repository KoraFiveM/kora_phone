KoraPhone = KoraPhone or {}

---Thin helpers over Kora.sql used by the repositories. Nothing here contains SQL.
---@class KoraPhoneDatabase
local Database = {}
KoraPhone.Database = Database

---@param sql string
---@param params? any[]
---@return table[] rows Empty when the query failed.
function Database.rows(sql, params)
    return Kora.sql.query(sql, params or {}) or {}
end

---@param sql string
---@param params? any[]
---@return table|nil
function Database.row(sql, params)
    return Kora.sql.single(sql, params or {})
end

---@param sql string
---@param params? any[]
---@return any
function Database.value(sql, params)
    return Kora.sql.scalar(sql, params or {})
end

---First column of the first row as a number (0 when missing).
---@param sql string
---@param params? any[]
---@return number
function Database.number(sql, params)
    return tonumber(Kora.sql.scalar(sql, params or {})) or 0
end

---True when a `SELECT EXISTS(...)` style query returns 1.
---@param sql string
---@param params? any[]
---@return boolean
function Database.flag(sql, params)
    return Kora.sql.scalar(sql, params or {}) == 1
end

---Runs a write and returns the affected row count, or nil when it failed.
---@param sql string
---@param params? any[]
---@return integer|nil
function Database.write(sql, params)
    return Kora.sql.update(sql, params or {})
end

---True when a write changed at least one row.
---@param sql string
---@param params? any[]
---@return boolean
function Database.changed(sql, params)
    return (tonumber(Kora.sql.update(sql, params or {})) or 0) > 0
end

---@param sql string
---@param params? any[]
---@return integer|nil insertId
function Database.insert(sql, params)
    return Kora.sql.insert(sql, params or {})
end

---Runs the statements in one transaction. True only when everything committed.
---@param statements { sql: string, params: any[] }[]
---@return boolean
function Database.transaction(statements)
    return Kora.sql.transaction(statements) == true
end

---@return boolean
function Database.isReady()
    return KoraPhone.Repositories.Health.ping()
end
