KoraPhone.Repositories = KoraPhone.Repositories or {}
local Health = {}
KoraPhone.Repositories.Health = Health

---True when the database answers a trivial query.
---@return boolean
function Health.ping()
    return KoraPhone.Database.value('SELECT 1') == 1
end
