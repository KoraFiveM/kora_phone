KoraPhone = KoraPhone or {}

---Client side of the phone call voice integration (kora_voice).
---SetMuted calls kora_voice's call-only microphone mute (proximity and radio keep
---working); speaker is a presentation flag only, because kora_voice has no call
---volume boost and call routing stays private and server-owned.
local Voice = { channel = nil, muted = false, speaker = false }

---Current call channel as published by the server, or false.
---@return integer|false
function Voice.CallChannel()
    local ok, channel = pcall(exports.kora_voice.getCallChannel, exports.kora_voice)
    return ok and channel or false
end

function Voice.Leave()
    Voice.channel = nil
    Voice.muted = false
    Voice.speaker = false
end

---@param value boolean
---@return boolean ok, string|nil err
function Voice.SetMuted(value)
    local wanted = value == true
    local called, ok, reason = pcall(exports.kora_voice.setCallMuted, exports.kora_voice, wanted)
    if not called then
        Kora.logging.warn('voice.mute_failed', 'kora_voice setCallMuted failed', { error = tostring(ok) })
        return false, 'CALL_MUTE_FAILED'
    end
    if ok ~= true then
        Voice.muted = false
        return false, reason or 'CALL_MUTE_FAILED'
    end
    Voice.muted = wanted
    return true
end

---@param value boolean
---@return boolean
function Voice.SetSpeaker(value)
    Voice.speaker = value == true
    return true
end

---@return { provider: string, available: boolean, inCall: boolean }
function Voice.Capabilities()
    return { provider = 'kora_voice', available = true, inCall = Voice.CallChannel() ~= false }
end

KoraPhone.Voice = Voice
