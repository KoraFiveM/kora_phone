QBPhone = QBPhone or {}

local State = {
    open = false,
    ready = false,
    playerLoaded = false,
    initialData = nil,
    currentApp = nil,
    activeCall = nil,
    cameraMode = false,
    phoneProp = nil,
    phoneObject = nil,
    generation = 0,
    quiet = false,
}

local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

function State.ResetCharacter()
    State.generation = State.generation + 1
    State.ready = false
    State.playerLoaded = false
    State.initialData = nil
    State.currentApp = nil
    State.activeCall = nil
    State.cameraMode = false
end

function State.Public()
    return {
        open = State.open,
        ready = State.ready,
        playerLoaded = State.playerLoaded,
        currentApp = State.currentApp,
        activeCall = clone(State.activeCall),
        cameraMode = State.cameraMode,
    }
end

QBPhone.State = State

