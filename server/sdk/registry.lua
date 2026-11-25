KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Server-side app registry. One entry per app id, owned by the resource that registered it
-- (first registrant wins; the same resource may re-register, e.g. after a restart).
local Registry = { apps = {}, removeListeners = {} }
KoraPhone.SDK.Registry = Registry

---@param raw table manifest as declared by the app
---@param resource string owning resource
---@param opts? { files?: fun(resource: string): string[]? }
---@return boolean ok
---@return string? err
function Registry.register(raw, resource, opts)
    if type(resource) ~= 'string' or resource == '' then return false, 'INVALID_MANIFEST: unknown resource' end
    local manifest, err = KoraPhone.SDK.Manifest.validate(raw)
    if not manifest then return false, err end

    local existing = Registry.apps[manifest.id]
    if existing and existing.resource ~= resource then
        return false, ('CONFLICT: app id %s is owned by %s'):format(manifest.id, existing.resource)
    end

    local listFiles = opts and opts.files
    local files = listFiles and listFiles(resource)
    if files and not KoraPhone.SDK.Manifest.fileListed(files, manifest.entry) then
        return false, ('INVALID_MANIFEST: entry %s is not listed in the files of %s'):format(manifest.entry, resource)
    end

    manifest.resource = resource
    Registry.apps[manifest.id] = manifest
    return true
end

function Registry.get(id)
    return type(id) == 'string' and Registry.apps[id] or nil
end

--- Registers a function called with (appId) after an app is removed.
function Registry.onRemove(listener)
    Registry.removeListeners[#Registry.removeListeners + 1] = listener
end

---@param id string
---@param resource? string when given, only the owning resource may remove the app
function Registry.remove(id, resource)
    local app = Registry.get(id)
    if not app then return false end
    if resource and app.resource ~= resource then return false end
    Registry.apps[id] = nil
    for _, listener in ipairs(Registry.removeListeners) do listener(id) end
    return true
end

function Registry.removeByResource(resource)
    local ids = {}
    for id, app in pairs(Registry.apps) do
        if app.resource == resource then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do Registry.remove(id) end
    return #ids
end

--- Sorted array of every registered app.
function Registry.list()
    local list = {}
    for _, app in pairs(Registry.apps) do list[#list + 1] = app end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function Registry.url(app)
    return ('https://cfx-nui-%s/%s'):format(app.resource, app.entry)
end

--- Whether `source` may see and use the app. A `staff` app is for moderators only (server-side, not a display filter).
function Registry.visibleTo(app, source)
    if not app.staff then return true end
    local moderation = KoraPhone.Services and KoraPhone.Services.Moderation
    return moderation ~= nil and type(source) == 'number' and moderation.isModerator(source) == true
end

-- Job gating is a display filter only: it decides what the store shows.
function Registry.jobMatches(app, job)
    if not app.job then return true end
    if type(job) ~= 'table' or not job.name then return false end
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    grade = tonumber(grade) or 0
    for _, rule in ipairs(app.job) do
        if rule.name == job.name and (rule.grade == nil or grade >= rule.grade) then return true end
    end
    return false
end
