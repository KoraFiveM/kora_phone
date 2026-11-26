---
title: "Kora stack usage"
sidebar_position: 5.8
---

# Kora stack usage

`kora_phone` builds on `kora_lib` and `kora_core` and does not reimplement what they provide. This page records where each is used, and the few places the phone deliberately uses a raw native, so a new change can be checked against it. The counts are files that reference the module, taken from the code when this page was written.

## kora_lib

| Module | Used for | Files |
| --- | --- | --- |
| `Kora.callback` | Every client to server request (the route gateway and each app callback `app:ID:NAME`) | 7 |
| `Kora.config` | Config definition, live `/config` editing, `config.local.lua` | 4 |
| `Kora.lang` | Server and client strings (`locales/`) | 8 |
| `Kora.logging`, `Kora.print` | Structured server events and console output (a test blocks raw `print`) | 15, 3 |
| `Kora.keybind`, `Kora.commands` | The phone key mapping and `/phonereset` (with permission gate and chat suggestions) | 2, 2 |
| `Kora.notify`, `Kora.sound` | Game notifications and the notification, share and alarm sounds | 6, 3 |
| `Kora.cache`, `Kora.state` | Ped, coordinates, death state, and the UI-block state bag | 4, 1 |
| `Kora.timers` | `KoraPhone.After` (every delayed server action), the Clock scheduler | 4 |
| `Kora.anim`, `Kora.entities` | The phone pose and the handset prop in the hand | 1, 1 |
| `Kora.blips`, `Kora.interact`, `Kora.screenshot` | Maps blips, the third-eye share option, camera capture | 1, 1, 2 |

## kora_core and the other Kora resources

`exports.kora_core` supplies the player (`getPlayerData`, `getPlayerByCitizenId`, `onPlayerDataChange`), money, jobs, items and permissions. `kora_inventory` owns handset and SIM items (`PhoneItemTransaction`) and the shop counters. `kora_banking` moves money, `kora_multijob` the duty roster, `kora_garages` the vehicle list, `kora_voice` call audio, and `kora_hud` and `kora_target` are optional integrations. The phone never writes a player's money, job or items directly.

## Where a raw native is used on purpose

| Where | Native | Why it stays |
| --- | --- | --- |
| `client/main.lua` | `RegisterCommand` for `/phone` | `Kora.commands` is server side; opening the phone must not wait for a round trip. The key itself goes through `Kora.keybind` |
| `client/camera.lua`, `client/video.lua`, `client/map.lua` | `CreateThread` with `Wait(0)` | Per-frame drawing and recording that has to run every frame |
| `client/animations.lua`, `client/share.lua`, `client/services.lua`, `apps/*/client.lua` | `CreateThread` | One-off startup and watcher threads that end with the resource |
| `server/rate_limits.lua`, `server/handsets/*.lua`, `server/main.lua` | `GetGameTimer`, `Wait` | Monotonic millisecond clock for rate windows and lock waits |
| `client/nui.lua` | `SendNUIMessage`, `RegisterNUICallback` | The phone owns its own NUI frame. `Kora.nui` talks to kora_lib's frame, not this one (see the comment at the top of that file) |

Everything else that used a raw native has moved: delayed server work uses `KoraPhone.After` (over `Kora.timers.setTimeout`), the handset prop uses `Kora.entities.create`, and sounds use `Kora.sound.playFrontend`.

## Rules for new code

1. Use the `Kora.*` module before a native. If a module exists for it, a pull request that uses the native needs a reason in a comment and a row in the table above.
2. Money, jobs and items go through `kora_core` or `kora_inventory`, never through the database.
3. Delayed server work uses `KoraPhone.After`, never `SetTimeout`.
4. App code (`apps/<id>/server.lua`, `client.lua`) follows the same rules; it is trusted code in this resource.
