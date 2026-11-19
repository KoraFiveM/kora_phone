---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Phone (folder `kora_phone`) is the server-authoritative in-game phone for the Kora stack: three handset shells (Standard/Flip/Fold), removable SIMs, cloud accounts, and a money-touching surface — a bank-transfer app, a Wallet ID card, a classifieds marketplace, and in-world phone-shop commerce (buying handsets, SIM replacement, cloud recovery, resale). Every app in the NUI is a thin client over server callbacks; nothing about money, identity or permissions is decided in the browser.

## Install Kora Phone

1. **Add the folder.** The resource folder must be named `kora_phone`. kora_inventory also still accepts the old folder name `kora_phone-stevie` for the `PhoneItemTransaction` gateway. The manifest `provide`s `lb-phone`, `sd-phone`, `17mov_Phone`, `yseries` and `high-phone` so `GetResourceState()` checks and dependency resolution for those ecosystems resolve to this resource. Run only one phone provider: stop any real lb-phone, sd-phone and so on, because two active providers of the same name race for the same registrations.

2. **Start its dependencies first.** The manifest declares `kora_theme`, `kora_lib`, `kora_core`, `kora_sql`, `kora_inventory`, `kora_voice` and `kora_phone_props` (the in-hand handset models, kept in their own resource so restarting the phone cannot crash a player holding it) as dependencies. `kora_inventory` must export `PhoneItemTransaction`; it does so natively, so no companion file is needed. Start-up stops the resource if the export is missing.

   ```cfg title="server.cfg"
   set kora_phone_pin_pepper "REPLACE_WITH_A_LONG_RANDOM_SECRET"
   set kora_fivemanage_token "YOUR_FIVEMANAGE_TOKEN"
   set kora_phone_workshop_wifi_password "YOUR_PRIVATE_HOTSPOT_PASSWORD"

   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_inventory
   ensure kora_theme
   ensure kora_voice
   ensure kora_phone_props
   ensure kora_banking
   ensure kora_phone
   ```

   `kora_banking` is not a manifest dependency, but bank transfers need it (see Optional resources below). Photos use `kora_lib`'s screenshot module, so no separate screenshot resource is started.

3. **Load order inside the resource.** Read `fxmanifest.lua` for the exact lists; the order matters in these places:

   - Shared scripts load `kora_lib`, `kora_core`, the config files (`config/shared.lua` then `config/handsets.lua`), then `shared/constants.lua`, `shared/validation.lua` and `shared/contracts.lua`.
   - Server scripts load `@kora_sql/init.lua`, `config/server.lua`, `server/schema.lua` and `server/sdk/schema.lua`, then the integrations, repositories and services globs, then rate limits, permissions, sessions, the handset files in `server/handsets/` (core, location, sim, identity, cloud, actions, lifecycle), `server/mailboxes.lua`, `server/mail/system.lua`, `server/phone_commerce.lua`, the app SDK files in `server/sdk/`, the gateway `server/callbacks.lua`, the per-domain `server/modules/*_callbacks.lua` files, `server/handset_callbacks.lua` and `server/main.lua` last (it waits for the database and creates the tables).
   - Client scripts use an explicit order: the SDK registry (`client/sdk/registry.lua`) must exist before `client/customapps.lua`, and `client/nui.lua` before `client/video.lua`.
   - `shared/routes.json` and `locales/*.lua` are listed in `files`; the server and the web bundle read the same route table.

4. **Database setup.** On start, `server/main.lua` waits up to `Config.Server.DatabaseReadyTimeoutMs` (default 15000) for `KoraPhone.Database.isReady()`, then runs `KoraPhone.SchemaSetup.run()`, which passes the tables of `server/schema.lua` and `server/sdk/schema.lua` to `Kora.sql.ensureTables`. Either step failing logs the reason and stops the resource (`StopResource`). This targets a new server with an empty database; nothing is migrated from an older phone script.

5. **Set secrets before first start.** Keep `kora_phone_pin_pepper` stable across restarts (back it up with your server secrets), because it is the hashing pepper for phone PINs. Set `kora_fivemanage_token` if `Config.Server.Media.Provider = 'fivemanage'` (the shipped default), and `kora_phone_workshop_wifi_password` if you use the private workshop hotspot in `config/handsets.lua`.

## Review the config

Settings are typed fields declared with `Kora.config.define` and `Kora.config.extend`. Edit them in game with `/config` (ACE `kora_lib.config.edit`) or by hand in `config.local.lua`; the tracked files under `config/` are never rewritten. See [Configuration](./configuration.md) for every option.

- `config/shared.lua`: phone item requirement, phone number shape, input limits, share-number rules, home-screen reordering, gallery viewer, `Config.Apps` (per-app switches), and the client-scoped `Config.Client`, `Config.Camera` and `Config.Animation`.
- `config/handsets.lua`: handset item mapping, `Config.SimItem`, `Config.SimSwap`, `Config.ConsumeSimOnInstall`, `Config.LaunchApps`, `Config.PhoneServices.shops` and `.wifi` (the Circuit Mobile counters and Wi-Fi hotspots that `server/phone_commerce.lua` checks proximity and job against).
- `config/server.lua`: rate limits, banking, jobs, PIN lockout, wallet licences, item limits, map places, garage and property sources, media provider and limits, call timing and video ICE servers.
- `config/client.lua`: only a note about where reactions to live client changes would go; the client settings themselves live in `config/shared.lua`.

