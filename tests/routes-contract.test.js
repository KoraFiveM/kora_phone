// Run from the resource root: node tests/routes-contract.test.js
// shared/routes.json is the single source of truth for NUI routes. Every entry must name a server callback that
// is really registered, use a known rate key, and carry a valid app gate; nothing may be listed twice.
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const routes = JSON.parse(fs.readFileSync(path.join(root, 'shared/routes.json'), 'utf8'));
const APPS = new Set([null, 'social', 'classifieds', 'moderation']);

function walk(dir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) return walk(full);
        return entry.name.endsWith('.lua') ? [full] : [];
    });
}
const serverSource = walk(path.join(root, 'server')).map((file) => fs.readFileSync(file, 'utf8')).join('\n');

const nuiNames = new Set();
const serverNames = new Set();
for (const route of routes) {
    assert.deepStrictEqual(Object.keys(route).sort(), ['app', 'nui', 'rate', 'server'], `shape of ${route.nui}`);
    assert(APPS.has(route.app), `${route.nui}: unknown app gate ${route.app}`);
    assert(!nuiNames.has(route.nui), `duplicate NUI route ${route.nui}`);
    nuiNames.add(route.nui);
    assert(route.server.startsWith('kora_phone:server:'), `${route.nui}: server name`);
    const short = route.server.replace('kora_phone:server:', '');
    const registered = serverSource.includes(`'${short}'`) || serverSource.includes(`'${route.server}'`)
        || serverSource.includes(`"${route.server}"`);
    assert(registered, `${route.nui}: no server callback registers ${route.server}`);
    if (short.startsWith('social:')) assert.strictEqual(route.app, 'social');
    if (short.startsWith('market:')) assert.strictEqual(route.app, 'classifieds');
    if (short.startsWith('moderation:')) assert.strictEqual(route.app, 'moderation');
    serverNames.add(route.server);
}
assert(routes.length >= 30, 'routes.json lost entries');

// SDK and system mail routes: fixed rate bucket, no app gate, server name mirrors the NUI name.
const sdkRoutes = ['list', 'install', 'uninstall', 'call', 'storage:get', 'storage:list', 'storage:set', 'storage:remove',
    'contacts:list', 'contacts:save', 'notify'].map((name) => `apps:${name}`);
const systemMail = { list: 'read', activity: 'read', read: 'mutation', delete: 'mutation', accept: 'mutation' };
const byNui = new Map(routes.map((route) => [route.nui, route]));
for (const nui of sdkRoutes) {
    const route = byNui.get(nui);
    assert(route, `missing SDK route ${nui}`);
    assert.strictEqual(route.rate, 'sdk');
    assert.strictEqual(route.server, `kora_phone:server:${nui}`);
    assert.strictEqual(route.app, null);
}
// System mail is served by the Mail folder app (apps/mail), not by the route table.
for (const name of Object.keys(systemMail)) assert(!byNui.has(`mail:system:${name}`), `mail:system:${name} must not be a route`);
assert(!routes.some((route) => /legacy/i.test(route.nui + route.server)), 'legacy mail routes must stay removed');

// Every apps:* route is served by server/sdk/routes.lua and must be listed in the gateway's SDK binding loop
// (a route in routes.json that nothing binds fails at runtime with "Request failed").
const gateway = fs.readFileSync(path.join(root, 'server/callbacks.lua'), 'utf8');
const sdkRoutesSource = fs.readFileSync(path.join(root, 'server/sdk/routes.lua'), 'utf8');
for (const route of routes.filter((entry) => entry.nui.startsWith('apps:') && entry.nui !== 'apps:client' && entry.nui !== 'apps:html')) {
    assert(gateway.includes(`'${route.nui}'`), `${route.nui} is in routes.json but the gateway never binds it`);
    assert(sdkRoutesSource.includes(`KoraPhone.SDK.routes['${route.nui}']`), `${route.nui} has no handler in server/sdk/routes.lua`);
}

// Every rate key used by a route must exist in Config.Server.RateLimits.
const serverConfig = fs.readFileSync(path.join(root, 'config/server.lua'), 'utf8');
for (const rate of new Set(routes.map((route) => route.rate))) {
    const key = rate.includes('.') ? `['${rate}']` : rate;
    assert(serverConfig.includes(`${key} = bucket(`), `no rate limit bucket for ${rate}`);
}
// No hand-written NUI/callback registration outside the gateway.
assert(!/registerCallback\(/.test(serverSource.replace(/function KoraPhone\.registerCallback\([^)]*\)/, '')),
    'bind handlers with KoraPhone.Routes.handle, not registerCallback');
console.log(`routes-contract: ${routes.length} routes ok`);
