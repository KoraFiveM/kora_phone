KoraPhone.RateLimits = KoraPhone.RateLimits or { buckets = {} }
local RateLimits = KoraPhone.RateLimits

function RateLimits.consume(source, action)
    local rule = Config.Server.RateLimits[action] or Config.Server.RateLimits.mutation
    local key = ('%s:%s'):format(source, action)
    -- os.clock measures process CPU time, so idle time does not reliably refill a
    -- network rate-limit bucket. GetGameTimer is the server's monotonic clock.
    local now = GetGameTimer() / 1000
    local bucket = RateLimits.buckets[key] or { tokens = rule.capacity, updatedAt = now }
    bucket.tokens = math.min(rule.capacity, bucket.tokens + ((now - bucket.updatedAt) * rule.refillPerSecond))
    bucket.updatedAt = now
    if bucket.tokens < 1 then RateLimits.buckets[key] = bucket; return false end
    bucket.tokens = bucket.tokens - 1
    RateLimits.buckets[key] = bucket
    return true
end

function RateLimits.clear(source)
    local prefix = tostring(source) .. ':'
    for key in pairs(RateLimits.buckets) do if key:sub(1, #prefix) == prefix then RateLimits.buckets[key] = nil end end
end