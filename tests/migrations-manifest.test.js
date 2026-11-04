#!/usr/bin/env node
"use strict";

// Tables are declared in server/schema.lua and created by Kora.sql.ensureTables at start. This fails if the
// schema is not loaded before the runner, a table is dropped from it, or the old .sql files come back.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const manifest = fs.readFileSync(path.join(root, "fxmanifest.lua"), "utf8");
const schema = fs.readFileSync(path.join(root, "server/schema.lua"), "utf8");

const tables = [...schema.matchAll(/^\s{8}name = '(phone_[a-z_]+)'/gm)].map((match) => match[1]);
assert.equal(tables.length, 33, "schema must declare all 33 phone tables");
assert.equal(new Set(tables).size, tables.length, "a table is declared twice");
for (const table of ["phone_devices", "phone_messages", "phone_calls", "phone_economy_audit", "phone_sims", "phone_handsets", "phone_legacy_mail", "phone_legacy_transactions"]) {
  assert.ok(tables.includes(table), `schema must declare ${table}`);
}
assert.match(schema, /^KoraPhoneSchema = \{/m, "schema must expose the KoraPhoneSchema global");
assert.match(schema, /chk_phone_economy_positive_amount/, "the positive amount check must stay declared");
assert.match(schema, /generated = \{ expr = /, "phone_sims.active_number must stay a generated column");
assert.match(schema, /name = 'message_type'[^\n]*'video'[^\n]*modify = true/, "message_type must be widened with modify");

assert.ok(manifest.indexOf("'server/schema.lua'") !== -1, "fxmanifest must load server/schema.lua");
assert.ok(manifest.indexOf("'server/schema.lua'") < manifest.indexOf("'server/integrations/*.lua'"), "schema must load before the runner");
assert.doesNotMatch(manifest, /^migration\s+'/m, "no .sql migrations may be listed");
assert.equal(fs.existsSync(path.join(root, "migrations")), false, "the migrations/ .sql files are replaced by the schema");

const main = fs.readFileSync(path.join(root, "server/main.lua"), "utf8");
assert.match(main, /KoraPhone\.SchemaSetup\.run\(\)/, "the resource must set up the database at start");
assert.match(main, /Database setup failed, stopping resource/, "a failed setup must stop the resource, not run on a half-built schema");
assert.match(fs.readFileSync(path.join(root, "server/integrations/schema_setup.lua"), "utf8"), /Kora\.sql\.ensureTables, KoraPhoneSchema/, "the runner must call ensureTables");
assert.doesNotMatch(fs.readFileSync(path.join(root, "config/server.lua"), "utf8"), /AutoMigrate/, "no AutoMigrate flag");
const handsets = fs.readFileSync(path.join(root, "server/handsets.lua"), "utf8");
assert.doesNotMatch(main + handsets, /H\.migrate|MigrationReport|LegacyMail\.import/, "boot must not run any legacy conversion");
assert.equal(fs.existsSync(path.join(root, "server/migration_report.lua")), false, "migration_report.lua is removed");

console.log(`PASS migrations-manifest: ${tables.length} tables declared in schema.lua and created at start`);