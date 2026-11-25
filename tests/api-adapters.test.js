#!/usr/bin/env node
"use strict";

// Unit checks for the web API adapters (server shape -> UI shape), the error map and the dispatcher.
// Transpiles web/src with the repo's TypeScript into a temp dir and runs it with node built-ins only.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const root = path.resolve(process.argv[2] || path.join(__dirname, ".."));
let ts;
try { ts = require(path.join(root, "web/node_modules/typescript")); }
catch { console.log("SKIP api-adapters: web/node_modules/typescript is not installed"); process.exit(0); }

const out = fs.mkdtempSync(path.join(os.tmpdir(), "kora-api-"));
const compile = (rel) => {
  const source = fs.readFileSync(path.join(root, "web/src", rel), "utf8");
  const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } });
  const target = path.join(out, rel.replace(/\.ts$/, ".js"));
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, outputText);
};
// Pure modules only: no DOM, no mock, no transport.
["types.ts", "catalog.ts", "themes.ts", "api/adapters/common.ts", "api/adapters/messages.ts", "api/adapters/social.ts",
  "api/adapters/mail.ts", "api/adapters/apps.ts", "api/adapters/media.ts", "api/adapters/bootstrap.ts", "api/raw.ts",
  "api/errors.ts"].forEach(compile);
fs.writeFileSync(path.join(out, "package.json"), "{}");
const load = (rel) => require(path.join(out, rel));

let checks = 0;
const equal = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };

