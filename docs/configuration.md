---
title: Configuration
sidebar_position: 6
---

# Configuration

kora_phone uses the kora_lib config handler (`Kora.config`). Every setting is a typed field with a label, a description, bounds, a scope and a live or restart flag. You can change settings in two ways:

1. **In game with `/config`.** Open kora_phone in the workspace, edit a field and save. Fields marked **Applies now** take effect immediately; fields marked **Restart required** show a **Restart resource now** action after saving. Access needs the ACE `kora_lib.config.edit` (if `kora_admin` is running it owns the `/config` command and decides access instead):

```cfg
add_ace group.admin kora_lib.config.edit allow
```

2. **By hand in `config.local.lua`.** The editor writes only the values that differ from the defaults to `config.local.lua` in the resource folder (with the previous file kept as `config.local.lua.bak`). You can create or edit that file yourself: it must `return` a table that mirrors the `Config` paths (for example `return { Server = { Media = { Provider = 'disabled' } } }`). It is loaded with an empty environment, so only literal values work (no functions, no globals); if the primary file is invalid at start-up, kora_lib uses the `.bak` copy. The tracked files under `config/` are never rewritten. Add both generated files to `.gitignore`.

Resetting a field in the editor removes its override and restores the default from `config/`. Unknown or invalid values in `config.local.lua` are ignored.

## Files and scopes

`config/shared.lua` is the only file that calls `Kora.config.define`. `config/handsets.lua` and `config/server.lua` add their branches with `Kora.config.extend`, so the single `Config` table keeps the same access paths the code reads (for example `Config.Camera.zoom.step`).

| Scope | Meaning | Where |
| --- | --- | --- |
| shared | Validated and synced to every client; client code reads it | `config/shared.lua`, `config/handsets.lua` |
| client | Validated and saved by the server, synced to clients, no server handlers | `Config.Client`, `Config.Camera`, `Config.Animation` (declared in `config/shared.lua`) |
| server | Never sent to a client | `config/server.lua`, plus the server-scoped fields noted below |

Keep secrets out of shared and client files, which every player downloads. Secret fields are `sensitive`: they never appear in `/config` and never reach a client. Tokens belong in convars (see [Installation](./installation.md)).

`config/client.lua` currently only documents where client reactions to live changes would go: every live client setting is read at the moment it is used.

## Checking a change

Lua tests run without FiveM, so `tests/config_shim.lua` stands in for `Kora.config` and returns the authored defaults. The shim does not validate. To validate the schema, load the config files through the real `kora_lib/modules/config/consumer.lua` with stubbed natives; an invalid default, bound or pattern fails immediately.

## config/shared.lua

| Option | Default | Scope, live | Meaning |
| --- | --- | --- | --- |
| `Config.RequirePhoneItem` | `true` | shared, live | Require a handset item (any name in `Config.Handsets`). `false` skips the check |
| `Config.PhoneNumber.Prefix` / `SubscriberDigits` | `'555'` / `7` | shared, restart | Format of generated numbers (prefix plus zero-padded random digits) |
| `Config.Limits` | contact name 64, message 2000, conversation title 80, page 30 (max 100) | shared, restart | Input bounds |
| `Config.Settings.AcceptLegacyIds` / `LegacyIds` | `true` / `{ qbcore = 'kora_core' }` | shared, live | Map retired appearance ids (old saved settings) to current ones instead of rejecting a settings save |
| `Config.ShareNumber` | see below | shared, live | Share-your-number feature |
| `Config.HomeScreen.allowReorder` | `true` | shared, live | Let players drag home-screen icons; `false` hides the controls and the server ignores order changes |
| `Config.Gallery.fullscreenViewer` | `true` | server, live | Large full-screen photo and video viewer |
| `Config.AppStore` | `true` | server, live | `false` hides the App Store icon |
| `Config.Apps` | all `true` except `moderation = false` | server, live | Per-app switches sent to the UI at bootstrap: `social`, `classifieds`, `flash`, `moderation`, `gps`, `clock`, `music`. For folder apps (`notes`, `weather`, `calculator`, `banking`, `mail`, `services`, `property`, `vehicles` and any app you add under `apps/`) `false` stops the app registering, so it disappears from the store and the home screen |

