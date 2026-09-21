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
const migration = read("migrations/003_calls.sql");
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