try {
  const { stamp, kindOf, items } = load("api/adapters/common.js");
  equal(stamp(1700000000), "2023-11-14T22:13:20.000Z", "numeric stamps are unix seconds");
  equal(stamp("2024-01-01"), "2024-01-01", "string stamps pass through");
  equal(kindOf("video/mp4", "https://x/a"), "video", "video mime is a video");
  equal(kindOf("image/jpeg", "https://x/a"), "photo", "other mime is a photo");
  equal(kindOf("video/mp4", ""), undefined, "no url means no media");
  equal(items({ items: [1] }), [1], "items unwraps a page");
  equal(items([2]), [2], "items accepts a bare array");
  equal(items(null), [], "items tolerates null");

  const { mapMessage, mapConversation, mapCall, mapCallHistory } = load("api/adapters/messages.js");
  const message = mapMessage({ id: 1, body: "hi", senderNumber: 555, createdAt: 1700000000, mediaUrl: "https://x/v", mediaMime: "video/webm" });
  equal([message.sender_number, message.created_at, message.media_url, message.media_kind, message.body],
    ["555", "2023-11-14T22:13:20.000Z", "https://x/v", "video", "hi"], "messages map server fields to chat fields");
  equal(mapMessage({ id: 2 }).media_url, undefined, "no media url stays undefined");
  const group = mapConversation({ id: 3, type: "group", title: "Crew", lastMessagePreview: "yo", lastMessageAt: "2024-01-01" });
  equal([group.kind, group.name, group.last_body, group.last_at, group.last_number], ["group", "Crew", "yo", "2024-01-01", null], "group conversations");
  const direct = mapConversation({ id: 4, peerPhoneNumber: "5550001" });
  equal([direct.kind, direct.members, direct.name, direct.last_body, direct.last_at], ["direct", "5550001", null, "", null], "direct conversations");
  equal(mapCall({ id: 9, status: "rejected", remoteNumber: "555" }),
    { id: "9", status: "declined", number: "555", direction: "outgoing", deviceId: "kora_phone" }, "rejected calls are shown as declined");
  equal(mapCallHistory({ id: "c", callerNumber: "1", calleeNumber: "2", status: "ended", startedAt: 1700000000 }),
    { id: "c", caller: "1", recipient: "2", status: "ended", created_at: "2023-11-14T22:13:20.000Z" }, "call history rows");

  const social = load("api/adapters/social.js");
  const listing = social.mapListing({ id: 1, title: "Bike", description: "Fast", price: 50, sellerName: "Sam", createdAt: "t", isOwner: true });
  equal([listing.number, listing.body, listing.price, listing.mine, listing.likes], ["Sam", "Bike\nFast", 50, true, 0], "classifieds");
  const post = social.mapPost({ id: 2, handle: "@a", body: "b", likeCount: 3, liked: 1, mine: 1, createdAt: "t", mediaUrl: "https://x/i", mediaMime: "image/png" });
  equal([post.number, post.likes, post.liked, post.mine, post.media_kind], ["@a", 3, true, true, "photo"], "social posts");
  equal(social.mapComment({ id: 3, displayName: "Dee", body: "ok", createdAt: "t" }).number, "Dee", "comment author falls back to display name");
  equal(social.mapReport({ id: 4, targetType: "post", targetId: 5, reason: "spam", status: "open", createdAt: "t" }).snapshot, {}, "reports default their snapshot");
  equal(social.splitListing(`${"x".repeat(100)}\nline two\nline three`), { title: "x".repeat(80), description: "line two\nline three" }, "listing text splits into title and description");

  const mail = load("api/adapters/mail.js");
  equal(mail.mapMail({ id: 1, peer: 7, subject: "s", body: "b", unread: 1, createdAt: "t" }),
    { id: 1, peer: "7", subject: "s", body: "b", created_at: "t", unread: true }, "mail rows");
  equal(mail.mapSystemMail({ id: 1, peer: "p", subject: "s", body: "b", hasAction: true, unread: 0, createdAt: "t" }).hasAction, true, "system mail action flag");

  equal(mail.mapSystemMail({ id: 2, peer: "Job", subject: "s", body: "b", hasAction: 1, unread: 0, createdAt: "t" }),
    { id: 2, peer: "Job", subject: "s", body: "b", hasAction: true, created_at: "t", unread: false }, "system mail keeps its action flag");
  equal(mail.mapMailAccept({ accepted: true, dispatched: 0 }), { accepted: true, dispatched: false }, "accept result has both flags");
  equal(mail.mapMailAccept(undefined), { accepted: false, dispatched: false }, "empty accept result is a refusal");
  const sdk = load("api/adapters/apps.js").mapSdkApp({ id: "demo", name: "Demo", entry: "ui/index.html", resource: "demo_res", permissions: ["notify", 3], installed: 1 });
  equal([sdk.id, sdk.permissions, sdk.installed, sdk.defaultInstalled], ["demo", ["notify"], true, false], "SDK app listing is typed and filtered");
  const media = load("api/adapters/media.js");
  equal(media.mapPhoto({ id: 5, publicUrl: "https://x/p.jpg", createdAt: 9 }), { id: "5", url: "https://x/p.jpg", created_at: 9, kind: "photo" }, "gallery photos");
  equal(media.mapContact({ id: "7", displayName: "Al", phoneNumber: "555", isFavorite: 1 }), { id: 7, name: "Al", number: "555", photo: undefined, favorite: true }, "contacts");

  const { mapBootstrap } = load("api/adapters/bootstrap.js");
  const open = mapBootstrap({ device: { id: 12, phoneNumber: 555 }, features: { media: true, maps: false, video: { iceServers: [] }, flash: { maxSeconds: "20" } }, apps: { social: false }, moderator: true }, { a: true });
  equal([open.bootstrap.id, open.bootstrap.number, open.bootstrap.locked, open.bootstrap.model], ["12", "555", false, "standard"], "bootstrap identity");
  equal([open.bootstrap.capabilities.social, open.bootstrap.capabilities.camera, open.bootstrap.capabilities.gps, open.bootstrap.capabilities.moderation],
    [false, true, false, true], "capabilities combine app switches and server features");
  equal(open.bootstrap.flash, { maxSeconds: 20, maxBytes: undefined }, "flash limits");
  equal(open.cache.customApps, { a: true }, "custom app preferences are carried into the cache");
  const locked = mapBootstrap({ security: { locked: true, hasPin: true } }, {});
  equal([locked.bootstrap.locked, locked.bootstrap.hasPin, locked.bootstrap.data], [true, true, undefined], "locked phones hide their data");
  equal(locked.cache.contacts, [], "locked caches are empty");

  const { errorText, friendlyErrors } = load("api/errors.js");
  equal(errorText("MEDIA_TOO_LARGE"), "That file is too big", "known code");
  equal(errorText({ code: "PLAYER_DEAD" }), "You cannot use the camera right now", "known code in an object");
  equal(errorText({ message: "Custom" }), "Custom", "unknown message passes through");
  equal(errorText(undefined), "Request failed", "missing error");
  equal(Object.keys(friendlyErrors).length, 21, "the friendly error map keeps all 21 codes");

  console.log(`PASS api-adapters: ${checks} adapter, error-map and bootstrap checks`);
} finally {
  fs.rmSync(out, { recursive: true, force: true });
}
