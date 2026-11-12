---
title: Items
sidebar_position: 12
---

# Items

On start (`Handsets.start`) the resource registers its items with `kora_core` (`registerShared('items', ...)`), so you do not add them to a shared items file by hand. All are `unique` (each carries its own metadata).

| Item | Model / use | Notes |
| --- | --- | --- |
| `phone_standard` | Orchard One (Standard) | Useable; selects the handset and opens the phone |
| `phone_flip` | Circuit Flip | Useable |
| `phone_fold` | Atlas Fold | Useable |
| `phone` | Legacy item, treated as Standard | Registered from `Config.Handsets`; useable |
| `phone_sim` (`Config.SimItem`) | Removable SIM carrying a phone number | Not useable; inserted and removed through the phone's Settings. Label "Mobile SIM" |

Handset registration uses weight 250, image `phone.png`, label per model (Orchard One, Circuit Flip, Atlas Fold), description "Personal handset". Only item names present in `Config.Handsets` are registered and recognised, so removing an entry disables that model.

## Metadata

- Handsets carry `handsetId`. An inserted SIM is stored in the handset's metadata as `phoneSimId` and its original `phoneSimInfo`.
- A loose SIM carries `simId`.
- Inventory owns physical insertion state; SQL (`phone_handsets`, `phone_sims`) holds a reconciled routing mirror. See [Handsets, SIMs and cloud](./three-handsets.md).

## Shops

Each entry in `Config.PhoneServices.shops` registers a `kora_inventory` shop named `kora_phone:` plus the entry key, paid from the bank, with 64 slots reserved for stock and used handsets. Stock quantity per priced item is 100. Prices are set per shop in `config/handsets.lua`.
