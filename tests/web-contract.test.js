#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(process.argv[2] || path.join(__dirname, ".."));
// Run the production API and normalizer with a local NUI transport; no browser or server is started.
async function checkDeviceCache() {
  let ts;
  try { ts = require(path.join(root, "web/node_modules/typescript")); }
  catch { console.log("SKIP device-cache: web/node_modules/typescript is not installed"); return; }
  let checks = 0;
  const equal = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
  const replies = [];
  const storage = new Map([
    ["qbphone:installed", JSON.stringify(["notes", "mail"])],
    ["qbphone:customApps", JSON.stringify({ "test-addon": true })],
  ]);
  const transport = async (url, options) => {
    const reply = replies.shift();
    assert.ok(reply, `Unexpected NUI request: ${url}`);
    equal(url, `https://qbphone/${reply.route}`, "NUI route is unchanged");
    equal(JSON.parse(options.body), reply.body, "NUI arguments are unchanged");
    if (reply.started) reply.started();
    return { ok: true, json: async () => reply.result };
  };
  const modules = new Map();
  const load = (file) => {
    if (modules.has(file)) return modules.get(file).exports;
    const module = { exports: {} }; modules.set(file, module);
    const source = fs.readFileSync(file, "utf8");
    const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } });
    const requireLocal = (name) => {
      if (name === "./mock") return { mockRequest: () => { throw new Error("Production requests must not use the preview adapter"); } };
      assert.ok(name.startsWith("./"), `Unexpected runtime dependency: ${name}`);
      return load(path.resolve(path.dirname(file), `${name}.ts`));
    };
    new Function("require", "module", "exports", "window", "fetch", "localStorage", "addEventListener", "crypto", "AbortSignal", outputText)(
      requireLocal, module, module.exports, { GetParentResourceName: () => "qbphone" }, transport,
      { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
      () => {}, { randomUUID: () => "test-request" }, undefined);
    return module.exports;
  };
  const { api, adaptBootstrap, isPreview } = load(path.join(root, "web/src/api.ts"));
  equal(isPreview, false, "checks exercise the production API");
  const ok = (route, data, body = {}) => replies.push({ route, body, result: { ok: true, data } });
  const raw = (id, settings = {}, more = {}) => ({ device: { id, phoneNumber: `555${id}`, settings }, security: { locked: false }, ...more });
  const refresh = async (bootstrap, gallery) => {
    ok("bootstrap", bootstrap);
    replies.push({ route: "gallery:list", body: { limit: 100 }, result: gallery });
    return api("refresh", {});
  };
  const gallery = id => ({ ok: true, data: { items: [{ id, publicUrl: `https://example.invalid/${id}.jpg`, createdAt: 123 }] } });
  const failedGallery = { ok: false, error: "Gallery unavailable" };
  const privateSettings = { name: "Phone A", volume: .9, scale: 1.1, wallpaper: "custom", wallpaperUrl: "https://example.invalid/private.jpg", theme: "dark", setupComplete: true, dnd: true };
  const first = await refresh(raw(101, privateSettings, {
    contacts: [{ id: 1, displayName: "A contact", phoneNumber: "555001", isFavorite: 1 }],
    items: { notes: [{ id: "a", title: "Private", body: "A note" }], alarms: [{ id: "a", label: "Alarm", time: "07:00", days: [], enabled: true }], stations: [{ id: "a", label: "Station", url: "https://example.invalid/radio" }] },
  }), gallery(1));
  equal(first.id, "101", "the existing string device ID contract is retained");
  equal(first.data.photos, [{ id: "1", url: "https://example.invalid/1.jpg", created_at: 123 }], "gallery fields retain their public mapping");
  equal(first.data.contacts[0], { id: 1, name: "A contact", number: "555001", photo: undefined, favorite: true }, "contacts retain their public mapping");
  const same = adaptBootstrap(raw("101", { name: "Renamed A" }));
  equal(same.preferences.name, "Renamed A", "same-device partial settings are applied");
  equal(same.preferences.volume, .9, "numeric and string IDs identify the same device");
  equal(same.data.photos, first.data.photos, "same-device direct bootstrap retains its gallery");
  equal(same.data.notes, first.data.notes, "same-device omitted collections retain existing values");
  const locked = adaptBootstrap(raw(202, { volume: 0 }, { security: { locked: true, hasPin: true } }));
  equal(locked.id, "202", "new-device ID is preserved");
  equal(locked.data, undefined, "locked devices still hide private collections");
  equal(locked.hasPin, true, "PIN metadata is preserved");
  equal(locked.preferences, { name: "Nothing Phone", volume: 0, scale: 1, wallpaper: "qbcore", theme: "qbcore", setupComplete: false }, "a new locked phone uses its own partial settings and the existing defaults");
  const second = await refresh(raw(202, { name: "Phone B", scale: .8 }, { contacts: [], items: { notes: [], alarms: [], stations: [] } }), failedGallery);
  equal(second.data.settings.name, "Phone B", "new-phone settings remain usable when gallery fails");
  equal(second.data.settings.volume, 0, "same-device partial settings retain zero values");
  for (const key of ["contacts", "notes", "alarms", "stations", "photos"]) equal(second.data[key], [], `phone B has no phone A ${key}`);
  equal(second.data.installedApps, ["notes", "mail"], "the existing shared install preferences are preserved");
  equal(second.data.customApps, { "test-addon": true }, "the existing shared addon preferences are preserved");
  equal(first.data.settings, privateSettings, "resetting another device does not mutate an earlier returned snapshot");
  equal(first.data.photos.length, 1, "an earlier returned gallery remains intact");
  const loaded = await refresh(raw(202), gallery(2));
  equal(loaded.data.photos[0].id, "2", "a later successful gallery belongs to the current phone");
  const failed = await refresh(raw(202), failedGallery);
  equal(failed.data.photos, loaded.data.photos, "same-device optional gallery failure retains its existing cache fallback");
  await refresh(raw(202), gallery(3));
  let completeGallery, galleryStarted;
  const pendingGallery = new Promise(resolve => { completeGallery = resolve; });
  const started = new Promise(resolve => { galleryStarted = resolve; });
  ok("bootstrap", raw(202));
  replies.push({ route: "gallery:list", body: { limit: 100 }, result: pendingGallery, started: galleryStarted });
  const loading = api("refresh", {});
  await started;
  equal(adaptBootstrap(raw("202")).data.photos[0].id, "3", "same-device pending requests retain their existing gallery");
  completeGallery(gallery(4));
  equal((await loading).data.photos[0].id, "4", "the pending gallery still publishes a successful result");
  const settings = { name: "Saved B", volume: 0, scale: 1, wallpaper: "qbcore" };
  ok("settings:save", settings, settings);
  equal((await api("settings", settings)).settings, settings, "saving settings keeps its existing request and return shape");
  const newCollections = adaptBootstrap(raw(303, { name: "Phone C" }));
  for (const key of ["contacts", "notes", "alarms", "stations", "photos"]) equal(newCollections.data[key], [], `omitted new-device ${key} starts empty`);
  equal(newCollections.preferences.theme, "qbcore", "new-device theme has the existing default");
  equal(newCollections.preferences.setupComplete, false, "new-device setup has the existing default");
  const fallback = adaptBootstrap({});
  equal(fallback.id, "qbphone", "a missing device ID keeps the existing fallback");
  equal(fallback.preferences.name, "Nothing Phone", "the fallback device does not inherit a previous name");
  equal(fallback.number, "", "missing phone numbers keep the existing empty-string contract");
  equal(fallback.locked, false, "missing security retains the existing unlocked contract");
  equal(replies.length, 0, "every expected NUI request was consumed");
  console.log(`PASS device-cache: ${checks} production API controls`);
}

