---
title: kora_phone
sidebar_position: 1
---

# kora_phone

`kora_phone` is a server-authoritative phone for the Kora (`[v2]`) stack. Players own physical handsets in their inventory (Orchard One / Standard, Circuit Flip, Atlas Fold), each with a persistent serial, an optional removable SIM that carries the phone number, a PIN, Face ID check and a cloud account for backup and recovery. The NUI is a React app built from `web/src` and served from `web/dist`. Third-party apps run as sandboxed iframes through the manifest-declared app SDK (`@kora/phone-sdk`), and the resource still answers the custom-app export names of `lb-phone`, `sd-phone`, `17mov_Phone`, `yseries` and `high-phone`, so addon apps written for those phones keep registering. There is no qb-phone, ox or other framework compatibility.

Current version: see `version` in `fxmanifest.lua`.

## Documentation map

| Page | Contents |
| --- | --- |
| [Installation](./installation.md) | Install steps, dependencies, optional resources, convars, server.cfg, clean-install check, updating |
| [How to use](./how-to-use.md) | Request pipeline, opening the phone, Wallet, Banking transfers, Marketplace, shops, custom apps |
| [Configuration](./configuration.md) | Every option in `config/*.lua`, the `/config` editor and `config.local.lua` |
| [Features](./features.md) | What the phone and each app do |
| [UI](./ui.md) | Apps, handset styles, custom apps, NUI development |
| [Handsets, SIMs and cloud](./three-handsets.md) | Handset identity, security, inventory gateway, backup and rollback |
| [Commands](./commands.md) | Chat commands, key mappings, third-eye options |
| [App SDK](./apps.md) | Developer guide for folder apps and third-party apps (v1 SDK) |
| [App SDK API](./api/apps.md) | SDK exports, routes and iframe protocol reference |
| [Exports](./api/exports-events.md) | Client and server exports, including phone-alias exports |
| [Events and callbacks](./events.md) | Net events, local events, server callbacks, NUI callbacks |
| [Permissions](./permissions.md) | The moderator ACE, kora_core permissions and other access rules |
| [Items](./items.md) | Handset and SIM items |
| [Database](./database.md) | Tables declared in `server/schema.lua` and `server/sdk/schema.lua` |
| [Media storage](./media-storage.md) | Photo and video providers, Fivemanage, limits |
| [Banking and jobs](./banking-jobs.md) | kora_banking transfers, jobs and duty, Garage and Property sources |
| [Community security](./community-security.md) | Pulse, Market and moderation controls |
| [App style guide](./style-guide.md) | The rules every app follows, and the linter that checks them |
| [lb-phone apps](./lb-phone.md) | What of lb-phone's apps, page globals and server exports is supported |
| [System mail](./system-mail.md) | Server-delivered mail and activity notes, plus the custom-app alias note |
| [Security checklist](./security.md) | Security rules the code follows |
| [Troubleshooting](./troubleshooting.md) | Common start-up and runtime problems |
| [Acceptance tests](./acceptance-tests.md) | Manual release test plan (the scripted tests are in `tests/README.md`) |
| [Roadmap](./roadmap.md) | What ships and what is deferred |

## Quick start

1. Install the dependencies; `kora_inventory` already contains the `PhoneItemTransaction` gateway and needs no extra file ([Installation](./installation.md)).
2. Add the convars (`kora_phone_pin_pepper`, `kora_fivemanage_token`) and `ensure kora_phone` after its dependencies.
3. Start the server. Tables are created automatically through `Kora.sql.ensureTables`.
4. Buy a handset at a Circuit Mobile counter (see `Config.PhoneServices` in `config/handsets.lua`), then press `M` or run `/phone`.
