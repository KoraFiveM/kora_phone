// Tests the pure app-host logic (web/src/sdk). Transpiles the TS to a temp dir with tsc first.
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'kora-sdk-host-'));
const tsc = path.join(root, 'web', 'node_modules', '.bin', 'tsc');
execFileSync(tsc, ['--outDir', out, '--module', 'commonjs', '--target', 'ES2022', '--strict', '--skipLibCheck',
    ...fs.readdirSync(path.join(root, 'web/src/sdk')).filter(f => f.endsWith('.ts')).map(f => path.join(root, 'web/src/sdk', f))]);
const sdk = require(path.join(out, 'index.js'));
const { legacyEvent } = require(path.join(out, 'legacy.js'));

let failures = 0;
const queue = [];
const test = (name, fn) => queue.push([name, fn]);

const env = (type, payload, id = 'r1') => ({ kora: 'phone', v: 1, id, type, payload });
function setup(over = {}) {
    const win = {};
    const posted = [];
    const calls = [];
    const transport = { request: async (route, payload) => { calls.push([route, payload]); return over.reply ?? { ok: true, data: { fine: true } }; } };
    const router = sdk.createRouter({
        appId: 'demo', resource: 'demo_res', permissions: over.permissions ?? ['storage', 'notify'], transport,
        handset: 'standard', locale: 'en', getTheme: () => ({ vars: { '--primary': '84 100% 50%' }, scheme: 'dark' }),
        post: m => posted.push(m), timeoutMs: over.timeoutMs ?? 50, ...(over.router || {}),
    });
    const send = (data, extra = {}) => router.handle({ source: win, origin: 'https://cfx-nui-demo_res', data, ...extra }, win);
    return { win, posted, calls, router, send };
}

test('origin and source validation', async () => {
    const t = setup();
    assert.equal(await t.send(env('ready'), { origin: 'https://evil.example' }), false);
    assert.equal(await t.send(env('ready'), { source: {} }), false);
    assert.equal(await t.router.handle({ source: null, origin: t.router.origin, data: env('ready') }, null), false);
    assert.equal(t.posted.length, 0);
    assert.equal(await t.send(env('ready')), true);
});

test('rejects malformed envelopes', async () => {
    const t = setup();
    for (const bad of [null, 'x', {}, { kora: 'phone', v: 2, id: 'a', type: 'ready' }, env('bogus'), { kora: 'phone', v: 1, type: 'ready' }]) {
        assert.equal(await t.send(bad), false);
    }
});

test('ready returns init payload', async () => {
    const t = setup();
    await t.send(env('ready'));
    const res = t.posted[0];
    assert.equal(res.ok, true);
    assert.deepEqual(res.payload.permissions, ['storage', 'notify']);
    assert.equal(res.payload.appId, 'demo');
    assert.equal(res.payload.theme.scheme, 'dark');
    assert.equal(t.router.isReady(), true);
});

test('ready yields a response, then an init push, then onReady', async () => {
    let readyCalls = 0;
    const t = setup({ router: { onReady: () => { readyCalls++; t.posted.push('onReady'); } } });
    await t.send(env('ready', undefined, 'abc'));
    assert.equal(t.posted[0].type, 'response');
    assert.equal(t.posted[0].id, 'abc');
    assert.deepEqual(t.posted[1], { kora: 'phone', v: 1, type: 'init', payload: t.posted[0].payload });
    assert.equal(t.posted[2], 'onReady');
    assert.equal(readyCalls, 1);
    const denied = setup({ permissions: [] });
    await denied.send(env('getContext'));
    assert.equal(denied.posted.filter(m => m.type === 'init').length, 0);
});

test('permission gate blocks without calling transport', async () => {
    const t = setup({ permissions: [] });
    await t.send(env('storage.get', { key: 'a' }));
    await t.send(env('contacts.list'));
    await t.send(env('notify', { title: 'x' }));
    assert.equal(t.calls.length, 0);
    assert.ok(t.posted.every(r => r.ok === false && r.error.code === 'PERMISSION_DENIED'));
});

