KoraPhone = KoraPhone or {}

-- kora_lib's NUI helpers (Kora.nui.send / Kora.nui.registerCallback) run in kora_lib's resource VM and reach
-- kora_lib's own browser frame. This phone owns a separate frame, so its messages and callback routes must use
-- this resource's natives. Every NUI route in this resource goes through KoraPhone.RegisterNui below.

function KoraPhone.SendNui(action, data)
    SendNUIMessage({ action = action, data = data })
end

---Registers one NUI route in this resource's frame. The handler receives the decoded payload (always a table)
---and the reply function.
---@param name string
---@param handler fun(data: table, reply: fun(result: any))
function KoraPhone.RegisterNui(name, handler)
    assert(type(name) == 'string' and name ~= '', 'RegisterNui requires a route name')
    assert(type(handler) == 'function', 'RegisterNui requires a handler')
    RegisterNUICallback(name, function(data, reply)
        handler(type(data) == 'table' and data or {}, reply)
    end)
end

---Registers a route whose handler returns the reply synchronously.
---@param name string
---@param handler fun(data: table): any
local function route(name, handler)
    KoraPhone.RegisterNui(name, function(data, reply)
        reply(handler(data))
    end)
end

local function failure(code, message)
    return { ok = false, error = { code = code, message = message } }
end

local function stringField(value, maxLength)
    if type(value) ~= 'string' then return nil end
    return value:sub(1, maxLength)
end

local function safeReply(reply, result)
    if type(result) ~= 'table' then result = { ok = false, error = 'INVALID_SERVER_RESPONSE' } end
    reply(result)
end

-- Server-bound routes: shared/routes.json is the single source of truth (the web bundle imports the same file).
local function loadRoutes()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'shared/routes.json')
    assert(raw, 'shared/routes.json is missing; add it to the manifest files list')
    local routes = json.decode(raw)
    assert(type(routes) == 'table', 'shared/routes.json is not valid JSON')
    return routes
end

KoraPhone.Routes = loadRoutes()

for _, entry in ipairs(KoraPhone.Routes) do
    KoraPhone.RegisterNui(entry.nui, function(data, reply)
        KoraPhone.ServerCallback(entry.server, data, function(result)
            -- The UI's own bootstrap carries the held handset's model, which picks the in-hand prop.
            if entry.nui == 'bootstrap' and type(result) == 'table' and result.ok then KoraPhone.State.initialData = result.data end
            safeReply(reply, result)
        end)
    end)
end

route('phone:close', function(data)
    KoraPhone.Close(false)
    -- The UI reports why it could not open (for example no phone item) so the
    -- player gets feedback instead of an invisible phone that holds focus.
    local reason = stringField(data.error, 120)
    if reason and reason ~= '' then
        Kora.notify.send({ title = Kora.lang('title.phone'), message = reason, type = 'error', duration = 4000 })
    end
    return { ok = true }
end)

route('phone:ready', function()
    KoraPhone.State.ready = true
    return { ok = true, data = KoraPhone.State.Public() }
end)

route('route:changed', function()
    return { ok = true }
end)

route('camera:open', function(data)
    local opened, errorCode = KoraPhone.Camera.Open(data)
    return {
        ok = opened == true,
        error = errorCode,
        zoom = opened == true and KoraPhone.Camera.ZoomEnabled() or nil,
        mic = opened == true and KoraPhone.Camera.MicSettings() or nil,
        hint = opened == true and KoraPhone.Camera.Hint() or nil,
    }
end)

-- The phone cursor owns the mouse wheel while it is up, so the Camera app forwards wheel steps here.
route('camera:zoom', function(data)
    return { ok = KoraPhone.Camera.Zoom(tonumber(data.dir)) }
end)

route('camera:facing', function(data)
    return { ok = KoraPhone.Camera.SetFacing(data.front) }
end)

-- A video clip with followVoice is recording: report the game's talking state so the UI can open and close the mic.
route('camera:recording', function(data)
    return { ok = KoraPhone.Camera.SetRecording(data.active == true) }
end)

route('camera:close', function()
    KoraPhone.Camera.Close()
    return { ok = true }
end)

KoraPhone.RegisterNui('camera:capture', function(_, reply)
    KoraPhone.Camera.Capture(function(result) safeReply(reply, result) end)
end)

route('customList', function()
    return KoraPhone.CustomApps.List()
end)

-- Folder apps: the UI's `phone.client(name, payload)` reaches apps/<id>/client.lua handlers here.
route('apps:client', function(data)
    return KoraPhone.Apps.invokeClient(data.app, data.name, data.payload)
end)

-- Only the page of an app that registered itself; the UI never names a file.
route('apps:html', function(data)
    return { html = KoraPhone.SDK.ClientRegistry.html(data.app) }
end)