`Config.ShareNumber`: `Enabled = true`, `Distance = 3.0` m (server-measured, 1 to 15), `AnswerDistance = 10.0` m, `ExpireSeconds = 30` (5 to 120), `CooldownSeconds = 20` per pair, `AskForName = true`, `AllowShareBack = true`, `AllowWhileLocked = true`.

Server-side enforcement of `Config.Apps` is limited: the server refuses `social:*` callbacks when `social` is `false`, `market:*` when `classifieds` is `false`, `moderation:*` when `moderation` is `false`, and `transferBankMoney` when `banking` is `false`. Other switches only change what the UI offers.

## config/handsets.lua

| Option | Default | Scope, live | Meaning |
| --- | --- | --- | --- |
| `Config.Handsets` | `phone` to standard, `phone_standard`, `phone_flip`, `phone_fold` | shared, restart | Map of item name to model (`standard`, `flip`, `fold`). The legacy `phone` item is treated as Standard. `phone_standard` cannot be removed |
| `Config.SimItem` | `'phone_sim'` | server, restart | SIM item name |
| `Config.SimSwap` | `'both'` | server, live | Who may swap SIMs: `player`, `shop` or `both` |
| `Config.ConsumeSimOnInstall` | `true` | server, live | Re-check that inserting a SIM removed exactly one SIM item and correct it through `kora_inventory`. `false` skips the re-check |
| `Config.LaunchApps` | all apps `true` | shared, live | Which apps the server accepts in saved settings (`installedApps`, home order). An id set to false or missing is rejected or dropped |
| `Config.PhoneServices.shops` | `legion`, three Digital Den doors, `technician` | shared, restart | Map of service counters: `label`, `coords`, `distance`, `bucket`, `recoveryFee`, `replacementFee`, `resalePercent`, `prices` per item, optional `job` and `grade` for business counters. Each entry becomes a `kora_lib` circle zone and a `kora_inventory` shop named `kora_phone:` plus the key |
| `Config.PhoneServices.wifi` | `legion` (public), `workshop` (private) | server, live | Map of hotspots: `label`, `coords`, `radius`, `bucket`, optional `passwordConvar` and `ownerJob`. The password itself lives in the named convar |

Keep each counter several metres away from other interactions (bank teller, shops) so two prompts do not open together.

## Client settings (declared in config/shared.lua)

| Option | Default | Live | Meaning |
| --- | --- | --- | --- |
| `Config.Client.Command` | `'phone'` | restart | Toggle command |
| `Config.Client.Keybind` | `'M'` | restart | Default key mapping (players can rebind) |
| `Config.Client.DisableWhileDead` | `true` | live | No phone while dead or in last stand; an open phone closes |
| `Config.Client.NoPhoneNoticeWhileDown` | `true` | live | When down and without a phone, say "You don't have a phone" |
| `Config.Client.NotificationSound` | `true` | live | Game text tone for closed-phone notifications |
| `Config.Client.UiBlockBag` | `'koraUiBlocked'` | restart | Player state bag that keeps the phone shut while `true`. Empty disables |
| `Config.Camera` | see below | live | Camera controls, zoom and microphone |
| `Config.Animation` | enabled, prop `prop_npc_phone_02`, bone '28422' | live | Prop and animation while the phone is open. The held prop follows the handset model (`kora_phone_standard`, `kora_phone_flip`, `kora_phone_fold`, streamed from `stream/`); `model` is the fallback for any other handset. `anims` sets text, call, in-car text and in-car call clips |

`Config.Camera`: `lookMode` (`hold`, `toggle`, `off`) and `lookKey` (`LMENU`), both read once at start because the aiming keybind is registered then (not live), `hint`, `zoom` (`enabled`, `minFov` 10, `maxFov` 60, `defaultFov` 60, `step` 5, `smooth`, `smoothSpeed` 10, `selfie` overrides) and `micAudio` (`enabled`, `followVoice`). See [Features](./features.md).

`Config.Animation.bone` is text: digits are read as a bone index (the default `28422` is PH_R_Hand) and anything else as a bone name. It may contain letters, digits and underscores.

## config/server.lua

Everything here is server scope and never sent to a client.

