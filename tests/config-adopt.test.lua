-- The real config files must register cleanly with kora_lib's config consumer, keep their shape and defaults, and
-- keep the server-only settings out of the client snapshot. Uses the sibling ../kora_lib checkout and skips
-- without it. Run from the resource root: lua5.4 tests/config-adopt.test.lua
local consumerPath = '../kora_lib/modules/config/consumer.lua'
local probe = io.open(consumerPath)
if not probe then print('SKIP config adoption: ../kora_lib is not checked out next to this resource'); return end
probe:close()

local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function equal(actual, expected, message)
    assert(actual == expected, ('%s: expected %s, got %s'):format(message or 'value', tostring(expected), tostring(actual)))
    checks = checks + 1
end

local files, registrations = {}, {}
local function boot(isServer)
    registrations = {}
    _G.GetCurrentResourceName = function() return 'kora_phone-stevie' end
    _G.IsDuplicityVersion = function() return isServer end
    _G.LoadResourceFile = function(_, path) return files[path] end
    _G.SaveResourceFile = function() return true end
    _G.GetInvokingResource = function() return 'kora_lib' end
    _G.TriggerClientEvent = function() end
    _G.TriggerServerEvent = function() end
    _G.TriggerEvent = function() end
    _G.AddEventHandler = function() end
    _G.RegisterNetEvent = function() end
    _G.SetTimeout = function(_, fn) fn() end
    _G.exports = setmetatable({}, { __call = function() end })
    local library = { config_register = function(_, definition) registrations[#registrations + 1] = definition; return true end }
    local config = dofile(consumerPath)(library)
    _G.Kora = { config = config }
    _G.Config = nil
    dofile('config/shared.lua')
    dofile('config/handsets.lua')
    dofile('config/client.lua')
    dofile('config/register.lua')
    if isServer then
        dofile('config/server.lua')
    end
    return config
end

-- server realm: everything registers, defaults unchanged
boot(true)
check(Config.compat.koraPhoneExports.enabled == true, 'compat.koraPhoneExports.enabled defaults to true')
equal(Config.Server.AutoMigrate, true)
equal(Config.Server.RateLimits.mutation.capacity, 12)
equal(Config.Server.RateLimits['community.read'].capacity, 25, 'dotted rate limit keys survive adoption')
equal(Config.Calls.RingTimeoutMs, 30000)
equal(Config.Calls.Video.IceServers[1].urls, 'stun:stun.l.google.com:19302')
equal(Config.PhoneServices.shops.legion.prices.phone_sim, 100)
equal(Config.PhoneServices.shops.technician.job, 'mechanic')
equal(Config.Handsets.phone_flip, 'flip')
equal(Config.Client.Command, 'phone')
equal(Config.Camera.zoom.selfie.minFov, 30.0)
check(type(Config.Server.Wallet.Licences) == 'table' and #Config.Server.Wallet.Licences == 3, 'licence list is intact')
check(#registrations >= 1, 'the schema was announced to kora_lib')
local snapshot = registrations[#registrations].client
check(type(snapshot) == 'table' and snapshot.Server == nil and snapshot.Calls == nil, 'server-only settings are not in the client snapshot')
check(snapshot.compat and snapshot.compat.koraPhoneExports.enabled == true, 'shared settings are in the client snapshot')
check(snapshot.PhoneServices ~= nil and snapshot.Camera ~= nil, 'client and shared settings are registered')

-- client realm: no Server or Calls branch exists, the shared settings still register
boot(false)
check(Config.Server == nil and Config.Calls == nil, 'the client never loads the server-only settings')
check(Config.compat.koraPhoneExports.enabled == true, 'the client sees the compat key')

-- a saved override reaches the running config (server realm)
files['config.local.lua'] = "return { compat = { koraPhoneExports = { enabled = false } }, Server = { AutoMigrate = false } }"
boot(true)
equal(Config.compat.koraPhoneExports.enabled, false, 'config.local.lua can turn the kora_phone exports off')
equal(Config.Server.AutoMigrate, false, 'a server-only override applies')
equal(Config.Calls.RingTimeoutMs, 30000, 'untouched settings keep their defaults')

print(('PASS config adoption: %d checks'):format(checks))
