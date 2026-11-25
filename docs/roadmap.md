---
title: Roadmap
sidebar_position: 21
---

# Status and direction

This page summarises what ships today and what is in progress. [Features](./features.md) and the README describe the code in detail.

## Shipped

- Every feature listed in [Features](./features.md) ships in this release. Nothing is deferred from that list.
- Custom apps ship today, both as sandboxed iframe apps through the manifest SDK ([App SDK](./apps.md)) and through the client registry and alias exports described in [How to use](./how-to-use.md).
- The app SDK v1: manifest registration (`kora_phone_app` or `RegisterApp`), server-checked permissions, per-app storage and callbacks, the iframe protocol and the `@kora/phone-sdk` package.

## Folder apps

- Shipped: the `Phone.app` API, the UI kit, the style guide and linter, and Notes, Calculator, Weather, Wallet, Mail, Moderation, Market, Contacts, Phone, Messages, Gallery, Maps, Clock, Sound, Settings, Garage, Home and Work as folder apps.
- Still compiled into the host UI, in this order of difficulty:  Camera, Pulse and Flash (they need the in-game render canvas and clip recording, which only a running client can verify). The first-run Setup screen and the shop-counter services dialog stay in the host: Setup runs before the launcher is usable, and the dialog opens from the world rather than from an app. Each moves when its services are ready.
- `shared/routes.json` and the gateway remain the route table for the built-in apps; folder apps use `app.callback` and need no entry.

## Not enforced yet

- The manifest permissions `media.read`, `location` and `payments` are accepted and stored, but no route checks them, so they grant nothing today.
- Battery, physical damage, account-based Wi-Fi calling and technician crafting, wiping and SIM hacking are deferred (see [Handsets, SIMs and cloud](./three-handsets.md)).

## Stack

kora_phone is Kora-only. It runs on `kora_lib`, `kora_core`, `kora_sql`, `kora_inventory`, `kora_theme` and `kora_voice`. There is no qb-phone, ox or other framework compatibility layer. The only aliases are the custom-app exports for `lb-phone`, `sd-phone`, `17mov_Phone`, `yseries` and `high-phone`.
