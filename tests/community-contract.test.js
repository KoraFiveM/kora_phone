#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8");

const migration = read("migrations/006_community.sql");
for (const table of ["phone_social_profiles", "phone_social_posts", "phone_social_comments",
  "phone_social_likes", "phone_social_follows", "phone_blocks", "phone_market_listings",
  "phone_reports", "phone_moderation_audit"]) {
  assert.match(migration, new RegExp("CREATE TABLE IF NOT EXISTS `" + table + "`"), `missing ${table}`);
}
assert.match(migration, /UNIQUE KEY `uq_phone_social_post_request`/);
assert.match(migration, /UNIQUE KEY `uq_phone_market_request`/);
assert.match(migration, /UNIQUE KEY `uq_phone_report_repeat`/);

const repositoryFiles = ["social", "marketplace", "blocks", "reports"]
  .map(name => read(`server/repositories/${name}.lua`));
for (const source of repositoryFiles) {
  assert.doesNotMatch(source, /(?:string\.format|\.\.\s*tostring\s*\()/i,
    "SQL must not format user-controlled values into query text");
  assert.match(source, /\?/, "repository queries should use bound placeholders");
}

const social = read("server/services/social.lua");
const market = read("server/services/marketplace.lua");
const moderation = read("server/services/moderation.lua");
const callbacks = read("server/modules/community_callbacks.lua");
const reports = read("server/repositories/reports.lua");
assert.match(social, /isEitherBlocked/);
assert.match(social, /authorIsPrivate/);
assert.match(social, /isFollowing/);
assert.match(social, /clientRequestId/);
assert.match(market, /Services\.Messaging\.send/);
assert.doesNotMatch(market, /RemoveMoney|AddMoney|bank|getMoney/i,
  "marketplace v1 must not move money");
assert.match(moderation, /IsPlayerAceAllowed/);
assert.match(moderation, /hasPermission/);
assert.match(moderation, /Repositories\.Reports\.audit/);
assert.match(moderation, /Repositories\.Reports\.claim/);
assert.match(reports, /assigned_citizenid = \?/);
assert.match(callbacks, /= QBPhone\.registerCallback/);
assert.match(read("server/callbacks.lua"), /RateLimits\.consume/);
for (const callback of ["social:createPost", "social:report", "market:createListing", "market:contactSeller", "moderation:resolve"]) {
  assert.ok(callbacks.includes(callback), `missing callback ${callback}`);
}
console.log("PASS community-contract: schema, authorization and callback contracts present");
