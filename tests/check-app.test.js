// node tests/check-app.test.js: the app linter, the scaffold and the apps shipped in apps/.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const root = path.resolve(__dirname, '..');
const load = name => import(pathToFileURL(path.join(root, 'tools', name)).href);

(async () => {
    const { checkApp, checkAll } = await load('check-app.mjs');
    const { scaffold } = await load('new-app.mjs');
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'kora-apps-'));
    const errorsOf = dir => checkApp(dir).filter(f => f.level === 'error');
    const rulesOf = dir => errorsOf(dir).map(f => f.rule);
    let checks = 0;
    const ok = (condition, label) => { assert.ok(condition, label); checks += 1; };

    // The scaffold is the style guide's reference app: it must be clean.
    const demo = scaffold('demo', 'Demo', tmp);
    assert.deepEqual(errorsOf(demo), [], 'scaffold has errors'); checks += 1;
    ok(!checkApp(demo).some(f => f.rule === 'states'), 'scaffold shows loading/empty/error states');

    // Every rule fires on the thing it is named for.
    const mutate = (file, fn) => fs.writeFileSync(path.join(demo, file), fn(fs.readFileSync(path.join(demo, file), 'utf8')));
    const css = 'ui/app.css';
    const cases = [
        ['colour-hex', css, '.a { color: #fff; }'],
        ['colour-rgb', css, '.a { background: rgba(0,0,0,.5); }'],
        ['colour-hsl', css, '.a { color: hsl(120 50% 50%); }'],
        ['colour-name', css, '.a { border: 1px solid red; }'],
        ['font-family', css, '.a { font-family: Arial, sans-serif; }'],
        ['important', css, '.a { display: none !important; }'],
        ['radius-px', css, '.a { border-radius: 12px; }'],
        ['external-url', 'ui/app.js', "fetch('https://example.com/x');"],
    ];
    for (const [rule, file, add] of cases) {
        const original = fs.readFileSync(path.join(demo, file), 'utf8');
        mutate(file, text => `${text}\n${add}\n`);
        ok(rulesOf(demo).includes(rule), `${rule} was not flagged`);
        fs.writeFileSync(path.join(demo, file), original);
    }
    // Tokens and inherit stay legal.
    mutate(css, text => `${text}\n.b { color: hsl(var(--primary)); font-family: inherit; border-radius: var(--kp-radius); }\n`);
    assert.deepEqual(errorsOf(demo), [], 'token usage must pass'); checks += 1;

    // Inline styles and <style> blocks are scanned too.
    mutate('ui/index.html', text => text.replace('<main', '<main style="color: #123456"'));
    ok(rulesOf(demo).includes('colour-hex'), 'inline style colour was not flagged');

    // Structure.
    const broken = scaffold('broken', 'Broken', tmp);
    fs.writeFileSync(path.join(broken, 'app.lua'), "Phone.app('other', { name = 'X', icon = 'star' })");
    ok(rulesOf(broken).includes('app-id'), 'folder/id mismatch not flagged');
    fs.rmSync(path.join(broken, 'ui', 'index.html'));
    ok(rulesOf(broken).includes('ui-entry'), 'missing entry not flagged');
    assert.throws(() => scaffold('Bad Id', 'x', tmp)); checks += 1;
    assert.throws(() => scaffold('demo', 'x', tmp), /already exists/); checks += 1;

    // The manifest must serve everything a folder app loads: its icon, its pages, and the runtime they import.
    const manifest = fs.readFileSync(path.join(root, 'fxmanifest.lua'), 'utf8');
    for (const pattern of ['apps/*/icon.svg', 'apps/*/ui/*', 'apps/*/ui/**/*', 'sdk/runtime/*', 'web/dist/lb-shim.js', 'apps/*/app.lua', 'apps/*/server.lua', 'apps/*/client.lua'])
        ok(manifest.includes(`'${pattern}'`), `fxmanifest.lua must list ${pattern}`);
    for (const id of fs.readdirSync(path.join(root, 'apps')))
        ok(fs.existsSync(path.join(root, 'apps', id, 'icon.svg')), `apps/${id} ships icon.svg`);
    for (const file of fs.readdirSync(path.join(root, 'sdk/runtime')))
        ok(!/^kora-ui\.css$/.test(file) || fs.readFileSync(path.join(root, 'sdk/runtime', file), 'utf8').includes('kora-tokens.css'), 'kora-ui.css imports the split sheets');

    // The apps that ship with the phone follow the guide.
    const shipped = checkAll().filter(f => f.level === 'error');
    assert.deepEqual(shipped, [], `shipped apps have style errors:\n${shipped.map(f => `${f.file}:${f.line} ${f.rule}`).join('\n')}`); checks += 1;

    fs.rmSync(tmp, { recursive: true, force: true });
    console.log(`PASS check-app: ${checks} checks`);
})().catch(error => { console.error(error); process.exit(1); });
