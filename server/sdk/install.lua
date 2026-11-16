KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Per-device install state for third-party apps. It lives in the existing device settings
-- JSON under `sdkApps` as { [appId] = true|false }. An absent id falls back to the app's
-- `defaultInstalled`, so an explicit `false` records "the player removed a default app".
--
-- `settings:save` rewrites the whole settings object, so Phone.saveSettings must call
-- `Install.preserve(previousSettingsJson, newSettings)` before encoding (see the SDK docs).
local Install = {}
KoraPhone.SDK.Install = Install

local function decode(settingsJson)
    if type(settingsJson) ~= 'string' or settingsJson == '' then return {} end
    local ok, decoded = pcall(json.decode, settingsJson)
    return ok and type(decoded) == 'table' and decoded or {}
end

function Install.state(device)
    local sdkApps = decode(device.settingsJson).sdkApps
    return type(sdkApps) == 'table' and sdkApps or {}
end

function Install.isInstalled(device, app)
    local value = Install.state(device)[app.id]
    if value == nil then return app.defaultInstalled == true end
    return value == true
end

--- Copies the stored `sdkApps` into `newSettings` (a table about to be saved).
function Install.preserve(previousSettingsJson, newSettings)
    local sdkApps = decode(previousSettingsJson).sdkApps
    if type(sdkApps) == 'table' and type(newSettings) == 'table' then newSettings.sdkApps = sdkApps end
    return newSettings
end

---@return boolean ok
function Install.set(device, appId, installed)
    local settings = decode(device.settingsJson)
    settings.sdkApps = type(settings.sdkApps) == 'table' and settings.sdkApps or {}
    settings.sdkApps[appId] = installed == true
    local encoded = json.encode(settings)
    if not KoraPhone.Repositories.Phones.updateSettings(device.id, encoded) then return false end
    device.settingsJson = encoded
    return true
end

--- Ids of every registered app installed on the device.
function Install.list(device)
    local ids = {}
    for _, app in ipairs(KoraPhone.SDK.Registry.list()) do
        if Install.isInstalled(device, app) then ids[#ids + 1] = app.id end
    end
    return ids
end
