#!/usr/bin/env node
"use strict";

// The startup migration runner only knows the files listed in fxmanifest.lua. A new .sql file that is not
// listed there would never be applied, so this fails until it is.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const manifest = fs.readFileSync(path.join(root, "fxmanifest.lua"), "utf8");
const listed = [...manifest.matchAll(/^migration\s+'([^']+)'/gm)].map((match) => match[1]);
const onDisk = fs.readdirSync(path.join(root, "migrations")).filter((file) => file.endsWith(".sql")).sort().map((file) => `migrations/${file}`);

assert.deepEqual(listed, onDisk, "every migrations/*.sql file must be listed in fxmanifest.lua, in filename order");
for (const file of onDisk) assert.match(path.basename(file), /^\d{3}_[a-z0-9_]+\.sql$/, `${file} must be named NNN_name.sql`);
assert.equal(new Set(onDisk.map((file) => path.basename(file).slice(0, 3))).size, onDisk.length, "migration numbers must be unique");

const main = fs.readFileSync(path.join(root, "server/main.lua"), "utf8");
assert.match(main, /SteviePhone\.Migrations\.run\(\)/, "the resource must run migrations at start");
assert.match(main, /Database setup failed, stopping resource/, "a failed migration must stop the resource, not run on a half-built schema");
assert.match(fs.readFileSync(path.join(root, "config/server.lua"), "utf8"), /AutoMigrate = true/, "AutoMigrate must default on");

console.log(`PASS migrations-manifest: ${listed.length} migrations listed in order and run at start`);
