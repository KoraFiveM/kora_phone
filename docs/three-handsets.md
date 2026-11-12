---
title: Handsets, SIMs and cloud
sidebar_position: 9
---

# Three-handset deployment and acceptance

## Identity and security

`phone_handsets` binds a serial to a local device profile. Inventory metadata carries `handsetId`, and an inserted SIM's `phoneSimId` plus its original `phoneSimInfo`. Loose SIMs carry `simId`. Inventory owns physical insertion state; SQL holds a reconciled routing mirror.

Device access uses the current holder, not the original owner. Exact possession loss, character changes, death and replacement revoke sessions. Inventory observers revoke access immediately and schedule SQL call retirement outside the inventory lock. Changing handsets does not reset request throttles.

Messages have separate delivery copies for each handset. A SIM routes future delivery and grants no old history. Stored outgoing direction survives SIM changes. Legacy per-recipient deletions are respected; legacy groups remain read-only archives. Reset hides this handset's old call history without deleting the other participant's records.

Cloud restores grant access to existing media objects instead of duplicating provider keys. Local deletion removes local visibility; provider cleanup requires zero cloud, gallery, message or contact references. Account locks and revision checks prevent stale backups overwriting a newer snapshot. A stale handset must explicitly restore before replacing a newer backup; confirmation warns that its local content will be replaced.

New PINs use salted scrypt with the server pepper; old PINs remain verifiable until changed. Face ID checks the enrolled character and requires a backup PIN. Recovery codes use cryptographic randomness and are stored hashed. Identity-checked shop recovery rotates the code and removes previous cloud links. Player-business services require customer approval, and recovery details go only to that customer.

## Inventory companion API

The companion `integration/kora_inventory/server.lua` makes `kora_inventory` expose `PhoneItemTransaction(source, request)` and its lowercase alias, callable only by the resource named `kora_phone` (or the legacy `kora_phone-stevie`).

| Operation | Trusted request fields |
|---|---|
| `bindHandset` | `handsetSlot`, `handsetId`, `itemName`, optional `legacySimId` |
| `bindSim` | `simSlot`, `simId`, `itemName` |
| `insertSim` | `handsetSlot`, `handsetId`, `simSlot`, `simId` |
| `removeSim` | `handsetSlot`, `handsetId`, `simId` |
| `replaceSim` | `handsetSlot`, `handsetId`, expected `simId` or empty, `newSimId`, `fee` |
| `resell` | `handsetSlot`, `handsetId`, `payout`, `shopId`, `salePrice` |

Returns `ok, error, handsetOrBoundItem, returnedSim`. Slots, serials, definitions, access, capacity and money are checked inside the inventory authority. Removal restores exact SIM metadata. Resale deposits the actual handset into a separate durable shop slot; repurchase preserves its serial. Payment is compensated if the inventory commit fails.

Supported unique item names are `phone`, `phone_standard`, `phone_flip`, `phone_fold`, and `phone_sim`. Disabling models through config is supported; arbitrary new item names require a deliberate gateway update. Phone shops reserve 64 slots for stock and used handsets.

The gateway and its smoke test are also copied under `integration/kora_inventory/` for deployment review. This is a companion source copy, not another resource to start. Back up the inventory resource and compare versions before replacing its server file.

## Backup and rollback

This resource is for a new server with an empty database: tables are created from `server/schema.lua` at start and no legacy phone data is migrated or converted.

1. Take one consistent backup of all phone tables, player inventories/money and kora_inventory durable stock. Preserve provider files.
2. Interrupt SIM insertion/removal. A valid loose SIM must recover stale SQL location without needing the old handset. Fail replacement activation: `phone_sim_replacements` must stay prepared, and reopening the new handset must finish activation without another fee.
3. Rehearse rollback by stopping the phone and restoring database, inventories and shop stock **together**. Never restore only the phone tables.

Inventory/core persistence retains its documented hard-crash flush window. Reconciliation and the replacement journal recover committed identities, but cannot recover player-item writes lost by the underlying persistence layer. Include that limit in backup and restart procedures.

## Deferred expansion

Technician crafting, handset wiping and SIM hacking remain later-release skills learned through manuals/courses, teaching and practice. Crafting needs blueprints, parts and a workbench. Every use wears tools down, mistakes do extra damage, skill reduces wear, and broken tools are destroyed permanently. A locked wipe will remove local security/content/cloud login and block the old SIM. Hacking may restore calls/texts, never cloud access or a carrier-revoked SIM. No technician bypass endpoints ship now.
