import test from 'node:test';
import assert from 'node:assert/strict';
import { createPhoneClient, PhoneError } from '../dist/index.js';

const HOST = 'https://cfx-nui-kora_phone';

function harness(opts = {}) {
    const listeners = new Set();
    const sent = [];
    const props = new Map();
    const parent = { postMessage: (m, o) => sent.push({ m, o }) };
    const win = {
        parent,
        addEventListener: (_t, l) => listeners.add(l),
        removeEventListener: (_t, l) => listeners.delete(l),
        document: { documentElement: { style: { setProperty: (k, v) => props.set(k, v) } } },
    };
    let n = 0;
    const client = createPhoneClient({ window: win, idFactory: () => `id${++n}`, ...opts });
    const post = (data, { origin = HOST, source = parent } = {}) =>
        listeners.forEach((l) => l({ data, origin, source }));
    const env = (o) => ({ kora: 'phone', v: 1, ...o });
    const init = {
        appId: 'demo', handset: 'standard', locale: 'en', permissions: ['storage'],
        theme: { vars: { '--primary': '#123456', bg: '#000' }, scheme: 'dark' },
    };
    return { client, sent, props, post, env, init, listeners, parent };
}
const tick = () => new Promise((r) => setImmediate(r));

test('handshake awaits init', async () => {
    const h = harness();
    const p = h.client.ready();
    assert.equal(h.sent[0].m.type, 'ready');
    assert.equal(h.sent[0].o, HOST);
    h.post(h.env({ id: 'id1', type: 'response', ok: true }));
    h.post(h.env({ type: 'init', payload: h.init }));
    const got = await p;
    assert.equal(got.appId, 'demo');
    assert.equal(h.client.init.appId, 'demo');
});

test('init before ready() is retained', async () => {
    const h = harness();
    h.post(h.env({ type: 'init', payload: h.init }));
    const p = h.client.ready();
    h.post(h.env({ id: 'id1', type: 'response', ok: true }));
    assert.equal((await p).handset, 'standard');
});

test('request/response resolves and rejects with typed errors', async () => {
    const h = harness();
    const a = h.client.callback('ping', { x: 1 });
    assert.deepEqual(h.sent[0].m, { kora: 'phone', v: 1, id: 'id1', type: 'callback', payload: { name: 'ping', payload: { x: 1 } } });
    h.post(h.env({ id: 'id1', type: 'response', ok: true, payload: { pong: true } }));
    assert.deepEqual(await a, { pong: true });
    const b = h.client.callback('bad');
    h.post(h.env({ id: 'id2', type: 'response', ok: false, error: { code: 'NO_PERM', message: 'nope' } }));
    await assert.rejects(b, (e) => e instanceof PhoneError && e.code === 'NO_PERM' && e.message === 'nope');
});

test('timeout rejects with TIMEOUT', async () => {
    const h = harness({ timeoutMs: 10 });
    await assert.rejects(h.client.close(), (e) => e instanceof PhoneError && e.code === 'TIMEOUT');
});

test('foreign origin and source are rejected', async () => {
    const h = harness();
    const p = h.client.callback('x');
    h.post(h.env({ id: 'id1', type: 'response', ok: true, payload: 'evil' }), { origin: 'https://evil.example' });
    h.post(h.env({ id: 'id1', type: 'response', ok: true, payload: 'evil' }), { source: {} });
    h.post(h.env({ type: 'init', payload: h.init }), { origin: 'https://evil.example' });
    h.post(h.env({ type: 'theme', payload: { vars: { '--primary': 'red' }, scheme: 'light' } }), { source: {} });
    assert.equal(h.client.init, null);
    assert.equal(h.props.size, 0);
    h.post(h.env({ id: 'id1', type: 'response', ok: true, payload: 'good' }));
    assert.equal(await p, 'good');
});

