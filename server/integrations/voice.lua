QBPhone = QBPhone or {}
QBPhone.Integrations = QBPhone.Integrations or {}

local Voice = {}
QBPhone.Integrations.Voice = Voice

local function invoke(name, source, channel)
    local ok, result = pcall(function()
        return exports['pma-voice'][name](source, channel)
    end)
    return ok and result ~= false
end

-- Call membership is assigned only by the server. qbvoice exposes this through
-- its pma-voice compatibility surface; a real pma-voice provides the same API.
function Voice.join(firstSource, secondSource, channel)
    if not invoke('setPlayerCall', firstSource, channel) then return false end
    if invoke('setPlayerCall', secondSource, channel) then return true end
    invoke('removePlayerFromCall', firstSource, channel)
    return false
end

function Voice.leave(source, channel)
    if source then invoke('removePlayerFromCall', source, channel) end
end
