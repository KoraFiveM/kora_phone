#!/usr/bin/env node
"use strict";

// Tables are declared in server/schema.lua and created by Kora.sql.ensureTables at start. This fails if the
// schema is not loaded before the runner, a table is dropped from it, or SQL leaks out of server/repositories.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const manifest = fs.readFileSync(path.join(root, "fxmanifest.lua"), "utf8");
const schema = fs.readFileSync(path.join(root, "server/schema.lua"), "utf8");

const tables = [...schema.matchAll(/^\s{8}name = '(phone_[a-z_]+)'/gm)].map((match) => match[1]);
assert.equal(tables.length, 31, "schema must declare all 31 phone tables");
assert.equal(new Set(tables).size, tables.length, "a table is declared twice");
for (const table of ["phone_devices", "phone_messages", "phone_calls", "phone_bank_history", "phone_sims", "phone_handsets", "phone_system_mail", "phone_system_activity"]) {
  assert.ok(tables.includes(table), `schema must declare ${table}`);
}
assert.match(schema, /^KoraPhoneSchema = \{/m, "schema must expose the KoraPhoneSchema global");
assert.match(schema, /chk_phone_bank_history_positive_amount/, "the positive amount check must stay declared");
assert.match(schema, /generated = \{ expr = /, "phone_sims.active_number must stay a generated column");
assert.match(schema, /name = 'message_type'[^\n]*'video'[^\n]*modify = true/, "message_type must be widened with modify");

assert.ok(manifest.indexOf("'server/schema.lua'") !== -1, "fxmanifest must load server/schema.lua");
assert.ok(manifest.indexOf("'server/schema.lua'") < manifest.indexOf("'server/integrations/*.lua'"), "schema must load before the runner");
assert.doesNotMatch(manifest, /^migration\s+'/m, "no .sql migrations may be listed");
assert.equal(fs.existsSync(path.join(root, "migrations")), false, "the migrations/ .sql files are replaced by the schema");

const main = fs.readFileSync(path.join(root, "server/main.lua"), "utf8");
assert.match(main, /KoraPhone\.SchemaSetup\.run\(\)/, "the resource must set up the database at start");
assert.match(main, /Database setup failed; stopping resource/, "a failed setup must stop the resource, not run on a half-built schema");
assert.match(fs.readFileSync(path.join(root, "server/integrations/schema_setup.lua"), "utf8"), /Kora\.sql\.ensureTables, tables/, "the runner must call ensureTables");
assert.match(fs.readFileSync(path.join(root, "server/integrations/schema_setup.lua"), "utf8"), /KoraPhoneSchema, KoraPhoneSdkSchema/, "the runner must pass the core and SDK schemas together");
assert.doesNotMatch(fs.readFileSync(path.join(root, "config/server.lua"), "utf8"), /AutoMigrate/, "no AutoMigrate flag");
const handsetDir = path.join(root, "server/handsets");
const handsets = fs.readdirSync(handsetDir).map((file) => fs.readFileSync(path.join(handsetDir, file), "utf8")).join("\n");
assert.doesNotMatch(main + handsets, /H\.migrate|MigrationReport|LegacyMail\.import|phone_legacy_claims|phone_migration_issues/, "boot must not run any legacy conversion");
assert.equal(fs.existsSync(path.join(root, "server/handsets.lua")), false, "server/handsets.lua is split into server/handsets/*.lua");
for (const manifestLine of ["server/handsets/core.lua", "server/handsets/lifecycle.lua"]) {
  assert.ok(manifest.includes(`'${manifestLine}'`), `fxmanifest must load ${manifestLine}`);
}

// All SQL lives in repositories: nothing outside them may run a query or contain a statement.
const serverDir = path.join(root, "server");
const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => (entry.isDirectory() ? walk(path.join(dir, entry.name)) : [path.join(dir, entry.name)]));
const sqlCall = /Kora\.sql\.(query|single|scalar|insert|update|execute|transaction)\b|MySQL\.(query|single|scalar|insert|update|transaction)/;
const sqlText = /['"\[](SELECT|INSERT|UPDATE|DELETE)\s/;
const allowed = ["repositories", "schema.lua", "integrations/database.lua", "integrations/schema_setup.lua", "compat/qb-phone.lua", "callbacks.lua"];
for (const file of walk(serverDir).filter((f) => f.endsWith(".lua"))) {
  const relative = path.relative(serverDir, file).split(path.sep).join("/");
  if (allowed.some((prefix) => relative === prefix || relative.startsWith(prefix + "/")) || relative.endsWith("repository.lua")) continue;
  const source = fs.readFileSync(file, "utf8");
  assert.doesNotMatch(source, sqlCall, `${relative} must call a repository, not run SQL`);
  assert.doesNotMatch(source, sqlText, `${relative} must not contain SQL text`);
}
assert.equal(fs.existsSync(path.join(root, "server/migration_report.lua")), false, "migration_report.lua is removed");

console.log(`PASS schema-manifest: ${tables.length} tables declared in schema.lua and created at start`);