test('malformed envelopes ignored', () => {
    const h = harness();
    h.post({ type: 'init', payload: h.init });
    h.post(h.env({ v: 2, type: 'init', payload: h.init }));
    h.post('str');
    assert.equal(h.client.init, null);
});

test('theme applied on init and theme push', async () => {
    const h = harness();
    const seen = [];
    h.client.onTheme((t) => seen.push(t.scheme));
    h.post(h.env({ type: 'init', payload: h.init }));
    assert.equal(h.props.get('--primary'), '#123456');
    assert.equal(h.props.get('--bg'), '#000');
    assert.equal(h.props.get('color-scheme'), 'dark');
    h.post(h.env({ type: 'theme', payload: { vars: { '--primary': '#fff' }, scheme: 'light' } }));
    assert.equal(h.props.get('--primary'), '#fff');
    assert.equal(h.client.theme.scheme, 'light');
    assert.deepEqual(seen, ['light']);
});

test('event and visibility delivery, unsubscribe', () => {
    const h = harness();
    const got = [];
    const vis = [];
    const off = h.client.on('tick', (d) => got.push(d));
    h.client.onVisibility((v) => vis.push(v));
    h.post(h.env({ type: 'event', payload: { name: 'tick', data: 1 } }));
    h.post(h.env({ type: 'event', payload: { name: 'other', data: 9 } }));
    h.post(h.env({ type: 'visibility', payload: { visible: false } }));
    off();
    h.post(h.env({ type: 'event', payload: { name: 'tick', data: 2 } }));
    assert.deepEqual(got, [1]);
    assert.deepEqual(vis, [false]);
});

test('storage, contacts, notify, setTitle send correct messages', async () => {
    const h = harness();
    const reply = async (payload) => {
        await tick();
        const last = h.sent[h.sent.length - 1].m;
        h.post(h.env({ id: last.id, type: 'response', ok: true, payload }));
    };
    let p = h.client.storage.set('k', { a: 1 }); await reply(); await p;
    assert.deepEqual(h.sent.at(-1).m.payload, { key: 'k', value: { a: 1 } });
    assert.equal(h.sent.at(-1).m.type, 'storage.set');
    p = h.client.storage.get('k'); await reply({ a: 1 });
    assert.deepEqual(await p, { a: 1 });
    p = h.client.storage.get('missing'); await reply(undefined);
    assert.equal(await p, null);
    p = h.client.storage.remove('k'); await reply(); await p;
    assert.equal(h.sent.at(-1).m.type, 'storage.remove');
    p = h.client.contacts.list(); await reply([{ name: 'A', number: '1' }]);
    assert.equal((await p).length, 1);
    p = h.client.contacts.save({ name: 'B', number: '2' }); await reply({ id: 5, name: 'B', number: '2' });
    assert.equal((await p).id, 5);
    p = h.client.notify('t', 'b'); await reply(); await p;
    assert.deepEqual(h.sent.at(-1).m.payload, { title: 't', body: 'b' });
    p = h.client.setTitle('T'); await reply(); await p;
    assert.equal(h.sent.at(-1).m.type, 'setTitle');
});

test('destroy rejects pending and detaches listener', async () => {
    const h = harness();
    const p = h.client.close();
    h.client.destroy();
    await assert.rejects(p, (e) => e.code === 'DESTROYED');
    assert.equal(h.listeners.size, 0);
    await assert.rejects(h.client.close(), (e) => e.code === 'DESTROYED');
});

test('haptic and getContext', async () => {
    const h = harness();
    const hap = h.client.haptic();
    assert.equal(h.sent[0].m.type, 'haptic');
    h.post(h.env({ id: 'id1', type: 'response', ok: true, payload: true }));
    await hap;
    const ctx = h.client.getContext();
    assert.equal(h.sent[1].m.type, 'getContext');
    h.post(h.env({ id: 'id2', type: 'response', ok: true, payload: h.init }));
    assert.equal((await ctx).appId, 'demo');
    assert.equal(h.client.init.appId, 'demo');
});