| Option | Default | Live | Meaning |
| --- | --- | --- | --- |
| `Config.Server.AutoProvisionDevice` | `true` | live | Create a device row when a character first needs one |
| `Config.Server.DatabaseReadyTimeoutMs` | `15000` | restart | How long start-up waits for the database before stopping the resource |
| `Config.Server.RateLimits` | burst and refill (`capacity`, `refillPerSecond`) | live | A sliding window of `capacity` calls per `capacity / refillPerSecond` seconds, per player, shared by every route using the key (`server/rate_limits.lua`). Keys: `bootstrap`, `read`, `mutation`, `sendMessage`, `callStart`, `videoSignal`, `bankTransfer`, `mediaUpload`, `jobMutation`, `pin`, `shareNumber`, `sdk`, and `community.read`, `.profile`, `.post`, `.reaction`, `.follow`, `.comment`, `.block`, `.report`, `.listing`, `.contact`, `.moderation`. Each route names its key in `shared/routes.json`; the `sdk` key covers the ten `apps:*` routes. Unknown keys fall back to `mutation`, which cannot be removed |
| `Config.Server.Banking` | `Enabled = true`, `Account = 'bank'`, `MaximumTransfer = 1000000`, `HistoryPageSize = 30` | live | Balance account, transfer ceiling and history page size. Transfers also need kora_banking started. See [Banking and jobs](./banking-jobs.md). |
| `Config.Server.Jobs` | `Enabled = true`, `AllowDutyToggle = true`, `Actions = {}` | live | Job app and configured actions. `Actions` is a map of job, then action id, then `enabled`, `label`, `minimumGrade`, `requireDuty`, `serverEvent`. A `handler` function cannot be edited in `/config`; assign it in Lua after the config loads |
| `Config.Server.Pin` | `MaxAttempts = 5`, `LockSeconds = 300` | live | PIN lockout |
| `Config.Server.Handsets.ResumeEnrolledHandset` | `true` | live | With several handsets and none selected, resume the one whose Face ID is enrolled for the character |
| `Config.Server.Wallet` | `ShowDistance = 3.0`, `Licences` list of `id` and `label` | live | ID card licences read from `metadata.licences` (driver, weapon, business) |
| `Config.Server.Items` | alarm 20, station 30 | live | Per-phone limits for alarms and Sound stations. Notes are kept by the Notes app in its own storage (100 notes) |
| `Config.Server.Maps.Locations` | seven example places (`label`, `x`, `y`) | live | Saved places listed in Maps. An empty list turns the feature flag off |
| `Config.Server.SdkCallbackRateLimit` | `max = 30`, `window = 10000` (ms) | restart | Rate limit passed to `Kora.callback` for every sandboxed app callback (`app:<id>:<name>`). Read when an app registers its callbacks |
| `Config.Server.Garage` | `Enabled = true`, `UseGarageLabels = true` | restart | Garage app: `Enabled` switches it on (vehicles come from `exports.kora_garages:getOwnedVehicles`), `UseGarageLabels` shows kora_garages names. |
| `Config.Server.Property` | `Enabled = true` plus `OwnedTable`, `OwnerColumn`, `HouseColumn`, `LocationsTable`, `NameColumn`, `LabelColumn`, `CoordsColumn` (qb-houses names by default) | restart | Property app source. There is no Kora housing resource, so the table and column names are yours to set; the app is only available if every one exists |
| `Config.Server.Media` | `Provider = 'fivemanage'` plus limits | provider restarts, limits live | Provider, size and count limits, allowed types and hosts, cleanup timing, `External` broker URLs and `Fivemanage` settings. `External.Secret` and `Fivemanage.Token` are sensitive. See [Media storage](./media-storage.md) |
| `Config.Calls.RingTimeoutMs` | `30000` | restart | Ring time (10000 to 120000) |
| `Config.Calls.VoiceChannelMinimum` / `Maximum` | `31000` / `60999` | restart | Voice channel range for calls |
| `Config.Calls.Video` | `Enabled = true`, Google STUN | live | `IceServers` handed to clients; each entry has `urls` and, for TURN, `username` and a sensitive `credential` |

The Property availability check runs once and is cached until the resource restarts. Job action entries are described in [Banking and jobs](./banking-jobs.md).

App callbacks registered through the SDK (`app:<id>:<name>`) are additionally limited by kora_lib to 30 calls per 10 seconds per player and callback. That limit is built into `server/sdk/callbacks.lua`; it is not a config option.

## Removed options

`Config.Debug` and `Config.PhoneItem` were removed: no code read them. Handset item names come from `Config.Handsets`.
