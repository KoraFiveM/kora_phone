-- Per-player request limits shared by every route of one rate bucket.
--
-- Why this still exists next to Kora.callback's own `rateLimit` option: the lib counts calls per
-- (callback name, player), so two routes in the same bucket would each get the full allowance, and an
-- over-limit call is answered with a bare lib error instead of the phone's RATE_LIMITED PhoneError.
-- Phone buckets are shared on purpose (all 'mutation' routes draw from one pool), so the gateway
-- enforces them here. The window maths is the same sliding window the lib uses.
--
-- Config.Server.RateLimits stays in burst/refill form (capacity, refillPerSecond). A sliding window
-- allows `max = capacity` calls per `window = capacity / refillPerSecond` seconds, which is the same
-- burst and the same sustained rate as the old token bucket.

KoraPhone.RateLimits = KoraPhone.RateLimits or { windows = {} }
local RateLimits = KoraPhone.RateLimits
RateLimits.windows = RateLimits.windows or {}

local MAX_WINDOW_MS = 86400000

---@class PhoneRateLimit
---@field max integer Calls allowed per window.
---@field window integer Window length in milliseconds.

---Limit for a bucket name; unknown names fall back to `mutation`.
---@param action string
---@return PhoneRateLimit
function RateLimits.limitFor(action)
    local rules = Config.Server.RateLimits
    local rule = rules[action] or rules.mutation
    local max = math.max(1, math.floor(rule.capacity))
    local window = math.ceil(rule.capacity / rule.refillPerSecond * 1000)
    return { max = max, window = math.min(math.max(window, 1), MAX_WINDOW_MS) }
end

---@param source integer
---@param action string
---@return boolean allowed
function RateLimits.consume(source, action)
    local limit = RateLimits.limitFor(action)
    local key = ('%s:%s'):format(source, action)
    local now = GetGameTimer()
    local state = RateLimits.windows[key]
    if not state then
        state = { times = {}, head = 1, tail = 0 }
        RateLimits.windows[key] = state
    end
    local cutoff = now - limit.window
    while state.head <= state.tail and state.times[state.head] <= cutoff do
        state.times[state.head] = nil
        state.head = state.head + 1
    end
    if state.tail - state.head + 1 >= limit.max then return false end
    state.tail = state.tail + 1
    state.times[state.tail] = now
    return true
end

---Forgets one player's history (called when their session ends).
---@param source integer
function RateLimits.clear(source)
    local prefix = tostring(source) .. ':'
    for key in pairs(RateLimits.windows) do
        if key:sub(1, #prefix) == prefix then RateLimits.windows[key] = nil end
    end
end
