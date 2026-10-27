# QBPhone — Three Handsets

One FiveM phone system built from Stevie for your custom `[v2]` stack.

| Model | Unique item | Interface |
|---|---|---|
| Orchard One | `phone_standard` | Nothing-inspired Android interface |
| Circuit Flip | `phone_flip` | Tall display and quick-action cover screen |
| Atlas Fold | `phone_fold` | Full outer smartphone and expanded inner layouts |

Each model has a coordinated palette across its launcher, apps and Settings: monochrome for Orchard, soft colors for Circuit, and deeper tones for Atlas. Settings groups Appearance, Connections, Cloud, Privacy, Sound and Device controls, with expanded layouts on the unfolded Atlas.

Legacy `phone` items convert to standard handsets. Each physical handset keeps its own local content, optional PIN, Face ID and cloud login. Each removable SIM owns a separate number.

## Install

Keep the resource directory named **qbphone** and use the updated `qbinventory/server.lua` from your `[v2]` folder. Its new `PhoneItemTransaction` export provides atomic SIM exchanges and resale. A companion copy is included under `integration/qbinventory` for deployment review; compare versions before replacing inventory files.

```cfg
ensure qblib
ensure qbsql
ensure qbcore
ensure qbinventory
ensure qbtheme
ensure pma-voice
ensure screenshot-basic
ensure qbphone

set qbphone_pin_pepper "REPLACE_WITH_A_LONG_RANDOM_SECRET"
set qbphone_fivemanage_token "YOUR_FIVEMANAGE_TOKEN"
```

Edit `config/handsets.lua` for shops, prices, business jobs, public/private Wi-Fi and SIM swapping (`player`, `shop`, `both`; default `both`). Example Legion/workshop coordinates must be checked for your map. Phone shops use bank funds, finite stock and configurable resale payouts.

Fivemanage is selected in `config/server.lua`; photos also need screenshot-basic. Live video uses WebRTC independently. For TURN relaying:

```cfg
set qbphone_turn_urls "turn:YOUR_HOST:3478"
set qbphone_turn_secret "YOUR_TURN_REST_SHARED_SECRET"
set qbphone_workshop_wifi_password "YOUR_PRIVATE_HOTSPOT_PASSWORD"
```

Use a TURN service that supports time-limited REST credentials. STUN configuration stays in `Config.Calls.Video.IceServers`. Keep API tokens and shared TURN secrets server-side.

## Play

Use a handset from inventory, or press **M** to open the selected phone. Counter interactions allow new players to buy their first phone without already owning one.

Settings provides SIM swapping, optional PIN, character-based Face ID with a backup PIN, Wi-Fi, cloud registration/backup/restore and factory reset. Save the account ID and recovery code shown at registration. Identity-checked NPC or authorised business services can recover lost codes.

Calls begin as voice; the other participant must accept a video upgrade before either camera streams. Selfie and rear views use the game camera. Closing the flip pauses video while voice continues. Folding the fold moves video to its outer screen. Putting any handset away ends the call.

Normal resale requires a reset handset with its SIM removed. Shops preserve the physical serial for the next buyer. Replacing a stolen SIM keeps the number and permanently revokes the old SIM.

Launch apps: Phone, Contacts, Messages, Camera, Gallery, Maps, Settings, Mail, Notes, Weather, Calculator, Clock and Sound. Legacy `qb-phone` integrations can deliver offline system mail, billing notifications, one-use Accept actions and informational transaction notes through Mail. See [legacy compatibility](docs/legacy-compat.md). Legacy group history remains readable. Existing nonessential social/banking/job/marketplace screens are outside the launch interface.

## Database and migration

For a fresh database, **[qbphone.sql](qbphone.sql) is the single file to import**, once. You can also skip manual import and let startup install everything with `Config.Server.AutoMigrate = true` (the default). Leave automatic migrations enabled after importing the master file so startup records the schema history.

For an existing Stevie/QBPhone database, use automatic migrations instead of importing the master. The numbered files in `migrations/` are internal upgrade history; keep them with the resource. The master contains schema only; the startup preflight and legacy identity conversion still run normally.


**Back up database and player inventories together before replacing Stevie.** Stop the old resource; never run both against the same tables. SQL `001`–`012` is unchanged; new legacy support uses migration `013`. Both `012` and `013` use qbsql checksum protection. Existing numbers and supported content receive resumable legacy claims. Players without phones keep unclaimed records.

Follow [deployment and multiplayer acceptance](docs/three-handsets.md), including copied-database rehearsal and rollback. Startup now writes `migration-report.json` before identity conversion. Unknown registering characters, invalid legacy numbers or invalid settings block conversion and stop the resource. Review the report, fix or explicitly reconcile the source records, then restart. Invalid contacts and missing media references are reported for review; provider-object existence still needs a real Fivemanage check. The console-only `phonepreflight` command refreshes the read-only report while the resource is running.

Review `migration-report.json`, `phone_migration_issues` and `phone_legacy_claims` before release.

Battery/damage, Wi-Fi account calls, technician progression, crafted tools and SIM hacking remain deferred as agreed. Live FXServer, production-data migration rehearsal, Fivemanage and cross-network TURN acceptance remain deployment gates.
