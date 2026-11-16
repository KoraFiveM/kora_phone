KoraPhone.Repositories = KoraPhone.Repositories or {}
local Db = KoraPhone.Database
local Mail = {}
KoraPhone.Repositories.SystemMail = Mail

-- Beyond any real id, so "no cursor" can be bound as a number.
local MAX_ID = 9007199254740991

---@param citizenId string
---@param mail { sender: string, subject: string, message: string, button?: table }
---@return integer|nil id
function Mail.insert(citizenId, mail)
    return Db.insert([[
        INSERT INTO phone_system_mail (citizenid, sender, subject, body, button_json)
        VALUES (?, ?, ?, ?, NULLIF(?, ''))
    ]], { citizenId, mail.sender, mail.subject, mail.message, mail.button and json.encode(mail.button) or '' })
end

---@param citizenId string
---@param limit integer
---@param cursor? integer
---@return table[]
function Mail.list(citizenId, limit, cursor)
    return Db.rows([[
        SELECT id, sender AS peer, subject, body, UNIX_TIMESTAMP(created_at) AS createdAt,
               (read_at IS NULL) AS unread, (button_json IS NOT NULL) AS hasAction
        FROM phone_system_mail
        WHERE citizenid = ? AND deleted_at IS NULL AND id < ? ORDER BY id DESC LIMIT ?
    ]], { citizenId, cursor or MAX_ID, limit })
end

---@param citizenId string
---@param id integer
---@return integer|nil affected
function Mail.markRead(citizenId, id)
    return Db.write([[
        UPDATE phone_system_mail SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP)
        WHERE id = ? AND citizenid = ? AND deleted_at IS NULL
    ]], { id, citizenId })
end

---@param citizenId string
---@param id integer
---@return boolean
function Mail.delete(citizenId, id)
    return Db.changed([[
        UPDATE phone_system_mail SET deleted_at = CURRENT_TIMESTAMP, button_json = NULL
        WHERE id = ? AND citizenid = ? AND deleted_at IS NULL
    ]], { id, citizenId })
end

---@param citizenId string
---@param id integer
---@return boolean
function Mail.clearButton(citizenId, id)
    return Db.changed([[
        UPDATE phone_system_mail SET button_json = NULL
        WHERE id = ? AND citizenid = ? AND deleted_at IS NULL AND button_json IS NOT NULL
    ]], { id, citizenId })
end

---Consumes a mail's action button exactly once.
---@param citizenId string
---@param id integer
---@return table|nil button
function Mail.takeButton(citizenId, id)
    local row = Db.row(
        'SELECT button_json FROM phone_system_mail WHERE id = ? AND citizenid = ? AND deleted_at IS NULL',
        { id, citizenId })
    if not row or not row.button_json then return nil end
    local ok, button = pcall(json.decode, row.button_json)
    if not ok or type(button) ~= 'table' or type(button.event) ~= 'string' then return nil end
    return Mail.clearButton(citizenId, id) and button or nil
end

---@param citizenId string
---@param limit integer
---@param cursor? integer
---@return table[]
function Mail.activity(citizenId, limit, cursor)
    return Db.rows([[
        SELECT id, title, message, UNIX_TIMESTAMP(created_at) AS createdAt
        FROM phone_system_activity WHERE citizenid = ? AND id < ? ORDER BY id DESC LIMIT ?
    ]], { citizenId, cursor or MAX_ID, limit })
end

---Records an entry in the character's activity feed.
---@param citizenId string
---@param title string
---@param message string
---@return integer|nil id
function Mail.addActivity(citizenId, title, message)
    return Db.insert(
        'INSERT INTO phone_system_activity (citizenid, title, message) VALUES (?, ?, ?)',
        { citizenId, title, message })
end