route('customLifecycle', function(data)
    if type(data.app) == 'string' and type(data.event) == 'string' then
        KoraPhone.CustomApps.Fire(data.app, data.event)
    end
    return { ok = true }
end)

-- Location sharing: the UI asks where the player is and, on the receiving side, sets a waypoint.
local function roundTo(value, step)
    return math.floor(value / step + 0.5) * step
end

local function locationLabel(at)
    local street = GetStreetNameFromHashKey((GetStreetNameAtCoord(at.x, at.y, at.z)))
    local zone = GetLabelText(GetNameOfZone(at.x, at.y, at.z))
    local hasStreet, hasZone = street ~= '', zone ~= 'NULL'
    if hasStreet and hasZone then return street .. ', ' .. zone end
    if hasStreet then return street end
    if hasZone then return zone end
    return Kora.lang('notify.shared_location')
end

-- The game's current waypoint (blip sprite 8) feeds the Maps app's pin.
local function currentWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return nil end
    local at = GetBlipInfoIdCoord(blip)
    return { x = math.floor(at.x + 0.5), y = math.floor(at.y + 0.5) }
end

route('location:mine', function()
    local at = Kora.cache.coords()
    local label = locationLabel(at):gsub('[%[%]|]', ''):sub(1, 60)
    return {
        ok = true,
        data = {
            x = roundTo(at.x, 0.1),
            y = roundTo(at.y, 0.1),
            label = label,
            heading = math.floor(GetEntityHeading(Kora.cache.ped()) + 0.5),
            waypoint = currentWaypoint(),
        },
    }
end)

local MAX_WORLD = 20000

KoraPhone.World = KoraPhone.World or {}

---Sets the map waypoint. Returns false for coordinates outside the world.
---@return boolean
function KoraPhone.World.Waypoint(x, y)
    x, y = tonumber(x), tonumber(y)
    if not x or not y or math.abs(x) > MAX_WORLD or math.abs(y) > MAX_WORLD then return false end
    SetNewWaypoint(x + 0.0, y + 0.0)
    return true
end

route('waypoint', function(data)
    if not KoraPhone.World.Waypoint(data.x, data.y) then
        return failure('INVALID_INPUT', Kora.lang('error.invalid_location'))
    end
    return { ok = true, data = true }
end)

-- The UI asks for a game notification when something arrives (a text, mail, a missed call) and the phone is closed.
route('notify', function(data)
    local title = stringField(data.title, 60)
    if title and not KoraPhone.State.open then
        KoraPhone.Notifications.Native(title, stringField(data.body, 120) or '', data.urgent == true)
    end
    return { ok = true }
end)

-- Weather comes straight from the game, so it matches whatever weather script the server runs.
local WEATHER = {
    'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'SMOG', 'FOGGY', 'OVERCAST', 'RAIN', 'THUNDER',
    'CLEARING', 'NEUTRAL', 'SNOW', 'BLIZZARD', 'SNOWLIGHT', 'XMAS', 'HALLOWEEN',
}

local function currentWeather()
    local current = GetPrevWeatherTypeHashName() & 0xFFFFFFFF
    for _, name in ipairs(WEATHER) do
        if (GetHashKey(name) & 0xFFFFFFFF) == current then return name end
    end
    return 'CLEAR'
end

-- World services every app may use (the Weather app's client.lua, the home screen widget).
KoraPhone.World = KoraPhone.World or {}

---@return { condition: string, hour: integer, minute: integer, rain: number }
function KoraPhone.World.Weather()
    return {
        condition = currentWeather(),
        hour = GetClockHours(),
        minute = GetClockMinutes(),
        rain = math.max(0.0, GetRainLevel() + 0.0),
    }
end

route('weather:get', function()
    return { ok = true, data = KoraPhone.World.Weather() }
end)

-- An alarm went off in the UI. With the phone closed the player still needs to notice it.
route('alarm', function(data)
    if not KoraPhone.State.open then
        local label = stringField(data.label, 60) or ''
        Kora.notify.send({
            title = Kora.lang('title.alarm'),
            message = label ~= '' and label or Kora.lang('notify.alarm_untitled'),
            type = 'info',
            duration = 8000,
        })
        Kora.sound.playFrontend('Beep_Green', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', { network = true })
    end
    return { ok = true }
end)

-- Do Not Disturb: the UI owns the setting and schedule and tells the client whether it is quiet now.
route('quiet', function(data)
    KoraPhone.State.quiet = data.quiet == true
    return { ok = true }
end)

route('calls:setMuted', function(data)
    local ok, reason = KoraPhone.Voice.SetMuted(data.muted == true)
    return { ok = ok == true, error = reason }
end)

route('calls:setSpeaker', function(data)
    local ok, reason = KoraPhone.Voice.SetSpeaker(data.speaker == true)
    return { ok = ok == true, error = reason }
end)

route('map:blips', function()
    return { ok = true, data = KoraPhone.Map.Blips() }
end)
