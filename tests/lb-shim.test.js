// node tests/lb-shim.test.js: web/public/lb-shim.js run against a fake window, the way the phone injects it into an lb-phone app.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'web/public/lb-shim.js'), 'utf8');
const HOST = 'https://cfx-nui-kora_phone';

function load(config = {}) {
    const posted = [];
    const fetched = [];
    const listeners = {};
    const root = { style: { props: {}, setProperty(name, value) { this.props[name] = value; } }, attrs: {}, setAttribute(name, value) { this.attrs[name] = value; } };
    const parent = { postMessage: (message, origin) => posted.push({ message, origin }) };
    const window = {
        __koraLb: { resource: 'my_app', ui: 'ui/index.html', app: 'my', name: 'My App', hostOrigin: HOST, ...config },
        parent,
        addEventListener: (type, fn) => { (listeners[type] = listeners[type] || []).push(fn); },
        dispatchEvent: event => { dispatched.push(event); },
    };
    const dispatched = [];
    window.window = window;
    const context = vm.createContext({
        window, document: { documentElement: root, head: { appendChild() {} }, createElement: () => ({}) }, location: { origin: HOST },
        console: { warn() {} }, Promise, JSON, Object, Array, String, Math, Error,
        MessageEvent: class { constructor(type, init) { this.type = type; this.data = init.data; } },
        fetch: (url, init) => { fetched.push({ url, init }); return Promise.resolve({ json: () => Promise.resolve({ ok: true }) }); },
    });
    context.window = window;
    vm.runInContext(source, context);
    const deliver = (data, over = {}) => (listeners.message || []).forEach(fn => fn({ source: parent, origin: HOST, data, ...over }));
    return { window, posted, fetched, root, dispatched, deliver };
}

const run = async () => {
    let checks = 0;
    const ok = (condition, label) => { assert.ok(condition, label); checks += 1; };

    const t = load();
    const w = t.window;
    for (const name of ['resourceName', 'appName', 'appIdentifier', 'settings', 'components', 'fetchNui', 'onNuiEvent', 'onSettingsChange', 'formatPhoneNumber', 'setApp', 'createCall'])
        ok(name in w, `${name} is defined`);
    assert.equal(w.resourceName, 'my_app'); assert.equal(w.appName, 'My App'); assert.equal(w.appIdentifier, 'my'); checks += 3;
    for (const name of ['setPopUp', 'setContextMenu', 'setContactSelector', 'setGallery', 'setColorPicker', 'setEmojiPickerVisible', 'setFullscreenImage', 'setHomeIndicatorVisible', 'setShareComponent', 'setGifPickerVisible', 'createGameRender', 'GameMap', 'uploadMedia', 'saveToGallery'])
        ok(typeof w.components[name] === 'function', `components.${name}`);

    // It announces itself to the phone with the v1 protocol, only to the phone's origin.
    assert.equal(t.posted[0].message.type, 'ready'); assert.equal(t.posted[0].message.kora, 'phone'); assert.equal(t.posted[0].origin, HOST); checks += 3;

    // fetchNui goes to the app's own resource, or to the resource it names.
    await w.fetchNui('getData', { a: 1 });
    await w.fetchNui('other', {}, 'another_res');
    assert.equal(t.fetched[0].url, 'https://my_app/getData'); assert.equal(JSON.parse(t.fetched[0].init.body).a, 1);
    assert.equal(t.fetched[1].url, 'https://another_res/other'); checks += 3;

    // Theme push -> CSS variables and lb-phone's data-theme.
    t.deliver({ kora: 'phone', v: 1, type: 'init', payload: { theme: { vars: { '--primary': '84 100% 50%' }, scheme: 'light' } } });
    assert.equal(t.root.style.props['--primary'], '84 100% 50%'); assert.equal(t.root.attrs['data-theme'], 'light'); checks += 2;
    t.deliver({ kora: 'phone', v: 1, type: 'theme', payload: { vars: {}, scheme: 'dark' } });
    assert.equal(t.root.attrs['data-theme'], 'dark'); checks += 1;

    // SendCustomAppMessage: named events reach onNuiEvent, the raw payload also arrives as a window message.
    const seen = [];
    const off = w.onNuiEvent('tick', data => seen.push(data));
    t.deliver({ kora: 'phone', v: 1, type: 'event', payload: { name: 'tick', data: { n: 1 } } });
    off();
    t.deliver({ kora: 'phone', v: 1, type: 'event', payload: { name: 'tick', data: { n: 2 } } });
    assert.deepEqual(seen, [{ n: 1 }]); checks += 1;
    t.deliver({ kora: 'phone', v: 1, type: 'event', payload: { name: 'kora:raw', data: { action: 'x' } } });
    assert.deepEqual(t.dispatched[0].data, { action: 'x' }); checks += 1;

    // Settings.
    let changed;
    w.onSettingsChange(value => { changed = value; });
    t.deliver({ kora: 'phone', v: 1, type: 'event', payload: { name: 'kora:settings', data: { wallpaper: 'x' } } });
    assert.deepEqual(changed, { wallpaper: 'x' }); assert.deepEqual(w.settings, { wallpaper: 'x' }); checks += 2;

    // Messages from anywhere but the phone are ignored.
    t.deliver({ kora: 'phone', v: 1, type: 'event', payload: { name: 'kora:settings', data: { evil: true } } }, { origin: 'https://evil.example' });
    t.deliver({ kora: 'phone', v: 1, type: 'event', payload: { name: 'kora:settings', data: { evil: true } } }, { source: {} });
    assert.deepEqual(w.settings, { wallpaper: 'x' }); checks += 1;

    // setApp and createCall are requests to the phone.
    const before = t.posted.length;
    w.setApp({ name: 'Messages', data: { view: 'x' } });
    w.createCall({ number: '5550001', videoCall: true });
    const [openApp, call] = t.posted.slice(before).map(item => item.message);
    assert.equal(openApp.type, 'lb'); assert.equal(openApp.payload.action, 'openApp'); assert.equal(openApp.payload.app, 'Messages');
    assert.equal(call.payload.action, 'call'); assert.equal(call.payload.number, '5550001'); assert.equal(call.payload.videoCall, true); checks += 7;

    // A response resolves the pending request.
    const pendingCall = w.createCall({ number: '5550002' });
    const id = t.posted.at(-1).message.id;
    t.deliver({ kora: 'phone', v: 1, type: 'response', id, ok: true, payload: true });
    assert.equal(await pendingCall, true); checks += 1;

    // Unsupported pieces fail loudly instead of hanging.
    await assert.rejects(w.components.uploadMedia('Image', null), /not available in kora_phone/);
    assert.throws(() => new w.components.GameMap({}), /not available in kora_phone/); checks += 2;

    assert.equal(w.formatPhoneNumber('5550001'), '555-0001'); checks += 1;
    console.log(`PASS lb-shim: ${checks} checks`);
};

run().catch(error => { console.error(error); process.exit(1); });
