#!/usr/bin/env node
// Style and structure check for folder apps. docs/style-guide.md is the human version of these rules.
//
//   node tools/check-app.mjs                 check every apps/<id>
//   node tools/check-app.mjs apps/notes      check one app
//
// Exit code 1 when any rule fails. Warnings never fail the run.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const NAMED_COLOURS = 'aliceblue|antiquewhite|aqua|black|blue|brown|crimson|cyan|fuchsia|gold|gray|grey|green|indigo|lime|magenta|maroon|navy|olive|orange|pink|purple|red|salmon|silver|teal|violet|white|yellow';
const COLOUR_PROPERTY = '(?:color|background(?:-color)?|border(?:-[a-z]+)?(?:-color)?|fill|stroke|outline(?:-color)?|box-shadow|text-shadow)';

/** Each rule: id, what it flags, and the message that tells the developer what to do instead. */
const CSS_RULES = [
    { id: 'colour-hex', re: /#[0-9a-fA-F]{3,8}\b/, message: 'hard-coded hex colour: use a kit class or var(--kp-*) / hsl(var(--token))' },
    { id: 'colour-rgb', re: /\brgba?\(/, message: 'hard-coded rgb() colour: use a kora_theme token' },
    { id: 'colour-hsl', re: /\bhsla?\(\s*\d/, message: 'hard-coded hsl() colour: wrap a token instead, hsl(var(--primary))' },
    { id: 'colour-name', re: new RegExp(`${COLOUR_PROPERTY}\\s*:[^;}]*\\b(?:${NAMED_COLOURS})\\b`, 'i'), message: 'named colour: use a kora_theme token' },
    { id: 'font-family', re: /font-family\s*:\s*(?!\s|inherit|var\()/i, message: 'font-family: the theme font is already applied, use var(--kp-font) or inherit' },
    { id: 'important', re: /!important/, message: '!important: fix the selector instead' },
    { id: 'radius-px', re: /border-radius\s*:\s*[\d.]+\s*(?:px|rem|em)/i, message: 'fixed border-radius: use var(--kp-radius), var(--kp-radius-sm) or var(--kp-radius-lg)' },
];

const ANY_RULES = [
    { id: 'external-url', re: /https?:\/\/(?!cfx-nui-|www\.w3\.org\/)/i, message: 'external URL: an app may only load its own files and the phone runtime (list a player host in app.lua embeds)' },
];

/** The hosts an app declares in app.lua `embeds = { 'host', ... }`. */
function declaredEmbeds(lua) {
    const block = /\bembeds\s*=\s*\{([^}]*)\}/.exec(lua);
    return block ? [...block[1].matchAll(/['"]([^'"]+)['"]/g)].map(match => match[1]) : [];
}

/** @returns {{ rule: string, line: number, message: string, level: 'error' | 'warn' }[]} */
function scan(text, rules, level = 'error') {
    const findings = [];
    text.split('\n').forEach((line, index) => {
        // Strip comments so a "// no #fff here" note does not trip a rule.
        const code = line.replace(/\/\*.*?\*\//g, '').replace(/^\s*\/\/.*$/, '').replace(/^\s*<!--.*?-->\s*$/, '');
        for (const rule of rules) if (rule.re.test(code)) findings.push({ rule: rule.id, line: index + 1, message: rule.message, level });
    });
    return findings;
}

/** CSS found in a file: the whole file for .css, <style> blocks and style="" attributes for .html. */
function cssOf(file, text) {
    if (file.endsWith('.css')) return [{ offset: 0, css: text }];
    const blocks = [];
    for (const match of text.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)) blocks.push({ offset: text.slice(0, match.index).split('\n').length - 1, css: match[1] });
    for (const match of text.matchAll(/\sstyle="([^"]*)"/gi)) blocks.push({ offset: text.slice(0, match.index).split('\n').length - 1, css: match[1] });
    return blocks;
}

function walk(dir) {
    const files = [];
    for (const name of readdirSync(dir)) {
        if (name === 'node_modules') continue;
        const path = join(dir, name);
        if (statSync(path).isDirectory()) files.push(...walk(path)); else files.push(path);
    }
    return files;
}

/** Checks one app folder. Returns findings tagged with a path relative to the resource root. */
export function checkApp(appDir) {
    const id = basename(appDir);
    const findings = [];
    const add = (file, finding) => findings.push({ ...finding, file: relative(ROOT, file) || file });

    const definition = join(appDir, 'app.lua');
    let embeds = [];
    if (existsSync(definition)) embeds = declaredEmbeds(readFileSync(definition, 'utf8'));
    if (!existsSync(definition)) {
        add(appDir, { rule: 'app-lua', line: 0, level: 'error', message: 'missing app.lua (Phone.app definition)' });
    } else {
        const lua = readFileSync(definition, 'utf8');
        const defined = /Phone\.app\(\s*['"]([^'"]+)['"]\s*,/.exec(lua);
        if (!defined) add(definition, { rule: 'app-lua', line: 1, level: 'error', message: "app.lua must call Phone.app('<id>', { ... })" });
        else if (defined[1] !== id) add(definition, { rule: 'app-id', line: 1, level: 'error', message: `app id "${defined[1]}" must match the folder name "${id}"` });
        for (const field of ['name', 'icon']) {
            if (!new RegExp(`\\b${field}\\s*=`).test(lua)) add(definition, { rule: 'app-field', line: 1, level: 'error', message: `app.lua must set ${field}` });
        }
        const ui = /\bui\s*=\s*['"]([^'"]+)['"]/.exec(lua);
        const entry = join(appDir, ui ? ui[1] : 'ui/index.html');
        if (!existsSync(entry)) add(definition, { rule: 'ui-entry', line: 1, level: 'error', message: `UI entry ${relative(appDir, entry)} does not exist` });
    }

    const uiDir = join(appDir, 'ui');
    if (!existsSync(uiDir)) return findings;
    let usesStates = false;
    for (const file of walk(uiDir)) {
        if (/[\\/]dist[\\/]/.test(file) && /\.(map)$/.test(file)) continue;
        if (!/\.(html?|css|js|mjs)$/.test(file)) continue;
        const text = readFileSync(file, 'utf8');
        // A URL on a declared embed host is allowed; a `https:` source in the page's own CSP meta is not a URL to load.
        const allowed = embeds.length ? text.replace(new RegExp(`https?://(?:${embeds.map(host => host.replace(/\./g, '\\.')).join('|')})(?![\\w.-])`, 'gi'), '') : text;
        for (const finding of scan(allowed, ANY_RULES)) add(file, finding);
        for (const { offset, css } of cssOf(file, text)) {
            for (const finding of scan(css, CSS_RULES)) add(file, { ...finding, line: finding.line + offset });
        }
        if (/\bstates\.(loading|empty|error)\b|\bkp-state\b|\bload\(/.test(text)) usesStates = true;
        if (/[\\/]index\.html?$/.test(file) && file === join(uiDir, 'index.html')) {
            if (!/\/sdk\/runtime\/kora-ui\.css/.test(text)) add(file, { rule: 'kit-css', line: 1, level: 'error', message: 'index.html must link /sdk/runtime/kora-ui.css' });
            if (embeds.length) {
                const csp = /<meta[^>]+http-equiv=["']Content-Security-Policy["'][^>]*content=["']([^"']*)["']/i.exec(text);
                const frames = csp ? (/frame-src([^;]*)/.exec(csp[1]) || [])[1] || '' : '';
                const missing = embeds.filter(host => !frames.includes(host));
                if (!csp || missing.length) add(file, { rule: 'embed-csp', line: 1, level: 'error', message: `index.html needs a Content-Security-Policy meta whose frame-src lists ${missing.length ? missing.join(', ') : embeds.join(', ')}` });
            }
            if (!/<meta[^>]+name=["']viewport["']/.test(text)) add(file, { rule: 'viewport', line: 1, level: 'warn', message: 'add <meta name="viewport" content="width=device-width, initial-scale=1">' });
        }
    }
    if (!usesStates) add(uiDir, { rule: 'states', line: 0, level: 'warn', message: 'no loading, empty or error state found: show states.* from the kit instead of a blank screen' });
    return findings;
}

export function checkAll(appsDir = join(ROOT, 'apps')) {
    if (!existsSync(appsDir)) return [];
    return readdirSync(appsDir)
        .filter(name => !name.startsWith('.') && !name.startsWith('_') && statSync(join(appsDir, name)).isDirectory())
        .flatMap(name => checkApp(join(appsDir, name)));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const targets = process.argv.slice(2);
    const findings = targets.length ? targets.flatMap(target => checkApp(resolve(target))) : checkAll();
    for (const f of findings) console.log(`${f.level === 'error' ? 'ERROR' : 'warn '} ${f.file}${f.line ? `:${f.line}` : ''} [${f.rule}] ${f.message}`);
    const errors = findings.filter(f => f.level === 'error').length;
    const apps = targets.length || (existsSync(join(ROOT, 'apps')) ? readdirSync(join(ROOT, 'apps')).filter(n => !n.startsWith('_') && !n.startsWith('.')).length : 0);
    console.log(`check-app: ${apps} app(s), ${errors} error(s), ${findings.length - errors} warning(s)`);
    process.exit(errors ? 1 : 0);
}
