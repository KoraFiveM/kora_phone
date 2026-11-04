-- Run outside FiveM with: lua tests/validation.test.lua

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write("PASS ", name, "\n")
    else
        failed = failed + 1
        io.stderr:write("FAIL ", name, ": ", tostring(err), "\n")
    end
end

local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local script = arg and arg[0] or "tests/validation.test.lua"
local root = script:gsub("[\\/]tests[\\/]validation%.test%.lua$", "")
if root == script then root = "." end

dofile(root .. "/config/shared.lua")
dofile(root .. "/shared/validation.lua")
dofile(root .. "/shared/contracts.lua")

local function valid(value) return value ~= nil end

test("string accepts bounded content", function()
    equal(PhoneValidation.string("hello", "body", 1, 10), "hello")
end)
test("string trims content", function()
    equal(PhoneValidation.string("  hello  ", "body", 1, 10), "hello")
end)
test("string rejects non-string", function()
    equal(valid(PhoneValidation.string({}, "body", 1, 10)), false)
end)
test("string rejects empty content", function()
    equal(valid(PhoneValidation.string("", "body", 1, 10)), false)
end)
test("string rejects oversized content", function()
    equal(valid(PhoneValidation.string("123456", "body", 1, 5)), false)
end)
test("string rejects null bytes", function()
    equal(valid(PhoneValidation.string("bad\0value", "body", 1, 20)), false)
end)

test("integer accepts positive integer", function()
    equal(PhoneValidation.integer(25, "amount", 1, 1000), 25)
end)
test("integer rejects zero with positive minimum", function()
    equal(valid(PhoneValidation.integer(0, "amount", 1, 1000)), false)
end)
test("integer rejects negative", function()
    equal(valid(PhoneValidation.integer(-1, "amount", 1, 1000)), false)
end)
test("integer rejects fractional", function()
    equal(valid(PhoneValidation.integer(1.5, "amount", 1, 1000)), false)
end)
test("integer normalizes numeric string", function()
    equal(PhoneValidation.integer("25", "amount", 1, 1000), 25)
end)
test("integer enforces maximum", function()
    equal(valid(PhoneValidation.integer(1001, "amount", 1, 1000)), false)
end)

test("page accepts bounded limit", function()
    local result = PhoneValidation.page({ limit = Config.Limits.PageSizeMaximum })
    equal(result.limit, Config.Limits.PageSizeMaximum)
end)
test("page accepts positive integer cursor", function()
    local result = PhoneValidation.page({ limit = 20, cursor = 42 })
    equal(result.cursor, 42)
end)
test("page rejects excessive limit", function()
    equal(valid(PhoneValidation.page({ limit = Config.Limits.PageSizeMaximum + 1 })), false)
end)
test("page rejects invalid cursor type", function()
    equal(valid(PhoneValidation.page({ limit = 20, cursor = {} })), false)
end)

test("enum accepts allowlisted value", function()
    equal(PhoneValidation.enum("busy", "state", { "idle", "busy" }), "busy")
end)
test("enum rejects unknown value", function()
    equal(valid(PhoneValidation.enum("admin", "state", { "idle", "busy" })), false)
end)

local function okSettings(overrides)
    local base = { name = "My Phone", theme = "ocean", wallpaper = "midnight", phoneStyle = "flip", volume = 0.5, scale = 1 }
    for k, v in pairs(overrides or {}) do base[k] = v end
    return base
end

