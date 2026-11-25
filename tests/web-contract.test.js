#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(process.argv[2] || path.join(__dirname, ".."));
const { resolveWeb } = require("./helpers/web-source");
// Run the production API and normalizer with a local NUI transport; no browser or server is started.
async function checkDeviceCache() {
  let ts;
  try { ts = require(path.join(root, "web/node_modules/typescript")); }
  catch { console.log("SKIP device-cache: web/node_modules/typescript is not installed"); return; }
  let checks = 0;
  const equal = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
  const replies = [];
  const storage = new Map([
    ["kora_phone:installed", JSON.stringify(["music", "clock"])],
    ["kora_phone:customApps", JSON.stringify({ "test-addon": true })],
  ]);
  const transport = async (url, options) => {
    const reply = replies.shift();
    assert.ok(reply, `Unexpected NUI request: ${url}`);
    equal(url, `https://kora_phone/${reply.route}`, "NUI route is unchanged");
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
      if (name === "./mock" || name === "../mock") return { isDemo: false, mockRequest: () => { throw new Error("Production requests must not use the preview adapter"); } };
      assert.ok(name.startsWith("./") || name.startsWith("../"), `Unexpected runtime dependency: ${name}`);
      const target = path.resolve(path.dirname(file), name);
      return load(fs.existsSync(`${target}.ts`) ? `${target}.ts` : path.join(target, "index.ts"));
    };
    new Function("require", "module", "exports", "window", "fetch", "localStorage", "addEventListener", "crypto", "AbortSignal", outputText)(
      requireLocal, module, module.exports, { GetParentResourceName: () => "kora_phone" }, transport,
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
    items: { alarms: [{ id: "a", label: "Alarm", time: "07:00", days: [], enabled: true }], stations: [{ id: "a", label: "Station", url: "https://example.invalid/radio" }] },
  }), gallery(1));
  equal(first.id, "101", "the existing string device ID contract is retained");
  equal(first.data.photos, [{ id: "1", url: "https://example.invalid/1.jpg", created_at: 123, kind: 'photo' }], "gallery fields retain their public mapping");
  equal(first.data.contacts[0], { id: 1, name: "A contact", number: "555001", photo: undefined, favorite: true }, "contacts retain their public mapping");
  const same = adaptBootstrap(raw("101", { name: "Renamed A" }));
  equal(same.preferences.name, "Renamed A", "same-device partial settings are applied");
  equal(same.preferences.volume, .9, "numeric and string IDs identify the same device");
  equal(same.data.photos, first.data.photos, "same-device direct bootstrap retains its gallery");
  equal(same.data.alarms, first.data.alarms, "same-device omitted collections retain existing values");
  const locked = adaptBootstrap(raw(202, { volume: 0 }, { security: { locked: true, hasPin: true } }));
  equal(locked.id, "202", "new-device ID is preserved");
  equal(locked.data, undefined, "locked devices still hide private collections");
  equal(locked.hasPin, true, "PIN metadata is preserved");
  equal(locked.preferences, { name: "Kora Phone", volume: 0, scale: 1, wallpaper: "kora_core", theme: "kora_core", setupComplete: false }, "a new locked phone uses its own partial settings and the existing defaults");
  const second = await refresh(raw(202, { name: "Phone B", scale: .8 }, { contacts: [], items: { alarms: [], stations: [] } }), failedGallery);
  equal(second.data.settings.name, "Phone B", "new-phone settings remain usable when gallery fails");
  equal(second.data.settings.volume, 0, "same-device partial settings retain zero values");
  for (const key of ["contacts", "alarms", "stations", "photos"]) equal(second.data[key], [], `phone B has no phone A ${key}`);
  equal(second.data.installedApps, ["music", "clock"], "a phone with no saved installs starts with the starter apps (install lists live in device settings, not NUI storage)");
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
  const settings = { name: "Saved B", volume: 0, scale: 1, wallpaper: "kora_core" };
  ok("settings:save", settings, { ...settings, installedApps: ["music", "clock"], expectedDeviceId: "202" });
  equal((await api("settings", settings)).settings, settings, "saving settings keeps its existing request and return shape");
  const newCollections = adaptBootstrap(raw(303, { name: "Phone C" }));
  for (const key of ["contacts", "alarms", "stations", "photos"]) equal(newCollections.data[key], [], `omitted new-device ${key} starts empty`);
  equal(newCollections.preferences.theme, "kora_core", "new-device theme has the existing default");
  equal(newCollections.preferences.setupComplete, false, "new-device setup has the existing default");
  const fallback = adaptBootstrap({});
  equal(fallback.id, "kora_phone", "a missing device ID keeps the existing fallback");
  equal(fallback.preferences.name, "Kora Phone", "the fallback device does not inherit a previous name");
  equal(fallback.number, "", "missing phone numbers keep the existing empty-string contract");
  equal(fallback.locked, false, "missing security retains the existing unlocked contract");
  equal(replies.length, 0, "every expected NUI request was consumed");
  console.log(`PASS device-cache: ${checks} production API controls`);
  const contactChecks = checks;
  const contacts = [
    { id: 11, displayName: 'Contact A', phoneNumber: '5551111111', isFavorite: true, photo: 'https://example.invalid/77.jpg' },
    { id: 12, displayName: 'Contact B', phoneNumber: '5552222222', isFavorite: false },
  ];
  // The Contacts UI is a folder app (apps/contacts) that calls the server directly; the phone's own copy of the contact
  // list (used by Phone, Messages and Pulse) is changed only through api('contactSave'), which these steps drive.
  let data = (await refresh(raw(404, {}, { contacts }), gallery(77))).data;
  const reread = () => { ok('bootstrap', raw(404, {}, { contacts })); replies.push({ route: 'gallery:list', body: { limit: 100 }, result: gallery(77) }); };
  const firstContact = data.contacts[0];
  equal(firstContact.number, '5551111111', 'the phone starts with the stored contact');
  ok('contacts:update', { id: 11 }, { id: 11, displayName: 'Edited A', phoneNumber: '5554444444', isFavorite: true, avatarMediaId: 77 });
  contacts[0] = { ...contacts[0], displayName: 'Edited A', phoneNumber: '5554444444' };
  reread(); data = await api('contactSave', { id: firstContact.id, name: 'Edited A', number: '5554444444', photo: firstContact.photo, favorite: firstContact.favorite });
  equal(data.contacts[0].id, 11, 'number edit retains the original contact ID');
  equal(data.contacts[0].favorite, true, 'number edit retains the selected contact favourite');
  equal(data.contacts[1].number, '5552222222', 'another contact is unchanged by the reloaded response');
  ok('contacts:create', { id: 13 }, { displayName: 'New C', phoneNumber: '5557777777', isFavorite: false });
  contacts.push({ id: 13, displayName: 'New C', phoneNumber: '5557777777', isFavorite: false });
  reread(); data = await api('contactSave', { name: 'New C', number: '5557777777' });
  equal(data.contacts[2].id, 13, 'new contact uses the create route without a retired editing ID');
  ok('contacts:update', { id: 11 }, { id: 11, displayName: 'Edited A', phoneNumber: '5554444444', isFavorite: false, avatarMediaId: 77 });
  contacts[0].isFavorite = false; reread(); data = await api('contactSave', { ...data.contacts[0], favorite: false });
  equal(data.contacts[0].favorite, false, 'favourite spread keeps the existing saved ID path');
  ok('contacts:delete', { id: 12 }, { id: 12 }); contacts.splice(1, 1); reread(); data = await api('contactSave', { ...data.contacts[1], remove: true });
  equal(data.contacts.map(contact => contact.id), [11, 13], 'delete spread keeps the existing saved ID path');
  ok('contacts:update', { id: 11 }, { id: 11, displayName: 'Legacy A', phoneNumber: '5554444444', isFavorite: false });
  contacts[0].displayName = 'Legacy A'; reread();
  equal((await api('contactSave', { name: 'Legacy A', number: '5554444444' })).contacts[0].name, 'Legacy A', 'ID-less public callers retain the number lookup');
  replies.push({ route: 'contacts:update', body: { id: 99, displayName: 'Unknown', phoneNumber: '5554444444', isFavorite: false }, result: { ok: false, error: 'Contact was not found' } });
  await assert.rejects(api('contactSave', { id: 99, name: 'Unknown', number: '5554444444' }), /Contact was not found/);
  equal(replies.length, 0, 'supplied ID stays authoritative and existing server errors propagate without create/reload');
  console.log(`PASS contact-edit: ${checks - contactChecks} actual component/API state controls`);
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
assert.ok(remoteScripts.every((src) => /^https:\/\/cfx-nui-kora_theme\/theme\.js(?:\?|$)/.test(src)),
  "Only kora_theme's shared runtime may be loaded remotely");
