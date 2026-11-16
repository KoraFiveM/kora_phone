KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Finds apps declared through `kora_phone_app 'app.json'` in a resource's fxmanifest.
local Discovery = {}
KoraPhone.SDK.Discovery = Discovery

Discovery.METADATA_KEY = 'kora_phone_app'
Discovery.MAX_JSON_BYTES = 16 * 1024

--- The `file` / `files` patterns of a resource, or nil when they can not be read.
function Discovery.files(resource)
    if not GetNumResourceMetadata then return nil end
    local files = {}
    for _, key in ipairs({ 'file', 'files' }) do
        for index = 0, (GetNumResourceMetadata(resource, key) or 0) - 1 do
            local value = GetResourceMetadata(resource, key, index)
            if type(value) == 'string' then files[#files + 1] = value end
        end
    end
    return files
end

local function reject(resource, reason)
    Kora.logging.warn('phone.sdk.manifest_rejected', 'App manifest rejected', { resource = resource, error = reason })
    return false, reason
end

--- Registers every `kora_phone_app` manifest of `resource`. Returns the number registered.
function Discovery.scan(resource)
    if resource == GetCurrentResourceName() then return 0 end
    local declared = GetNumResourceMetadata(resource, Discovery.METADATA_KEY) or 0
    local registered = 0
    for index = 0, declared - 1 do
        local path = GetResourceMetadata(resource, Discovery.METADATA_KEY, index)
        local raw = type(path) == 'string' and LoadResourceFile(resource, path) or nil
        if not raw then
            reject(resource, ('cannot read %s'):format(tostring(path)))
        elseif #raw > Discovery.MAX_JSON_BYTES then
            reject(resource, ('%s is larger than %d bytes'):format(path, Discovery.MAX_JSON_BYTES))
        else
            local ok, manifest = pcall(json.decode, raw)
            if not ok or type(manifest) ~= 'table' then
                reject(resource, ('%s is not valid JSON'):format(path))
            else
                local added, err = KoraPhone.SDK.Registry.register(manifest, resource, { files = Discovery.files })
                if added then registered = registered + 1 else reject(resource, err) end
            end
        end
    end
    return registered
end

--- Scans every resource that is already started (called once when the phone starts).
function Discovery.scanAll()
    local total = 0
    for index = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(index)
        if resource and GetResourceState(resource) == 'started' then total = total + Discovery.scan(resource) end
    end
    return total
end