test("settings accepts a valid payload and drops unknown keys", function()
    local out = PhoneValidation.settings(okSettings({ evil = "x", setupComplete = true }))
    equal(out.theme, "ocean"); equal(out.setupComplete, true); equal(out.evil, nil)
end)
test("settings applies defaults for optional fields", function()
    local out = PhoneValidation.settings({ name = "P" })
    equal(out.theme, "light"); equal(out.wallpaper, "kora_core"); equal(out.phoneStyle, "classic"); equal(out.volume, 0.5); equal(out.scale, 1)
end)
test("settings rejects empty name", function() equal(PhoneValidation.settings(okSettings({ name = "  " })), nil) end)
test("settings rejects unknown theme", function() equal(PhoneValidation.settings(okSettings({ theme = "neon" })), nil) end)
test("settings rejects out-of-range volume", function() equal(PhoneValidation.settings(okSettings({ volume = 2 })), nil) end)
test("settings rejects out-of-range scale", function() equal(PhoneValidation.settings(okSettings({ scale = 3 })), nil) end)
test("settings rejects NaN volume", function() equal(PhoneValidation.settings(okSettings({ volume = 0 / 0 })), nil) end)
test("settings rejects non-https wallpaper url", function() equal(PhoneValidation.settings(okSettings({ wallpaperUrl = "http://x/y.png" })), nil) end)
test("settings accepts https wallpaper url and empty string", function()
    equal(PhoneValidation.settings(okSettings({ wallpaperUrl = "https://x/y.png" })).wallpaperUrl, "https://x/y.png")
    equal(PhoneValidation.settings(okSettings({ wallpaperUrl = "" })).wallpaperUrl, nil)
end)
test("settings rejects bad appOrder entries", function()
    equal(PhoneValidation.settings(okSettings({ appOrder = { "banking", "Bad Id" } })), nil)
    equal(PhoneValidation.settings(okSettings({ appOrder = "banking" })), nil)
end)
test("settings accepts a good appOrder", function()
    equal(PhoneValidation.settings(okSettings({ appOrder = { "banking", "notes" } })).appOrder[2], "notes")
end)
test("settings rejects non-table", function() equal(PhoneValidation.settings("x"), nil) end)
test("settings accepts the qbcore theme and wallpaper", function()
    local out = PhoneValidation.settings(okSettings({ theme = "kora_core", wallpaper = "kora_core" }))
    equal(out.theme, "kora_core"); equal(out.wallpaper, "kora_core")
end)

test("pin accepts 4 to 8 digits and keeps leading zeros", function()
    equal(PhoneValidation.pin("0042"), "0042")
    equal(PhoneValidation.pin("12345678"), "12345678")
end)
test("pin rejects short, long, non-digit and non-string values", function()
    equal(PhoneValidation.pin("123"), nil)
    equal(PhoneValidation.pin("123456789"), nil)
    equal(PhoneValidation.pin("12a4"), nil)
    equal(PhoneValidation.pin("12 34"), nil)
    equal(PhoneValidation.pin(1234), nil)
    equal(PhoneValidation.pin(nil), nil)
end)
test("pin names the field in its error", function()
    local _, err = PhoneValidation.pin("1", "currentPin")
    assert(err:find("currentPin", 1, true), err)
end)

