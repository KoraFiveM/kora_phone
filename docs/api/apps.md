---
title: "App SDK API reference"
sidebar_position: 3
---

# App SDK API reference

This page describes the **v1 SDK shipped with kora_phone**. See the [developer guide](../apps.md) for concepts, the manifest fields and the limits.

## Exports (server)

| Export | Signature | Returns |
| --- | --- | --- |
| `RegisterApp` | `exports.kora_phone:RegisterApp(manifest)` | `true`, or `false, err` where `err` is `INVALID_MANIFEST: reason` or `CONFLICT: app id ID is owned by RESOURCE` |
| `RemoveApp` | `exports.kora_phone:RemoveApp(id)` | `true` when removed; `false` for an unknown id or an app owned by another resource |
| `RegisterAppCallback` | `exports.kora_phone:RegisterAppCallback(appId, name, handler)` | `true`, or `false, err` (`NOT_FOUND`, `FORBIDDEN`, `INVALID_INPUT` followed by a reason). `handler(source, payload)` returns a JSON-able value of at most 64 KB |
| `SendAppEvent` | `exports.kora_phone:SendAppEvent(source, appId, name, data)` | `true` after sending the client event `kora_phone:client:appEvent`; `false` for a bad source, an app the caller does not own, or an invalid name |
| `GetInstalledApps` | `exports.kora_phone:GetInstalledApps(source)` | Array of installed app ids (empty without a character or phone) |

Manifest metadata key in `fxmanifest.lua`: `kora_phone_app 'app.json'` (JSON file of at most 16 KB, one key per app).

## Routes

Every route uses the `sdk` rate bucket, needs a loaded character holding a phone (and an unlocked session when a PIN is set), and, except `apps:list`, needs an app that is registered and installed for the device. Permissions are checked on the server against the registered manifest. Responses are `{ ok, data }` or `{ ok = false, error }`; the table shows `data`.

| Route | Payload | Permission | `data` |
| --- | --- | --- | --- |
| `apps:list` | none | none | `{ apps }`: each app has `id`, `name`, `description`, `icon`, `entry`, `version`, `permissions`, `job`, `defaultInstalled`, `price`, `resource`, `url` and `installed` |
| `apps:install` | `id` | none | `{ id, installed = true }` (needs only a registered app; the job filter is not checked) |
| `apps:uninstall` | `id` | none | `{ id, installed = false }` |
| `apps:call` | `app`, `name`, `payload` | none | The callback's return value |
| `apps:storage:get` | `app`, `key` | `storage` | `{ value }` (nil when the key is missing) |
| `apps:storage:list` | `app`, `prefix` (optional) | `storage` | `{ values }`, an object of every key starting with the prefix |
| `apps:storage:set` | `app`, `key`, `value` | `storage` | `{ saved = true }` |
| `apps:storage:remove` | `app`, `key` | `storage` | `{ removed = true }` |
| `apps:contacts:list` | `app` | `contacts.read` | `{ contacts }` with `id`, `name`, `number` per contact |
| `apps:contacts:save` | `app`, `name`, `number`, optional `id` | `contacts.write` | `{ id }` |
| `apps:notify` | `app`, `title`, `body` | `notify` | `{ sent = true }`; shows a game notification only |

Errors use the phone error codes, for example `NOT_FOUND` (app not registered or callback missing), `FORBIDDEN` (not installed, missing permission, phone locked), `INVALID_INPUT` (bad key, name, title or contact), `CONFLICT` (storage key or size quota) and `RATE_LIMITED`.

The `apps:*` routes skip the per-player handset lock so an app can overlap requests. The kora_lib callback `app:ID:NAME` is registered for each app callback as an alternative entry point, limited to 30 calls per 10 seconds per player and callback.

## Storage table

`phone_app_storage(device_id, app_id, key, value, updated_at)` with primary key `(device_id, app_id, key)`, declared in `server/sdk/schema.lua` and created by `Kora.sql.ensureTables`. Rows are removed with their device. Quotas: 64 keys, 16 KB per value, 128 KB total, per app per device. Storage keys are 1 to 64 characters from letters, digits, `_`, `.`, `:` and `-`.

## Iframe protocol

Messages are JSON sent with `window.postMessage`:

```json
{ "kora": "phone", "v": 1, "id": "uuid", "type": "callback", "payload": {} }
```

Responses use `type` of `response` with `ok: true` and `payload`, or `ok: false` and `error` holding `code` and `message`. Request ids are at most 64 characters. The host answers at most 32 pending requests at a time (`RATE_LIMITED` beyond that) and times a request out after 15 seconds with `TIMEOUT`. A request without the manifest permission gets `PERMISSION_DENIED` from the host before it reaches the server.

### iframe to host (request)

| Type | Payload | Permission |
| --- | --- | --- |
| `ready` | none | none |
| `callback` | `name`, `payload` | none |
| `open` | `app`, `target` (optional) | none (the host opens the app; the target reaches it as `init.target`) |
| `call` | `number` (7 to 16 digits) | none (the host dials through the call service and shows its call screen) |
| `system` | `action` plus fields | system apps of this resource only (`settings.get`, `settings.save`, `pin.set`, `blocks.list`, `blocks.set`, `handset`) |
| `refresh` | none | none (the host reloads the phone data other screens use, for example contacts) |
| `client` | `name`, `payload` | none (answered by the app's `client.lua`, NUI route `apps:client`, never a server call) |
| `lb` | `action` plus fields | lb-phone compatibility pages only: `contacts`, `gallery`, `call`, `openApp` |
| `notify` | `title`, `body` | `notify` |
| `storage.get` | `key` | `storage` |
| `storage.list` | `prefix` (optional) | `storage` |
| `storage.set` | `key`, `value` | `storage` |
| `storage.remove` | `key` | `storage` |
| `contacts.list` | none | `contacts.read` |
| `contacts.save` | `id` (optional), `name`, `number` | `contacts.write` |
| `close` | none | none |
| `setTitle` | `title` (at most 48 characters) | none |
| `haptic` | empty (a no-op) | none |
| `getContext` | none (returns the `init` payload) | none |

The host unwraps the server data so the response `payload` matches the SDK types: `storage.get` answers the stored value or null, `storage.set`, `storage.remove` and `notify` answer true, `contacts.list` answers an array of contacts, `contacts.save` answers the saved contact (`id`, `name`, `number`), `callback` answers the callback's own return value, `haptic` answers true and `getContext` answers the init payload.

### host to iframe (push)

| Type | Payload |
| --- | --- |
| `init` | `appId`, `handset` (`standard`, `flip`, `fold`), `locale`, `theme` (`vars`, `scheme` of `dark` or `light`), `permissions` |
| `theme` | `vars`, `scheme` |
| `event` | `name`, `data` |
| `visibility` | `visible` |

`init` is also sent right after the response to `ready`. Besides app events, the host forwards the device settings to legacy addons as an `event` named `kora:settings`.

## NPM package

`@kora/phone-sdk` (directory `sdk/`, version in `sdk/package.json`): `createPhoneClient()` returning `ready()`, `theme`, `init`, `callback`, `notify`, `storage` (`get`, `list`, `set`, `remove`), `client`, `contacts` (`list`, `save`), `on`, `onTheme`, `onVisibility`, `close`, `setTitle`, `haptic`, `getContext` and `destroy`. The `@kora/phone-sdk/react` entry exports `PhoneProvider`, `usePhone`, `useTheme`, `usePhoneCallback` and `usePhoneStorage`. The package also ships `src/theme.css` (see the theming note in the developer guide). `npm test` in `sdk/` builds it and runs `sdk/test/sdk.test.mjs`.
