---
title: Configuration
sidebar_position: 6
---

# Configuration

Files load in the order given in `fxmanifest.lua`: `config/shared.lua` and `config/handsets.lua` (shared), `config/client.lua` (client), `config/server.lua` (server only). Keep secrets out of shared and client files; they are sent to players. Tokens go in convars (see [Installation](./installation.md)).

## config/shared.lua

| Option | Default | Meaning |
| --- | --- | --- |
| `Config.Debug` | `false` | Not read by any code |
| `Config.PhoneItem` | `'phone'` | Not read by any code; handset item names come from `Config.Handsets` |
| `Config.RequirePhoneItem` | `true` | Require a handset item (any name in `Config.Handsets`) to use the phone. `false` skips the check |
| `Config.PhoneNumber.Prefix` / `SubscriberDigits` | `'555'` / `7` | Format of generated numbers (prefix plus zero-padded random digits) |
| `Config.Limits` | contact name 64, message body 2000, conversation title 80, page size 30 (max 100) | Input bounds |
| `Config.Settings.AcceptLegacyIds` / `LegacyIds` | `true` / `{ qbcore = "kora_core" }` | Map retired appearance ids to current ones instead of rejecting a settings save |
| `Config.ShareNumber` | see below | Share-your-number feature |
| `Config.HomeScreen.allowReorder` | `true` | Let players drag home-screen icons; `false` hides the controls and the server ignores order changes |
| `Config.Gallery.fullscreenViewer` | `true` | Large full-screen photo/video viewer |
| `Config.AppStore` | `true` | `false` hides the App Store icon |
| `Config.Apps` | all `true` except `moderation = false` | Per-app switches sent to the UI at bootstrap: `banking`, `social`, `classifieds`, `services`, `property`, `vehicles`, `flash`, `moderation`, `gps`, `notes`, `mail`, `weather`, `calculator`, `clock`, `music` |

`Config.ShareNumber`: `Enabled = true`, `Distance = 3.0` m (server-measured), `AnswerDistance = 10.0` m, `ExpireSeconds = 30` (clamped 5 to 120), `CooldownSeconds = 20` per pair, `AskForName = true`, `AllowShareBack = true`, `AllowWhileLocked = true`.

Server-side enforcement of `Config.Apps` is limited: the server refuses `social:*` callbacks when `social` is `false`, `market:*` when `classifieds` is `false`, `moderation:*` when `moderation` is `false`, and `transferBankMoney` when `banking` is `false`. Other switches only change what the UI offers.

## config/handsets.lua

| Option | Default | Meaning |
| --- | --- | --- |
| `Config.Handsets` | `phone` to standard, `phone_standard`, `phone_flip`, `phone_fold` | Item name to model. The legacy `phone` item is treated as Standard. Removing an entry disables that model |
| `Config.SimItem` | `'phone_sim'` | SIM item name |
| `Config.SimSwap` | `'both'` | Who may swap SIMs: `player`, `shop` or `both` |
| `Config.ConsumeSimOnInstall` | `true` | Re-check that inserting a SIM removed exactly one SIM item from the inventory and correct it through `kora_inventory`. `false` skips the re-check |
| `Config.LaunchApps` | all apps `true` | Which apps the server accepts in saved settings (`installedApps`, home order). An id set to false or missing is rejected or dropped |
| `Config.PhoneServices.shops` | `legion`, three Digital Den doors, `technician` | Service counters: `label`, `coords`, `distance`, `bucket`, `recoveryFee`, `replacementFee`, `resalePercent`, `prices` per item, optional `job` and `grade` for business counters. Each entry becomes a `kora_lib` circle zone and a `kora_inventory` shop named `kora_phone:` plus the key |
| `Config.PhoneServices.wifi` | `legion` (public), `workshop` (private) | Hotspots: `label`, `coords`, `radius`, `bucket`, optional `passwordConvar` and `ownerJob` |

Keep each counter several metres away from other interactions (bank teller, shops) so two prompts do not open together.

## config/client.lua

