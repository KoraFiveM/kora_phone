---
title: "Cross-resource exports & events"
sidebar_position: 2
---


# Cross-resource exports & events

## Client

What another client resource can call or listen for: opening/closing the local phone, pushing a notification into it, and registering a custom app (native, or through another phone ecosystem's export names).

Namespace: `exports.kora_phone / kora_phone:client:*` · Source: `client/main.lua, client/customapps.lua, client/notifications.lua, client/map.lua`

### Functions

4 open/close/notify exports, 3 custom-app exports (plus 5 aliased ecosystems), 2 map-blip exports, and net events like `kora_phone:client:notification`, `kora_phone:client:serviceRequest`/`serviceResult`, `kora_phone:client:wallet:shown`.

#### `exports.kora_phone:OpenPhone(app?, payload?) / ClosePhone() / IsPhoneOpen() / PushNotification(notification)`

Client-side exports to drive the LOCAL phone from another client script.

**Parameters**



**Returns**

- **`OpenPhone` returns `boolean` (opened or not). `IsPhoneOpen` returns `boolean`. `ClosePhone`/`PushNotification` return nothing meaningful beyond their side effect.**

**Example**

```lua
exports.kora_phone:OpenPhone('messages')
```

**Representative console output**

```text
Equivalent to pressing the phone keybind, but can target a specific app and payload.
```

#### `exports.kora_phone:RegisterApp({ identifier, ui, name?, description?, icon?, defaultApp?, job?, price?, onOpen?, onClose?, onInstall?, onDelete? }) / RemoveApp(identifier) / SendAppMessage(identifier, data)`

Client-side custom-app registry (`client/customapps.lua`). Lets another resource add an installable app to the Store/home screen and push it messages.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `app` | table | See signature; `identifier` and `ui` are required. |

**Returns**

- **`RegisterApp`/`RemoveApp`/`SendAppMessage` return `true`, or `false, reason` (`INVALID_APP`, `INVALID_UI`, `NOT_FOUND`).**

**Example**

```lua
exports.kora_phone:RegisterApp({ identifier = 'mygarage', name = 'My Garage', ui = 'web/index.html' })
```

**Representative console output**

```text
Also reachable through the export/event names of lb-phone, sd-phone, 17mov_Phone, yseries and high-phone (aliased onto `__cfx_export_<resource>_<fn>`), so an addon app written for one of those registers here unmodified. `job` on a registered app is a DISPLAY filter only — never a security boundary.
```

#### `exports.kora_phone:RegisterMapBlip(handle, title)`

Makes a blip created with plain GTA natives appear in the phone's Maps app. Blips created with `Kora.blips` are listed automatically.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handle` | integer | An existing blip handle. |
| `title` | string | The label to show: not blank, at most 160 bytes. |

**Returns**

- **`boolean`** — `true` when registered; `false` for an invalid handle or title, or when another resource already registered that blip.

**Example**

```lua
local blip = AddBlipForCoord(215.0, -810.0, 30.7)
exports.kora_phone:RegisterMapBlip(blip, 'Garage')
```

**Representative console output**

```text
The blip is listed in the Maps app, with its colour and position, for as long as it exists. A blip that is hidden or fully transparent is not listed. Registrations are removed automatically when the registering resource stops.
```

#### `exports.kora_phone:UnregisterMapBlip(handle)`

Removes a map-blip registration the calling resource made with `RegisterMapBlip`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handle` | integer | The blip handle that was registered. |

**Returns**

- **`boolean`** — `true` when the registration was removed; `false` when it does not exist or belongs to another resource.

**Example**

```lua
exports.kora_phone:UnregisterMapBlip(blip)
```

**Representative console output**

```text
The blip itself is not deleted; it just stops being listed (unless it was created with `Kora.blips`).
```

## Server

Server-side exports: resolve a phone number for/from a player, push a notification to one, and deliver mail to a character even while they are offline.

Namespace: `exports.kora_phone / kora_phone:client:*` · Source: `server/main.lua, server/compat/qb-phone.lua`

### Functions

4 server exports.

#### `exports.kora_phone:GetPhoneNumber(source)`

The phone number of the handset currently selected by that player, if it has an active cellular SIM.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `source` | integer |  |

**Returns**

- **`string | nil`** — the phone number, or `nil` with no active cellular handset.

**Example**

```lua
local number = exports.kora_phone:GetPhoneNumber(src)
```

**Representative console output**

```text
Server-side only.
```

#### `exports.kora_phone:GetSourceByPhoneNumber(phoneNumber)`

Reverse lookup: which online player currently holds a given phone number.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `phoneNumber` | string |  |

**Returns**

- **`integer | nil`** — server id, or `nil` for an invalid number or nobody online holding it.

**Example**

```lua
local src = exports.kora_phone:GetSourceByPhoneNumber('5550109999')
```

**Representative console output**

```text
Validates the number shape first (`PhoneValidation.phoneNumber`) before looking it up.
```

#### `exports.kora_phone:SendNotification(target, { app?, title?, body?, data? })`

Pushes a phone notification to a specific player from another resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target` | integer |  |
| `notification` | table | `{ app? (truncated 32 chars), title? (truncated 80), body? (truncated 240), data? (table) }`. |

**Returns**

- **`boolean`** — `false` only for bad argument types; otherwise always `true` (it does not confirm the client received it).

**Example**

```lua
exports.kora_phone:SendNotification(src, { app = 'dispatch', title = 'New call', body = 'Robbery in progress near Legion Square.' })
```

**Representative console output**

```text
Fires `kora_phone:client:notification`, which `client/notifications.lua` turns into an in-phone push and (if the phone is closed and not Do Not Disturb-silenced) a native on-screen alert.
```

#### `exports.kora_phone:sendNewMailToOffline(citizenId, { sender, subject, message, button? })`

Delivers a mail to a character's Mail app by citizen id, whether or not that player is online.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `citizenId` | string | The character's citizen id (at most 64 bytes). |
| `data` | table | `sender` (up to 100 bytes), `subject` (up to 120) and `message` (up to 16000) are required. HTML tags are stripped from `message`, with `<br>` and `</p>` becoming line breaks. Optional `button = { enabled?, buttonEvent, buttonData }` adds a button. |

**Returns**

- **No return value; invalid input is silently ignored.**

**Example**

```lua
exports.kora_phone:sendNewMailToOffline(citizenId, {
    sender = 'Los Santos Bank',
    subject = 'Statement ready',
    message = 'Your monthly statement is available.',
})
```

**Representative console output**

```text
The mail is stored for the character. If that player is online, their phone also receives a `kora_phone:client:mail:new` event. Also reachable as `exports['qb-phone']:sendNewMailToOffline`.
```

### Limits and related APIs

`SendNotification` fires the client event unconditionally — it does not confirm the target's phone is reachable or that the resource is even running on their client.

## Additional exports and aliases

Reference of every export, including those not covered above: client and server tables, internal helpers and the phone-alias exports.

### Server exports (`exports.kora_phone`)

| Export | Signature | Returns |
| --- | --- | --- |
| `GetPhoneNumber` | `(source)` | The selected handset's active SIM number, or `nil` without a handset or SIM |
| `GetSourceByPhoneNumber` | `(phoneNumber)` | The online player source holding that number, or `nil` |
| `SendNotification` | `(target, notification)` | `true` after sending the `kora_phone:client:notification` event to `target`; `false` if the arguments are not a number and a table. `notification` fields: `app` (32 chars), `title` (80), `body` (240), `data` |
| `sendNewMailToOffline` | `(citizenId, data)` | Nothing (void). Trusted legacy mail; also provided as `exports['qb-phone']:sendNewMailToOffline`. See [Legacy qb-phone support](../legacy-compat.md) |
| `CanResellHandset` | `(source, slot)` | `true` when the handset in that slot is factory reset, has no SIM, account, PIN or Face ID, and holds no local content |
| `randomHex` | `(bytes)` | Random hex string (16 to 64 bytes). Used internally via the resource's own exports |
| `pinHash` / `pinVerify` | `(pin)` / `(pin, stored)` | Salted scrypt PIN hash and constant-time verify, mixed with the `kora_phone_pin_pepper` convar. Internal helpers |
| `turnCredentials` | `(subject)` | Time-limited TURN REST credentials, or `nil` when `kora_phone_turn_secret` is unset. Internal helper |

`randomHex`, `pinHash`, `pinVerify` and `turnCredentials` are defined in `server/crypto.js` and are callable by any server resource; they exist for the phone's own use.

### Client exports

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

Maps also mirrors the visible blips registered through `kora_lib`; see [Features](../features.md).

### Phone-alias exports

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
