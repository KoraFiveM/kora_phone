-- Alarms ring from here, not from the page, so they go off with the phone closed (the page only exists while it is open).
-- The list comes from the server when the character loads and again whenever the page changes it.
local app = Phone.app('clock')

local alarms = {}
local rang = {}       -- alarm id -> the minute it last rang, so one minute never rings twice

-- Day of week (0 = Sunday) of a calendar date, so the repeat days match the player's own clock.
local function weekday(year, month, day)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if month < 3 then year = year - 1 end
    return (year + year // 4 - year // 100 + year // 400 + t[month] + day) % 7
end

local function clean(list)
    local out = {}
    for _, alarm in ipairs(type(list) == 'table' and list or {}) do
        if type(alarm) == 'table' and type(alarm.id) == 'string' and type(alarm.time) == 'string' and alarm.time:match('^%d%d:%d%d$') then
            out[#out + 1] = { id = alarm.id, label = type(alarm.label) == 'string' and alarm.label:sub(1, 60) or '', time = alarm.time,
                days = type(alarm.days) == 'table' and alarm.days or {}, enabled = alarm.enabled == true }
        end
    end
    return out
end

local function sync()
    local ok, result = pcall(Kora.callback.trigger, 'app:clock:list')
    if ok and type(result) == 'table' and result.ok then alarms = clean(result.data) return true end
    return false
end

local function ring(alarm)
    Kora.notify.send({
        title = Kora.lang('title.alarm'),
        message = alarm.label ~= '' and alarm.label or Kora.lang('notify.alarm_untitled'),
        type = 'info', duration = 8000,
    })
    for i = 0, 2 do
        Kora.timers.setTimeout(function() Kora.sound.playFrontend('Beep_Green', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', { network = true }) end, i * 350)
    end
    app.push('ring', { id = alarm.id })
end

local function tick()
    if not KoraPhone.State.playerLoaded or #alarms == 0 then return end
    local year, month, day, hour, minute = GetLocalTime()
    local now = ('%02d:%02d'):format(hour, minute)
    local dow = weekday(year, month, day)
    for _, alarm in ipairs(alarms) do
        local today = #alarm.days == 0
        for _, value in ipairs(alarm.days) do if value == dow then today = true end end
        local stamp = ('%d-%d-%d %s'):format(year, month, day, now)
        if alarm.enabled and alarm.time == now and today and rang[alarm.id] ~= stamp then
            rang[alarm.id] = stamp
            ring(alarm)
            if #alarm.days == 0 then
                -- A one-time alarm turns itself off after ringing.
                alarm.enabled = false
                CreateThread(function()
                    pcall(Kora.callback.trigger, 'app:clock:save', { id = alarm.id, label = alarm.label, time = alarm.time, days = alarm.days, enabled = false })
                end)
            end
        end
    end
end

-- The page hands over its list after every change (and when it opens).
app.client('sync', function(list)
    alarms = clean(list)
    return true
end)

Kora.timers.setInterval(tick, 1000)

-- Load the list once the character is in. A PIN-locked phone refuses until it is unlocked, so keep trying quietly.
CreateThread(function()
    while not KoraPhone.State.playerLoaded do Wait(1000) end
    while not sync() do Wait(15000) end
end)