console.log("PASS web-contract: manifest and UI entry contract valid");
}

main().catch(error => { console.error(error); process.exitCode = 1; });

{
  // Setup ids must stay in step with the server allow-list, and legacy "kora_core" ids are normalised.
  const setupSrc = fs.readFileSync(resolveWeb(root, "web/src/Setup.tsx"), "utf8");
  const validationSrc = fs.readFileSync(path.join(root, "shared/validation.lua"), "utf8");
  const allowed = validationSrc.match(/SETTINGS_WALLPAPERS = \{([^}]*)\}/)[1].match(/\x27([a-z_]+)\x27/g).map(v => v.slice(1, -1));
  const offered = [...setupSrc.match(/WALLPAPERS = \[([\s\S]*?)\] as const/)[1].matchAll(/id: \x27([a-z_]+)\x27/g)].map(m => m[1]);
  assert.ok(offered.length > 0 && offered.every(id => allowed.includes(id)), "every setup wallpaper id is accepted by the server allow-list");
  assert.ok(offered.includes("kora_core"), "the default Signature wallpaper uses kora_core");
  assert.match(fs.readFileSync(path.join(root, "web/src/types.ts"), "utf8"), /wallpaper === \x27qbcore\x27\) legacy\.wallpaper = \x27kora_core\x27/, "legacy kora_core wallpaper is normalised");
}

