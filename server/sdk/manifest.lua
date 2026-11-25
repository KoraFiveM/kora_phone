KoraPhone = KoraPhone or {}
KoraPhone.SDK = KoraPhone.SDK or {}

-- Strict validation of a third-party app manifest. `validate` returns a fresh, normalised
-- manifest table, or `nil, 'INVALID_MANIFEST: <reason>'`. Nothing from the raw input is
-- kept by reference, so a caller can not mutate a registered manifest afterwards.
local Manifest = {}
KoraPhone.SDK.Manifest = Manifest

Manifest.PERMISSIONS = {
    notify = true, storage = true, ['contacts.read'] = true, ['contacts.write'] = true,
    ['media.read'] = true, location = true, payments = true,
}

local FIELDS = {
    id = true, name = true, description = true, icon = true, entry = true, version = true,
    permissions = true, job = true, defaultInstalled = true, price = true,
    category = true, system = true, storage = true, staff = true,
}

Manifest.STORAGE_MAX = { keys = 512, totalBytes = 1024 * 1024 }
Manifest.CATEGORIES = { tools = true, life = true, social = true, games = true, system = true }

Manifest.ID_PATTERN = '^[a-z0-9][a-z0-9_-]+$'
Manifest.LIMITS = { id = 32, name = 24, description = 120, version = 32, icon = 256, entry = 200 }

local function fail(reason)
    return nil, 'INVALID_MANIFEST: ' .. reason
end

local function textLength(value)
    return utf8 and utf8.len(value) or #value
end

local function isText(value)
    return type(value) == 'string' and (not utf8 or utf8.len(value) ~= nil)
end

function Manifest.isValidId(id)
    return type(id) == 'string' and #id >= 2 and #id <= Manifest.LIMITS.id and id:match(Manifest.ID_PATTERN) ~= nil
end

local function validateText(raw, field, maxLength, required)
    local value = raw[field]
    if value == nil then
        if required then return nil, ('%s is required'):format(field) end
        return ''
    end
    if not isText(value) then return nil, ('%s must be a string'):format(field) end
    if required and value == '' then return nil, ('%s must not be empty'):format(field) end
    if textLength(value) > maxLength then return nil, ('%s must be at most %d characters'):format(field, maxLength) end
    return value
end

local function validateIcon(icon)
    if type(icon) ~= 'string' or icon == '' then return 'icon is required' end
    if #icon > Manifest.LIMITS.icon then return 'icon is too long' end
    if icon:match('^[a-z0-9][a-z0-9-]*$') and #icon <= 48 then return nil end
    if icon:match('^https://[^%s]+$') then return nil end
    if icon:match('^nui://[%w_.-]+/[^%s]+$') and not icon:find('..', 1, true) then return nil end
    return 'icon must be a lucide icon name, an https:// URL or a nui://resource/path'
end

local function validateEntry(entry)
    if type(entry) ~= 'string' or entry == '' then return 'entry is required' end
    if #entry > Manifest.LIMITS.entry then return 'entry is too long' end
    if not entry:match('^[%w_%-%./]+$') then return 'entry contains unsupported characters' end
    if entry:sub(1, 1) == '/' or entry:find('..', 1, true) or entry:find('//', 1, true) then
        return 'entry must be a relative path inside the app resource'
    end
    if not entry:match('%.html?$') then return 'entry must point at an .html file' end
    return nil
end