| Option | Default | Meaning |
| --- | --- | --- |
| `Config.Client.Command` | `'phone'` | Toggle command |
| `Config.Client.Keybind` | `'M'` | Default key mapping (players can rebind) |
| `Config.Client.DisableWhileDead` | `true` | No phone while dead or in last stand; an open phone closes |
| `Config.Client.NoPhoneNoticeWhileDown` | `true` | When down and without a phone, say "You don't have a phone" |
| `Config.Client.NotificationSound` | `true` | Game text tone for closed-phone notifications |
| `Config.Client.UiBlockBag` | `'koraUiBlocked'` | Player state bag that keeps the phone shut while `true`. `false` or `''` disables. Read once at start |
| `Config.Camera` | see below | Camera controls, zoom and microphone |
| `Config.Animation` | enabled, prop `prop_npc_phone_02`, bone 28422 | Prop and animation while the phone is open. `anims` sets text, call, in-car text and in-car call clips |

`Config.Camera`: `lookMode` (`hold`, `toggle`, `off`), `lookKey` (`LMENU`), `hint`, `zoom` (`enabled`, `minFov` 10, `maxFov` 60, `defaultFov` 60, `step` 5, `smooth`, `smoothSpeed` 10, `selfie` overrides) and `micAudio` (`enabled`, `followVoice`). See [Features](./features.md).

## config/server.lua

| Option | Default | Meaning |
| --- | --- | --- |
| `Config.Server.AutoProvisionDevice` | `true` | Create a device row when a character first needs one |
| `Config.Server.DatabaseReadyTimeoutMs` | `15000` | How long start-up waits for the database before stopping the resource |
| `Config.Server.RateLimits` | token buckets (`capacity`, `refillPerSecond`) | Keys: `bootstrap`, `read`, `mutation`, `sendMessage`, `callStart`, `videoSignal`, `bankTransfer`, `mediaUpload`, `jobMutation`, `pin`, `shareNumber`, and `community.read`, `.profile`, `.post`, `.reaction`, `.follow`, `.comment`, `.block`, `.report`, `.listing`, `.contact`, `.moderation`. Unknown keys fall back to `mutation` |
| `Config.Server.Banking` | `Enabled = true`, `Account = 'bank'`, `MaximumTransfer = 1000000`, `AllowCompensatingTransfers = false` | Also `HistoryPageSize` (default 30). See [Banking and jobs](./banking-jobs.md) |
| `Config.Server.Jobs` | `Enabled = true`, `AllowDutyToggle = true`, `Actions = {}` | Job app and configured actions |
| `Config.Server.Pin` | `MaxAttempts = 5`, `LockSeconds = 300` | PIN lockout |
| `Config.Server.Handsets.ResumeEnrolledHandset` | `true` | With several handsets and none selected, resume the one whose Face ID is enrolled for the character |
| `Config.Server.Wallet` | `ShowDistance = 3.0`, `Licences` | ID card licences read from `metadata.licences` (driver, weapon, business) |
| `Config.Server.Items` | note 100, alarm 20, station 30 | Per-phone limits for notes, alarms and Sound stations |
| `Config.Server.Maps.Locations` | seven example places | Saved places listed in Maps. An empty list turns the feature flag off |
| `Config.Server.Garage` | `Enabled = true`, `Table = 'player_vehicles'`, `UseGarageLabels = true` | Garage app source table |
| `Config.Server.Property` | qb-houses table and column names | Property app source; only available if every table and column exists |
| `Config.Server.Media` | `Provider = 'fivemanage'` plus limits | See [Media storage](./media-storage.md) |
| `Config.Calls.RingTimeoutMs` | `30000` | Ring time (server clamps 10000 to 120000) |
| `Config.Calls.VoiceChannelMinimum` / `Maximum` | `31000` / `60999` | pma-voice call channel range |
| `Config.Calls.Video` | `Enabled = true`, Google STUN | `IceServers` handed to clients; add TURN via convars |

The Garage and Property availability checks run once and are cached until the resource restarts. Job action entries are described in [Banking and jobs](./banking-jobs.md).
