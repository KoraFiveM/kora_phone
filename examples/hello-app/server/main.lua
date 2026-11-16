-- Server-side counter kept in memory per player; the UI also stores its own
-- copy through the storage permission.
local counters = {}

exports.kora_phone:RegisterAppCallback('hello', 'increment', function(source, payload)
    local step = type(payload) == 'table' and tonumber(payload.step) or 1
    step = math.max(1, math.min(10, math.floor(step or 1)))
    counters[source] = (counters[source] or 0) + step
    return { count = counters[source] }
end)

AddEventHandler('playerDropped', function()
    counters[source] = nil
end)
