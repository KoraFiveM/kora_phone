#!/usr/bin/env node
"use strict";

// Do Not Disturb, notification history, location/photo sharing and the Wallet ID card.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

const nui = read("client/nui.lua");
const notifications = read("client/notifications.lua");
const calls = read("client/calls.lua");
const wallet = read("server/services/wallet.lua");
const economy = read("server/modules/economy_callbacks.lua");
const api = read("web/src/api.ts");
const app = read("web/src/App.tsx");

// Every new NUI route the UI calls exists on the client and reaches a registered server callback.
for (const [route, callback] of [["wallet:get", "getWallet"], ["wallet:show", "showWalletId"]]) {
  assert.match(nui, new RegExp(`\\['${route}'\\] = 'qbphone:server:${callback}'`), `${route} must map to ${callback}`);
  assert.match(economy, new RegExp(`register\\('${callback}'`), `${callback} must be registered on the server`);
  assert.match(api, new RegExp(`server\\('${route}'\\)`), `the UI must call ${route}`);
}
for (const route of ["location:mine", "waypoint", "quiet"]) {
  assert.match(nui, new RegExp(`RegisterNUICallback\\('${route}'`), `${route} must be registered on the client`);
}
assert.match(api, /server\('location:mine'\)/);
assert.match(api, /server\('waypoint',/);
assert.match(app, /nui\('quiet',/, "the UI must tell the client when Do Not Disturb changes");

// The waypoint route only accepts sane numbers.
assert.match(nui, /math\.abs\(x\) > 20000/, "waypoint coordinates must be bounded");

// The ID card is built from the server's copy of the character and shown only to a nearby player.
assert.match(wallet, /PlayerData/, "the card must come from server-side player data");
assert.match(wallet, /GetEntityCoords\(GetPlayerPed\(source\)\)/, "distance must use server-side positions");
assert.match(wallet, /ShowDistance/, "the show distance must be configurable");
assert.match(wallet, /requireDevice\(source\)/, "a locked phone must not show an ID");
assert.doesNotMatch(wallet, /payload/, "the ID card must not read any client-supplied field");
assert.match(notifications, /qbphone:client:wallet:shown/, "the receiving client must handle the shown ID");

// Do Not Disturb silences native alerts and doesn't pop the phone open for a call, except for urgent alerts.
assert.match(notifications, /QBPhone\.State\.quiet and not urgent/, "Do Not Disturb silences the native alert unless it is urgent");
assert.match(notifications, /Notifications\.Native\(notification\.title/, "pushed notifications must go through the same silenced path");
assert.match(nui, /RegisterNUICallback\('notify'/, "the UI must be able to ask the game for a notification while the phone is closed");
assert.match(app, /nui\('notify'/, "texts, mail and missed calls must raise a game notification when the phone is closed");
assert.match(api, /case'shareToChat'/, "sharing a Flash post to a chat must be wired in game");
assert.match(calls, /QBPhone\.State\.quiet/);

// Persistent notes/alarms/stations, group chats and the Garage go through registered, validated server code.
const callbacks = read("server/callbacks.lua");
const items = read("server/services/items.lua");
const garage = read("server/services/garage.lua");
const messaging = read("server/services/messaging.lua");
const migration9 = read("migrations/009_items.sql");
for (const [route, callback] of [["items:save", "saveItem"], ["items:remove", "removeItem"], ["garage:list", "getVehicles"], ["messages:createGroup", "createGroup"], ["messages:leaveGroup", "leaveGroup"]]) {
  assert.match(nui, new RegExp(`\\['${route}'\\] = 'qbphone:server:${callback}'`), `${route} must map to ${callback}`);
  assert.match(callbacks, new RegExp(`register\\('${callback}'`), `${callback} must be registered on the server`);
  assert.match(api, new RegExp(`'${route}'`), `the UI must call ${route}`);
}
assert.match(nui, /RegisterNUICallback\('weather:get'/);
assert.match(nui, /RegisterNUICallback\('alarm'/);
assert.match(items, /PhoneValidation\.item\(/, "items must be validated on the server");
assert.match(items, /Config\.Server\.Items\[kind\]/, "items must be limited per phone");
assert.match(migration9, /PRIMARY KEY \(`device_id`, `kind`, `item_key`\)/, "an item is unique per device, kind and key");
assert.match(garage, /\^\[%w_\]\+\$/, "the vehicles table name must be checked before it is put in SQL");
assert.match(garage, /device\.ownerCitizenId/, "vehicles must be looked up by the caller's own character");
assert.match(messaging, /otherMembers\(conversationId, sender\.id\)/, "group messages must go to the other members");
assert.match(messaging, /requireConversation\(device, payload\)/, "leaving a group must check membership");

// Mail, Property and adding group members.
const mailSvc = read("server/services/mail.lua");
const mailRepo = read("server/repositories/mail.lua");
const property = read("server/services/property.lua");
for (const [route, callback] of [["messages:addMember", "addGroupMember"], ["mail:list", "getMail"], ["mail:send", "sendMail"], ["mail:read", "readMail"], ["mail:delete", "deleteMail"], ["property:list", "getProperties"]]) {
  assert.match(nui, new RegExp(`\\['${route}'\\] = 'qbphone:server:${callback}'`), `${route} must map to ${callback}`);
  assert.match(callbacks, new RegExp(`register\\('${callback}'`), `${callback} must be registered on the server`);
  assert.match(api, new RegExp(`'${route}'`), `the UI must call ${route}`);
}
assert.match(mailSvc, /PhoneContracts\.mail\(/, "mail must be validated on the server");
assert.match(mailSvc, /isEitherBlocked/, "mail must respect blocks");
assert.match(mailRepo, /INSERT IGNORE INTO phone_mail/, "a retried mail request must not send twice");
assert.match(mailRepo, /recipient_device_id = \?/, "mail is only read or deleted by its own sender or recipient");
assert.match(property, /\^\[%w_\]\+\$/, "housing table and column names must be checked before they go into SQL");
assert.match(property, /device\.ownerCitizenId/, "homes must be looked up by the caller's own character");
assert.match(messaging, /memberCount\(conversationId\) >= 50/, "groups are capped");
assert.match(app, /type === 'mail:new'/, "the UI must handle new mail");

// Blocking numbers, contact photos and the gallery loading with the phone.
const blocking = read("server/services/blocking.lua");
const contactsSvc = read("server/services/contacts.lua");
const contactsRepo = read("server/repositories/contacts.lua");
const phoneSvc = read("server/services/phone.lua");
for (const [route, callback] of [["blocks:list", "getBlocked"], ["blocks:set", "setBlocked"]]) {
  assert.match(nui, new RegExp(`\\['${route}'\\] = 'qbphone:server:${callback}'`), `${route} must map to ${callback}`);
  assert.match(callbacks, new RegExp(`register\\('${callback}'`), `${callback} must be registered on the server`);
  assert.match(api, new RegExp(`'${route}'`), `the UI must call ${route}`);
}
assert.match(blocking, /You cannot block your own number/, "a player must not be able to block themselves");
assert.match(blocking, /findByNumber\(number\)/, "blocking resolves the number on the server");
assert.match(contactsSvc, /Media\.findOwned\(device\.id, contact\.avatarMediaId\)/, "a contact photo must be one of the caller's own gallery photos");
assert.match(contactsRepo, /NULLIF\(\?, 0\)/, "a cleared contact photo must be stored as NULL");
assert.match(phoneSvc, /media = QBPhone\.Storage\.provider\(\) ~= 'disabled'/, "the UI must be told whether photo storage exists");
assert.match(api, /server\('gallery:list'/, "the gallery must load with the phone");
assert.match(app, /Missed call/, "a missed call must leave a notification");

// Wallet honesty, favourites and the death check.
const clientMain = read("client/main.lua");
const txRepo = read("server/repositories/transactions.lua");
const bankSvc = read("server/services/banking.lua");
assert.match(clientMain, /QBPhone\.Unavailable\(\)/, "Config.Client.DisableWhileDead must be enforced");
assert.match(clientMain, /metadata\.isdead == true or metadata\.inlaststand == true/, "last stand must count as unavailable");
assert.match(txRepo, /AND t\.id < \?/, "the history cursor must be qualified now that the query joins devices");
assert.match(txRepo, /item\.peer =/, "history must say who the other person was");
assert.match(bankSvc, /holder = holder, number = pd\.citizenid/, "the wallet must show the holder and account number");
assert.match(phoneSvc, /transfers = QBPhone\.Integrations\.Banking\.canTransfer\(\)/, "the UI must know whether transfers are on");
assert.match(read("web/src/SocialBank.tsx"), /!device\.transfers/, "the Send money form must be hidden when transfers are off");
assert.match(api, /isFavorite:p\.favorite===true/, "saving a contact must not wipe its favourite flag");

// Flash and chat clips: the upload pipeline and where its trust boundaries are.
const storageSvc = read("server/integrations/storage.lua");
const mediaSvc = read("server/services/media.lua");
const socialSvc = read("server/services/social.lua");
const socialRepo = read("server/repositories/social.lua");
const mediaRepo = read("server/repositories/media.lua");
const migration11 = read("migrations/011_media_posts.sql");
const flash = read("web/src/Flash.tsx");
for (const [route, callback] of [["media:request", "requestMediaUpload"], ["media:complete", "completeMediaUpload"]]) {
  assert.match(nui, new RegExp(`\\['${route}'\\] = 'qbphone:server:${callback}'`), `${route} must map to ${callback}`);
  assert.match(api, new RegExp(`'${route}'`), `the UI must call ${route}`);
}
assert.match(storageSvc, /GetConvar\('qbphone_fivemanage_token'/, "the Fivemanage token must come from a server convar");
assert.doesNotMatch(storageSvc.split("function Storage.begin")[1].split("function Storage.completeLocal")[0].replace(/\{ Authorization = token \}/, ""), /apiToken|Authorization\s*=\s*token[^}]*token = /, "the API token must never be put in the upload instruction");
assert.match(storageSvc, /completeFivemanage/, "uploads to Fivemanage must be verified server-side");
assert.match(storageSvc, /hostAllowed\(fm\.ApiBase, fm\.UploadHosts\)/, "the presign host must be allowlisted");
assert.match(storageSvc, /file\.size|tonumber\(file\.size\)/, "the real uploaded size must be checked");
assert.match(mediaSvc, /countRecentVideos/, "clips need a per-phone daily allowance");
assert.match(mediaSvc, /completeFivemanage\(ticket, payload\.receipt/, "the media service must verify with the provider");
assert.match(mediaRepo, /phone_social_posts WHERE media_id/, "media used by a Flash post must not be deletable from the gallery");
assert.match(mediaRepo, /NULLIF\(\?, -1\)/, "media rows without dimensions must not drop trailing SQL parameters");
assert.match(socialSvc, /Media\.findOwned\(device\.id, mediaId\)/, "a post may only carry the author's own media");
assert.match(socialRepo, /\(po\.author_profile_id = \?\) AS mine/, "the feed must say which posts are the viewer's own");
assert.match(migration11, /ADD COLUMN `media_id`/, "posts need a media column");
assert.match(migration11, /'video'/, "messages need a video type");
assert.match(api, /if\(action==='uploadMedia'\)/, "uploads must bypass the serial request queue so they don't block the phone");
assert.match(api, /qbphoneTicket/, "the upload must carry its ticket tag");
assert.match(flash, /createProfile/, "Flash must create a social profile on first use");
assert.match(flash, /uploadMedia/, "Flash clips must go through the upload pipeline");

// The pure logic, executed for real (skipped when the web toolchain isn't installed).
let ts;
try { ts = require(path.join(root, "web/node_modules/typescript")); } catch { console.log("SKIP logic checks: web/node_modules/typescript is not installed"); }
if (ts) {
  const load = (file) => {
    const { outputText } = ts.transpileModule(read(file), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } });
    const module = { exports: {} };
    new Function("module", "exports", outputText)(module, module.exports);
    return module.exports;
  };
  const { isQuiet } = load("web/src/quiet.ts");
  const at = (h, m) => new Date(2026, 0, 1, h, m);
  assert.equal(isQuiet({}, at(12, 0)), false, "off by default");
  assert.equal(isQuiet({ dnd: true }, at(12, 0)), true, "on when switched on");
  assert.equal(isQuiet({ dndFrom: "13:00", dndTo: "15:00" }, at(14, 0)), true, "inside a same-day window");
  assert.equal(isQuiet({ dndFrom: "13:00", dndTo: "15:00" }, at(15, 0)), false, "the end of the window is exclusive");
  assert.equal(isQuiet({ dndFrom: "22:00", dndTo: "07:00" }, at(23, 30)), true, "before midnight in an overnight window");
  assert.equal(isQuiet({ dndFrom: "22:00", dndTo: "07:00" }, at(6, 59)), true, "after midnight in an overnight window");
  assert.equal(isQuiet({ dndFrom: "22:00", dndTo: "07:00" }, at(12, 0)), false, "outside an overnight window");
  assert.equal(isQuiet({ dndFrom: "22:00" }, at(23, 0)), false, "half a schedule does nothing");
  assert.equal(isQuiet({ dndFrom: "08:00", dndTo: "08:00" }, at(8, 0)), false, "an empty window does nothing");

  const { locationBody, photoBody, parseToken, previewText } = load("web/src/chatTokens.ts");
  const place = { x: 195.2, y: -933.8, label: "Legion Square, [Vinewood|Blvd]" };
  const body = locationBody(place);
  assert.ok(body.length < 200 && !/\]\]./.test(body), "a location token is short and cannot be broken out of");
  assert.deepEqual(parseToken(body), { kind: "location", x: 195.2, y: -933.8, label: "Legion Square, VinewoodBlvd" });
  assert.deepEqual(parseToken(photoBody("https://cdn.example.com/a.png")), { kind: "photo", url: "https://cdn.example.com/a.png" });
  assert.equal(parseToken("[[photo:http://insecure.example/a.png]]"), null, "photos must be https");
  assert.equal(parseToken("[[photo:javascript:alert(1)]]"), null);
  assert.equal(parseToken("hello [[loc:1,2|x]] there"), null, "a token must be the entire message");
  assert.equal(parseToken("[[loc:99999999,2|x]]"), null, "absurd coordinates are plain text");
  assert.equal(previewText(body), "Shared a location");
  assert.equal(previewText(photoBody("https://a.example/b.png")), "Sent a photo");
  assert.equal(previewText("just text"), "just text");
  const { videoBody } = load("web/src/chatTokens.ts");
  assert.deepEqual(parseToken(videoBody("https://r2.example.com/c.webm")), { kind: "video", url: "https://r2.example.com/c.webm" });
  assert.equal(previewText(videoBody("https://r2.example.com/c.webm")), "Sent a clip");
  assert.equal(parseToken("[[video:http://insecure.example/c.webm]]"), null, "shared clips must be https");
}

console.log("features-contract: all checks passed");