test("settings defaults the phone case and accepts a valid one", function()
    equal(PhoneValidation.settings(okSettings()).phoneCase, "default")
    equal(PhoneValidation.settings(okSettings({ phoneCase = "nightdrive" })).phoneCase, "nightdrive")
end)
test("settings rejects an unknown phone case", function() equal(PhoneValidation.settings(okSettings({ phoneCase = "photo-of-a-real-car" })), nil) end)
test("settings case photo must be https", function()
    equal(PhoneValidation.settings(okSettings({ phoneCase = "custom", phoneCaseUrl = "http://x/y.png" })), nil)
    equal(PhoneValidation.settings(okSettings({ phoneCase = "custom", phoneCaseUrl = "https://x/y.png" })).phoneCaseUrl, "https://x/y.png")
end)
test("settings accepts the new flip case scenes", function()
    for _, id in ipairs({ "arcade", "space", "palms", "skyline" }) do
        equal(PhoneValidation.settings(okSettings({ phoneCase = id })).phoneCase, id)
    end
end)
test("settings icon style defaults to circle and rejects unknown styles", function()
    equal(PhoneValidation.settings(okSettings()).iconStyle, "circle")
    equal(PhoneValidation.settings(okSettings({ iconStyle = "solid" })).iconStyle, "solid")
    equal(PhoneValidation.settings(okSettings({ iconStyle = "star" })), nil)
end)
test("settings do-not-disturb is a boolean", function()
    equal(PhoneValidation.settings(okSettings({ dnd = true })).dnd, true)
    equal(PhoneValidation.settings(okSettings()).dnd, nil)
    equal(PhoneValidation.settings(okSettings({ dnd = "yes" })), nil)
end)
test("settings quiet hours must be real HH:MM times", function()
    local out = PhoneValidation.settings(okSettings({ dndFrom = "22:00", dndTo = "07:30" }))
    equal(out.dndFrom, "22:00"); equal(out.dndTo, "07:30")
    equal(PhoneValidation.settings(okSettings({ dndFrom = "" })).dndFrom, nil)
    equal(PhoneValidation.settings(okSettings({ dndFrom = "24:00" })), nil)
    equal(PhoneValidation.settings(okSettings({ dndTo = "7:30" })), nil)
    equal(PhoneValidation.settings(okSettings({ dndTo = "07:60" })), nil)
    equal(PhoneValidation.settings(okSettings({ dndTo = 700 })), nil)
end)
test("note item keeps only known fields and needs a title", function()
    local out = PhoneValidation.item("note", { id = "n-1", title = " Plan ", body = "x", evil = "y" })
    equal(out.title, "Plan"); equal(out.evil, nil)
    equal(PhoneValidation.item("note", { id = "n-1", title = "", body = "x" }), nil)
    equal(PhoneValidation.item("note", { id = "bad id!", title = "t" }), nil)
    equal(PhoneValidation.item("note", { id = "n-1", title = "t" }).body, "")
end)
test("alarm item needs a real time and sorts unique days", function()
    local out = PhoneValidation.item("alarm", { id = "a1", label = "Wake", time = "07:30", days = { 3, 1, 3 }, enabled = true })
    equal(#out.days, 2); equal(out.days[1], 1); equal(out.days[2], 3)
    equal(PhoneValidation.item("alarm", { id = "a1", time = "7:30", enabled = true }), nil)
    equal(PhoneValidation.item("alarm", { id = "a1", time = "25:00", enabled = true }), nil)
    equal(PhoneValidation.item("alarm", { id = "a1", time = "07:30", enabled = "yes" }), nil)
    equal(PhoneValidation.item("alarm", { id = "a1", time = "07:30", enabled = true, days = { 9 } }), nil)
    equal(#PhoneValidation.item("alarm", { id = "a1", time = "07:30", enabled = false }).days, 0)
end)
test("station item must be https", function()
    equal(PhoneValidation.item("station", { id = "s1", label = "Lo-fi", url = "https://x.example/a" }).url, "https://x.example/a")
    equal(PhoneValidation.item("station", { id = "s1", label = "Lo-fi", url = "http://x.example/a" }), nil)
    equal(PhoneValidation.item("station", { id = "s1", label = "", url = "https://x.example/a" }), nil)
end)
test("unknown item kind is rejected", function() equal(PhoneValidation.item("photo", { id = "p1" }), nil) end)
test("group needs a name and 1 to 49 valid numbers, duplicates dropped", function()
    local g = PhoneContracts.group({ name = "Crew", numbers = { "5550001111", "555-000-1111", "5550002222" } })
    equal(g.name, "Crew"); equal(#g.numbers, 2)
    equal(PhoneContracts.group({ name = "", numbers = { "5550001111" } }), nil)
    equal(PhoneContracts.group({ name = "Crew", numbers = {} }), nil)
    equal(PhoneContracts.group({ name = "Crew", numbers = { "12" } }), nil)
    equal(PhoneContracts.group({ name = "Crew", numbers = "5550001111" }), nil)
    local many = {}
    for i = 1, 50 do many[i] = string.format("555%07d", i) end
    equal(PhoneContracts.group({ name = "Crew", numbers = many }), nil)
end)
test("mail needs a number, subject, body and request id", function()
    local m = PhoneContracts.mail({ to = "5550001111", subject = " Hi ", body = "Hello there", clientRequestId = "req-12345" })
    equal(m.subject, "Hi"); equal(m.to, "5550001111")
    equal(PhoneContracts.mail({ to = "12", subject = "Hi", body = "x", clientRequestId = "req-12345" }), nil)
    equal(PhoneContracts.mail({ to = "5550001111", subject = "", body = "x", clientRequestId = "req-12345" }), nil)
    equal(PhoneContracts.mail({ to = "5550001111", subject = "Hi", body = "", clientRequestId = "req-12345" }), nil)
    equal(PhoneContracts.mail({ to = "5550001111", subject = "Hi", body = "x", clientRequestId = "short" }), nil)
    equal(PhoneContracts.mail({ to = "5550001111", subject = string.rep("a", 121), body = "x", clientRequestId = "req-12345" }), nil)
end)
test("contact may carry a gallery photo id, which must be a positive integer", function()
    local base = { displayName = "Alex", phoneNumber = "5550001111" }
    equal(PhoneContracts.contact(base).avatarMediaId, nil)
    base.avatarMediaId = 7
    equal(PhoneContracts.contact(base).avatarMediaId, 7)
    base.avatarMediaId = 0
    equal(PhoneContracts.contact(base), nil)
    base.avatarMediaId = "abc"
    equal(PhoneContracts.contact(base), nil)
end)
test("a message may be a clip or photo with no text, but plain text still needs a body", function()
    local base = { conversationId = 3, clientRequestId = "req-12345" }
    base.mediaId = 9
    local m = PhoneContracts.message(base)
    equal(m.mediaId, 9); equal(m.body, "")
    base.mediaId = nil
    equal(PhoneContracts.message(base), nil)
    base.body = "hi"
    equal(PhoneContracts.message(base).body, "hi")
    base.mediaId = 0
    equal(PhoneContracts.message(base), nil)
end)
test("a call signal must be a valid offer, answer, or ICE candidate for a real call id", function()
    local callId = "12345678-1234-4123-8123-123456789012"
    equal(PhoneContracts.callSignal({ id = callId, kind = "offer", sdp = { type = "offer", sdp = "v=0" } }).sdp.sdp, "v=0")
    equal(PhoneContracts.callSignal({ id = callId, kind = "ice", candidate = { candidate = "candidate:1 1 UDP 1 1.1.1.1 1 typ host" } }).candidate.candidate, "candidate:1 1 UDP 1 1.1.1.1 1 typ host")
    equal(PhoneContracts.callSignal({ id = "short", kind = "offer", sdp = { type = "offer", sdp = "v=0" } }), nil)
    equal(PhoneContracts.callSignal({ id = callId, kind = "hangup", sdp = { type = "offer", sdp = "v=0" } }), nil)
    equal(PhoneContracts.callSignal({ id = callId, kind = "offer", sdp = { type = "answer", sdp = "v=0" } }), nil)
    equal(PhoneContracts.callSignal({ id = callId, kind = "offer" }), nil)
    equal(PhoneContracts.callSignal({ id = callId, kind = "ice", candidate = { candidate = string.rep("a", 2001) } }), nil)
end)
test("a call signal keeps the SDP byte-for-byte, including its final CRLF", function()
    local callId = "12345678-1234-4123-8123-123456789012"
    local sdp = "v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\n"
    equal(PhoneContracts.callSignal({ id = callId, kind = "offer", sdp = { type = "offer", sdp = sdp } }).sdp.sdp, sdp)
end)
test("conversation pages preserve tied sort keys without changing numeric cursors", function()
    local oldPhone, oldMySQL, oldConstants, oldResult, oldError = KoraPhone, MySQL, PhoneConstants, PhoneResult, PhoneError
    dofile(root .. "/shared/constants.lua")
    -- An inert row host applies the emitted keyset predicates, not a database engine.
    local rows = {
        { id = 80, deviceId = 11 }, { id = 50, deviceId = 11 },
        { id = 7, deviceId = 11, lastMessageId = 50 }, { id = 40, deviceId = 11 },
        { id = 3, deviceId = 11, lastMessageId = 40 }, { id = 2, deviceId = 11, lastMessageId = 10 },
        { id = 1, deviceId = 11 }, { id = 90, deviceId = 22 }, { id = 99, deviceId = 11, left = true },
    }
    local queries = {}
    MySQL = { query = { await = function(sql, params)
        queries[#queries + 1] = { sql = sql, params = params }
        equal(params[1], params[2]); equal(params[2], params[3])
        assert(sql:find('cm.device_id = ? AND cm.left_at IS NULL', 1, true))
        assert(sql:find('latest.deleted_at IS NULL AND ld.message_id IS NULL', 1, true))
        local pair = sql:find('OR (COALESCE(last_message.id, c.id) = ? AND c.id < ?)', 1, true)
        local legacy = not pair and sql:find('COALESCE(last_message.id, c.id) < ?', 1, true)
        local only = sql:find(' AND c.id = ?', 1, true)
        local cursor, cursorId, onlyId, index = nil, nil, nil, 4
        if pair then
            cursor, cursorId, index = params[4], params[6], 7
            equal(params[4], params[5])
        elseif legacy then cursor, index = params[4], 5 end
        if only then onlyId, index = params[index], index + 1 end
        equal(index, #params)
        local selected = {}
        for _, row in ipairs(rows) do
            local sortId = row.lastMessageId or row.id
            if row.deviceId == params[3] and not row.left and (not onlyId or row.id == onlyId)
                and (not cursor or sortId < cursor or (cursorId and sortId == cursor and row.id < cursorId)) then
                selected[#selected + 1] = { id = row.id, sortId = sortId }
            end
        end
        -- Descending IDs are one permitted old tie order as well as the new explicit order.
        table.sort(selected, function(a, b) return a.sortId > b.sortId or (a.sortId == b.sortId and a.id > b.id) end)
        local out = {}
        for i = 1, math.min(params[#params], #selected) do out[i] = selected[i] end
        return out
    end } }
    KoraPhone = { Repositories = {}, Permissions = { requireDevice = function(source)
        if source == 7 then return { id = 11 } end
        if source == 8 then return { id = 22 } end
        return nil, PhoneError(PhoneConstants.Errors.UNAUTHORIZED, 'No device')
    end } }
    dofile(root .. "/server/repositories/messages.lua")
    dofile(root .. "/server/services/messaging.lua")
    local list, repository = KoraPhone.Services.Messaging.listConversations, KoraPhone.Repositories.Messages
    local first = list(7, { limit = 2 }).data
    local second = list(7, { limit = 2, cursor = first.nextCursor, cursorId = first.items[#first.items].id }).data
    equal(second.items[1].id, 7) -- Original strict cutoff skips this tied conversation.
    equal(first.nextCursor, 50); equal(first.nextCursorId, 50)
    equal(type(first.nextCursor), 'number'); equal(type(first.nextCursorId), 'number')
    assert(queries[1].sql:find('ORDER BY sortId DESC, c.id DESC LIMIT ?', 1, true))
    local ids, cursor, cursorId = {}, nil, nil
    for _ = 1, 8 do
        local result = list(7, { limit = 2, cursor = cursor, cursorId = cursorId })
        equal(result.ok, true)
        for _, item in ipairs(result.data.items) do ids[#ids + 1] = item.id end
        cursor, cursorId = result.data.nextCursor, result.data.nextCursorId
        if not cursor then break end
    end
    equal(table.concat(ids, ','), '80,50,7,40,3,2,1')
    equal(cursor, nil); equal(cursorId, nil)
    local legacy = list(7, { limit = 2, cursor = 50 }).data
    equal(legacy.items[1].id, 40); equal(legacy.items[2].id, 3)
    equal(legacy.nextCursor, 40); equal(type(legacy.nextCursor), 'number')
    equal(repository.getConversation(11, 7).id, 7)
    equal(#repository.listConversations(11, 2, 50, 7, 50), 1)
    equal(repository.listConversations(11, 2, 50, 7, 50)[1].id, 7)
    equal(repository.getConversation(22, 7), nil)
    equal(list(8, { limit = 2 }).data.items[1].id, 90)
    equal(list(7, { limit = 2, cursor = 1, cursorId = 1 }).data.nextCursor, nil)
    equal(list(7, { limit = 2, cursor = 1, cursorId = 1 }).data.nextCursorId, nil)
    for _, value in ipairs({ 0, -1, 1.5, 'bad', {}, false }) do
        local calls = #queries
        local result = list(7, { limit = 2, cursor = 50, cursorId = value })
        equal(result.ok, false); equal(result.error.code, PhoneConstants.Errors.INVALID_INPUT)
        equal(#queries, calls)
    end
    equal(list(7, { cursorId = 7 }).error.code, PhoneConstants.Errors.INVALID_INPUT)
    equal(list(7, { cursor = 50, cursorId = '50', limit = 2 }).data.items[1].id, 7)
    equal(list(7, { cursor = '50', cursorId = '50', limit = 2 }).data.items[1].id, 7)
    equal(list(99, { cursorId = -1 }).error.code, PhoneConstants.Errors.UNAUTHORIZED)
    equal(PhoneValidation.page({ cursor = 50, cursorId = -1 }).cursor, 50)
    KoraPhone, MySQL, PhoneConstants, PhoneResult, PhoneError = oldPhone, oldMySQL, oldConstants, oldResult, oldError
end)


test("settings maps legacy qbcore ids to kora_core", function()
    local out = PhoneValidation.settings(okSettings({ theme = "qbcore", wallpaper = "qbcore", phoneCase = "qbcore" }))
    equal(out.theme, "kora_core"); equal(out.wallpaper, "kora_core"); equal(out.phoneCase, "kora_core")
end)
test("settings rejects legacy ids when AcceptLegacyIds is off", function()
    Config.Settings.AcceptLegacyIds = false
    local out = PhoneValidation.settings(okSettings({ wallpaper = "qbcore" }))
    Config.Settings.AcceptLegacyIds = true
    equal(out, nil)
end)
test("settings still rejects unknown wallpaper and empty-string wallpaper", function()
    equal(PhoneValidation.settings(okSettings({ wallpaper = "signature" })), nil)
    equal(PhoneValidation.settings(okSettings({ wallpaper = "" })), nil)
end)
test("settings accepts every wallpaper the setup UI offers", function()
    for _, id in ipairs({ "kora_core", "orbit", "plain", "midnight", "slate", "ember" }) do
        equal(PhoneValidation.settings(okSettings({ wallpaper = id })).wallpaper, id)
    end
end)


local function joined(list) return list and table.concat(list, ",") or "nil" end
local function withHome(allow, fn)
    local oldApps, oldHome = Config.LaunchApps, Config.HomeScreen
    Config.LaunchApps = { gps = true, notes = true, mail = true, music = true, gallery = true }
    Config.HomeScreen = { allowReorder = allow }
    local ok, err = pcall(fn)
    Config.LaunchApps, Config.HomeScreen = oldApps, oldHome
    assert(ok, err)
end
test("appOrder keeps a valid order and drops repeated and unknown apps", function()
    withHome(true, function()
        local out = PhoneValidation.settings(okSettings({ appOrder = { "music", "gps", "music", "bogus", "gallery" } }))
        equal(joined(out.appOrder), "music,gps,gallery")
    end)
end)
test("appOrder follows installedApps: removed apps drop out, new apps append", function()
    withHome(true, function()
        local out = PhoneValidation.settings(okSettings({ appOrder = { "music", "gps", "gallery" }, installedApps = { "gps", "notes" } }))
        equal(joined(out.appOrder), "gps,gallery,notes")
    end)
end)
test("dockOrder is cleaned the same way", function()
    withHome(true, function()
        equal(joined(PhoneValidation.settings(okSettings({ dockOrder = { "mail", "gps", "mail", "bogus" } })).dockOrder), "mail,gps")
        equal(PhoneValidation.settings(okSettings({ dockOrder = { "Bad Id" } })), nil)
    end)
end)
test("appOrder with bad ids is still rejected", function()
    withHome(true, function() equal(PhoneValidation.settings(okSettings({ appOrder = { "../x" } })), nil) end)
end)
test("Config.HomeScreen.allowReorder = false ignores order changes", function()
    withHome(false, function()
        local out = PhoneValidation.settings(okSettings({ appOrder = { "gps" }, dockOrder = { "mail" } }))
        equal(out.appOrder, nil)
        equal(out.dockOrder, nil)
    end)
end)

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end