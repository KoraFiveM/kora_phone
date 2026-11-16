KoraPhone.Repositories = KoraPhone.Repositories or {}
local Db = KoraPhone.Database
local Sims = {}
KoraPhone.Repositories.Sims = Sims

-- A handset without a SIM carries '@' plus the first 20 characters of its id as a placeholder number.
local DETACH_NUMBER_SQL = "CONCAT('@', LEFT(h.id, 20))"

---@param simId string
---@return table|nil
function Sims.findById(simId)
    return Db.row('SELECT * FROM phone_sims WHERE id = ?', { simId })
end

---@param phoneNumber string
---@return boolean
function Sims.numberTaken(phoneNumber)
    return Db.row('SELECT id FROM phone_sims WHERE phone_number = ? LIMIT 1', { phoneNumber }) ~= nil
end

---@param simId string
---@param phoneNumber string
---@param citizenId string
function Sims.insert(simId, phoneNumber, citizenId)
    Db.write('INSERT INTO phone_sims (id, phone_number, owner_citizenid) VALUES (?, ?, ?)', { simId, phoneNumber, citizenId })
end

---Points a device at a number and the SIM at its handset, releasing any other SIM the handset held.
---@param device table Handset view with `id` and `handsetId`.
---@param simId string|nil
---@param number string Number to store on the device (the SIM's, or the placeholder).
---@return boolean
function Sims.attach(device, simId, number)
    local statements = {
        {
            sql = 'UPDATE phone_sims SET handset_id = NULL WHERE handset_id = ? AND id <> ?',
            params = { device.handsetId, simId or '' },
        },
        { sql = 'UPDATE phone_devices SET phone_number = ? WHERE id = ?', params = { number, device.id } },
    }
    if simId then
        statements[#statements + 1] = {
            sql = 'UPDATE phone_sims SET handset_id = ? WHERE id = ?',
            params = { device.handsetId, simId },
        }
    end
    return Db.transaction(statements)
end

---Detaches a SIM from the handset that still lists it (a loose SIM proves it was removed).
---@param handsetId string
---@param sim table
---@return boolean
function Sims.detach(handsetId, sim)
    return Db.transaction({
        {
            sql = 'UPDATE phone_devices d JOIN phone_handsets h ON h.device_id = d.id SET d.phone_number = '
                .. DETACH_NUMBER_SQL .. ' WHERE h.id = ? AND d.phone_number = ?',
            params = { handsetId, sim.phone_number },
        },
        { sql = 'UPDATE phone_sims SET handset_id = NULL WHERE id = ?', params = { sim.id } },
    })
end

---The character's own subscription for a number, preferring the active and attached one.
---@param phoneNumber string
---@param citizenId string
---@return table|nil
function Sims.findOwnedSubscription(phoneNumber, citizenId)
    return Db.row([[
        SELECT * FROM phone_sims
        WHERE phone_number = ? AND owner_citizenid = ? AND status <> 'revoked'
        ORDER BY (status = 'active') DESC, (handset_id IS NOT NULL) DESC, created_at, id LIMIT 1
    ]], { phoneNumber, citizenId })
end

---Registers the replacement SIM as blocked and the replacement job that will activate it.
---@param newSimId string
---@param jobId string
---@param oldSimId string
---@param handsetId string
---@param phoneNumber string
---@param citizenId string
function Sims.prepareReplacement(newSimId, jobId, oldSimId, handsetId, phoneNumber, citizenId)
    Db.insert(
        "INSERT INTO phone_sims (id, phone_number, owner_citizenid, status) VALUES (?, ?, ?, 'blocked')",
        { newSimId, phoneNumber, citizenId })
    Db.insert(
        'INSERT INTO phone_sim_replacements (id, old_sim_id, new_sim_id, handset_id, citizenid) VALUES (?, ?, ?, ?, ?)',
        { jobId, oldSimId, newSimId, handsetId, citizenId })
end

---@param newSimId string
function Sims.cancelReplacement(newSimId)
    Db.write("UPDATE phone_sim_replacements SET state = 'cancelled' WHERE new_sim_id = ?", { newSimId })
end

---@param newSimId string
---@param handsetId string
---@return table|nil job The prepared replacement joined with the new SIM's number.
function Sims.findPreparedReplacement(newSimId, handsetId)
    return Db.row([[
        SELECT r.*, s.phone_number FROM phone_sim_replacements r
        JOIN phone_sims s ON s.id = r.new_sim_id
        WHERE r.new_sim_id = ? AND r.handset_id = ? AND r.state = 'prepared'
    ]], { newSimId, handsetId })
end

---@param simId string
---@return string|nil handsetId
function Sims.handsetOf(simId)
    local row = Db.row('SELECT handset_id FROM phone_sims WHERE id = ?', { simId })
    return row and row.handset_id or nil
end

---Activates the replacement: frees the number from every device, revokes older SIMs, attaches the new one.
---@param job table From findPreparedReplacement.
---@param newSimId string
---@param handsetId string
---@return boolean
function Sims.activateReplacement(job, newSimId, handsetId)
    return Db.transaction({
        {
            sql = "UPDATE phone_devices SET phone_number = CONCAT('@', LEFT((SELECT h.id FROM phone_handsets h "
                .. 'WHERE h.device_id = phone_devices.id), 20)) WHERE phone_number = ?',
            params = { job.phone_number },
        },
        {
            sql = "UPDATE phone_sims SET status = 'revoked', handset_id = NULL WHERE phone_number = ? AND id <> ?",
            params = { job.phone_number, newSimId },
        },
        {
            sql = "UPDATE phone_sims SET status = 'active', handset_id = ? WHERE id = ?",
            params = { handsetId, newSimId },
        },
        { sql = "UPDATE phone_sim_replacements SET state = 'complete' WHERE id = ?", params = { job.id } },
    })
end
