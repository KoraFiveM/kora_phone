---
title: Installation
sidebar_position: 2
---

# Installation

## Dependencies

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

## Steps

1. Name the directory `kora_phone`. The inventory gateway also still accepts the old name `kora_phone-stevie`.
2. Integrate the companion gateway from `integration/kora_inventory/server.lua` into your `kora_inventory` resource. It provides the `PhoneItemTransaction` export (see [Handsets, SIMs and cloud](./three-handsets.md)). Back up and compare versions before replacing files.
3. Add the convars and `ensure` lines to `server.cfg` (before `ensure kora_phone`):

```cfg
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

4. Review [Configuration](./configuration.md): shop coordinates, business job names, Wi-Fi hotspots, media provider.
5. Optional TURN relay for video calls:

```cfg
set kora_phone_turn_urls "turn:YOUR_TURN_HOST:3478"
set kora_phone_turn_secret "YOUR_TURN_REST_SHARED_SECRET"
```

STUN servers come from `Config.Calls.Video.IceServers`.

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
