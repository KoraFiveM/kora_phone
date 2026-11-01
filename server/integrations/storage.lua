QBPhone = QBPhone or {}
local Storage = {}
QBPhone.Storage = Storage

local defaults = {
    Provider = 'disabled', TokenTtlSeconds = 120, MaxBytes = 8 * 1024 * 1024,
    MaxWidth = 8192, MaxHeight = 8192,
    AllowedMimeTypes = { 'image/jpeg', 'image/png', 'image/webp' },
    AllowedVideoMimeTypes = { 'video/webm', 'video/mp4' },
    MaxVideoBytes = 24 * 1024 * 1024, MaxVideoSeconds = 15, MaxImagesPerDevice = 300, MaxVideosPerDay = 20,
    AllowedPublicHosts = {}, LocalDirectory = 'local-media',
    CleanupIntervalMinutes = 30, DeletedRetentionHours = 24, CleanupBatchSize = 25,
    External = { BrokerUrl = '', VerifyUrl = '', DeleteUrl = '', Secret = '' },
    -- Fivemanage's media API. The API token is only ever read on the server; the phone gets a short-lived
    -- presigned upload URL for one file. RequireTag makes the server insist the uploaded file carries this
    -- ticket's tag (only possible for uploads made from the phone UI, not screenshot-basic photos).
    Fivemanage = {
        Token = '', RequireTag = false, ApiBase = 'https://api.fivemanage.com',
        UploadHosts = { 'api.fivemanage.com', 'fmapi.net' }, PublicHosts = { 'r2.fivemanage.com' }
    }
}

local function cfg()
    local configured = Config.Server.Media or {}
    setmetatable(configured, { __index = defaults })
    configured.External = configured.External or defaults.External
    setmetatable(configured.External, { __index = defaults.External })
    configured.Fivemanage = configured.Fivemanage or {}
    setmetatable(configured.Fivemanage, { __index = defaults.Fivemanage })
    return configured
end

local function isAllowed(list, value)
    for _, allowed in ipairs(list or {}) do if allowed == value then return true end end
    return false
end

local function parseHttpsHost(url)
    if type(url) ~= 'string' or #url > 2048 then return nil end
    return url:match('^https://([^/%?#:]+)')
end

local function hostAllowed(url, hosts)
    local host = parseHttpsHost(url)
    if not host then return false end
    host = host:lower()
    for _, allowed in ipairs(hosts or {}) do
        allowed = tostring(allowed):lower()
        if host == allowed then return true end
    end
    return false
end

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function decodeBase64(data)
    data = data:gsub('[^' .. b64chars .. '=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r, f = '', (b64chars:find(x, 1, true) or 1) - 1
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do if x:sub(i, i) == '1' then c = c + 2 ^ (8 - i) end end
        return string.char(c)
    end))
end

local function httpJson(url, method, payload, callback)
    PerformHttpRequest(url, function(status, body)
        local ok, decoded = pcall(json.decode, body or '')
        callback(status >= 200 and status < 300 and ok and type(decoded) == 'table', decoded, status)
    end, method, json.encode(payload), { ['Content-Type'] = 'application/json' })
end

function Storage.provider()
    local provider = tostring(cfg().Provider):lower()
    if provider ~= 'disabled' and provider ~= 'local-development' and provider ~= 'external' and provider ~= 'fivemanage' then return 'disabled' end
    return provider
end

-- Video needs a provider that can take a file from the phone itself.
function Storage.supportsVideo()
    local provider = Storage.provider()
    return provider == 'fivemanage' or provider == 'external'
end

function Storage.isVideo(mimeType)
    return isAllowed(cfg().AllowedVideoMimeTypes, mimeType)
end

function Storage.maxBytesFor(mimeType)
    local c = cfg()
    return Storage.isVideo(mimeType) and c.MaxVideoBytes or c.MaxBytes
end

