---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Phone (folder `kora_phone`) is the server-authoritative in-game phone for the Kora stack: three handset shells (Standard/Flip/Fold), removable SIMs, cloud accounts, and a money-touching surface — a bank-transfer app, a Wallet ID card, a classifieds marketplace, and in-world phone-shop commerce (buying handsets, SIM replacement, cloud recovery, resale). Every app in the NUI is a thin client over server callbacks; nothing about money, identity or permissions is decided in the browser.

## Install Kora Phone

1. **Add the folder** — The resource folder must be named `kora_phone`. The kora_inventory gateway also still accepts the old folder name `kora_phone-stevie` for existing installs. It `provide`s `qb-phone`, `lb-phone`, `sd-phone`, `17mov_Phone`, `yseries` and `high-phone` so `GetResourceState()` checks and dependency resolution for those ecosystems resolve to this resource. Only run one phone provider at a time — stop any real lb-phone/sd-phone/etc, since two active providers of the same name race for the same registrations.

2. **Start its dependencies first** — The manifest declares `kora_theme`, `kora_lib`, `kora_core`, `kora_sql`, `kora_inventory` and `pma-voice` as dependencies.

   ```bash title="server.cfg" {5,6,7,8,9,10,11}
   set kora_phone_pin_pepper "REPLACE_WITH_A_LONG_RANDOM_SECRET"
   set kora_fivemanage_token "YOUR_FIVEMANAGE_TOKEN"
   set kora_phone_workshop_wifi_password "YOUR_PRIVATE_HOTSPOT_PASSWORD"

   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_inventory
   ensure kora_theme
   ensure pma-voice
   ensure screenshot-basic
   ensure kora_phone
   ```

3. **Integrate the inventory companion** — Compare `integration/kora_inventory/server.lua` with your installed `kora_inventory` version before replacing files. It supplies `PhoneItemTransaction`, which handles handset binding, SIM exchange and resale through inventory authority — the shop flows in `server/phone_commerce.lua` call it directly.

4. **Load order inside the resource** — Server scripts load `config/server.lua` and `server/schema.lua` before the integrations/repositories/services globs, then rate limits, permissions, sessions and handset state, then `server/phone_commerce.lua` and `server/callbacks.lua` (which registers most app callbacks), then the per-domain `server/modules/*_callbacks.lua` files, legacy `qb-phone` compat, and `server/main.lua` last (boots the database wait loop).

   ```lua title="fxmanifest.lua" {28-51}
   fx_version 'cerulean'
   game 'gta5'

   name 'kora_phone'
   author 'Kora Team'
   description 'Server-authoritative Kora phone'
   version '0.2.0'

   lua54 'yes'

   shared_scripts {
       '@kora_lib/init.lua',
       '@kora_core/init.lua',
       '@kora_core/shared/locale.lua',
       'config/shared.lua',
       'config/handsets.lua',
       'shared/constants.lua',
       'shared/validation.lua',
       'shared/contracts.lua'
   }

   client_scripts {
       '@kora_theme/client/bridge.lua',
       'config/client.lua',
       'client/**/*.lua'
   }

   server_scripts {
       '@kora_sql/init.lua',
       'server/crypto.js',
       '@kora_sql/lib/MySQL.lua',
       'config/server.lua',
       'server/schema.lua',
       'server/integrations/*.lua',
       'server/repositories/*.lua',
       'server/services/*.lua',
       'server/rate_limits.lua',
       'server/permissions.lua',
       'server/sessions.lua',
       'server/handsets.lua',
       'server/mailboxes.lua',
       'server/phone_commerce.lua',
       'server/callbacks.lua',
       'server/modules/call_callbacks.lua',
       'server/modules/economy_callbacks.lua',
       'server/modules/media_callbacks.lua',
       'server/modules/community_callbacks.lua',
       'server/handset_callbacks.lua',
       'server/compat/qb-phone.lua',
       'server/main.lua'
   }

   ui_page 'web/dist/index.html'

   files {
       'web/dist/index.html',
       'web/dist/assets/*',
       'web/dist/compat.js',
       'web/dist/map.jpg',
       'local-media/*'
   }

   dependencies {
       'kora_theme',
       'kora_lib',
       'kora_core',
       'kora_sql',
       'kora_inventory',
       'pma-voice'
   }

   -- Lets this resource answer as each aliased phone (client/customapps.lua) for real: many
   -- custom apps gate their AddCustomApp-style call behind GetResourceState('lb-phone') (etc)
   -- being 'started' before ever attempting the export, which the export-event trick alone
   -- can't satisfy. `provide` makes GetResourceState and dependency resolution treat this
   -- resource as if it were that one too. Don't also run the real lb-phone/sd-phone/etc
   -- alongside this -- same warning sky_phone documents for the same trick: two active
   -- providers of the same name race for the same registrations.
   provide 'qb-phone'
   provide 'lb-phone'
   provide 'sd-phone'
   provide '17mov_Phone'
   provide 'yseries'
   provide 'high-phone'

   -- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
   qa_feature 'tests/*.feature'
   ```

5. **Database setup** — On start, `server/main.lua` waits up to `Config.Server.DatabaseReadyTimeoutMs` (default 15000) for `KoraPhone.Database.isReady()`, then runs `KoraPhone.SchemaSetup.run()` (`server/schema.lua`). Either failing prints the reason and stops the resource (`StopResource`). This targets a new server with an empty database — nothing is migrated from an older phone script.

