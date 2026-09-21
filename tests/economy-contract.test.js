#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

const banking = read("server/services/banking.lua");
const bankIntegration = read("server/integrations/banking.lua");
const jobs = read("server/services/jobs.lua");
const migration = read("migrations/005_economy_audit.sql");
const callbacks = read("server/modules/economy_callbacks.lua");
const config = read("config/server.lua");

assert.match(banking, /Permissions\.requireDevice\(source\)/, "banking must require the server-side device");
assert.match(banking, /GetCitizenId\(source\)/, "sender identity must derive from source");
assert.match(banking, /PhoneValidation\.integer\(payload\.amount/, "amount must be bounded by shared validation");
assert.match(banking, /PhoneValidation\.string\(payload\.clientRequestId/, "transfer must require an idempotency key");
assert.match(banking, /Transactions\.claim/, "transfer must claim its idempotency record before money movement");
assert.match(banking, /rolled_back/, "credit failure must have compensating rollback state");
assert.match(banking, /manual_review/, "failed rollback must be auditable");
assert.match(bankIntegration, /AllowCompensatingTransfers == true/, "non-atomic transfer path must require explicit opt-in");
assert.match(config, /bankTransfer\s*=\s*\{\s*capacity\s*=\s*3/, "bank transfers need a dedicated strict rate limit");
assert.match(callbacks, /'transferBankMoney', 'bankTransfer'/, "bank transfer callback must use its strict rate key");
assert.doesNotMatch(banking, /payload\.(?:citizenId|sender|balance)/, "client must not provide sender identity or balance");

assert.match(jobs, /Integrations\.Jobs\.snapshot\(player\)/, "job must be loaded from the server-side player");
assert.match(jobs, /snapshot\.grade < \(tonumber\(action\.minimumGrade\)/, "job actions must enforce current grade");
assert.match(jobs, /action\.requireDuty == true and not snapshot\.onDuty/, "job actions must enforce duty state");
assert.doesNotMatch(jobs, /payload\.(?:job|grade|citizenId)/, "client must not select its job, grade or identity");

assert.match(migration, /UNIQUE KEY `uq_phone_economy_idempotency`/, "database must enforce transfer idempotency");
assert.match(migration, /'manual_review'/, "audit schema must represent failed compensation");
for (const name of ["getBankBalance", "getBankHistory", "transferBankMoney", "getJob", "setJobDuty", "runJobAction"]) {
  assert.match(callbacks, new RegExp(`register\\('${name}'`), `missing callback ${name}`);
}

console.log("PASS economy-contract: banking and jobs security contracts present");