test('routes and unwraps server replies', async () => {
    const t = setup();
    await t.send(env('storage.set', { key: 'k', value: { a: 1 } }));
    assert.deepEqual(t.calls[0], ['apps:storage:set', { app: 'demo', key: 'k', value: { a: 1 } }]);
    assert.equal(t.posted[0].payload, true);
});

test('server error becomes error response', async () => {
    const t = setup({ reply: { ok: false, error: { code: 'QUOTA', message: 'full' } }, permissions: ['storage'] });
    await t.send(env('storage.get', { key: 'k' }));
    assert.deepEqual(t.posted[0].error, { code: 'QUOTA', message: 'full' });
});

test('callback name validation and routing', async () => {
    const t = setup();
    await t.send(env('callback', { name: 'bad name!' }, 'a'));
    assert.equal(t.posted[0].error.code, 'INVALID_PAYLOAD');
    await t.send(env('callback', { name: 'get.items', payload: { n: 1 } }, 'b'));
    assert.deepEqual(t.calls[0], ['apps:call', { app: 'demo', name: 'get.items', payload: { n: 1 } }]);
});

test('timeout', async () => {
    const win = {};
    const posted = [];
    const router = sdk.createRouter({
        appId: 'demo', resource: 'r', permissions: ['storage'], transport: { request: () => new Promise(() => {}) },
        handset: 'flip', locale: 'en', getTheme: () => ({ vars: {}, scheme: 'dark' }), post: m => posted.push(m), timeoutMs: 20,
    });
    await router.handle({ source: win, origin: 'https://cfx-nui-r', data: env('storage.get', { key: 'k' }) }, win);
    assert.equal(posted[0].error.code, 'TIMEOUT');
});

test('close / setTitle callbacks and dispose', async () => {
    let closed = 0; let title = null;
    const t = setup({ router: { onClose: () => { closed++; }, onSetTitle: v => { title = v; } } });
    await t.send(env('close'));
    await t.send(env('setTitle', { title: 'Hi' }));
    assert.equal(closed, 1); assert.equal(title, 'Hi');
    t.router.dispose();
    assert.equal(await t.send(env('ready')), false);
});

test('permission helpers', () => {
    assert.deepEqual(sdk.normalizePermissions(['storage', 'storage', 'nope', 5]), ['storage']);
    assert.equal(sdk.isAllowed(['contacts.read'], 'contacts.list'), true);
    assert.equal(sdk.isAllowed(['contacts.read'], 'contacts.save'), false);
    assert.equal(sdk.isAllowed([], 'haptic'), true);
});

test('theme collection and scheme', () => {
    const style = { '--background': '0 0% 98%', '--primary': '84 100% 50%', '--radius': '0.625rem' };
    const vars = sdk.collectThemeVars(n => style[n] ?? '');
    assert.deepEqual(Object.keys(vars).sort(), ['--background', '--primary', '--radius']);
    assert.equal(sdk.schemeFromVars(vars), 'light');
    assert.equal(sdk.schemeFromVars({ '--background': '0 0% 6%' }), 'dark');
    assert.equal(sdk.schemeFromVars({}), 'dark');
    assert.equal(sdk.sameTheme({ vars, scheme: 'light' }, { vars: { ...vars }, scheme: 'light' }), true);
    assert.equal(sdk.sameTheme(null, { vars, scheme: 'light' }), false);
});

test('url building and legacy events', () => {
    assert.equal(sdk.appUrl('res', 'ui/index.html', { a: '1' }), 'https://cfx-nui-res/ui/index.html?a=1');
    assert.equal(sdk.appUrl('res', 'https://x.test/p?z=1', { a: '1' }), 'https://x.test/p?z=1&a=1');
    assert.equal(sdk.originOf('https://x.test/p'), 'https://x.test');
    assert.equal(sdk.originOf('nonsense'), '');
    assert.deepEqual(legacyEvent({ action: 'a', data: 1 }), { name: 'a', data: 1 });
    assert.equal(legacyEvent({}), null);
});