6. **Set secrets before first start** — Keep `kora_phone_pin_pepper` stable across restarts (back it up with your server secrets) — it is the hashing pepper for phone PINs. Set `kora_fivemanage_token` if `Config.Server.Media.Provider = 'fivemanage'`, and `kora_phone_workshop_wifi_password` if you use the private workshop hotspot in `config/handsets.lua`.

## Review the config

- `config/shared.lua` — `Config.PhoneItem`/`Config.RequirePhoneItem`, phone number shape (`Config.PhoneNumber.Prefix`/`SubscriberDigits`), text/field length limits (`Config.Limits`), Share Number rules, home-screen reordering, gallery viewer, and `Config.Apps` (per-app on/off switches — banking, social, classifieds, services, property, vehicles, flash, moderation (off by default), gps, notes, mail, weather, calculator, clock, music).
- `config/server.lua` (`Config.Server`) — rate-limit buckets (capacity/refill per action), `Banking` (`Enabled`, `Account` = 'bank', `MaximumTransfer` = 1,000,000, `AllowCompensatingTransfers` = false), `Jobs`, `Pin` (`MaxAttempts` = 5, `LockSeconds` = 300), `Wallet` (`ShowDistance` = 3.0, licence list read from character metadata), `Items` (note/alarm/station caps), `Garage`, `Property`, `Media` (provider, size/duration/day caps) and `Calls`/`Video` (STUN/TURN).
- `config/handsets.lua` — handset item mapping, `Config.SimSwap` (`player`/`shop`/`both`), `Config.LaunchApps`, and `Config.PhoneServices.shops`/`.wifi` — the in-world Circuit Mobile counters and Wi-Fi hotspots that `server/phone_commerce.lua` checks proximity and job against.
- `config/client.lua` — the `/phone` command and keybind (default `M`), `DisableWhileDead`, the `UiBlockBag` state-bag name another resource can set to keep the phone shut, camera look/zoom/mic behaviour, and the held-phone animation.

## Dependencies (from the manifest)


`fxmanifest.lua` declares these `dependencies`; the resource will not start without them:

| Resource | Used for |
| --- | --- |
| `kora_lib` | Shared helpers, callbacks (`Kora.callback`), NUI menus and dialogs, notifications, interaction zones, blip registry |
| `kora_core` | Player data (`getPlayerData`), items (`getItemByName`, `registerShared`, `createUseable`), money, jobs, permissions, character change events |
| `kora_sql` | Database access (`MySQL`) and declarative table setup (`Kora.sql.ensureTables`) |
| `kora_inventory` | Physical handset and SIM ownership. It must expose the `PhoneItemTransaction` gateway (see below); start-up fails otherwise |
| `kora_theme` | Client theme bridge (`@kora_theme/client/bridge.lua`) |
| `pma-voice` | Call audio (the server calls `setPlayerCall`; `kora_voice` can provide the same API) |

Used when present, not declared in the manifest:

| Resource | Used for |
| --- | --- |
| `screenshot-basic` | Camera photos (`requestScreenshotUpload` on the client, `requestClientScreenshot` for the `local-development` provider). Without it the camera reports `SCREENSHOT_PROVIDER_UNAVAILABLE` |
| `kora_target` | The third-eye **Share phone number** option (`client/share.lua`) |
| `kora_garages` | Garage names in the Garage app (`Config.Server.Garage.UseGarageLabels`) |
| `kora_hud` | Restores the minimap layout after the Maps app (`applyMinimapLayout`) |
| Fivemanage account | Photo and video hosting when `Config.Server.Media.Provider = 'fivemanage'` |

Do not run another phone alongside this resource. The manifest uses `provide` for `qb-phone`, `lb-phone`, `sd-phone`, `17mov_Phone`, `yseries` and `high-phone`, so any resource that depends on one of those resolves to `kora_phone`.

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

The tables are declared in `server/schema.lua` and created by `Kora.sql.ensureTables` when the resource starts. Later starts only add missing tables, columns, indexes and keys; existing ones are never altered or dropped and differences are logged as warnings. If setup fails, the reason is printed and the resource stops. Nothing is migrated or converted from another phone. See [Database](./database.md).

## Clean-install verification

1. Start with an empty database and start the resource; the console prints `server foundation ready`.
2. Create two characters, give each a handset item (or buy one at a counter) and a SIM.
3. Complete one call, one message, one photo (if a media provider is configured) and one mail.
4. Reconnect both characters and verify contacts, messages and unread state persist.
5. Restart `kora_phone` during an active call and confirm voice routing is cleaned up.

## Updating

Back up the database, then replace the resource. Start-up only creates missing tables from `server/schema.lua`. If you changed `integration/kora_inventory/server.lua`, update the inventory gateway at the same time.

## Operational guidance

- Treat the Fivemanage token, TURN secret, PIN pepper and hotspot passwords as server-only values.
- Take one consistent backup of phone tables, inventories and inventory shop stock together (see [Handsets, SIMs and cloud](./three-handsets.md)).
- `Config.Debug` exists in `config/shared.lua` but is not read by any code.