local function validatePermissions(list)
    if list == nil then return {} end
    if type(list) ~= 'table' then return nil, 'permissions must be an array' end
    local result, seen, count = {}, {}, 0
    for key in pairs(list) do
        count = count + 1
        if type(key) ~= 'number' then return nil, 'permissions must be an array' end
    end
    for index = 1, count do
        local permission = list[index]
        if type(permission) ~= 'string' or not Manifest.PERMISSIONS[permission] then
            return nil, ('unknown permission %s'):format(tostring(permission))
        end
        if not seen[permission] then
            seen[permission] = true
            result[#result + 1] = permission
        end
    end
    return result
end

local function jobRule(spec)
    if type(spec) == 'string' then
        if spec == '' or #spec > 64 then return nil, 'job name is invalid' end
        return { name = spec }
    end
    if type(spec) ~= 'table' then return nil, 'job must be a string, a table or an array' end
    for key in pairs(spec) do
        if key ~= 'name' and key ~= 'grade' then return nil, ('unknown job field %s'):format(tostring(key)) end
    end
    if type(spec.name) ~= 'string' or spec.name == '' or #spec.name > 64 then return nil, 'job.name is invalid' end
    if spec.grade ~= nil and (type(spec.grade) ~= 'number' or spec.grade < 0 or spec.grade ~= math.floor(spec.grade)) then
        return nil, 'job.grade must be a non-negative integer'
    end
    return { name = spec.name, grade = spec.grade }
end

-- Normalises `job` into an array of { name, grade? } rules, or nil when absent.
local function validateJob(job)
    if job == nil then return nil end
    if type(job) == 'table' and job[1] ~= nil then
        local rules = {}
        for index, spec in ipairs(job) do
            local rule, err = jobRule(spec)
            if not rule then return nil, err end
            rules[index] = rule
        end
        return rules
    end
    local rule, err = jobRule(job)
    if not rule then return nil, err end
    return { rule }
end

function Manifest.validate(raw)
    if type(raw) ~= 'table' then return fail('manifest must be a table') end
    for key in pairs(raw) do
        if not FIELDS[key] then return fail(('unknown field %s'):format(tostring(key))) end
    end
    if not Manifest.isValidId(raw.id) then
        return fail('id must match ^[a-z0-9][a-z0-9_-]{1,31}$')
    end

    local manifest = { id = raw.id }
    local err
    manifest.name, err = validateText(raw, 'name', Manifest.LIMITS.name, true)
    if err then return fail(err) end
    manifest.description, err = validateText(raw, 'description', Manifest.LIMITS.description, false)
    if err then return fail(err) end
    manifest.version, err = validateText(raw, 'version', Manifest.LIMITS.version, true)
    if err then return fail(err) end

    err = validateIcon(raw.icon)
    if err then return fail(err) end
    manifest.icon = raw.icon
    err = validateEntry(raw.entry)
    if err then return fail(err) end
    manifest.entry = raw.entry

    manifest.permissions, err = validatePermissions(raw.permissions)
    if not manifest.permissions then return fail(err) end
    manifest.job, err = validateJob(raw.job)
    if err then return fail(err) end

    if raw.defaultInstalled ~= nil and type(raw.defaultInstalled) ~= 'boolean' then
        return fail('defaultInstalled must be a boolean')
    end
    manifest.defaultInstalled = raw.defaultInstalled == true

    if raw.category ~= nil and (type(raw.category) ~= 'string' or not Manifest.CATEGORIES[raw.category]) then
        return fail('category must be one of tools, life, social, games, system')
    end
    manifest.category = raw.category or 'tools'
    if raw.storage ~= nil then
        if type(raw.storage) ~= 'table' then return fail('storage must be a table') end
        manifest.storage = {}
        for key, value in pairs(raw.storage) do
            local max = Manifest.STORAGE_MAX[key]
            if not max then return fail(('unknown storage field %s'):format(tostring(key))) end
            if type(value) ~= 'number' or value ~= math.floor(value) or value < 1 or value > max then
                return fail(('storage.%s must be an integer from 1 to %d'):format(key, max))
            end
            manifest.storage[key] = value
        end
    end
    if raw.system ~= nil and type(raw.system) ~= 'boolean' then return fail('system must be a boolean') end
    manifest.system = raw.system == true
    if raw.staff ~= nil and type(raw.staff) ~= 'boolean' then return fail('staff must be a boolean') end
    manifest.staff = raw.staff == true

    if raw.price ~= nil then
        if type(raw.price) ~= 'number' or raw.price ~= raw.price or raw.price < 0 or raw.price == math.huge then
            return fail('price must be a non-negative number')
        end
        manifest.price = raw.price
    end
    return manifest
end

-- True when `path` is covered by one of a resource's `file` / `files` patterns.
function Manifest.fileListed(patterns, path)
    for _, pattern in ipairs(patterns or {}) do
        local lua = pattern:gsub('[%^%$%(%)%%%.%[%]%+%-%?]', '%%%0')
        lua = lua:gsub('%*%*', '\1'):gsub('%*', '[^/]*'):gsub('\1', '.*')
        if path:match('^' .. lua .. '$') then return true end
    end
    return false
end
