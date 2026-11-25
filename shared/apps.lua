KoraPhone = KoraPhone or {}

-- The one way to define a phone app that lives in this resource's `apps/<id>/` folder.
--
--   apps/notes/app.lua      Phone.app('notes', { name = 'Notes', icon = 'notebook', ... })   (shared realm)
--   apps/notes/server.lua   local app = Phone.app('notes'); app.callback('save', function(source, payload) ... end)
--   apps/notes/client.lua   local app = Phone.app('notes'); app.client('position', function(payload) ... end)
--   apps/notes/ui/          index.html plus whatever the UI needs
--
-- `Phone.app(id, definition)` records a definition (static data, validated by the same
-- KoraPhone.SDK.Manifest every other app goes through). `Phone.app(id)` returns the handle for that
-- app. The handle's methods are added by server/sdk/apps.lua and client/sdk/apps.lua, so the same
-- `Phone.app` call works in every realm.
--
-- Folder apps are trusted code, exactly like any resource the server owner starts: their Lua runs in
-- this resource and their UI is served from this resource's origin. Manifest permissions are enforced
-- for iframe UIs; see docs/apps.md "Trust".
local Apps = { defs = {}, order = {}, methods = {} }
KoraPhone.Apps = Apps

Apps.FIELDS = {
    name = true, description = true, icon = true, ui = true, version = true, permissions = true, job = true,
    defaultInstalled = true, price = true, category = true, system = true, storage = true, staff = true,
}

---Where a file lives in the resource, from the chunk name FiveM gives it (`@kora_phone/apps/notes/app.lua`).
---@param level integer stack level of the file that called Phone.app
---@return string? folder the `apps/<folder>/` segment, nil when the caller is not inside one
local function callerFolder(level)
    if not (debug and debug.getinfo) then return nil end
    local info = debug.getinfo(level, 'S')
    local source = info and info.source
    return type(source) == 'string' and source:match('apps[/\\]([^/\\]+)[/\\]') or nil
end

---Turns a folder-app definition into the manifest table KoraPhone.SDK.Manifest validates.
---@param id string
---@param def table
---@return table manifest
function Apps.manifest(id, def)
    local ui = def.ui or 'ui/index.html'
    local icon = def.icon
    -- An .svg icon ships inside the app folder: apps/<id>/icon.svg. The host draws it as a theme-coloured mask.
    if type(icon) == 'string' and icon:match('^[%w_%-%./]+%.svg$') and not icon:find('..', 1, true) then
        icon = ('nui://%s/apps/%s/%s'):format(GetCurrentResourceName(), id, icon)
    end
    return {
        id = id, name = def.name, description = def.description, icon = icon,
        entry = ('apps/%s/%s'):format(id, ui), version = def.version or '1.0.0',
        permissions = def.permissions, job = def.job, defaultInstalled = def.defaultInstalled,
        price = def.price, category = def.category, system = def.system, storage = def.storage, staff = def.staff,
    }
end

local function define(id, def, level)
    if type(id) ~= 'string' or id == '' then error('Phone.app(id, definition): id must be a string', level) end
    if type(def) ~= 'table' then error('Phone.app: definition must be a table', level) end
    local folder = callerFolder(level + 1)
    if folder and folder ~= id then
        error(('Phone.app: app %q is defined in apps/%s/, the folder name must match the id'):format(id, folder), level)
    end
    for key in pairs(def) do
        if not Apps.FIELDS[key] then error(('Phone.app(%q): unknown field %s'):format(id, tostring(key)), level) end
    end
    if Apps.defs[id] then error(('Phone.app: app %q is already defined'):format(id), level) end
    Apps.defs[id] = def
    Apps.order[#Apps.order + 1] = id
end

---@param id string
---@param def? table when given the app is defined; without it the existing app's handle is returned
function Apps.app(id, def)
    if def ~= nil then define(id, def, 3) end
    if not Apps.defs[id] then error(('Phone.app(%q): no such app is defined (does apps/%s/app.lua run first?)'):format(tostring(id), tostring(id)), 2) end
    return Apps.handle(id)
end

local handles = {}

---@param id string
---@return table handle
function Apps.handle(id)
    if handles[id] then return handles[id] end
    local handle = { id = id }
    setmetatable(handle, { __index = function(_, key)
        local method = Apps.methods[key]
        if not method then return nil end
        return function(...) return method(id, ...) end
    end })
    handles[id] = handle
    return handle
end

Phone = Phone or {}
Phone.app = Apps.app
