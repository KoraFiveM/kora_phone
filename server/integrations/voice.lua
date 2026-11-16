KoraPhone = KoraPhone or {}
KoraPhone.Integrations = KoraPhone.Integrations or {}

---Server side of the phone call voice integration, built on kora_voice's
---trusted call exports (`setPlayerCall`, `removePlayerFromCall`).
---Call membership is assigned only here, never by a client.
local Voice = {}
KoraPhone.Integrations.Voice = Voice

---@param source integer|nil
---@param channel integer
---@return boolean
local function assign(source, channel)
    if type(source) ~= 'number' then return false end
    local ok, result = pcall(exports.kora_voice.setPlayerCall, exports.kora_voice, source, channel)
    if not ok then
        Kora.logging.warn(
            'voice.assign_failed',
            'kora_voice setPlayerCall failed',
            { source = source, error = tostring(result) }
        )
        return false
    end
    return result ~= false
end

---Puts both parties on the call channel; rolls back the first if the second fails.
---@param firstSource integer
---@param secondSource integer
---@param channel integer
---@return boolean
function Voice.join(firstSource, secondSource, channel)
    if not assign(firstSource, channel) then return false end
    if assign(secondSource, channel) then return true end
    Voice.leave(firstSource, channel)
    return false
end

---Removes a player from the call channel (only if still on that channel).
---@param source integer|nil
---@param channel integer|nil
function Voice.leave(source, channel)
    if type(source) ~= 'number' then return end
    local ok, err = pcall(exports.kora_voice.removePlayerFromCall, exports.kora_voice, source, channel)
    if not ok then
        Kora.logging.warn(
            'voice.leave_failed',
            'kora_voice removePlayerFromCall failed',
            { source = source, error = tostring(err) }
        )
    end
end
