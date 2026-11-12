---
title: kora_phone
sidebar_position: 1
---

# kora_phone

`kora_phone` is a server-authoritative phone for the Kora (`[v2]`) stack. Players own physical handsets in their inventory (Orchard One / Standard, Circuit Flip, Atlas Fold), each with a persistent serial, an optional removable SIM that carries the phone number, a PIN, Face ID check and a cloud account for backup and recovery. The NUI is a React app built from `web/src` and served from `web/dist`. The resource also answers as several other phone resources (`qb-phone`, `lb-phone`, `sd-phone`, `17mov_Phone`, `yseries`, `high-phone`) so custom apps and legacy mail integrations keep working.

Current version: see `version` in `fxmanifest.lua`.

## Documentation map

| Page | Contents |
| --- | --- |
| [Installation](./installation.md) | Install steps, manifest, dependencies, inventory companion, convars, server.cfg, clean-install check, updating |
| [How to use](./how-to-use.md) | Request pipeline, opening the phone, Wallet, Banking transfers and rollback, Marketplace, shops, custom apps |
| [Configuration](./configuration.md) | Every option in `config/*.lua` |
| [Features](./features.md) | What the phone and each app do |
| [UI](./ui.md) | Apps, handset styles, custom apps, NUI development |
| [Handsets, SIMs and cloud](./three-handsets.md) | Handset identity, security, inventory gateway, backup and rollback |
| [Commands](./commands.md) | Chat commands, key mappings, third-eye options |
| [Exports](./api/exports-events.md) | Client and server exports, including phone-alias exports |
| [Events and callbacks](./events.md) | Net events, local events, server callbacks, NUI callbacks |
| [Permissions](./permissions.md) | ACE and QBCore permissions |
| [Items](./items.md) | Handset and SIM items |
| [Database](./database.md) | Tables created by `server/schema.lua` |
| [Media storage](./media-storage.md) | Photo and video providers, Fivemanage, limits |
| [Banking and jobs](./banking-jobs.md) | Wallet transfers and job actions |
| [Community security](./community-security.md) | Pulse, Market and moderation controls |
| [Legacy qb-phone support](./legacy-compat.md) | Mail and transaction compatibility surface |
| [Security checklist](./security.md) | Security rules the code follows |
| [Troubleshooting](./troubleshooting.md) | Common start-up and runtime problems |
| [Acceptance tests](./acceptance-tests.md) | Manual release test plan |
| [Roadmap](./roadmap.md) | Original phase plan (historical) |

## Quick start

1. Install the dependencies and the `kora_inventory` companion gateway ([Installation](./installation.md)).
2. Add the convars (`kora_phone_pin_pepper`, `kora_fivemanage_token`) and `ensure kora_phone` after its dependencies.
3. Start the server. Tables are created from `server/schema.lua` automatically.
4. Buy a handset at a Circuit Mobile counter (see `Config.PhoneServices` in `config/handsets.lua`), then press `M` or run `/phone`.