async function main() {
  await checkDeviceCache();
const manifest = path.join(root, "fxmanifest.lua");

if (!fs.existsSync(manifest)) {
  console.log("SKIP web-contract: fxmanifest.lua does not exist yet");
  return;
}

const text = fs.readFileSync(manifest, "utf8");
const match = text.match(/ui_page\s+["']([^"']+)["']/);
assert.ok(match, "fxmanifest.lua must declare ui_page");

const uiEntry = path.resolve(root, match[1]);
assert.ok(uiEntry.startsWith(root + path.sep), "ui_page must remain inside the resource");
if (!fs.existsSync(uiEntry)) {
  console.log(`SKIP web-contract: declared UI build entry does not exist yet (${match[1]})`);
  return;
}

const html = fs.readFileSync(uiEntry, "utf8");
assert.match(html, /<meta[^>]+charset=/i, "UI entry should declare charset");
assert.match(html, /<meta[^>]+viewport/i, "UI entry should declare viewport");
const remoteScripts = [...html.matchAll(/<script[^>]+src=["'](https?:\/\/[^"']+)/gi)].map((match) => match[1]);
assert.ok(remoteScripts.every((src) => /^https:\/\/cfx-nui-qbtheme\/theme\.js(?:\?|$)/.test(src)),
  "Only qbtheme's shared runtime may be loaded remotely");
console.log("PASS web-contract: manifest and UI entry contract valid");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
