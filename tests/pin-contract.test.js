#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

const migration = read("server/schema.lua");
const phone = read("server/services/phone.lua");
const repo = read("server/repositories/phones.lua");
const permissions = read("server/permissions.lua");
const sessions = read("server/sessions.lua");
const callbacks = read("server/callbacks.lua");
const nui = read("client/nui.lua");
const clientMain = read("client/main.lua");
const serverMain = read("server/main.lua");
const calling = read("server/services/calling.lua");
const config = read("config/server.lua");
const api = read("web/src/api.ts");

// The PIN is never stored: only a salted SHA-256 computed inside the database.
assert.match(migration, /pin_hash/, "migration must add a hash column");
assert.match(migration, /pin_salt/, "migration must add a salt column");
assert.doesNotMatch(migration, /name = 'pin'/, "no plaintext pin column may exist");
assert.match(repo, /SHA2\(CONCAT\(/, "the hash must be computed in SQL so Lua never holds a hash of the PIN");
assert.doesNotMatch(phone + repo, /print\([^)]*pin/i, "the PIN must never be logged");

// Attempts are limited and locking is server-side.
assert.match(phone, /recordPinFailure/, "failed attempts must be recorded");
assert.match(phone, /Too many attempts/, "lockout must be reported to the caller");
assert.match(config, /Pin = \{ MaxAttempts = \d+, LockSeconds = \d+ \}/, "attempt limits must be configurable");
assert.match(config, /pin = \{ capacity/, "PIN routes must be rate limited");

// A locked phone refuses data requests on the server, not just in the UI.
assert.match(permissions, /Phone is locked/, "requireDevice must refuse a locked phone");
assert.match(permissions, /allowLocked/, "calls must be able to opt out of the lock");
assert.match(calling, /requireDevice\(source, true\)/, "a locked phone must still be able to answer a call");
assert.match(sessions, /unlocked = false/, "sessions must start locked");
assert.match(sessions, /function QBPhone\.Sessions\.ensure/, "bootstrap must keep the unlocked state of a live session");
assert.match(phone, /Sessions\.ensure\(source, device\)/, "bootstrap must not reset an unlocked session");
assert.match(phone, /security = \{ hasPin = true, locked = true \}/, "a locked bootstrap must not expose phone data");

// Removing a PIN needs the current PIN and the same attempt limiting.
assert.match(phone, /function Phone\.removePin[\s\S]*checkPin\(device, current\)/, "removing a PIN must verify the current PIN");
assert.match(repo, /pin_hash = NULL/, "removing a PIN must clear the hash");

// The phone re-locks when it closes.
assert.match(clientMain, /qbphone:server:phone:closed/, "closing the phone must notify the server");
assert.match(serverMain, /RegisterNetEvent\('qbphone:server:phone:closed'/, "server must handle the close event");
assert.match(serverMain, /consume\(requestSource, 'mutation'\)/, "the close event must be rate limited");

// Routes are wired end to end: UI -> NUI callback -> server callback.
for (const [route, server] of [["security:unlock", "unlockPhone"], ["security:lock", "lockPhone"], ["security:setPin", "setPhonePin"], ["security:removePin", "removePhonePin"]]) {
  assert.match(nui, new RegExp(`\\['${route}'\\] = 'qbphone:server:${server}'`), `${route} must be mapped in client/nui.lua`);
  assert.match(callbacks, new RegExp(`register(?:Callback)?\\('${server}'`), `${server} must be registered as a server callback`);
  assert.match(api, new RegExp(`'${route}'`), `${route} must be called by the web api layer`);
}
assert.match(api, /raw\.security\?\.locked===true/, "the UI must take its lock state from the server");

console.log("PASS pin-contract: hashing, attempt limits, server-side lock, re-lock on close and route wiring verified");