{
  // kora_theme owns colour, font and shape: the web build imports its Vite plugin from the real resource, loads
  // its theme.css/theme.js at runtime and carries no palette, bundled font or vendored copy of its own.
  const web = path.join(root, "web");
  const src = path.join(web, "src");
  const read = (file) => fs.readFileSync(file, "utf8");
  const strip = (text) => text.replace(/\/\*[\s\S]*?\*\//g, "");
  assert.ok(!fs.existsSync(path.join(web, "vendor")), "no vendored kora_theme copy in web/");
  assert.match(read(path.join(web, "vite.config.ts")), /\[standalone\]\/kora_theme\/vite-plugin\.mjs/, "vite imports the plugin from the real kora_theme resource");
  const pkg = JSON.parse(read(path.join(web, "package.json")));
  assert.deepEqual(Object.keys({ ...pkg.dependencies, ...pkg.devDependencies }).filter((name) => name.startsWith("@fontsource")), [], "no @fontsource packages");
  const indexHtml = read(path.join(web, "index.html"));
  assert.match(indexHtml, /__KORA_THEME_BASE__\/theme\.css/, "index.html loads kora_theme's theme.css");
  assert.match(indexHtml, /__KORA_THEME_BASE__\/theme\.js/, "index.html loads kora_theme's theme.js");
  // The bundled fonts load from cfx-nui-kora_theme, and an underscore host is an invalid CSP source, so font-src allows the https: scheme.
  assert.match(indexHtml, /font-src 'self' data: https:;/, "CSP allows kora_theme's bundled fonts");

  const files = fs.readdirSync(src).filter((file) => /\.(css|tsx?)$/.test(file));
  const css = files.filter((file) => file.endsWith(".css"));
  // Artwork and sample data are content, not UI colour: CoverArt draws the Flip cover scenes, mock.ts is demo data.
  const contentOnly = new Set(["CoverArt.tsx", "mock.ts"]);
  let rules = 0;
  for (const file of files) {
    const text = strip(read(path.join(src, file)));
    assert.ok(!/@fontsource/.test(text), `${file} does not import @fontsource`);
    assert.ok(!/--ui-|--tone-|resolveHandsetTheme|handsetThemeTokens/.test(text), `${file} has no private palette tokens`);
    if (contentOnly.has(file)) continue;
    assert.ok(!/#[0-9a-fA-F]{3,8}\b|\brgba?\(/.test(text), `${file} has no hard-coded hex or rgb colour`);
    if (file.endsWith(".css")) {
      assert.ok(!/font-family:\s*['"]|font:[^;]*['"][A-Za-z ]+['"]/.test(text), `${file} sets no hard-coded font family`);
      assert.ok(!/var\(--font-(?:sans|mono|heading),/.test(text), `${file} uses the kora_theme font tokens without private fallbacks`);
      rules += (text.match(/var\(--font-(?:sans|mono|heading)\)/g) || []).length;
    }
  }
  assert.ok(rules >= 50, "UI text follows the kora_theme font tokens");
  assert.match(read(path.join(src, "style.css")), /:root \{ font-family: var\(--font-sans\);/, "body text uses --font-sans");
  assert.match(read(path.join(src, "style.css")), /:where\(h1, h2, h3, h4, h5, h6\) \{ font-family: var\(--font-heading\); \}/, "headings use --font-heading");

  // Colour is derived from kora_theme's tokens by scheme.css; handsets only carry structure.
  const scheme = read(path.join(src, "scheme.css"));
  for (const token of ["--foreground", "--background", "--primary", "--border", "--surface-raised"]) assert.ok(scheme.includes(`var(${token})`), `scheme.css derives from kora_theme ${token}`);
  assert.match(scheme, /\.appearance-light\s*\{/, "scheme.css derives a light appearance");
  const themes = read(path.join(src, "themes.ts"));
  assert.ok(!/(?:dark|light|flip|fold)\s*:\s*Palette|#[0-9a-fA-F]{3,8}\b/.test(themes), "themes.ts carries no palette tables");
  const validation = read(path.join(root, "shared/validation.lua"));
  const serverThemes = validation.match(/SETTINGS_THEMES = \{([^}]*)\}/)[1].match(/'([a-z_]+)'/g).map((id) => id.slice(1, -1));
  const clientThemes = [...themes.match(/THEME_IDS = \[([^\]]*)\]/)[1].matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
  assert.deepEqual([...clientThemes].sort(), [...serverThemes].sort(), "client theme ids match the server allow-list");
  assert.ok(css.length <= 11, "the stylesheet set stays consolidated");
  console.log(`PASS web-contract: kora_theme owns colour, font and shape; ${rules} font declarations, ${css.length} stylesheets, no hard-coded colours`);
}

