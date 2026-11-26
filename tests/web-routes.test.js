// Run from the resource root: node tests/web-routes.test.js
// Every NUI route the web layer calls must exist in shared/routes.json, and every route in routes.json must be
// reachable from the web (api layer, SDK router, or a screen that posts to it directly).
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const routes = JSON.parse(fs.readFileSync(path.join(root, 'shared/routes.json'), 'utf8')).map((route) => route.nui);

// Handled by the phone's client script only (never a server callback), so they are not in routes.json.
const CLIENT_ONLY = new Set(['phone:ready', 'phone:close', 'camera:close', 'camera:open', 'camera:capture',
    'customList', 'customLifecycle', 'apps:client', 'apps:html', 'camera:coverStart', 'camera:facing', 'camera:recording', 'camera:zoom',
    'location:mine', 'notify', 'quiet', 'waypoint', 'weather:get',
    // UI-side aliases for client callbacks (see routeAliases in web/src/api/transport.ts).
    'close', 'captureDone']);

// Server routes the web has no action for yet (the bootstrap already carries contacts; follow/profile/listing-edit
// have no screen). Listed so a NEW unused route fails this test instead of rotting silently.
const SERVER_ONLY = new Set(['contacts:list']);

function walk(dir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) return entry.name === 'node_modules' ? [] : walk(full);
        return /\.(ts|tsx)$/.test(entry.name) ? [full] : [];
    });
}

const used = new Set();
const call = /\b(?:server|nui|call|request)\s*(?:<[^>()]*>)?\(\s*['"]([A-Za-z]+(?::[A-Za-z]+)+|[A-Za-z]+)['"]/g;
const quoted = /['"]([a-z]+(?::[A-Za-z]+)+)['"]/g;
for (const file of walk(path.join(root, 'web/src'))) {
    if (file.endsWith(path.join('src', 'mock.ts'))) continue;
    const text = fs.readFileSync(file, 'utf8');
    const inApi = file.includes(`${path.sep}api${path.sep}`) || file.includes(`${path.sep}sdk${path.sep}`);
    for (const match of text.matchAll(call)) used.add(match[1]);
    // Screens may also name a route in a literal passed to a helper; only route-shaped literals in the API/SDK layers count.
    if (inApi) for (const match of text.matchAll(quoted)) if (routes.includes(match[1])) used.add(match[1]);
}

const unknown = [...used].filter((name) => !routes.includes(name) && !CLIENT_ONLY.has(name)).sort();
assert.deepStrictEqual(unknown, [], `web calls routes missing from shared/routes.json: ${unknown.join(', ')}`);

const unused = routes.filter((name) => !used.has(name) && !SERVER_ONLY.has(name)).sort();
assert.deepStrictEqual(unused, [], `routes.json entries the web never calls: ${unused.join(', ')}`);

for (const name of SERVER_ONLY) assert(routes.includes(name) && !used.has(name), `${name} is in SERVER_ONLY but is wired or gone: remove it from the list`);
for (const gone of routes.filter((name) => name.startsWith('legacy:'))) assert.fail(`legacy route ${gone} must be removed`);
assert(routes.includes('apps:list') && routes.includes('apps:storage:list'), 'SDK routes are present');
console.log(`PASS web-routes: ${used.size} web routes checked against ${routes.length} in routes.json`);
