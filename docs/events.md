---
title: Events and callbacks
sidebar_position: 10
---

# Events and callbacks

The NUI talks to the client through NUI callbacks. The client forwards most of them to the server through `Kora.callback` (`kora_lib`) under the name `kora_phone:server:` plus the callback name. Every route in `shared/routes.json` is rate limited (one shared sliding window per rate key and player), runs inside the handset lock (SDK `apps:*` calls skip the lock so an app can overlap requests) and fails with `Handset session changed` if the character or selected handset changes while it runs. Results are `{ ok = true, data = ... }` or `{ ok = false, error = { code, message } }`.

## Server events (client to server)

| Event | Purpose |
| --- | --- |
| `kora_phone:server:phone:closed` | The phone was closed: ends the player's call and re-locks the session |
| `kora_phone:server:calls:hangup` | Hang up call id (rate limited) |
| `kora_phone:server:calls:voiceFailure` | The client could not join the voice channel for a call id |

See [System mail](./system-mail.md) for the mail exports.

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
| `kora_phone:client:activity:new` | `citizenId` | A system activity note was stored; the Mail app refreshes its Activity list |
| `kora_phone:client:calls:incoming` / `outgoing` / `accepted` / `ended` | call table | Call lifecycle |
| `kora_phone:client:calls:signal` | WebRTC offer, answer or ICE | Video signalling |
| `kora_phone:client:calls:videoControl` | `id`, `action`, `epoch` | Video upgrade control |
| `kora_phone:client:share:request` | `id`, `label`, `number`, `expiresIn`, `shareBack` | Share-your-number prompt |
| `kora_phone:client:wallet:shown` | ID card | Someone showed you their ID |
| `kora_phone:client:openServices`, `serviceRequest`, `serviceResult` | | Service counter UI |
| `kora_phone:client:appEvent` | `appId`, `name`, `data` | SDK app event (from `SendAppEvent`); forwarded to the NUI as `app:event` |
| `kora_phone:client:appNotify` | `appId`, `appName`, `title`, `body` | SDK app notification (from `apps:notify`); shows a game notification only |

The client also listens to the local kora_core events `kora_core:client:playerLoaded` and `kora_core:client:playerLoggedOut`, subscribes to kora_core's player-data mirror (`job`, `money`, `metadata`) through `exports.kora_core:onPlayerDataChange`, watches `Kora.cache.onChange('isDead')`, and listens to `kora_lib:blips:changed`. The server listens to `kora_core:server:playerUnloaded` (arguments: source, citizen id, cause `logout` or `disconnect`), `playerDropped` and `onResourceStop`, plus `onServerResourceStart` to discover SDK apps.

## Server callbacks (`kora_phone:server:<name>`)

Every NUI route that forwards to a server callback is listed once in `shared/routes.json` (NUI name, server callback, rate-limit key and optional app gate). `client/nui.lua` registers one NUI callback per entry and the web bundle imports the same file.

| Area | Names |
| --- | --- |
| Phone | `getBootstrap`, `saveSettings`, `unlockPhone`, `lockPhone`, `setPhonePin`, `removePhonePin`, `hasPhone` |
| Handsets | `handsetAction` (ops: `status`, `select`, `faceUnlock`, `faceEnroll`, `wifi`, `insertSim`, `removeSim`, `registerCloud`, `backup`, `restoreCloud`, `reset`, and service ops `buy`, `recoverCloud`, `replaceSim`, `resell`, `consent`) |
| Contacts and sharing | `getContacts`, `saveContact`, `deleteContact`, `share:offer`, `share:answer` |
| Messages | `sendMessage`, `getMessages`, `getConversations`, `startDirectConversation`, `markConversationRead`, `deleteMessageForSelf`, `createGroup`, `leaveGroup`, `addGroupMember`, `getBlocked`, `setBlocked` |
| Calls | `calls:start`, `calls:accept`, `calls:reject`, `calls:hangup`, `calls:signal`, `calls:videoControl` |
| Mail | `getMail`, `sendMail`, `readMail`, `deleteMail` |
| Media | `requestMediaUpload`, `completeMediaUpload`, `getGallery` |
| Utilities | `saveItem`, `removeItem` |
| Apps (SDK) | `apps:list`, `apps:install`, `apps:uninstall`, `apps:call`, `apps:storage:get`, `apps:storage:list`, `apps:storage:set`, `apps:storage:remove`, `apps:contacts:list`, `apps:contacts:save`, `apps:notify` (see [App SDK API](./api/apps.md)) |
| Community | `social:createAccount`, `getFeed`, `getProfile`, `createPost`, `deletePost`, `toggleLike`, `follow`, `unfollow`, `createComment`, `deleteComment`, `getComments`, `block`, `report` (each prefixed with its group, for example `social:getFeed`) |

The gateway in `server/callbacks.lua` registers one callback per `server` name in `shared/routes.json` and takes the rate key and app gate from there. Two callbacks the NUI never calls are registered in code: `share:offer` (rate key `shareNumber`, called by the client's third-eye option) and `hasPhone` (no rate limit; the client uses it to tell a downed player without a phone from one who cannot use it). Modules only bind handlers with `KoraPhone.Routes.handle(name, handler)`; a handler can be bound before or after the gateway loads. The `apps:*` routes (SDK) and `mail:system:*` routes (system mail) are bound the same way. Limits are in [Configuration](./configuration.md).

## NUI callbacks

Forwarded to the server callbacks above, using the NUI names in `shared/routes.json` (for example `contacts:list`, `messages:send`, `calls:start`, `gallery:list`, `settings:save`, `security:unlock`, `handset:action`, `social:*`, `moderation:*`, `apps:*`, `mail:system:*`). Handled on the client:

| Callback | Purpose |
| --- | --- |
| `phone:ready`, `phone:close`, `route:changed` | Shell lifecycle; `phone:close` can carry an `error` string shown as a game notification |
| `camera:open`, `camera:close`, `camera:capture`, `camera:zoom`, `camera:facing`, `camera:recording` | In-game camera and screenshots |
| `camera:videoStart`, `camera:videoStop`, `camera:videoFacing`, `camera:coverStart` | Video-call camera |
| `calls:setMuted`, `calls:setSpeaker` | Call audio; muting calls `exports.kora_voice:setCallMuted` (call-only microphone mute) and returns `ok` or an `error` reason such as `not_in_call`; speaker is a presentation flag only |
| `location:mine`, `waypoint` | Location sharing and waypoints (coordinates limited to 20000 units) |
| `map:blips` | Visible game blips for Maps |
| `weather:get` | Game weather, clock and rain level |
| `notify`, `alarm`, `quiet` | Closed-phone notification, alarm and Do Not Disturb state |
| `customList`, `customLifecycle` | Custom app registry and lifecycle hooks |
