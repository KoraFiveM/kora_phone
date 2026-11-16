---
title: Troubleshooting
sidebar_position: 19
---

# Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Resource stops with `Install the kora_inventory PhoneItemTransaction companion before starting kora_phone` | `kora_inventory` is missing, not started yet, or too old to export `PhoneItemTransaction` (it ships in kora_inventory itself; there is no separate companion file). Start `kora_inventory` first and update it ([Installation](./installation.md)) |
| `Database unavailable; stopping resource` | `kora_sql` was not ready within `Config.Server.DatabaseReadyTimeoutMs`. Check the database and start order |
| `Database setup failed; stopping resource` | Table creation failed; the reason is in the log line. Check database permissions |
| `Schema setup reported a warning` lines | An existing table differs from `server/schema.lua` or `server/sdk/schema.lua`. Nothing is altered; reconcile by hand |
| Phone will not open | No handset item (`Config.RequirePhoneItem`), the player is dead or in last stand (`Config.Client.DisableWhileDead`), or another resource set the `Config.Client.UiBlockBag` state bag. The UI shows the reason |
| Camera or Gallery unavailable | `Config.Server.Media.Provider` is `disabled`. Photos are captured by `kora_lib` (`Kora.screenshot`), so check that `kora_lib` is started. With the `local-development` provider, `CAPTURE_FAILED` means the client could not return the screenshot to `Kora.screenshot.requestClient`, and `SCREENSHOT_PROVIDER_UNAVAILABLE` means kora_lib's screenshot module is not loaded ([Media storage](./media-storage.md)) |
| `PROVIDER_MISCONFIGURED` or console message that Fivemanage would not issue an upload URL | `kora_fivemanage_token` is unset or wrong ([Media storage](./media-storage.md)) |
| No video clips | Only `fivemanage` and `external` providers support video |
| Wallet shows no Send form, or a transfer says transfers are unavailable | `Config.Server.Banking.Enabled` is off, `kora_banking` is not started, or `Config.transactionCallers` in kora_banking lacks `kora_phone` ([Banking and jobs](./banking-jobs.md)) |
| Garage app missing | `Config.Server.Garage.Enabled` is off or `kora_garages` is not started |
| Home (Property) app missing | A configured housing table or column does not exist, or `Config.Server.Property.Enabled` is off ([Configuration](./configuration.md)); the check is cached until restart |
| Duty button refused | `Config.Server.Jobs.AllowDutyToggle` is off, or `kora_multijob` marks the active job as duty locked |
| A third-party app does not appear | Its manifest was rejected (look for `phone.sdk.manifest_rejected` in the log), its resource started before `kora_phone` finished loading and has not been rescanned, or the `entry` file is missing from its `files` ([App SDK](./apps.md)) |
| PINs stop working after a restart | `kora_phone_pin_pepper` changed; it must stay stable |
| Calls ring but no audio | `kora_voice` is not started or its `setPlayerCall` export fails (see the server log for `voice.assign_failed`) |
| The mute button fails in a call | The phone calls `exports.kora_voice:setCallMuted`, which only mutes the call. It returns `not_in_call` when kora_voice has no call published for this player yet, and `CALL_MUTE_FAILED` when the export errors (check that kora_voice is started and up to date). The speaker button is a presentation flag and does not change audio |
| Video call connects only for some players | STUN alone fails behind strict NAT; add a TURN server via `kora_phone_turn_urls` and `kora_phone_turn_secret` |
| Custom app addon errors when calling `exports['lb-phone']` | Another real phone with the same name is running; run only one provider |
| `Share phone number` option missing | `Config.ShareNumber.Enabled` is false, `kora_target` is not started, or the player holds no handset |
| Service counter prompts overlap other interactions | Move the shop coordinates a few metres away from other zones |
