---
title: Exports
sidebar_position: 8
---

# Exports

## Server exports (`exports.kora_phone`)

| Export | Signature | Returns |
| --- | --- | --- |
| `GetPhoneNumber` | `(source)` | The selected handset's active SIM number, or `nil` without a handset or SIM |
| `GetSourceByPhoneNumber` | `(phoneNumber)` | The online player source holding that number, or `nil` |
| `SendNotification` | `(target, notification)` | `true` after sending the `kora_phone:client:notification` event to `target`; `false` if the arguments are not a number and a table. `notification` fields: `app` (32 chars), `title` (80), `body` (240), `data` |
| `sendNewMailToOffline` | `(citizenId, data)` | Nothing (void). Trusted legacy mail; also provided as `exports['qb-phone']:sendNewMailToOffline`. See [Legacy qb-phone support](./legacy-compat.md) |
| `CanResellHandset` | `(source, slot)` | `true` when the handset in that slot is factory reset, has no SIM, account, PIN or Face ID, and holds no local content |
| `randomHex` | `(bytes)` | Random hex string (16 to 64 bytes). Used internally via the resource's own exports |
| `pinHash` / `pinVerify` | `(pin)` / `(pin, stored)` | Salted scrypt PIN hash and constant-time verify, mixed with the `kora_phone_pin_pepper` convar. Internal helpers |
| `turnCredentials` | `(subject)` | Time-limited TURN REST credentials, or `nil` when `kora_phone_turn_secret` is unset. Internal helper |

`randomHex`, `pinHash`, `pinVerify` and `turnCredentials` are defined in `server/crypto.js` and are callable by any server resource; they exist for the phone's own use.

## Client exports

| Export | Signature | Behaviour |
| --- | --- | --- |
| `OpenPhone` | `(app, payload)` | Opens the phone, optionally on an app. Returns `false` if already open, the character is not loaded, the player is down or the UI is blocked by `Config.Client.UiBlockBag` |
| `ClosePhone` | `()` | Closes the phone |
| `IsPhoneOpen` | `()` | `true` while open |
| `PushNotification` | `(notification)` | Shows a notification in the phone; also a game notification when the phone is closed. `title` is required (80 chars), `message` optional (500). Optional `app`, `urgent`, `native` (`false` suppresses the game notification). Returns `false` if invalid |
| `RegisterMapBlip` | `(blipHandle, title)` | Lists a blip in the Maps app under the given title (160 chars). Fails if the blip does not exist or another resource already registered it. Entries are removed when the owning resource stops |
| `UnregisterMapBlip` | `(blipHandle)` | Removes a blip registered by the calling resource |
| `RegisterApp` | `(app)` | Registers a custom app. Required: `identifier`, `ui`. Optional: `name`, `description`, `resource`, `icon`, `defaultApp`, `job`, `price` (display only, never charged), `onOpen`, `onClose`, `onInstall`, `onDelete`. Returns `true`, or `false` plus `INVALID_APP` or `INVALID_UI` |
| `RemoveApp` | `(identifier)` | Unregisters a custom app |
| `SendAppMessage` | `(identifier, data)` | Sends data to a registered custom app's UI |

Maps also mirrors the visible blips registered through `kora_lib`; see [Features](./features.md).

## Phone-alias exports

`client/customapps.lua` answers the export names other phone resources use, through `__cfx_export_` handlers, and `fxmanifest.lua` declares `provide` for each. A custom app written for one of them can register unmodified:

| Resource name | Functions answered |
| --- | --- |
| `lb-phone` | `AddCustomApp`, `RemoveCustomApp`, `SendCustomAppMessage`, `SendNotification` |
| `sd-phone` | `addCustomApp`, `removeCustomApp`, `sendCustomAppMessage` |
| `17mov_Phone` | `AddApplication`, `RemoveApplication`, `SendAppMessage` |
| `yseries` | `AddCustomApp`, `RemoveCustomApp`, `SendAppMessage` |
| `high-phone` | `addApplication`, `removeApplication`, `sendAppNui`, `sendNotification` |

The `SendNotification` aliases show a game notification only; they do not create a shade notification. `web/dist/compat.js` (source `web/public/compat.js`) can be added as a script tag in a custom app UI to provide the `fetchNui`, `onNuiEvent`, `resourceName`, `appName` and `settings` data bridge. Job gating on custom apps is a display filter, not a security boundary.

On the server, `Kora.compat.provideExport('qb-phone', 'sendNewMailToOffline', ...)` makes `exports['qb-phone']:sendNewMailToOffline` resolve to this resource.
