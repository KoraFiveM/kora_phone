#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8");

const migration = read("server/schema.lua");
for (const table of ["phone_social_profiles", "phone_social_posts", "phone_social_comments",
  "phone_social_likes", "phone_social_follows", "phone_blocks", "phone_market_listings",
  "phone_reports", "phone_moderation_audit"]) {
  assert.match(migration, new RegExp("name = '" + table + "'"), `missing ${table}`);
}
assert.match(migration, /name = 'uq_phone_social_post_request'[^\n]*unique = true/);
assert.match(migration, /name = 'uq_phone_market_request'[^\n]*unique = true/);
assert.match(migration, /name = 'uq_phone_report_repeat'[^\n]*unique = true/);

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
assert.match(callbacks, /local bind = KoraPhone\.Routes\.handle/, "callbacks bind through the route gateway");
assert.match(read("server/callbacks.lua"), /RateLimits\.consume/);
for (const callback of ["social:createPost", "social:report"]) {
  assert.ok(callbacks.includes(callback), `missing callback ${callback}`);
}
// Market is a folder app: every callback runs the validated marketplace service for the caller's own source
// and charges the community bucket its old route used.
const marketApp = read("apps/classifieds/server.lua");
for (const [callback, service, rate] of [["list", "getListings", "community.read"], ["create", "createListing", "community.listing"], ["remove", "setStatus", "community.listing"],
  ["sold", "setStatus", "community.listing"], ["contact", "contactSeller", "community.contact"], ["report", "report", "community.report"]]) {
  assert.match(marketApp, new RegExp(`app\\.callback\\('${callback}'[\\s\\S]*?Services\\.\\w+\\.${service}\\(source[\\s\\S]*?rate = '${rate.replace(".", "\\.")}'`), `market ${callback} must call ${service}(source) and charge ${rate}`);
}
assert.doesNotMatch(marketApp, /payload\.(?:ownerDeviceId|deviceId|citizenId|sender)/, "the UI must not choose the seller, owner or device");

// Moderation is a staff-only folder app: both callbacks run the moderation service (which re-checks the moderator)
// and charge its strict bucket; the manifest marks it staff so the phone refuses everyone else.
const moderationApp = read("apps/moderation/server.lua");
for (const [callback, service] of [["queue", "getQueue"], ["resolve", "resolve"]])
  assert.match(moderationApp, new RegExp(`app\\.callback\\('${callback}'[\\s\\S]*?Services\\.Moderation\\.${service}\\(source`), `moderation ${callback} must call the service with the caller's source`);
assert.equal((moderationApp.match(/rate = 'community\.moderation'/g) || []).length, 2, "moderation callbacks must charge community.moderation");
assert.match(read("apps/moderation/app.lua"), /staff = true/, "moderation must be a staff app");
console.log("PASS community-contract: schema, authorization and callback contracts present");