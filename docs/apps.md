---
title: "App SDK developer guide"
sidebar_position: 5.5
---

# App SDK developer guide

> This page describes the **v1 SDK shipped with kora_phone**, checked against `server/sdk/*.lua`, `web/src/sdk/*`, `web/src/apps/custom/CustomApps.tsx` and `sdk/src/*`. Tables of exports, routes and protocol messages are in [App SDK API](./api/apps.md).

## Concepts

A third-party app is a separate FiveM resource that ships a small web UI. The phone shows that UI in a sandboxed iframe at `https://cfx-nui-RESOURCE/ENTRY`, where RESOURCE is the app resource name and ENTRY is the manifest `entry` path. The app talks to the phone through `window.postMessage` (wrapped by the `@kora/phone-sdk` package) and may run its own server logic through per-app callbacks.

- The app is described by a **manifest** (JSON).
- The app declares **permissions**. The phone enforces them on the server, not in the UI.
- The app gets its own **storage** and its own **callbacks**, namespaced by app id.
- Colours, fonts and shape come from `kora_theme` and are pushed into the iframe.

## Folder apps (the recommended way)

An app can live inside this resource, in `apps/<id>/`. No manifest edit, no separate resource and no build step: drop the folder in and restart `kora_phone`.

```text
apps/notes/
  app.lua        Phone.app('notes', { ... })   what the app is (static data, both realms)
  server.lua     optional: server callbacks and events
  client.lua     optional: client callbacks that read game state
  icon.svg       the app icon, one colour
  ui/index.html  the page (plus app.js, app.css, ...)
```

Scaffold one with `node tools/new-app.mjs my-app "My App"`, then run `node tools/check-app.mjs apps/my-app`. The UI follows the [App style guide](./style-guide.md).

### app.lua

```lua
Phone.app('notes', {
    name = 'Notes',
    description = 'A home for your plans, ideas, and little reminders.',
    icon = 'icon.svg',
    category = 'tools',
    permissions = { 'storage' },
    storage = { keys = 128, totalBytes = 512 * 1024 },
    defaultInstalled = true,
})
```

The first argument must equal the folder name; a mismatch stops the phone loading that app. Fields are the manifest fields below, except that `ui` replaces `entry` (a path inside the app folder, default `ui/index.html`) and an `.svg` icon is a file inside the folder. An invalid definition is logged as `phone.app.rejected` and skipped; the other apps still load. An admin can switch an app off with `Config.Apps.<id> = false`.

### server.lua and client.lua

```lua
-- server.lua
local app = Phone.app('notes')
app.callback('save', function(source, payload) return { saved = true } end)   -- UI: phone.callback('save', data)
app.callback('list', function(source) return Phone.unwrap(KoraPhone.Services.Garage.list(source)) end)  -- raises a failed service result as the UI error
app.callback('pay', handler, { rate = 'bankTransfer' })                         -- also charge a strict Config.Server.RateLimits bucket
app.send(source, 'refresh', { n = 1 })                                         -- UI: phone.on('refresh', fn)
app.notify(source, 'Title', 'Body')
local value = app.getStorage(source, 'key')   -- also setStorage, removeStorage, listStorage
```

```lua
-- client.lua
local app = Phone.app('weather')
app.client('get', function(payload) return KoraPhone.World.Weather() end)     -- UI: phone.client('get')
app.on('refresh', function(data) end)       -- server app.send, handled in Lua
app.push('refresh', data)                   -- Lua to the open UI
```

`app.callback` handlers run behind the same gate as every SDK callback (character loaded, phone held, PIN unlocked, app installed). `app.client` handlers have no server gate: they run on the player's own client.

### The dock

If a folder app's id is one of the dock ids (`phone`, `messages`, `contacts`, `camera`, `gallery`) the phone shows it in the dock instead of the grid, in the default dock order. An app opened with `phone.open('phone', number)` receives that target as `init.target` (`phone.init.target` after `ready()`).

### Events from the phone

The phone forwards `messages:new` and `messages:read` to an open Messages app as app events (`phone.on('messages:new', fn)`). A wide app area (an unfolded Atlas Fold) shows list and detail together when the page uses the kit's `kp-split`, as Messages does.

### The UI kit

An app page loads the kit from the phone, with no build step:

```html
<link rel="stylesheet" href="/sdk/runtime/kora-ui.css">
<script type="module">
    import { phone, ready, h, render, states, load, toast, confirm, menu, prompt, popup, icon, i18n } from '/sdk/runtime/kit.js';
</script>
```

