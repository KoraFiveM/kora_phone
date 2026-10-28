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
      if (name === "./mock") return { mockRequest: () => { throw new Error("Production requests must not use the preview adapter"); } };
      assert.ok(name.startsWith("./"), `Unexpected runtime dependency: ${name}`);
      return load(path.resolve(path.dirname(file), `${name}.ts`));
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
  equal(locked.preferences, { name: "Nothing Phone", volume: 0, scale: 1, wallpaper: "kora_core", theme: "kora_core", setupComplete: false }, "a new locked phone uses its own partial settings and the existing defaults");
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
  const settings = { name: "Saved B", volume: 0, scale: 1, wallpaper: "kora_core" };
  ok("settings:save", settings, settings);
  equal((await api("settings", settings)).settings, settings, "saving settings keeps its existing request and return shape");
  const newCollections = adaptBootstrap(raw(303, { name: "Phone C" }));
  for (const key of ["contacts", "notes", "alarms", "stations", "photos"]) equal(newCollections.data[key], [], `omitted new-device ${key} starts empty`);
  equal(newCollections.preferences.theme, "kora_core", "new-device theme has the existing default");
  equal(newCollections.preferences.setupComplete, false, "new-device setup has the existing default");
  const fallback = adaptBootstrap({});
  equal(fallback.id, "kora_phone", "a missing device ID keeps the existing fallback");
  equal(fallback.preferences.name, "Nothing Phone", "the fallback device does not inherit a previous name");
  equal(fallback.number, "", "missing phone numbers keep the existing empty-string contract");
  equal(fallback.locked, false, "missing security retains the existing unlocked contract");
  equal(replies.length, 0, "every expected NUI request was consumed");
  console.log(`PASS device-cache: ${checks} production API controls`);
  const contactChecks = checks;
  const contacts = [
    { id: 11, displayName: 'Contact A', phoneNumber: '5551111111', isFavorite: true, photo: 'https://example.invalid/77.jpg' },
    { id: 12, displayName: 'Contact B', phoneNumber: '5552222222', isFavorite: false },
  ];
  const context = { data: (await refresh(raw(404, {}, { contacts }), gallery(77))).data, updateData: value => { context.data = value; }, busy: false, navigate: () => {} };
  let pending, hookIndex = 0;
  const hooks = [];
  context.run = fn => { pending = fn(); };
  const useState = initial => {
    const slot = hookIndex++;
    if (!(slot in hooks)) hooks[slot] = initial;
    return [hooks[slot], value => { hooks[slot] = typeof value === 'function' ? value(hooks[slot]) : value; }];
  };
  const jsx = (type, props) => ({ type, props: props || {} });
  const componentModule = { exports: {} };
  const componentSource = ts.transpileModule(fs.readFileSync(path.join(root, 'web/src/Communication.tsx'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, jsx: ts.JsxEmit.ReactJSX },
  }).outputText;
  const componentRequire = name => {
    if (name === 'react') return { useState, useEffect: () => {} };
    if (name === 'react/jsx-runtime') return { jsx, jsxs: jsx, Fragment: 'Fragment' };
    if (name === './api') return { api, isPreview: false };
    if (name === './PhoneContext') return { usePhone: () => context };
    if (name === './types') return load(path.join(root, 'web/src/types.ts'));
    if (name === './chatTokens') return load(path.join(root, 'web/src/chatTokens.ts'));
    if (name === './Images') return { ImagePicker: 'ImagePicker', PhotoImage: 'PhotoImage' };
    if (name === './components') return { Row: 'Row', Empty: 'Empty' };
    if (name === 'lucide-react') return {};
    throw new Error(`Unexpected component import: ${name}`);
  };
  new Function('require', 'module', 'exports', componentSource)(componentRequire, componentModule, componentModule.exports);
  const view = () => { hookIndex = 0; return componentModule.exports.ContactsScreen(); };
  const nodes = value => {
    if (Array.isArray(value)) return value.flatMap(nodes);
    if (!value || typeof value !== 'object') return [];
    return [value, ...nodes(value.props?.children)];
  };
  const button = label => { const value = nodes(view()).find(node => node.type === 'button' && node.props['aria-label'] === label); assert.ok(value, label); return value.props; };
  const field = label => { const node = nodes(view()).find(node => node.type === 'label' && node.props.children[0] === label); assert.ok(node, label); return nodes(node).find(child => child.type === 'input').props; };
  const submit = async () => { const form = nodes(view()).find(node => node.type === 'form'); assert.ok(form, 'contact editor is open'); form.props.onSubmit({ preventDefault: () => {} }); await pending; };
  const reread = () => { ok('bootstrap', raw(404, {}, { contacts })); replies.push({ route: 'gallery:list', body: { limit: 100 }, result: gallery(77) }); };
  button('Edit Contact A').onClick();
  equal(field('Number').value, '5551111111', 'actual editor starts with selected contact');
  field('Name').onChange({ target: { value: 'Edited A' } });
  field('Number').onChange({ target: { value: '5554444444' } });
  ok('contacts:update', { id: 11 }, { id: 11, displayName: 'Edited A', phoneNumber: '5554444444', isFavorite: true, avatarMediaId: 77 });
  contacts[0] = { ...contacts[0], displayName: 'Edited A', phoneNumber: '5554444444' };
  reread(); await submit();
  equal(context.data.contacts[0].id, 11, 'number edit retains the original contact ID');
  equal(context.data.contacts[0].favorite, true, 'number edit retains the selected contact favourite');
  equal(context.data.contacts[1].number, '5552222222', 'another contact is unchanged by the reloaded response');
  equal(nodes(view()).some(node => node.type === 'form'), false, 'successful save closes the existing editor');
  button('Edit Contact B').onClick();
  button('Add contact').onClick(); button('Add contact').onClick();
  equal(field('Name').value, '', 'Add clears the old editor');
  field('Name').onChange({ target: { value: 'New C' } }); field('Number').onChange({ target: { value: '5557777777' } });
  ok('contacts:create', { id: 13 }, { displayName: 'New C', phoneNumber: '5557777777', isFavorite: false });
  contacts.push({ id: 13, displayName: 'New C', phoneNumber: '5557777777', isFavorite: false });
  reread(); await submit();
  equal(context.data.contacts[2].id, 13, 'new contact uses existing create route without a retired editing ID');
  ok('contacts:update', { id: 11 }, { id: 11, displayName: 'Edited A', phoneNumber: '5554444444', isFavorite: false, avatarMediaId: 77 });
  contacts[0].isFavorite = false; reread(); button('Remove Edited A from favourites').onClick(); await pending;
  equal(context.data.contacts[0].favorite, false, 'favourite spread keeps the existing saved ID path');
  ok('contacts:delete', { id: 12 }, { id: 12 }); contacts.splice(1, 1); reread(); button('Delete Contact B').onClick(); await pending;
  equal(context.data.contacts.map(contact => contact.id), [11, 13], 'delete spread keeps the existing saved ID path');
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
assert.ok(remoteScripts.every((src) => /^https:\/\/cfx-nui-qbtheme\/theme\.js(?:\?|$)/.test(src)),
  "Only qbtheme's shared runtime may be loaded remotely");
console.log("PASS web-contract: manifest and UI entry contract valid");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
