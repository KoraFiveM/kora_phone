#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const service = read("server/services/calling.lua");
const repository = read("server/repositories/calls.lua");
const moduleSource = read("server/modules/call_callbacks.lua");
const migration = read("server/schema.lua");
const client = read("client/calls.lua");
const voice = read("client/integrations/voice.lua");
const serverVoice = read("server/integrations/voice.lua");

for (const status of ["ringing", "active", "ended", "rejected", "missed", "cancelled"]) {
  assert.match(migration, new RegExp(`['\"]${status}['\"]`), `migration must support ${status}`);
}

assert.match(service, /Permissions\.requireDevice\(source\)/, "calls must derive identity from QBCore source");
assert.match(service, /device\.id\s*~=/, "accept/reject must verify the callee");
assert.match(service, /participant\(call, deviceId\)/, "mutations must verify call membership");
assert.match(service, /SetTimeout\(ringTimeoutMs/, "ringing calls need a server timeout");
assert.match(service, /Calling\.callByDevice\[caller\.id\]/, "caller concurrency must be guarded");
assert.match(service, /Calling\.callByDevice\[callee\.id\]/, "callee concurrency must be guarded");
assert.match(service, /Repositories\.Phones\.findByNumber/, "callee must resolve from an owned phone number");
assert.match(service, /Blocks\.isEitherBlocked/, "blocked devices must not call each other");
assert.match(service, /Repositories\.Calls\.transition/, "state changes must be persisted conditionally");
assert.match(repository, /WHERE id = \? AND status IN/, "database transition must be compare-and-set");
assert.match(moduleSource, /RateLimits\.consume/, "call entry points must be rate limited");
assert.match(moduleSource, /local requestSource = source/, "network events must use the FiveM event source");
assert.doesNotMatch(service, /payload\.(?:citizenId|deviceId|source)/, "client identity fields must not be trusted");

assert.match(client, /current\.id ~= call\.id/, "client must ignore cross-call state injection");
assert.match(client, /Voice\.Leave\(\)/, "call end must leave voice routing");
assert.match(voice, /GetResourceState\(name\) == 'started'/, "voice resource must be capability checked");
assert.doesNotMatch(client, /Voice\.Join/, "clients must not assign themselves to call channels");
assert.match(service, /Integrations\.Voice\.join/, "the server must assign voice call membership");
assert.match(service, /Integrations\.Voice\.leave/, "the server must remove voice call membership");
assert.match(serverVoice, /setPlayerCall/, "voice assignment must use the trusted server export");
assert.match(serverVoice, /removePlayerFromCall/, "voice cleanup must use the trusted server export");
assert.doesNotMatch(voice, /MumbleSetPlayerMuted/, "call mute must not misuse receive-side player muting");

console.log("PASS calls: server authority, persistence, routing and cleanup contracts verified");

// Execute the actual Lua service/repositories with controlled yielding SQL.
const { execFileSync } = require("node:child_process");
const callingRegression = String.raw`local root = assert(arg[1], 'supply the phone resource root')
local checks = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    checks = checks + 1
end
local function count(values)
    local n = 0
    for _ in pairs(values) do n = n + 1 end
    return n
end

local function host()
    local state = { pending = {}, rows = {}, events = {}, timers = {}, callbacks = {}, handlers = {}, voice = {}, pause = nil }
    KoraPhone, MySQL = {}, nil
    dofile(root .. '/config/shared.lua')
    dofile(root .. '/config/server.lua')
    dofile(root .. '/shared/constants.lua')
    dofile(root .. '/shared/validation.lua')
    local devices, byNumber, players = {}, {}, {}
    for i = 1, 4 do
        local citizenId, number = 'character-' .. i, '555000000' .. i
        devices[citizenId] = { id = i, ownerCitizenId = citizenId, phoneNumber = number, isActive = 1 }
        byNumber[number] = devices[citizenId]
        players[i] = { PlayerData = { source = i, citizenid = citizenId }, Functions = { GetItemByName = function() return { name = 'phone' } end } }
    end
    local core = { Functions = {
        GetPlayer = function(source) return players[source] end,
        CreateCallback = function(name, fn) state.callbacks[name] = fn end,
    } }
    GetCurrentResourceName = function() return 'kora_phone-stevie' end
    GetNumResourceMetadata = function() return 0 end
    GetGameTimer = function() return 60000 end
    CreateThread = function() end
    Wait = function() error('unexpected startup thread') end
    SetTimeout = function(ms, fn) state.timers[#state.timers + 1] = { ms = ms, fn = fn } end
    TriggerClientEvent = function(name, source, ...) state.events[#state.events + 1] = { name = name, source = source, args = table.pack(...) } end
    AddEventHandler = function(name, fn)
        state.handlers[name] = state.handlers[name] or {}
        table.insert(state.handlers[name], fn)
    end
    RegisterNetEvent = function() end
    local voice = {
        setPlayerCall = function(source, channel) state.voice[#state.voice + 1] = { 'join', source, channel }; return true end,
        removePlayerFromCall = function(source, channel) state.voice[#state.voice + 1] = { 'leave', source, channel }; return true end,
    }
    exports = { qbcore = {
        getPlayerData = function(_, src) return players[src] and players[src].PlayerData end,
        getItemByName = function(_, src) return players[src] and { name = 'phone' } end,
        createCallback = function(_, name, fn) state.callbacks[name] = fn end,
    }, ['pma-voice'] = voice }
    promise = { new = function()
        local p = {}
        p.resolve = function(_, value) p.done, p.value = true, value end
        p.reject = function(_, err) p.done, p.err = true, err end
        return p
    end }
    Citizen = { Await = function(p)
        if not p.done then coroutine.yield(p) end
        assert(p.done, 'resume only after controlled SQL completion')
        if p.err then error(p.err, 0) end
        return p.value
    end }
    local function sql(method, query, params, cb)
        local phase
        if query:find('WHERE owner_citizenid', 1, true) then phase = 'caller'
        elseif query:find('WHERE phone_number', 1, true) then phase = 'lookup'
        elseif query:find('phone_blocks', 1, true) then phase = 'block'
        elseif query:find('INSERT INTO phone_calls', 1, true) then phase = 'create'
        elseif query:find('UPDATE phone_calls SET status', 1, true) then phase = 'transition'
        else error('unexpected SQL: ' .. query) end
        local function complete(value, err)
            if err then cb(nil, err); return end
            if phase == 'caller' then value = devices[params[1]]
            elseif phase == 'lookup' then value = byNumber[params[1]]
            elseif phase == 'block' then value = 0
            elseif phase == 'create' then
                value = value == nil and 1 or value
                if value == 1 then state.rows[params[1]] = { status = 'ringing' } end
            elseif phase == 'transition' then
                local row = state.rows[params[2]]
                -- Terminal transitions include an ended_reason parameter before the ID.
                if not row then row = state.rows[params[3]] end
                value = value == nil and (row and 1 or 0) or value
                if row and value > 0 then row.status = params[1] end
            end
            cb(value)
        end
        if state.pause == phase then
            state.pause = nil
            state.pending[#state.pending + 1] = { phase = phase, complete = complete, params = params }
        else complete() end
    end
    MySQL = {}
    for _, method in ipairs({ 'single', 'scalar', 'update' }) do
        MySQL[method] = { await = function(query, params)
            local p = promise.new()
            sql(method, query, params, function(value, err) if err then p:reject(err) else p:resolve(value) end end)
            return Citizen.Await(p)
        end }
    end
    for _, file in ipairs({ 'server/integrations/qbcore.lua', 'server/repositories/phones.lua', 'server/repositories/blocks.lua',
        'server/repositories/calls.lua', 'server/services/phone.lua', 'server/rate_limits.lua', 'server/permissions.lua',
        'server/sessions.lua', 'server/integrations/voice.lua', 'server/services/calling.lua' }) do dofile(root .. '/' .. file) end
    local file = assert(io.open(root .. '/server/callbacks.lua')); local callbackSource = file:read('*a'); file:close()
    -- Use the real protected dispatcher, without registering unrelated phone services.
    local boundary = assert(callbackSource:find("KoraPhone.registerCallback('getBootstrap'", 1, true))
    assert(load(callbackSource:sub(1, boundary - 1), '@server/callbacks.lua'))()
    dofile(root .. '/server/modules/call_callbacks.lua')
    for i = 1, 4 do KoraPhone.Sessions.open(i, devices['character-' .. i]) end
    local mainFile = assert(io.open(root .. '/server/main.lua')); local mainSource = mainFile:read('*a'); mainFile:close()
    local unloadStart = assert(mainSource:find("AddEventHandler('QBCore:Server:OnPlayerUnload'", 1, true))
    local unloadEnd = assert(mainSource:find('\nend)', unloadStart, true))
    assert(load(mainSource:sub(unloadStart, unloadEnd + 4), '@server/main.lua:unload'))()
    function state.retire(src, dropped)
        if dropped then
            local previous = source; source = src
            for _, fn in ipairs(state.handlers.playerDropped) do fn() end
            source = previous
        else
            for _, fn in ipairs(state.handlers['QBCore:Server:OnPlayerUnload']) do fn(src) end
        end
        -- Core logout removes its character after local unload handlers finish.
        players[src] = nil
    end
    function state.reopen(src, id)
        local device = devices['character-' .. id]
        players[src] = { PlayerData = { source = src, citizenid = device.ownerCitizenId }, Functions = { GetItemByName = function() return { name = 'phone' } end } }
        KoraPhone.Sessions.open(src, device)
    end
    state.calling = KoraPhone.Services.Calling
    function state.request(name, source, payload)
        local response
        local thread = coroutine.create(function()
            state.callbacks['kora_phone:server:calls:' .. name](source, function(...) response = table.pack(...) end, payload)
        end)
        local ok, err = coroutine.resume(thread); assert(ok, err)
        return { thread = thread, result = function() return response and response[1] end, arity = function() return response and response.n end }
    end
    function state.complete(request, value, err, allowPending)
        local pending = table.remove(state.pending, 1); assert(pending, 'SQL must be pending')
        pending.complete(value, err)
        local ok, result = coroutine.resume(request.thread); assert(ok, result)
        if not allowPending then equal(coroutine.status(request.thread), 'dead', 'settled request') end
    end
    return state
end

local function conflict(response, message)
    equal(response.ok, false, message)
    equal(response.error.code, 'CONFLICT', message)
end

for _, second in ipairs({ { 1, '5550000003' }, { 3, '5550000002' }, { 2, '5550000001' } }) do
    local h = host(); h.pause = 'create'
    local first = h.request('start', 1, { to = '5550000002' })
    equal(coroutine.status(first.thread), 'suspended')
    equal(count(h.calling.activeById), 0, 'publish only after insert')
    equal(#h.events, 0, 'no early call event')
    equal(#h.timers, 0, 'no early ring timeout')
    local next = h.request('start', second[1], { to = second[2] })
    conflict(next.result(), 'pending insert reserves both participants')
    h.complete(first)
    equal(first.result().ok, true)
    equal(first.arity(), 1)
    equal(count(h.calling.activeById), 1)
    equal(h.calling.callByDevice[1], first.result().data.id)
    equal(h.calling.callByDevice[2], first.result().data.id)
    equal(count(h.rows), 1)
    equal(#h.events, 2)
    equal(h.timers[1].ms, 30000)
end

for _, phase in ipairs({ 'lookup', 'block' }) do
    local h = host(); h.pause = phase
    local first = h.request('start', 1, { to = '5550000002' })
    local second = h.request('start', 1, { to = '5550000003' })
    equal(second.result().ok, true)
    h.complete(first)
    conflict(first.result(), 'recheck caller after yielding reads')
    equal(count(h.calling.activeById), 1)
    equal(count(h.rows), 1)
    equal(#h.events, 2)
end

for _, failure in ipairs({ 'false', 'error' }) do
    local h = host(); h.pause = 'create'
    local request = h.request('start', 1, { to = '5550000002' })
    if failure == 'error' then h.complete(request, nil, 'controlled create failure') else h.complete(request, 0) end
    equal(request.result().ok, false)
    equal(request.result().error.code, 'INTERNAL_ERROR')
    equal(request.arity(), 1, 'outer protected callback error transport')
    equal(request.result().error.message, failure == 'error' and 'Request failed' or 'Unable to create call')
    equal(h.calling.callByDevice[1], nil, 'failed creation releases caller')
    equal(h.calling.callByDevice[2], nil, 'failed creation releases callee')
    equal(count(h.calling.activeById), 0)
    equal(#h.events, 0)
    equal(#h.timers, 0)
    equal(h.request('start', 1, { to = '5550000002' }).result().ok, true, 'retry after failure')
end

local h = host()
local started = h.request('start', 1, { to = '555-000-0002', deviceId = 4, source = 4 }).result()
equal(started.ok, true)
equal(started.data.direction, 'outgoing')
equal(started.data.remoteNumber, '5550000002')
equal(started.data.status, 'ringing')
equal(started.data.voiceChannel, nil)
equal(h.events[1].source, 1)
equal(h.events[2].source, 2)
equal(h.events[2].args[1].direction, 'incoming')
local rejected = h.request('accept', 1, { id = started.data.id }).result()
conflict(rejected, 'only callee can accept')
local accepted = h.request('accept', 2, { id = started.data.id }).result()
equal(accepted.ok, true)
equal(accepted.data.status, 'active')
equal(h.voice[1][2], 1)
equal(h.voice[2][2], 2)
equal(h.voice[1][3], h.voice[2][3])
local ended = h.request('hangup', 1, { id = started.data.id }).result()
equal(ended.ok, true)
equal(ended.data.status, 'ended')
equal(h.calling.callByDevice[1], nil)
equal(h.calling.callByDevice[2], nil)
equal(count(h.calling.activeById), 0)
equal(h.voice[3][1], 'leave')
equal(h.voice[4][1], 'leave')
equal(h.request('start', 1, { to = '5550000001' }).result().error.code, 'INVALID_INPUT')
equal(h.request('start', 1, { to = '5550000099' }).result().error.code, 'NOT_FOUND')
print(('PASS call-start coroutine regression: %d checks'):format(checks))
local retirementChecks = checks
for _, phase in ipairs({ 'caller', 'lookup', 'block', 'create' }) do
    for _, replaced in ipairs({ false, true }) do
        local h = host(); h.pause = phase
        local request = h.request('start', 1, { to = '5550000002' })
        equal(coroutine.status(request.thread), 'suspended')
        h.retire(1)
        if replaced then h.reopen(1, 4) end
        h.complete(request)
        conflict(request.result(), 'retired caller cannot continue after ' .. phase)
        equal(request.arity(), 1)
        equal(count(h.calling.activeById), 0)
        equal(h.calling.callByDevice[1], nil)
        equal(h.calling.callByDevice[2], nil)
        equal(#h.events, 0, 'retired start emits no ringing event')
        equal(#h.timers, 0)
        equal(count(h.rows), phase == 'create' and 1 or 0)
        for _, row in pairs(h.rows) do equal(row.status, 'cancelled', 'issued insert is retired conditionally') end
    end
end
for _, participant in ipairs({ 1, 2 }) do
    local h = host(); h.pause = 'create'
    local request = h.request('start', 1, { to = '5550000002' })
    local old = KoraPhone.Sessions.bySource[participant]
    h.reopen(participant, participant) -- Same character, different local session record.
    equal(KoraPhone.Sessions.bySource[participant] == old, false)
    h.complete(request)
    conflict(request.result(), 'a replacement participant session retires the old start')
    equal(count(h.calling.activeById), 0)
    equal(count(h.calling.callByDevice), 0)
    equal(#h.events, 0)
    for _, row in pairs(h.rows) do equal(row.status, 'cancelled') end
end
for _, participant in ipairs({ 1, 2 }) do
    local h = host(); h.pause = 'create'
    local request = h.request('start', 1, { to = '5550000002' })
    h.retire(participant, true)
    h.complete(request)
    conflict(request.result(), 'raw drop retires a pending participant')
    equal(count(h.calling.activeById), 0)
    equal(count(h.calling.callByDevice), 0)
    equal(#h.events, 0)
end
local sessionless = host()
KoraPhone.Sessions.close(1)
equal(sessionless.request('start', 1, { to = '5550000002' }).result().ok, true, 'existing start API accepts a loaded caller without a phone session')
local sessionlessRetired = host()
KoraPhone.Sessions.close(1); sessionlessRetired.pause = 'create'
local oldStart = sessionlessRetired.request('start', 1, { to = '5550000002' })
sessionlessRetired.retire(1); sessionlessRetired.complete(oldStart)
conflict(oldStart.result(), 'current-character check still protects an initially sessionless caller')
equal(#sessionlessRetired.events, 0)
for _, failure in ipairs({ 'false', 'error' }) do
    local h = host(); h.pause = 'create'
    local request = h.request('start', 1, { to = '5550000002' })
    h.reopen(1, 1); h.pause = 'transition'
    h.complete(request, nil, nil, true)
    equal(coroutine.status(request.thread), 'suspended', 'retirement update can also await SQL')
    equal(count(h.calling.callByDevice), 0, 'release local reservations before attempted SQL cleanup')
    equal(count(h.calling.activeById), 0)
    equal(#h.events, 0)
    local replacement = h.request('start', 1, { to = '5550000003' })
    equal(replacement.result().ok, true, 'a current request can start during old SQL cleanup')
    if failure == 'error' then h.complete(request, nil, 'controlled retirement failure') else h.complete(request, 0) end
    equal(request.result().ok, false)
    equal(request.result().error.code, failure == 'error' and 'INTERNAL_ERROR' or 'CONFLICT')
    equal(request.arity(), 1)
    equal(h.calling.callByDevice[1], replacement.result().data.id, 'old cleanup cannot clear a newer call')
    equal(count(h.calling.activeById), 1)
    equal(#h.events, 2, 'only the replacement call publishes')
    local statuses = {}
    for _, row in pairs(h.rows) do statuses[row.status] = (statuses[row.status] or 0) + 1 end
    equal(statuses.ringing, 2, 'failed cleanup cannot undo the already-issued SQL insert')
end
print(('PASS call-start retirement regression: %d checks'):format(checks - retirementChecks))
`;
process.stdout.write(execFileSync(process.env.LUA || "lua", ["-", root], { input: callingRegression, encoding: "utf8" }));

// Run the actual App callbacks with inert camera/RTC boundaries, never a camera device.
async function videoConsentRegression() {
  const ts = require(path.join(root, "web/node_modules/typescript"));
  const vm = require("node:vm");
  const source = ts.createSourceFile("App.tsx", read("web/src/App.tsx"), ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const wanted = new Set(["stopVideo", "ensurePeer", "startVideo", "handleVideoSignal"]);
  const declarations = [];
  function visit(node) {
    if (ts.isVariableDeclaration(node) && wanted.has(node.name.getText(source))) {
      declarations.push(`const ${node.name.getText(source)} = ${node.initializer.getText(source)};`);
      wanted.delete(node.name.getText(source));
    }
    ts.forEachChild(node, visit);
  }
  visit(source);
  assert.equal(wanted.size, 0, "extract every actual video callback");
  let checks = 0;
  const equal = (actual, expected, label) => { assert.deepEqual(actual, expected, label); checks++; };
  const state = { cameraRequests: 0, videoOn: false, remoteVideo: false, stopped: 0, signals: [], connections: [] };
  const track = { stop: () => { state.stopped++; } };
  const stream = { getTracks: () => [track] };
  const refs = { peerConnection: { current: undefined }, localStream: { current: undefined }, localVideoRef: { current: { srcObject: null } }, remoteVideoRef: { current: { srcObject: null } } };
  class Peer {
    constructor(config) { this.config = config; this.senders = []; this.ice = []; state.connections.push(this); }
    getSenders() { return this.senders; }
    addTrack(value, owner) { this.senders.push({ track: value, owner }); }
    async setRemoteDescription(value) { this.remote = value; }
    async setLocalDescription(value) { this.local = value; }
    async createAnswer() { return { type: "answer", sdp: "inert-answer" }; }
    async createOffer() { return { type: "offer", sdp: "inert-offer" }; }
    async addIceCandidate(value) { this.ice.push(value); }
    close() { this.closed = true; }
  }
  const host = {
    ...refs, device: { video: { iceServers: [] } }, callRef: { current: { id: "call-1" } },
    useCallback: fn => fn, run: work => work(), RTCPeerConnection: Peer,
    navigator: { mediaDevices: { getUserMedia: async options => { equal(options.video, true); state.cameraRequests++; return stream; } } },
    setVideoOn: value => { state.videoOn = value; }, setRemoteVideo: value => { state.remoteVideo = value; },
    sendSignal: value => { state.signals.push(value); },
  };
  const emitted = ts.transpileModule(declarations.join("\n") + "\n({ stopVideo, ensurePeer, startVideo, handleVideoSignal });", { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } }).outputText;
  const callbacks = vm.runInNewContext(emitted, host, { filename: "App.tsx:video-callbacks" });
  await callbacks.handleVideoSignal({ kind: "offer", sdp: { type: "offer", sdp: "remote-offer" } });
  const connection = refs.peerConnection.current;
  equal(state.cameraRequests, 0, "remote offer cannot request a previously permitted local camera");
  equal(connection.senders.length, 0, "receive-only answer publishes no local track");
  equal(refs.localStream.current, undefined);
  equal(state.videoOn, false, "camera button remains Start video");
  equal(state.signals[0].kind, "answer"); equal(state.signals[0].id, "call-1");
  equal(connection.local.type, "answer"); equal(connection.remote.sdp, "remote-offer");
  const remoteStream = { id: "remote-stream" };
  connection.ontrack({ streams: [remoteStream] });
  equal(state.remoteVideo, true); equal(refs.remoteVideoRef.current.srcObject, remoteStream);
  await callbacks.startVideo();
  equal(state.cameraRequests, 1, "only explicit Start video obtains local tracks");
  equal(state.videoOn, true); equal(refs.localStream.current, stream);
  equal(refs.localVideoRef.current.srcObject, stream); equal(connection.senders.length, 1);
  equal(connection.senders[0].track, track); equal(connection.senders[0].owner, stream);
  equal(state.signals[1].kind, "offer");
  await callbacks.handleVideoSignal({ kind: "offer", sdp: { type: "offer", sdp: "renegotiation" } });
  equal(state.cameraRequests, 1, "later offers reuse explicitly enabled local camera");
  equal(connection.senders.length, 1, "renegotiation does not duplicate local tracks");
  equal(state.videoOn, true); equal(state.signals[2].kind, "answer");
  await callbacks.handleVideoSignal({ kind: "answer", sdp: { type: "answer", sdp: "remote-answer" } });
  equal(connection.remote.sdp, "remote-answer");
  await callbacks.handleVideoSignal({ kind: "ice", candidate: { candidate: "inert-ice" } });
  equal(connection.ice[0].candidate, "inert-ice");
  connection.onicecandidate({ candidate: { toJSON: () => ({ candidate: "local-ice" }) } });
  equal(state.signals[3].kind, "ice"); equal(state.signals[3].id, "call-1");
  callbacks.stopVideo();
  equal(connection.closed, true); equal(state.stopped, 1);
  equal(refs.peerConnection.current, undefined); equal(refs.localStream.current, undefined);
  equal(refs.localVideoRef.current.srcObject, null); equal(refs.remoteVideoRef.current.srcObject, null);
  equal(state.videoOn, false); equal(state.remoteVideo, false);
  callbacks.stopVideo(); equal(state.stopped, 1, "cleanup releases local tracks once");
  await callbacks.handleVideoSignal(null); equal(state.connections.length, 1);
  host.device = undefined;
  await callbacks.handleVideoSignal({ kind: "offer", sdp: { type: "offer", sdp: "ignored" } });
  await callbacks.startVideo(); equal(state.connections.length, 1); equal(state.cameraRequests, 1);
  console.log(`PASS video consent: ${checks} actual callback checks with inert camera/RTC boundaries`);
}
videoConsentRegression().catch(error => { console.error(error); process.exitCode = 1; });