`phone` is the SDK client (`phone.callback`, `phone.client`, `phone.open(app, target)` to open another app, `phone.call(number)` to start a call (the phone's own call screen takes over), `phone.refresh()` to make the phone reload its own copy of shared data such as contacts,  `phone.storage.get/list/set/remove`, `phone.contacts`, `phone.notify`). `h` builds elements without `innerHTML`. See the [style guide](./style-guide.md) for the CSS classes.

### Trust

Folder apps are trusted code. Their Lua runs in this resource's VM, and their page is served from this resource's own origin, so it can reach the phone's own NUI callbacks. The manifest `permissions` are enforced for the SDK requests an iframe sends (`storage`, `notify`, contacts), and for apps from other resources; they do not sandbox a folder app's Lua. Treat adding a folder to `apps/` like starting a resource.

### Built-in apps

Notes, Calculator, Weather, Wallet (`banking`), Mail (`mail`), Moderation (`moderation`, a `staff` app), Market (`classifieds`), Contacts, Phone, Messages and Gallery (in the dock), Garage (`vehicles`), Home (`property`) and Work (`services`) ship as folder apps and are the reference implementations: `notes` for storage, `calculator` for pure UI, `weather` and `property` for `client.lua`, and `vehicles`, `property` and `services` for wrapping an existing server service with `Phone.unwrap`. The remaining built-in apps (Camera, Settings, Maps, Pulse, Flash, Clock, Sound) are still compiled into the host UI and move into `apps/` one at a time as they gain the services they need; see `patchnotes.md`.

## Other ways to register an app

The two ways below are for apps that live in their own resource. They produce the same manifest.

### Registering from another resource

There are two ways; both produce the same manifest object.

1. Metadata: add `kora_phone_app 'app.json'` to the app resource's `fxmanifest.lua`. When that resource starts (`onServerResourceStart`), and for resources already running when the phone starts, the phone reads the metadata and loads the JSON with `LoadResourceFile`. The file must be valid JSON of at most 16 KB. A resource can declare several `kora_phone_app` entries. The phone resource itself is never scanned.
2. Export: call `exports.kora_phone:RegisterApp(manifest)` from server code. The resource is the invoking resource.

Rules for both:

- An id is owned by the first resource that registers it. The same resource may register it again (for example after a restart); another resource gets `(false, 'CONFLICT: app id ID is owned by RESOURCE')`.
- Invalid manifests are rejected with `(false, 'INVALID_MANIFEST: reason')`. Metadata rejections are also logged as `phone.sdk.manifest_rejected`.
- The `entry` file must be covered by the app resource's `file` or `files` patterns; otherwise registration fails with `INVALID_MANIFEST: entry ... is not listed in the files of ...`. Every asset the entry loads must be listed too (that part is up to you).
- Registrations are removed when the app resource stops (`onResourceStop`), together with the app's callbacks. A registration does not survive a phone restart on its own: apps are found again by rescanning started resources, so an app registered only through the export must register again.

## Manifest reference

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `id` | string | yes | Pattern `^[a-z0-9][a-z0-9_-]{1,31}$` (2 to 32 characters), globally unique |
| `name` | string | yes | Not empty, at most 24 characters |
| `description` | string | no | At most 120 characters; empty when omitted |
| `icon` | string | yes | A lucide icon name (lowercase letters, digits and hyphens, at most 48 characters), an `https://` URL, or `nui://resource/path` without `..` |
| `entry` | string | yes | Relative path of an `.html` or `.htm` file inside the app resource, for example `ui/index.html`. At most 200 characters of letters, digits, `_`, `-`, `.` and `/`; no leading slash, `..` or `//` |
| `version` | string | yes | Not empty, at most 32 characters |
| `permissions` | array | no | Subset of the permissions below; empty when omitted. Duplicates are dropped |
| `job` | string, table or array | no | A job name, or a table with `name` and optional `grade` (the minimum one-based grade, as in kora_core), or an array of those. Display filter only |
| `defaultInstalled` | boolean | no | Whether the app counts as installed until the player installs or removes it. `false` when omitted |
| `price` | number | no | Non-negative number. Display only: nothing charges it |
| `category` | string | no | `tools` (default), `life`, `social`, `games` or `system`. Used by the App Store filters |
| `staff` | boolean | no | `true` shows and serves the app to moderators only (the same check as the moderation queue), enforced on the server for every call. `false` when omitted |
| `system` | boolean | no | `true` hides the Remove button in the App Store. `false` when omitted |
| `storage` | table | no | Raises the storage quota: `keys` up to 512 and `totalBytes` up to 1048576 (1 MB). Defaults are 64 keys and 128 KB |

Unknown fields or unknown permissions reject the registration.

Job grades in a manifest are one-based, the same as kora_core's native grade level, and are compared the same way on the server (`Registry.jobMatches`) and in the client registry used for client-registered apps.

## Permissions

| Permission | Enforced for |
| --- | --- |
| `notify` | `apps:notify` (the iframe request `notify`) |
| `storage` | `apps:storage:get`, `apps:storage:list`, `apps:storage:set`, `apps:storage:remove` |
| `contacts.read` | `apps:contacts:list` |
| `contacts.write` | `apps:contacts:save` |
| `media.read` | Accepted in manifests, but no route checks it yet: it grants nothing |
| `location` | Accepted in manifests, but no route checks it yet: it grants nothing |
| `payments` | Accepted in manifests, but no route checks it yet: it grants nothing |

`apps:call` (server callbacks) and the install routes need no permission, only a registered, installed app.

## Server API

Server exports of the phone resource:

```lua
local ok, err = exports.kora_phone:RegisterApp({
    id = 'hello',
    name = 'Hello',
    description = 'Counter demo',
    icon = 'smile',
    entry = 'ui/dist/index.html',
    version = '1.0.0',
    permissions = { 'storage', 'notify' },
    defaultInstalled = true,
})

exports.kora_phone:RegisterAppCallback('hello', 'ping', function(source, payload)
    return { pong = true, echo = payload }
end)

exports.kora_phone:SendAppEvent(source, 'hello', 'tick', { n = 1 })
local installed = exports.kora_phone:GetInstalledApps(source)
exports.kora_phone:RemoveApp('hello')
```

- `RegisterAppCallback` returns `(true)` or `(false, 'CODE: reason')` with `NOT_FOUND`, `FORBIDDEN` (the app belongs to another resource) or `INVALID_INPUT`. Callback names match `^[a-zA-Z0-9_:.-]{1,48}$`. Registering the same name again replaces the handler.
- The handler receives `(source, payload)` and returns a JSON-able value. An error in the handler, a value that cannot be encoded, or a result larger than 64 KB is answered with an internal error.
- Each callback is reachable two ways, through the same gate (character loaded, phone held, PIN unlocked if a PIN is set, app registered and installed): the `apps:call` route used by the SDK client, and the kora_lib callback `app:ID:NAME`. The kora_lib callback is limited to 30 calls per 10 seconds per player and callback; the `apps:call` route uses the `sdk` bucket ([Configuration](./configuration.md)).
- `SendAppEvent(source, appId, name, data)` returns `false` unless the caller owns the app, `source` is a player id and the name is valid. It sends the client event `kora_phone:client:appEvent`; the NUI forwards it to that app's iframe as an `event` message. It does not check that the player has the app open or installed.
- `RemoveApp(id)` only works for the owning resource.
- `GetInstalledApps(source)` returns the ids of registered apps installed on that player's phone (an empty list when no character or phone).

Only the resource that registered an app id may register callbacks for it. Callbacks are cleaned up when the app is removed or its resource stops. Internally they are named `app:ID:NAME`.

## Install state

Install state is stored per phone in the device settings (`sdkApps`). An app with no stored choice follows its manifest `defaultInstalled`; installing or uninstalling records an explicit choice. `apps:list` returns every installed app plus the not-installed apps whose `job` filter matches the player's job. `apps:install` and `apps:uninstall` work on any registered app: the job filter is display-only and is not checked there.

## Client lifecycle

The `ready` request tells the host the iframe has loaded. The host answers, then pushes `init` with the app id, handset (`standard`, `flip` or `fold`), locale, theme and granted permissions. Later it pushes `theme` when the theme changes, `event` for `SendAppEvent` data, and `visibility` when the phone page is shown or hidden. If no `ready` arrives within 10 seconds the screen shows an error with a retry button; if the app resource stops, the screen says the app is offline.

Client-side apps registered through the client exports (`RegisterApp`, `RemoveApp`, `SendAppMessage`, with `onOpen`, `onClose`, `onInstall` and `onDelete` hooks) and the lb-phone, sd-phone, 17mov_Phone, yseries and high-phone aliases keep working and share the same list in the UI, but have no server permissions, storage or callbacks.

## Security model

- **Server-side enforcement.** Every `apps:*` call is rate limited, needs a loaded character holding a phone (and an unlocked session when a PIN is set), needs the app to be registered and installed for that device, and has its permission checked on the server against the registered manifest. The UI cannot grant itself permissions.
- **Sandbox.** The iframe uses `sandbox="allow-scripts allow-same-origin allow-forms"` and `referrerpolicy="no-referrer"`. There is no top navigation and no popups.
- **Origin checks.** The host accepts messages only when `event.source` is the iframe window and `event.origin` is `https://cfx-nui-RESOURCE`. The SDK client accepts messages only from its parent window and the host origin (default `https://cfx-nui-kora_phone`).
- **Storage quotas.** By default 64 keys per app per device, 16 KB per value (JSON encoded), 128 KB total per app per device. The manifest `storage` field raises keys and total size (up to 512 keys and 1 MB); the value limit stays 16 KB. Keys are 1 to 64 characters from letters, digits, `_`, `.`, `:` and `-`.
- **Callback ownership.** Only the registering resource may add callbacks for an app id.
- **Field limits.** Notification title at most 48 and body at most 200 characters; contact name at most 64, number 3 to 24 characters of digits, `+`, `-`, spaces and brackets.

## Theming

The host resolves kora_theme CSS custom properties from its own document and sends them in `init` and `theme`. The set is fixed in `web/src/sdk/theme.ts`: the colour roles (`--background`, `--foreground`, `--card`, `--primary`, `--primary-foreground`, `--secondary`, `--muted`, `--accent`, `--border`, `--input`, `--ring`, `--surface`, `--surface-raised`, the success, warning, destructive and info families, and others), fonts (`--font-sans`, `--font-heading`, `--font-mono`), spacing, radii (`--radius`, `--radius-sm`, `--radius-lg`), shadows and motion. Colour values are HSL triplets such as `84 100% 50%`, so use them as `hsl(var(--primary))`. The `scheme` is `dark` or `light`, derived from the lightness of `--background`. The SDK client writes the variables onto the iframe `:root` and sets `color-scheme`. Do not hard-code colours or fonts.

The package also ships `theme.css`, which defines friendly aliases over the real forwarded tokens, each wrapped in `hsl()` with a neutral fallback that applies until `init` arrives: `--kp-bg`, `--kp-fg`, `--kp-surface`, `--kp-surface-raised`, `--kp-muted`, `--kp-accent`, `--kp-accent-fg`, `--kp-border`, `--kp-danger`, `--kp-success`, `--kp-radius`, `--kp-font`, `--kp-font-heading` and `--kp-font-mono`. It also styles `body`, `.kora-surface` and `.kora-button`. Use the aliases (for example `background: var(--kp-bg)`) or build your own rules on `hsl(var(--background))`.

## Using the SDK

Vanilla:

```ts
import { createPhoneClient } from '@kora/phone-sdk';

const phone = createPhoneClient();
await phone.ready();
const result = await phone.callback('ping', { hello: 1 });
await phone.storage.set('count', 3);
phone.on('tick', (data) => console.log(data));
```

React:

```tsx
import { PhoneProvider, usePhoneCallback, usePhoneStorage } from '@kora/phone-sdk/react';

function Counter() {
    const { value, set } = usePhoneStorage<number>('count');
    const ping = usePhoneCallback('ping');
    return <button onClick={() => set(Number(value ?? 0) + 1)}>Tap</button>;
}

export function App() {
    return <PhoneProvider><Counter /></PhoneProvider>;
}
```

The client surface is `ready()`, `theme`, `init`, `callback`, `client`, `notify`, `storage` (`get`, `list`, `set`, `remove`), `contacts` (`list`, `save`), `on`, `onTheme`, `onVisibility`, `close`, `setTitle`, `haptic`, `getContext` and `destroy`. Requests time out after 10 seconds by default (`timeoutMs`) with a `PhoneError` of code `TIMEOUT`. The React entry adds `PhoneProvider`, `usePhone`, `useTheme`, `usePhoneCallback` (returns `data`, `loading`, `error` and `call`) and `usePhoneStorage` (returns `value`, `loading`, `error`, `set` and `remove`). See `examples/hello-app/` for a complete resource and `sdk/README.md` for the package.

## Known gaps

- `media.read`, `location` and `payments` are declared but gate nothing (see Permissions).
- `apps:notify` shows a game notification only; it does not add a card to the phone's notification shade.

## Packaging checklist

1. `app.json` is valid and referenced by `kora_phone_app` in `fxmanifest.lua`.
2. `dependency 'kora_phone'` is present.
3. Built UI (`ui/dist`) and `app.json` are listed in `files`.
4. Request only the permissions you use.
5. Server callbacks validate their payload; never trust the client.
6. No hard-coded colours; the UI follows the theme.
7. Build output is generated at release time and not committed.

## Migration from lb-phone and sd-phone aliases

lb-phone apps need no migration: see [lb-phone apps](./lb-phone.md) for what is supported.


The existing alias exports for `lb-phone`, `sd-phone`, `17mov_Phone`, `yseries` and `high-phone` remain and feed the same registry as the client `RegisterApp`. Such apps get UI and their own resource logic only, with no server permissions. To use storage, contacts, notifications or server callbacks, move the app to the manifest model above. The legacy bridge `web/dist/compat.js` keeps `fetchNui`, `onNuiEvent`, `onSettingsChange`, `resourceName`, `appName` and `settings` working for old addons.
