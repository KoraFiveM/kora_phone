#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const read = file => fs.readFileSync(path.join(root, file), "utf8");

const manifest = read("fxmanifest.lua");
for (const module of ["call_callbacks", "economy_callbacks", "media_callbacks", "community_callbacks"]) {
  assert.ok(manifest.includes(`server/modules/${module}.lua`), `manifest must load ${module}`);
}
assert.ok(manifest.indexOf("server/rate_limits.lua") < manifest.indexOf("server/modules/call_callbacks.lua"),
  "rate limits must load before callback modules");
assert.ok(manifest.indexOf("server/permissions.lua") < manifest.indexOf("server/modules/call_callbacks.lua"),
  "permissions must load before callback modules");

const sessions = read("server/sessions.lua");
assert.match(sessions, /session\.citizenId ~= citizenId/, "online session must remain character-bound");
assert.match(sessions, /not SteviePhone\.HasPhone\(source\)/, "online session must revalidate phone possession");

const web = read("web/app.js");
assert.match(web, /finally\{await bridge\.send\('camera:close'/,
  "camera capture must restore focus on success and failure");
assert.doesNotMatch(web, /\.innerHTML\s*=\s*`[^`]*\$\{(?:n\.|m\.body|state\.error)/s,
  "unescaped notification/message/error data must not reach innerHTML");

const callbackFiles = ["server/callbacks.lua", "server/modules/economy_callbacks.lua",
  "server/modules/media_callbacks.lua", "server/modules/community_callbacks.lua"];
const names = [];
for (const file of callbackFiles) {
  const source = read(file);
  for (const match of source.matchAll(/register(?:Async|Sync)?\('([^']+)'/g)) names.push(match[1]);
}
for (const match of read("server/modules/call_callbacks.lua").matchAll(/\['(calls:[^']+)'\]\s*=/g)) names.push(match[1]);
const duplicates = names.filter((name, index) => names.indexOf(name) !== index);
assert.deepEqual([...new Set(duplicates)], [], `duplicate server callbacks: ${duplicates.join(", ")}`);

const nui = read("client/nui.lua");
for (const route of ["calls:start", "calls:accept", "calls:reject", "calls:hangup", "calls:history",
  "gallery:list", "gallery:delete", "bank:getData", "bank:getTransactions", "bank:transfer",
  "jobs:getData", "jobs:setDuty", "jobs:runAction", "messages:send", "social:getFeed",
  "market:getListings", "market:contactSeller"]) {
  assert.ok(nui.includes(`['${route}']`), `NUI route missing: ${route}`);
}
console.log("PASS final-security: load order, sessions, focus, callback uniqueness and NUI coverage verified");
