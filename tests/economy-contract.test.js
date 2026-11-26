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
const migration = read("server/schema.lua");
const config = read("config/server.lua");
const transactions = read("server/repositories/transactions.lua");

assert.match(banking, /Permissions\.requireDevice\(source\)/, "banking must require the server-side device");
assert.match(banking, /GetCitizenId\(source\)/, "sender identity must derive from source");
assert.match(banking, /PhoneValidation\.integer\(payload\.amount/, "amount must be bounded by shared validation");
assert.match(banking, /PhoneValidation\.string\(payload\.clientRequestId/, "transfer must require an idempotency key");
assert.match(banking, /Banking\.execute\(operationKey/, "transfer must run on kora_banking's durable transaction");
assert.match(bankIntegration, /exports\.kora_banking:ExecuteTransaction\(operationKey, request\)/, "integration must call ExecuteTransaction");
assert.match(banking, /'transfer:%s:%s'\):format\(senderCitizenId, requestId\)/, "idempotency key is sender character plus clientRequestId");
assert.match(banking, /statements = \{ Transactions\.historyStatement/, "history row must ride in the same transaction");
assert.match(banking, /insufficient_funds/, "insufficient funds must be mapped");
assert.match(banking, /RETRYABLE = \{ pending = true, indeterminate = true, unavailable = true \}/, "ambiguous codes must be retryable");
assert.doesNotMatch(banking, /rolled_back|manual_review|removeMoney|addMoney|getOnlinePlayerByCitizenId/, "no compensating state machine or online-only restriction");
assert.doesNotMatch(bankIntegration, /AllowCompensatingTransfers|removeMoney|addMoney/, "no direct money mutation in the phone");
assert.doesNotMatch(transactions, /INSERT IGNORE|UPDATE /, "history repository only inserts inside the bank transaction and reads");
assert.match(config, /bankTransfer\s*=\s*bucket\(3,/, "bank transfers need a dedicated strict rate limit");
const routeTable = JSON.parse(fs.readFileSync(path.join(root, "shared/routes.json"), "utf8"));
assert.match(read("apps/banking/server.lua"), /end, \{ rate = 'bankTransfer' \}\)/, "the Wallet transfer callback must charge the strict bankTransfer bucket");
assert.equal(JSON.parse(read("shared/routes.json")).some((route) => /^bank:/.test(route.nui)), false, "bank routes live in the Wallet app, not the route table");
assert.doesNotMatch(banking, /payload\.(?:citizenId|sender|balance)/, "client must not provide sender identity or balance");

assert.match(jobs, /Integrations\.Jobs\.snapshot\(source\)/, "job must be loaded from the server-side player");
assert.match(jobs, /snapshot\.grade < \(tonumber\(action\.minimumGrade\)/, "job actions must enforce current grade");
assert.match(jobs, /action\.requireDuty == true and not snapshot\.onDuty/, "job actions must enforce duty state");
assert.doesNotMatch(jobs, /payload\.(?:job|grade|citizenId)/, "client must not select its job, grade or identity");

assert.match(migration, /name = 'uq_phone_bank_history_operation'[^\n]*unique = true/, "history must be unique per bank operation");
assert.doesNotMatch(migration, /phone_economy_audit|manual_review/, "the old audit state machine table is gone");
// Wallet is a folder app: the transfer callback runs the idempotent service, reading only the three fields below.
const walletApp = read("apps/banking/server.lua");
assert.match(walletApp, /Services\.Banking\.transfer\(source, \{\s*to = payload\.to, amount = payload\.amount, clientRequestId = payload\.clientRequestId,\s*\}\)/, "Wallet transfer must pass only to, amount and clientRequestId");
assert.match(walletApp, /Services\.Banking\.balance\(source\)/, "balance must come from the caller's own source");
assert.doesNotMatch(walletApp, /payload\.(?:account|citizenId|from|sender)/, "the UI must not choose the account or sender");

// The Work app is a folder app: its callbacks are the only way in, and each one runs the validated service.
const workApp = fs.readFileSync(path.join(root, "apps/services/server.lua"), "utf8");
for (const [callback, service] of [["get", "Jobs.get"], ["setDuty", "Jobs.setDuty"], ["runAction", "Jobs.runAction"]]) {
  assert.match(workApp, new RegExp(`app\\.callback\\('${callback}'[\\s\\S]*?Services\\.${service.replace(".", "\\.")}\\(source`), `Work ${callback} must call ${service} with the caller's source`);
}
assert.equal((workApp.match(/\{ rate = 'jobMutation' \}/g) || []).length, 2, "Work duty and action callbacks must charge the jobMutation bucket");
assert.doesNotMatch(workApp, /payload\.(?:job|grade|citizenId)/, "the Work app must not let the client pick job, grade or identity");

console.log("PASS economy-contract: banking and jobs security contracts present");