test('SDK client <-> host router cross-check', async () => {
    const distEntry = path.join(root, 'sdk', 'dist', 'index.js');
    if (!fs.existsSync(distEntry)) { console.log('skip - sdk/dist missing (run npm run build in sdk/)'); return; }
    const { createPhoneClient } = await import(require('node:url').pathToFileURL(distEntry).href);
    const PHONE_ORIGIN = 'https://cfx-nui-kora_phone';
    const APP_ORIGIN = 'https://cfx-nui-demo_res';
    const listeners = new Set();
    const props = new Map();
    const hostWindow = {}; // what the iframe sees as window.parent
    const iframeWindow = {}; // iframe.contentWindow on the host side
    const targets = [];
    const router = sdk.createRouter({
        appId: 'demo', resource: 'demo_res', permissions: ['storage'], handset: 'flip', locale: 'en-GB',
        transport: { request: async () => ({ ok: true, data: { value: 'v' } }) },
        getTheme: () => ({ vars: { '--primary': '84 100% 50%' }, scheme: 'dark' }),
        post: message => setImmediate(() => listeners.forEach(l => l({ data: message, origin: PHONE_ORIGIN, source: hostWindow }))),
    });
    const parent = {
        postMessage: (message, targetOrigin) => {
            targets.push(targetOrigin);
            void router.handle({ data: message, origin: APP_ORIGIN, source: iframeWindow }, iframeWindow);
        },
    };
    const win = {
        parent: Object.assign(hostWindow, parent),
        addEventListener: (_t, l) => listeners.add(l),
        removeEventListener: (_t, l) => listeners.delete(l),
        document: { documentElement: { style: { setProperty: (k, v) => props.set(k, v) } } },
    };
    const client = createPhoneClient({ window: win, hostOrigin: PHONE_ORIGIN, timeoutMs: 500 });
    const init = await client.ready();
    assert.equal(init.appId, 'demo');
    assert.equal(init.handset, 'flip');
    assert.equal(props.get('--primary'), '84 100% 50%');
    assert.equal(props.get('color-scheme'), 'dark');
    assert.equal(client.theme.scheme, 'dark');
    assert.equal(await client.storage.get('k'), 'v');
    assert.ok(targets.every(t => t === PHONE_ORIGIN), 'iframe posts to the phone origin');
    client.destroy();
});

// ---- response shapes: host payloads must match sdk/src/protocol.ts ----
const shapeCases = [
    ['storage.get', { key: 'k' }, { ok: true, data: { value: { a: 1 } } }, { a: 1 }, ['storage']],
    ['storage.get', { key: 'k' }, { ok: true, data: {} }, null, ['storage']],
    ['storage.set', { key: 'k', value: 1 }, { ok: true, data: { saved: true } }, true, ['storage']],
    ['storage.remove', { key: 'k' }, { ok: true, data: { removed: true } }, true, ['storage']],
    ['contacts.list', undefined, { ok: true, data: { contacts: [{ id: 1, name: 'A', number: '555' }] } }, [{ id: 1, name: 'A', number: '555' }], ['contacts.read']],
    ['contacts.list', undefined, { ok: true, data: {} }, [], ['contacts.read']],
    ['contacts.save', { name: 'A', number: '555' }, { ok: true, data: { id: 7 } }, { id: 7, name: 'A', number: '555' }, ['contacts.write']],
    ['notify', { title: 'T', body: 'B' }, { ok: true, data: { sent: true } }, true, ['notify']],
    ['callback', { name: 'inc', payload: 1 }, { ok: true, data: { count: 2 } }, { count: 2 }, []],
    ['haptic', {}, { ok: true, data: null }, true, []],
];
for (const [type, payload, reply, expected, permissions] of shapeCases) {
    test(`response shape: ${type} -> ${JSON.stringify(expected)}`, async () => {
        const t = setup({ reply, permissions });
        await t.send(env(type, payload));
        assert.deepEqual(t.posted[0], { kora: 'phone', v: 1, id: 'r1', type: 'response', ok: true, payload: expected });
    });
}

test('response shape: getContext returns the init payload', async () => {
    const t = setup();
    await t.send(env('getContext'));
    assert.equal(t.posted[0].payload.appId, 'demo');
    assert.equal(t.posted.filter(m => m.type === 'init').length, 0);
});

