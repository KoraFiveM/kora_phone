---
title: Events and callbacks
sidebar_position: 10
---

# Events and callbacks

The NUI talks to the client through NUI callbacks. The client forwards most of them to the server through `Kora.callback` (`kora_lib`) under the name `kora_phone:server:` plus the callback name. Every server callback is rate limited, runs inside the handset lock and fails with `Handset session changed` if the character or selected handset changes while it runs. Results are `{ ok = true, data = ... }` or `{ ok = false, error = { code, message } }`.

## Server events (client to server)

| Event | Purpose |
| --- | --- |
| `kora_phone:server:phone:closed` | The phone was closed: ends the player's call and re-locks the session |
| `kora_phone:server:calls:hangup` | Hang up call id (rate limited) |
| `kora_phone:server:calls:voiceFailure` | The client could not join the voice channel for a call id |
| `qb-phone:server:sendNewMail` | Legacy: mail to the calling character only |
| `qb-phone:server:ClearButtonData` | Legacy: clear a mail's button, by mail id |
| `qb-phone:server:RemoveMail` | Legacy: delete a mail, by mail id |
| `qb-phone:server:AddTransaction` | Legacy: store a transaction note for the calling character |
| `qb-phone:server:sendNewEventMail` | Local-only legacy event (`AddEventHandler`): ignored when it arrives from a client |

See [Legacy qb-phone support](./legacy-compat.md) for the compat events.

## Client events (server to client)

| Event | Payload | Purpose |
| --- | --- | --- |
| `kora_phone:client:ready` | none | Handsets are ready; the client bootstraps |
| `kora_phone:client:sessionRevoked` | none | Possession lost or character changed: close the phone and clean up calls |
| `kora_phone:client:useHandset` | none | A handset item was used: reopen the phone |
| `kora_phone:client:contentCleared` | none | A handset was reset |
| `kora_phone:client:reset` | none | `/phonereset`: close and reload |
| `kora_phone:client:notification` | `app`, `title`, `body`, `data` | Shows a notification (see the `SendNotification` export) |
| `kora_phone:client:messages:new` | message row | New message; pops a preview when the phone is closed |
| `kora_phone:client:messages:read` | receipt | Read receipt |
| `kora_phone:client:mail:new` | `sender`, `subject`, `citizenId`, `deviceId` | New mail notice |
| `kora_phone:client:calls:incoming` / `outgoing` / `accepted` / `ended` | call table | Call lifecycle |
| `kora_phone:client:calls:signal` | WebRTC offer, answer or ICE | Video signalling |
| `kora_phone:client:calls:videoControl` | `id`, `action`, `epoch` | Video upgrade control |
| `kora_phone:client:calls:remoteMute` | `id`, `source`, `muted` | Mutes or unmutes the other party through pma-voice |
| `kora_phone:client:share:request` | `id`, `label`, `number`, `expiresIn`, `shareBack` | Share-your-number prompt |
| `kora_phone:client:wallet:shown` | ID card | Someone showed you their ID |
| `kora_phone:client:openServices`, `serviceRequest`, `serviceResult` | | Service counter UI |
| `kora_phone:client:legacyTransactionSaved` | `citizenId` | Refresh Mail activity |
| `qb-phone:client:NewMailNotify`, `RefreshPhone`, `BillingEmail`, `RemoveBankMoney`, `AddTransaction` | | Legacy compat handlers |

The client also listens to `QBCore:Client:OnPlayerLoaded`, `OnPlayerUnload`, `QBCore:Player:SetPlayerData`, `QBCore:Client:OnJobUpdate` and `kora_lib:blips:changed`; the server to `QBCore:Server:OnPlayerUnload`, `playerDropped` and `onResourceStop`.

## Server callbacks (`kora_phone:server:<name>`)

| Area | Names |
| --- | --- |
| Phone | `getBootstrap`, `saveSettings`, `unlockPhone`, `lockPhone`, `setPhonePin`, `removePhonePin`, `hasPhone` |
| Handsets | `handsetAction` (ops: `status`, `select`, `faceUnlock`, `faceEnroll`, `wifi`, `insertSim`, `removeSim`, `registerCloud`, `backup`, `restoreCloud`, `reset`, and service ops `buy`, `recoverCloud`, `replaceSim`, `resell`, `consent`) |
| Contacts and sharing | `getContacts`, `saveContact`, `deleteContact`, `share:offer`, `share:answer` |
| Messages | `sendMessage`, `getMessages`, `getConversations`, `startDirectConversation`, `markConversationRead`, `deleteMessageForSelf`, `createGroup`, `leaveGroup`, `addGroupMember`, `getBlocked`, `setBlocked` |
| Calls | `calls:start`, `calls:accept`, `calls:reject`, `calls:hangup`, `calls:history`, `calls:signal`, `calls:videoControl` |
| Mail | `getMail`, `sendMail`, `readMail`, `deleteMail`, `legacy:getMail`, `legacy:getActivity`, `legacy:readMail`, `legacy:deleteMail`, `acceptLegacyMail` |
| Media | `requestMediaUpload`, `completeMediaUpload`, `getGallery`, `deleteMedia` |
| Economy | `getBankBalance`, `getBankHistory`, `transferBankMoney`, `getWallet`, `showWalletId`, `getJob`, `setJobDuty`, `runJobAction` |
| Utilities | `saveItem`, `removeItem`, `getVehicles`, `getProperties` |
| Community | `social:createAccount`, `getFeed`, `getProfile`, `createPost`, `deletePost`, `toggleLike`, `follow`, `unfollow`, `createComment`, `deleteComment`, `getComments`, `block`, `report`; `market:getListings`, `getListing`, `createListing`, `updateListing`, `removeListing`, `markSold`, `contactSeller`; `moderation:getQueue`, `resolve` (each prefixed with its group, for example `social:getFeed`) |

Rate keys per callback are in `server/callbacks.lua` and the `server/modules/*.lua` files; limits are in [Configuration](./configuration.md).

## NUI callbacks

Forwarded to the server callbacks above (for example `contacts:list`, `messages:send`, `bank:getData`, `calls:start`, `gallery:list`, `settings:save`, `security:unlock`, `handset:action`, `social:*`, `market:*`, `moderation:*`, `legacy:*`, `mail:accept`). Handled on the client:

| Callback | Purpose |
| --- | --- |
| `phone:ready`, `phone:close`, `route:changed` | Shell lifecycle; `phone:close` can carry an `error` string shown as a game notification |
| `camera:open`, `camera:close`, `camera:capture`, `camera:zoom`, `camera:facing`, `camera:recording` | In-game camera and screenshots |
| `camera:videoStart`, `camera:videoStop`, `camera:videoFacing`, `camera:coverStart` | Video-call camera |
| `calls:setMuted`, `calls:setSpeaker` | Call audio; muting returns `CALL_MUTE_UNSUPPORTED` because pma-voice has no call-only mute |
| `location:mine`, `waypoint` | Location sharing and waypoints (coordinates limited to 20000 units) |
| `map:blips` | Visible game blips for Maps |
| `weather:get` | Game weather, clock and rain level |
| `notify`, `alarm`, `quiet` | Closed-phone notification, alarm and Do Not Disturb state |
| `customList`, `customLifecycle` | Custom app registry and lifecycle hooks |