function Storage.validateRequest(mimeType, byteSize)
    local c = cfg()
    local video = Storage.isVideo(mimeType)
    if not video and not isAllowed(c.AllowedMimeTypes, mimeType) then return false, 'UNSUPPORTED_MEDIA_TYPE' end
    if video and not Storage.supportsVideo() then return false, 'VIDEO_UNSUPPORTED' end
    if type(byteSize) ~= 'number' or byteSize < 1 or byteSize > Storage.maxBytesFor(mimeType) then return false, 'MEDIA_TOO_LARGE' end
    return true
end

local function fivemanageToken()
    local convar = GetConvar('kora_fivemanage_token', '')
    if convar ~= '' then return convar end
    return tostring(cfg().Fivemanage.Token or '')
end

local function newTag()
    local parts = {}
    for i = 1, 3 do parts[i] = string.format('%08x', math.random(0, 0x7fffffff)) end
    return table.concat(parts)
end

local function mergedHosts(...)
    local out = {}
    for _, list in ipairs({ ... }) do for _, host in ipairs(list or {}) do out[#out + 1] = host end end
    return out
end

function Storage.begin(ticket, callback)
    local provider, c = Storage.provider(), cfg()
    if provider == 'disabled' then return callback(false, nil, 'MEDIA_DISABLED') end
    if provider == 'local-development' then
        return callback(true, { mode = 'server-capture', token = ticket.token }, nil, { extension = ticket.mimeType == 'image/png' and 'png' or 'jpg' })
    end
    if provider == 'fivemanage' then
        local token, fm = fivemanageToken(), c.Fivemanage
        if token == '' then return callback(false, nil, 'PROVIDER_MISCONFIGURED') end
        if not hostAllowed(fm.ApiBase, fm.UploadHosts) then return callback(false, nil, 'PROVIDER_HOST_DENIED') end
        -- The token stays here. The phone only ever sees the presigned URL this call returns.
        return PerformHttpRequest(('%s/api/v3/file/presigned-url?expiresAt=%d'):format(fm.ApiBase, ticket.expiresAt), function(status, body)
            local ok, decoded = pcall(json.decode, body or '')
            local url = ok and type(decoded) == 'table' and type(decoded.data) == 'table' and decoded.data.presignedUrl
            if status < 200 or status >= 300 or type(url) ~= 'string' then
                print(('[qbphone] Fivemanage would not issue an upload URL (HTTP %s). Check the kora_fivemanage_token convar.'):format(tostring(status)))
                return callback(false, nil, 'PROVIDER_BEGIN_FAILED')
            end
            if not hostAllowed(url, fm.UploadHosts) then return callback(false, nil, 'UPLOAD_HOST_DENIED') end
            local tag = newTag()
            callback(true, { mode = 'direct-upload', token = ticket.token, uploadUrl = url, field = 'file', tag = tag }, nil, { tag = tag })
        end, 'GET', '', { Authorization = token })
    end
    if c.External.BrokerUrl == '' or c.External.VerifyUrl == '' or c.External.Secret == '' then
        return callback(false, nil, 'PROVIDER_MISCONFIGURED')
    end
    if not hostAllowed(c.External.BrokerUrl, c.AllowedProviderHosts or c.AllowedPublicHosts) then
        return callback(false, nil, 'PROVIDER_HOST_DENIED')
    end
    httpJson(c.External.BrokerUrl, 'POST', {
        secret = c.External.Secret, uploadId = ticket.token, mimeType = ticket.mimeType,
        maxBytes = ticket.byteSize, expiresAt = ticket.expiresAt
    }, function(ok, response)
        if not ok or type(response.uploadUrl) ~= 'string' or type(response.objectKey) ~= 'string' then
            return callback(false, nil, 'PROVIDER_BEGIN_FAILED')
        end
        if not hostAllowed(response.uploadUrl, c.AllowedUploadHosts or c.AllowedPublicHosts) then
            return callback(false, nil, 'UPLOAD_HOST_DENIED')
        end
        callback(true, {
            mode = 'multipart-upload', token = ticket.token, uploadUrl = response.uploadUrl,
            field = tostring(response.field or 'file'):sub(1, 32)
        }, nil, { objectKey = response.objectKey:sub(1, 512), providerReceipt = response.providerReceipt })
    end)
end

function Storage.completeLocal(source, ticket, callback)
    if GetResourceState('screenshot-basic') ~= 'started' then return callback(false, nil, 'SCREENSHOT_PROVIDER_UNAVAILABLE') end
    exports['screenshot-basic']:requestClientScreenshot(source, {
        encoding = ticket.mimeType == 'image/png' and 'png' or 'jpg', quality = 0.90
    }, function(errorMessage, data)
        if errorMessage or type(data) ~= 'string' then return callback(false, nil, 'CAPTURE_FAILED') end
        local encoded = data:match('^data:image/[%w.+-]+;base64,(.+)$')
        if not encoded then return callback(false, nil, 'CAPTURE_INVALID') end
        if #encoded > math.ceil(ticket.byteSize * 4 / 3) + 4 then return callback(false, nil, 'MEDIA_TOO_LARGE') end
        local binary = decodeBase64(encoded)
        if #binary < 1 or #binary > ticket.byteSize then return callback(false, nil, 'MEDIA_TOO_LARGE') end
        local extension = ticket.mimeType == 'image/png' and 'png' or 'jpg'
        local key = ('%s/%s.%s'):format(cfg().LocalDirectory, ticket.token, extension)
        if not SaveResourceFile(GetCurrentResourceName(), key, binary, #binary) then return callback(false, nil, 'LOCAL_WRITE_FAILED') end
        callback(true, {
            storageProvider = 'local-development', storageKey = key,
            publicUrl = ('https://cfx-nui-%s/%s'):format(GetCurrentResourceName(), key),
            mimeType = ticket.mimeType, byteSize = #binary
        })
    end)
end

function Storage.completeExternal(ticket, receipt, callback)
    local c = cfg()
    if type(receipt) ~= 'string' or #receipt < 1 or #receipt > 2048 then return callback(false, nil, 'INVALID_RECEIPT') end
    if not hostAllowed(c.External.VerifyUrl, c.AllowedProviderHosts or c.AllowedPublicHosts) then return callback(false, nil, 'PROVIDER_HOST_DENIED') end
    httpJson(c.External.VerifyUrl, 'POST', {
        secret = c.External.Secret, uploadId = ticket.token, objectKey = ticket.providerData.objectKey, receipt = receipt
    }, function(ok, response)
        if not ok or response.verified ~= true then return callback(false, nil, 'UPLOAD_NOT_VERIFIED') end
        local actualBytes = tonumber(response.byteSize)
        local width, height = tonumber(response.width), tonumber(response.height)
        if response.mimeType ~= ticket.mimeType or not actualBytes or actualBytes < 1 or actualBytes > ticket.byteSize then
            return callback(false, nil, 'UPLOAD_MISMATCH')
        end
        if not Storage.isVideo(ticket.mimeType) and (not width or not height or width < 1 or height < 1 or width > c.MaxWidth or height > c.MaxHeight) then
            return callback(false, nil, 'MEDIA_DIMENSIONS_INVALID')
        end
        if response.checksum ~= nil and (type(response.checksum) ~= 'string' or #response.checksum > 128) then
            return callback(false, nil, 'CHECKSUM_INVALID')
        end
        if not hostAllowed(response.publicUrl, c.AllowedPublicHosts) then return callback(false, nil, 'PUBLIC_HOST_DENIED') end
        callback(true, {
            storageProvider = 'external', storageKey = ticket.providerData.objectKey,
            publicUrl = response.publicUrl, mimeType = response.mimeType, byteSize = actualBytes,
            width = width, height = height, checksum = response.checksum
        })
    end)
end

-- The phone uploaded straight to Fivemanage; the server checks what actually arrived before recording it.
-- The metadata endpoint gives the real size, type and public URL, so nothing the phone says is trusted.
function Storage.completeFivemanage(ticket, receipt, callback)
    local c = cfg()
    local fm = c.Fivemanage
    if type(receipt) ~= 'string' or not receipt:match('^[%w_%-]+$') or #receipt < 6 or #receipt > 64 then return callback(false, nil, 'INVALID_RECEIPT') end
    local token = fivemanageToken()
    if token == '' or not hostAllowed(fm.ApiBase, fm.UploadHosts) then return callback(false, nil, 'PROVIDER_MISCONFIGURED') end
    PerformHttpRequest(('%s/api/v3/file/%s'):format(fm.ApiBase, receipt), function(status, body)
        local ok, decoded = pcall(json.decode, body or '')
        local file = ok and type(decoded) == 'table' and type(decoded.data) == 'table' and decoded.data or nil
        if status < 200 or status >= 300 or not file or tostring(file.id) ~= receipt then return callback(false, nil, 'UPLOAD_NOT_VERIFIED') end
        local size = tonumber(file.size)
        if not size or size < 1 or size > ticket.byteSize then
            print(('[qbphone] Upload size mismatch: provider=%s, maximum=%s'):format(tostring(size), tostring(ticket.byteSize)))
            return callback(false, nil, 'UPLOAD_MISMATCH')
        end
        -- Providers may report a media category, MIME type, or bare extension.
        local kind = tostring(file.type or ''):lower()
        local major, minor = ticket.mimeType:match('^(%a+)/(.+)$')
        if kind ~= '' and not (kind == major or kind:find('^' .. major .. '/') or kind == minor or (minor == 'jpeg' and kind == 'jpg')) then
            print(('[qbphone] Upload type mismatch: provider=%s, expected=%s'):format(kind, ticket.mimeType))
            return callback(false, nil, 'UPLOAD_MISMATCH')
        end
        local hosts = mergedHosts(fm.PublicHosts, c.AllowedPublicHosts)
        local url = hostAllowed(file.url, hosts) and file.url or (hostAllowed(file.originalUrl, hosts) and file.originalUrl or nil)
        if not url then return callback(false, nil, 'PUBLIC_HOST_DENIED') end
        local metadata = file.metadata
        if type(metadata) == 'string' then local parsed, value = pcall(json.decode, metadata); metadata = parsed and value or nil end
        local tag = type(metadata) == 'table' and metadata.qbphoneTicket or nil
        if tag ~= nil and tag ~= ticket.providerData.tag then return callback(false, nil, 'UPLOAD_NOT_BOUND') end
        if tag == nil and fm.RequireTag == true then
            print('[qbphone] An upload arrived without its ticket tag. Fivemanage may not return metadata; set Config.Server.Media.Fivemanage.RequireTag = false if this is expected.')
            return callback(false, nil, 'UPLOAD_NOT_BOUND')
        end
        callback(true, { storageProvider = 'fivemanage', storageKey = receipt, publicUrl = url, mimeType = ticket.mimeType, byteSize = size })
    end, 'GET', '', { Authorization = token })
end

function Storage.delete(record, callback)
    -- Fivemanage's API has no delete call, so the file stays in their storage (their retention settings apply)
    -- and the phone forgets it.
    if record.storageProvider == 'fivemanage' then return callback(true) end
    if record.storageProvider == 'local-development' then
        -- FiveM has no safe portable delete primitive. The row is removed; documented maintenance cleans orphaned dev files.
        return callback(true)
    end
    local c = cfg()
    if record.storageProvider ~= 'external' or c.External.DeleteUrl == '' then return callback(false) end
    if not hostAllowed(c.External.DeleteUrl, c.AllowedProviderHosts or c.AllowedPublicHosts) then return callback(false) end
    httpJson(c.External.DeleteUrl, 'POST', { secret = c.External.Secret, objectKey = record.storageKey }, function(ok) callback(ok) end)
end

Storage.Config = cfg
