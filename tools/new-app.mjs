#!/usr/bin/env node
// Scaffolds a folder app:  node tools/new-app.mjs <id> ["Display name"]
import { cpSync, existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function files(dir) {
    return readdirSync(dir).flatMap(name => statSync(join(dir, name)).isDirectory() ? files(join(dir, name)) : [join(dir, name)]);
}

/** Copies tools/template into `<appsDir>/<id>` with the id and name filled in. Returns the new folder. */
export function scaffold(id, name, appsDir = join(ROOT, 'apps')) {
    if (!/^[a-z0-9][a-z0-9_-]{1,31}$/.test(id)) throw new Error('id must be 2-32 characters of a-z, 0-9, _ and -');
    const target = join(appsDir, id);
    if (existsSync(target)) throw new Error(`apps/${id} already exists`);
    cpSync(join(ROOT, 'tools', 'template'), target, { recursive: true });
    const title = name || id.replace(/[-_]+/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    for (const file of files(target)) {
        writeFileSync(file, readFileSync(file, 'utf8').replaceAll('__ID__', id).replaceAll('__NAME__', title));
    }
    return target;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const [id, name] = process.argv.slice(2);
    if (!id) { console.error('usage: node tools/new-app.mjs <id> ["Display name"]'); process.exit(2); }
    try {
        console.log(`created ${scaffold(id, name)}\nrestart kora_phone (or run: ensure kora_phone) to load it`);
    } catch (error) { console.error(error.message); process.exit(1); }
}
