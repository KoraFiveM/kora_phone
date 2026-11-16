#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const { resolveWeb } = require("./helpers/web-source");
const read = file => fs.readFileSync(resolveWeb(root, file), "utf8");
const readApi = () => { // the web API layer is split across web/src/api/**
  const walk = (dir) => fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(`${dir}/${e.name}`) : e.name.endsWith(".ts") ? [read(`${dir}/${e.name}`)] : []);
  return [read("web/src/api.ts"), ...walk("web/src/api")].join("\n");
};

const manifest = read("fxmanifest.lua");
for (const module of ["call_callbacks", "economy_callbacks", "media_callbacks", "community_callbacks"]) {
  assert.ok(manifest.includes(`server/modules/${module}.lua`), `manifest must load ${module}`);
}
assert.ok(manifest.indexOf("server/rate_limits.lua") < manifest.indexOf("server/modules/call_callbacks.lua"),
  "rate limits must load before callback modules");
assert.ok(manifest.indexOf("server/permissions.lua") < manifest.indexOf("server/modules/call_callbacks.lua"),
  "permissions must load before callback modules");

const sessions = read("server/sessions.lua");
assert.match(sessions, /session\.citizenId ~= KoraPhone\.GetCitizenId\(source\)/, "online session must remain character-bound");
assert.match(sessions, /KoraPhone\.Handsets\.current\(source, false\)/, "online session must revalidate the handset the player is actually carrying");

const web = readApi();
assert.match(web, /captureDone: 'camera:close'/, "camera capture must restore phone visibility");
{
  // The UI is split across core/, apps/, sdk/ and api/: scan every source file, not a hand-picked pair.
  const walkSource = (dir) => fs.readdirSync(path.join(root, dir), { withFileTypes: true })
    .flatMap(e => e.isDirectory() ? walkSource(`${dir}/${e.name}`) : /\.(tsx?|jsx?)$/.test(e.name) ? [`${dir}/${e.name}`] : []);
  const sources = walkSource("web/src");
  assert.ok(sources.length > 40, "the web source scan must find the split UI files");
  for (const file of sources) {
    assert.doesNotMatch(fs.readFileSync(path.join(root, file), "utf8"), /dangerouslySetInnerHTML/, `${file}: React must not inject unescaped phone data`);
  }
}

const callbackFiles = ["server/callbacks.lua", "server/modules/economy_callbacks.lua",
  "server/modules/media_callbacks.lua", "server/modules/community_callbacks.lua", "server/modules/call_callbacks.lua"];
const names = [];
for (const file of callbackFiles) {
  const source = read(file);
  for (const match of source.matchAll(/(?:register(?:Async|Sync)?|bind)\('([^']+)'/g)) names.push(match[1]);
}
const duplicates = names.filter((name, index) => names.indexOf(name) !== index);
assert.deepEqual([...new Set(duplicates)], [], `duplicate server callbacks: ${duplicates.join(", ")}`);

const nui = require("./helpers/nui-source").source;
for (const route of ["calls:start", "calls:accept", "calls:reject", "calls:hangup", "calls:history",
  "gallery:list", "gallery:delete", "bank:getData", "bank:getTransactions", "bank:transfer",
  "jobs:getData", "jobs:setDuty", "jobs:runAction", "messages:send", "social:getFeed",
  "market:getListings", "market:contactSeller"]) {
  assert.ok(nui.includes(`['${route}']`), `NUI route missing: ${route}`);
}
console.log("PASS final-security: load order, sessions, focus, callback uniqueness and NUI coverage verified");