// ---- end to end: REAL built SDK client <-> REAL host router with fake windows ----
test('end to end: built SDK client against the host router', async () => {
    const sdkDist = path.join(root, 'sdk', 'dist', 'index.js');
    assert.ok(fs.existsSync(sdkDist), 'run `cd sdk && npm run build` first');
    const { createPhoneClient } = await import(require('node:url').pathToFileURL(sdkDist).href);
    const HOST = 'https://cfx-nui-kora_phone';
    const listeners = new Set();
    const props = new Map();
    const store = new Map();
    const routes = [];
    const iframeWin = {};
    const hostWin = {};
    let theme = { vars: { '--primary': '84 100% 50%', '--background': '0 0% 4%' }, scheme: 'dark' };
    const deliver = data => listeners.forEach(l => l({ data, origin: HOST, source: hostWin }));
    const transport = {
        request: async (route, payload) => {
            routes.push(route);
            switch (route) {
                case 'apps:storage:get': return { ok: true, data: { value: store.has(payload.key) ? store.get(payload.key) : null } };
                case 'apps:storage:set': store.set(payload.key, payload.value); return { ok: true, data: { saved: true } };
                case 'apps:storage:remove': store.delete(payload.key); return { ok: true, data: { removed: true } };
                case 'apps:call': return { ok: true, data: { echoed: payload.payload } };
                case 'apps:contacts:list': return { ok: true, data: { contacts: [{ id: 1, name: 'Ann', number: '555-1' }] } };
                case 'apps:notify': return { ok: true, data: { sent: true } };
                default: return { ok: false, error: { code: 'NOT_FOUND', message: route } };
            }
        },
    };
    const router = sdk.createRouter({
        appId: 'demo', resource: 'demo_res', permissions: ['storage', 'notify', 'contacts.read'], transport,
        handset: 'flip', locale: 'en-GB', getTheme: () => theme, post: m => queueMicrotask(() => deliver(m)),
    });
    const client = createPhoneClient({
        hostOrigin: HOST,
        window: {
            parent: hostWin,
            addEventListener: (_t, l) => listeners.add(l),
            removeEventListener: (_t, l) => listeners.delete(l),
            document: { documentElement: { style: { setProperty: (k, v) => props.set(k, v) } } },
        },
    });
    hostWin.postMessage = (message, targetOrigin) => {
        assert.equal(targetOrigin, HOST);
        void router.handle({ source: iframeWin, origin: 'https://cfx-nui-demo_res', data: message }, iframeWin);
    };

    const init = await client.ready();
    assert.equal(init.appId, 'demo');
    assert.equal(init.handset, 'flip');
    assert.equal(props.get('--primary'), '84 100% 50%');
    assert.equal(props.get('color-scheme'), 'dark');

    const seen = [];
    client.onTheme(t => seen.push(t.scheme));
    theme = { vars: { '--primary': '10 90% 50%', '--background': '0 0% 98%' }, scheme: 'light' };
    deliver({ kora: 'phone', v: 1, type: 'theme', payload: theme });
    assert.deepEqual(seen, ['light']);
    assert.equal(props.get('--primary'), '10 90% 50%');

    assert.equal(await client.storage.get('k'), null);
    await client.storage.set('k', { n: 1 });
    assert.deepEqual(await client.storage.get('k'), { n: 1 });
    await client.storage.remove('k');
    assert.equal(await client.storage.get('k'), null);
    assert.deepEqual(await client.callback('inc', { step: 1 }), { echoed: { step: 1 } });
    assert.deepEqual(await client.contacts.list(), [{ id: 1, name: 'Ann', number: '555-1' }]);
    await client.notify('Hi', 'there');
    await client.haptic();
    assert.equal((await client.getContext()).appId, 'demo');
    await assert.rejects(client.contacts.save({ name: 'x', number: '123' }), e => e.code === 'PERMISSION_DENIED');
    assert.ok(routes.includes('apps:notify') && routes.includes('apps:call'));
    client.destroy();
});

(async () => {
    for (const [name, fn] of queue) {
        try { await fn(); console.log(`ok - ${name}`); } catch (e) { failures++; console.error(`not ok - ${name}\n${e.stack}`); }
    }
    fs.rmSync(out, { recursive: true, force: true });
    console.log(`${queue.length - failures}/${queue.length} passed`);
    process.exit(failures ? 1 : 0);
})();
