KoraPhone = KoraPhone or {}
local Voice = { provider = 'none', channel = nil, muted = false, speaker = false }

local function resourceStarted(name)
    return GetResourceState(name) == 'started'
end

function Voice.Detect()
    Voice.provider = resourceStarted('pma-voice') and 'pma-voice' or 'none'
    return Voice.provider
end

function Voice.Leave()
    Voice.channel = nil
    Voice.muted = false
    Voice.speaker = false
end

function Voice.SetMuted(value)
    -- pma-voice does not expose a call-only microphone mute. The native
    -- per-player mute API alters receive state, not this player's microphone.
    Voice.muted = false
    return false, 'CALL_MUTE_UNSUPPORTED'
end

function Voice.SetSpeaker(value)
    -- Speaker is presentation/volume policy only; pma call routing stays private.
    Voice.speaker = value == true
    return true
end

function Voice.Capabilities()
    return { provider = Voice.Detect(), available = Voice.provider ~= 'none' }
end

KoraPhone.Voice = Voice