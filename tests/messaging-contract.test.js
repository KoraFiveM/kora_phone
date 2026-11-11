#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const read = file => fs.readFileSync(path.join(root, file), "utf8");

const repository = read("server/repositories/messages.lua");
const service = read("server/services/messaging.lua");
const callbacks = read("server/callbacks.lua");
const nui = read("client/nui.lua");
const migration = read("server/schema.lua");
const web = read("web/src/api.ts");
const contracts = read("shared/contracts.lua");

for (const callback of ["getContacts", "getConversations", "startDirectConversation", "markConversationRead", "deleteMessageForSelf"]) {
  assert.match(callbacks, new RegExp(`registerCallback\\('${callback}'`), `${callback} must be registered`);
}
for (const route of ["contacts:list", "messages:getConversations", "messages:startDirect", "messages:markRead", "messages:deleteForSelf"]) {
  assert.match(nui, new RegExp(`\\['${route.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}']`), `${route} needs an explicit NUI bridge`);
}

assert.match(service, /Permissions\.requireDevice\(source\)/, "identity must derive from source");
assert.match(service, /Blocks\.isEitherBlocked/, "direct messaging must enforce blocks");
assert.match(service, /requireConversation\(device/, "thread actions must verify membership");
assert.doesNotMatch(service, /payload\.(?:deviceId|citizenId|source)/, "client identity fields must not be trusted");
assert.match(repository, /cm\.device_id = \? AND cm\.left_at IS NULL/, "message reads must enforce active membership");
assert.match(repository, /phone_message_deletions/, "per-user deletion must not erase peer history");
assert.match(repository, /last_read_message_id/, "read state must be persisted");
assert.match(repository, /displayLabel/, "conversation rows need a safe display label");
assert.match(repository, /findIdempotent/, "message retries need an idempotency lookup");
assert.match(contracts, /PhoneValidation\.string\(payload\.clientRequestId, 'clientRequestId', 8, 64\)/,
  "messages must require a bounded idempotency key");
assert.match(repository, /lastMessagePreview/, "conversation rows need a message preview");
assert.match(repository, /unreadCount/, "conversation rows need unread counts");
assert.match(migration, /name = 'uq_phone_conversations_direct_key'[^\n]*unique = true/, "direct conversations need concurrency uniqueness");

assert.match(web, /messages:getConversations/, "UI must load real conversations");
assert.match(web, /messages:getPage/, "UI must load real message pages");
assert.match(web, /conversationId:p\.conversationId,body:p\.body.*clientRequestId:id/, "composer must send against the selected conversation");
assert.doesNotMatch(web, /5550000000/, "composer must not use a hard-coded recipient");
assert.doesNotMatch(read("web/src/Communication.tsx"), /dangerouslySetInnerHTML/, "React must render message bodies as text");

console.log("PASS messaging-contract: authority, ownership, paging, unread, blocks and UI contracts verified");
