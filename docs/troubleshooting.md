---
title: Troubleshooting
sidebar_position: 19
---

# Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Resource stops with `Install the kora_inventory PhoneItemTransaction companion before starting kora_phone` | `kora_inventory` does not export `PhoneItemTransaction`. Integrate `integration/kora_inventory/server.lua` ([Installation](./installation.md)) |
| `Database unavailable; stopping resource` | `kora_sql` was not ready within `Config.Server.DatabaseReadyTimeoutMs`. Check the database and start order |
| `Database setup failed, stopping resource: ...` | Table creation failed; the reason is printed. Check database permissions |
| `schema warning (...)` lines | An existing table differs from `server/schema.lua`. Nothing is altered; reconcile by hand |
| Phone will not open | No handset item (`Config.RequirePhoneItem`), the player is dead or in last stand (`Config.Client.DisableWhileDead`), or another resource set the `Config.Client.UiBlockBag` state bag. The UI shows the reason |
| Camera or Gallery unavailable | `Config.Server.Media.Provider` is `disabled`, or `screenshot-basic` is not started (`SCREENSHOT_PROVIDER_UNAVAILABLE`) |
| `PROVIDER_MISCONFIGURED` or console message that Fivemanage would not issue an upload URL | `kora_fivemanage_token` is unset or wrong ([Media storage](./media-storage.md)) |
| No video clips | Only `fivemanage` and `external` providers support video |
| Wallet shows no Send form | `Config.Server.Banking.AllowCompensatingTransfers` is `false` (default) ([Banking and jobs](./banking-jobs.md)) |
| Garage or Home app missing | The configured vehicle or housing table or columns do not exist ([Configuration](./configuration.md)); the check is cached until restart |
| PINs stop working after a restart | `kora_phone_pin_pepper` changed; it must stay stable |
| Calls ring but no audio | `pma-voice` (or `kora_voice`) is not started or its `setPlayerCall` export fails |
| Video call connects only for some players | STUN alone fails behind strict NAT; add a TURN server via `kora_phone_turn_urls` and `kora_phone_turn_secret` |
| Custom app addon errors when calling `exports['lb-phone']` | Another real phone with the same name is running; run only one provider |
| `Share phone number` option missing | `Config.ShareNumber.Enabled` is false, `kora_target` is not started, or the player holds no handset |
| Service counter prompts overlap other interactions | Move the shop coordinates a few metres away from other zones |