Add `config.local.lua` and `config.local.lua.bak` to your `.gitignore` if you track the resource (the shipped `.gitignore` already lists them).

## Dependencies (from the manifest)

`fxmanifest.lua` declares these `dependencies`; the resource will not start without them:

| Resource | Used for |
| --- | --- |
| `kora_lib` | Config handler (`Kora.config`), callbacks (`Kora.callback`), keybinds, language files, logging, notifications, interaction zones, screenshots, blip registry |
| `kora_core` | Player data, items (`registerShared`, `createUseable`, `getItemBySlot`, `getItemsByName`), money, jobs (`getJob`, `setJobDuty`), owned vehicles (`getByOwner`), permissions, the `kora_core:server:playerUnloaded` and client `playerLoaded` and `playerLoggedOut` events |
| `kora_sql` | Database access (`Kora.sql`) and declarative table setup (`Kora.sql.ensureTables`) |
| `kora_inventory` | Physical handset and SIM ownership through `PhoneItemTransaction`, and the `kora_phone:` shops (`GetShopItems`, `BuyItem`) |
| `kora_theme` | Client theme bridge (`@kora_theme/client/bridge.lua`) and the colours, fonts and shapes the NUI uses |
| `kora_voice` | Call audio through its native API (`setPlayerCall`, `removePlayerFromCall` on the server, `getCallChannel` on the client). Call muting is not supported |

## Optional resources

Used when present, not declared in the manifest:

| Resource | Used for |
| --- | --- |
| `kora_banking` | Phone-to-phone transfers (`ExecuteTransaction`). Without it the Banking app still shows the balance, but transfers report that they are unavailable. Its `Config.transactionCallers` must list `kora_phone`; kora_banking's default already does |
| `kora_multijob` | Duty changes: the phone toggles duty through `exports.kora_multijob:setDuty`, which refuses jobs in `Config.disabledDuty`. Without kora_multijob started, duty changes from the phone are refused |
| `kora_garages` | Garage names in the Garage app (`getAllGarages`, `Config.Server.Garage.UseGarageLabels`). Without it the raw garage id is shown |
| `kora_target` | The third-eye **Share phone number** option (`client/share.lua`) |
| `kora_hud` | Restores the minimap layout after the Maps app (`applyMinimapLayout`) |
| Fivemanage account | Photo and video hosting when `Config.Server.Media.Provider = 'fivemanage'` |

There is no housing dependency: the Property app reads the table names you configure in `Config.Server.Property`.

Do not run another phone alongside this resource. The manifest uses `provide` for `lb-phone`, `sd-phone`, `17mov_Phone`, `yseries` and `high-phone`, so any resource that depends on one of those resolves to `kora_phone`.

Third-party apps built on the SDK are separate resources that declare `kora_phone_app 'app.json'` in their own `fxmanifest.lua` (see [App SDK](./apps.md)); start them after `kora_phone` or restart `kora_phone` to rescan.

## Optional TURN relay

Video calls can use a TURN relay. STUN servers come from `Config.Calls.Video.IceServers`.

```cfg
set kora_phone_turn_urls "turn:YOUR_TURN_HOST:3478"
set kora_phone_turn_secret "YOUR_TURN_REST_SHARED_SECRET"
```

## Convars

| Convar | Purpose |
| --- | --- |
| `kora_phone_pin_pepper` | Server secret mixed into PIN hashes. Keep it stable between restarts and in your backups; changing it invalidates existing PINs |
| `kora_fivemanage_token` | Fivemanage Media API token (server only) |
| `kora_phone_workshop_wifi_password` | Password for the example private hotspot (named by `passwordConvar` in `config/handsets.lua`) |
| `kora_phone_turn_urls` | TURN server URLs handed to video-call clients |
| `kora_phone_turn_secret` | Shared secret for time-limited TURN REST credentials |

## Database

The tables are declared in `server/schema.lua` and `server/sdk/schema.lua` and created by `Kora.sql.ensureTables` when the resource starts; there is no SQL file to import and there are no migrations. Later starts only add missing tables, columns, indexes and keys; existing ones are never altered or dropped and differences are logged as warnings. If setup fails, the reason is logged and the resource stops. Nothing is migrated or converted from another phone. See [Database](./database.md).

## Clean-install verification

1. Start with an empty database and start the resource; the console logs `Server foundation ready` (event `phone.server_ready`).
2. Create two characters, give each a handset item (or buy one at a counter) and a SIM.
3. Complete one call, one message, one photo (if a media provider is configured) and one mail.
4. Reconnect both characters and verify contacts, messages and unread state persist.
5. Restart `kora_phone` during an active call and confirm voice routing is cleaned up.

## Updating

Back up the database, then replace the resource. Start-up only adds missing tables, columns, indexes and keys. Keep `kora_inventory` on a version that exports `PhoneItemTransaction`. Your `config.local.lua` overrides stay in place; values it holds that no longer match the schema are ignored.

## Operational guidance

- Treat the Fivemanage token, TURN secret, PIN pepper and hotspot passwords as server-only values.
- Take one consistent backup of phone tables, inventories and inventory shop stock together (see [Handsets, SIMs and cloud](./three-handsets.md)).
