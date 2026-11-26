---
title: Database
sidebar_position: 13
---

# Database

`server/schema.lua` declares the tables (`KoraPhoneSchema`) and `server/sdk/schema.lua` declares the app SDK table (`KoraPhoneSdkSchema`, listed after the core tables because it references `phone_devices`). `server/integrations/schema_setup.lua` passes both to `Kora.sql.ensureTables` after `kora_sql` is ready. There are no migrations, no `.sql` files and no converters. Only missing tables, columns, indexes and keys are added; nothing is altered or dropped. If the database is not ready within `Config.Server.DatabaseReadyTimeoutMs`, or setup fails, the resource stops itself. Collation is `utf8mb4_unicode_ci`. There is no SQL file to import.

## Where the SQL lives

All queries run through `Kora.sql` and live in `server/repositories/`. Services, handlers and the handset files call repositories only; `tests/schema-manifest.test.js` fails when SQL appears anywhere else. The SDK storage table has its own repository, `server/sdk/storage_repository.lua`. `server/integrations/database.lua` holds the small shared helpers (`rows`, `row`, `value`, `number`, `flag`, `write`, `changed`, `insert`, `transaction`) the repositories use.

| Repository | Owns |
| --- | --- |
| `phones` | Device profile, settings and PIN state (legacy hash and handset KDF) |
| `handsets` | Handset identity, Face ID, factory reset and resale content count |
| `sims` | SIM rows, attaching a SIM to a handset, replacement journal |
| `cloud` | Cloud accounts, backup snapshots, restore and recovery code rotation |
| `mailboxes` | Per-handset message copies and thread index |
| `media`, `contacts`, `items`, `blocks`, `calls`, `mail`, `system_mail`, `messages`, `social`, `marketplace`, `reports`, `transactions` | One app each (`transactions` is the Banking history) |
| `external` | Read-only access to the housing tables named in `Config.Server.Property` (vehicles come from kora_core, not SQL) |
| `health` | Database liveness check used at start |

JSON columns (`settings_json`, report snapshots) are read with `CAST(... AS CHAR)` so callers always receive text, and timestamps are read with `UNIX_TIMESTAMP`, because `Kora.sql` does not convert column types.

## Tables

| Table | Purpose | Key columns |
| --- | --- | --- |
| `phone_devices` | One local profile per handset | `owner_citizenid`, `phone_number` (unique), `label`, `settings_json`, `pin_hash`, `pin_salt` (legacy PIN storage), `pin_failed_attempts`, `pin_locked_until`, `is_active` |
| `phone_handsets` | Binds a handset serial to a device | `id` (serial), `model`, `device_id`, `account_id`, `face_citizenid`, `pin_kdf` (scrypt PIN), `is_reset`, `cloud_revision` |
| `phone_sims` | SIMs and their numbers | `id`, `phone_number`, `owner_citizenid`, `status` (`active`, `blocked`, `revoked`), `active_number` (generated, unique), `handset_id` |
| `phone_sim_replacements` | Replacement journal | `old_sim_id`, `new_sim_id`, `handset_id`, `citizenid`, `state` (`prepared`, `complete`, `cancelled`) |
| `phone_cloud_accounts` | Cloud accounts | `id`, `owner_citizenid`, `recovery_hash`, `revision` |
| `phone_cloud_media` | Media granted to cloud accounts | `account_id`, `media_id` |
| `phone_contacts` | Contacts per device | `owner_device_id`, `display_name`, `phone_number` |
| `phone_items` | Alarms and Sound stations | `device_id`, `kind` (`alarm`, `station`), `item_key`, `payload` |
| `phone_mailboxes`, `phone_threads` | Per-handset message copies and thread index | `device_id`, `peer_number`, `sender_number`, `body`, `request_id`, `is_read`, `is_outgoing` |
| `phone_conversations`, `phone_conversation_members`, `phone_messages`, `phone_message_deletions` | Older conversation tables, still read for legacy groups and message media | `type`, `direct_key`, `message_type` |
| `phone_calls`, `phone_call_hidden` | Call history and per-handset hidden calls | `caller_number_snapshot`, `callee_number_snapshot`, `status`, `voice_channel`, `started_at` |
| `phone_media`, `phone_gallery_links` | Uploaded media and which handsets show them | `owner_device_id`, `storage_provider`, `storage_key`, `public_url`, `mime_type`, `byte_size`, `width`, `height`, `checksum`, `deleted_at` |
| `phone_mail` | Device-to-device mail | `sender_device_id`, `recipient_device_id`, `subject`, `body`, `client_request_id`, `read_at`, `sender_deleted`, `recipient_deleted` |
| `phone_system_mail` | Character-owned system mail | `citizenid`, `sender`, `subject`, `body`, `button_json`, `read_at`, `deleted_at` |
| `phone_system_activity` | Character-owned transaction notes | `citizenid`, `title`, `message` |
| `phone_bank_history` | One row per completed phone-to-phone transfer, written inside kora_banking's durable transaction | `operation_key` (unique), `sender_device_id`, `recipient_device_id`, `amount` |
| `phone_app_storage` | Per-device storage of SDK apps (`server/sdk/schema.lua`) | `device_id`, `app_id`, `key` (the three form the primary key), `value` (JSON), `updated_at` |
| `phone_blocks` | Device-level blocks | `blocker_device_id`, `blocked_device_id` |
| `phone_social_profiles`, `phone_social_posts`, `phone_social_comments`, `phone_social_likes`, `phone_social_follows` | Pulse and Flash data | `handle`, `display_name`, `bio`, `body`, `media_id`, `client_request_id` |
| `phone_market_listings` | Market listings | `title`, `description`, `category`, `price`, `client_request_id`, `status` |
| `phone_reports`, `phone_moderation_audit` | Reports and moderator actions | `target_type`, `reason`, `details`, `snapshot_json`, `status`; `actor_citizenid`, `action`, `metadata_json` |

## Reads of other tables

The phone runs no SQL against vehicle tables: the Garage app reads owned vehicles through `exports.kora_garages:getOwnedVehicles`. The Property app reads the tables and columns named in `Config.Server.Property` (defaults follow qb-houses: `player_houses`, `houselocations`); there is no Kora housing resource, so the names are configurable. That access is read only. See [Configuration](./configuration.md).

## Operational notes

- Back up all `phone_*` tables together with inventories and `kora_inventory` shop stock; never restore the phone tables alone ([Handsets, SIMs and cloud](./three-handsets.md)).
- Media rows are soft-deleted first; see [Media storage](./media-storage.md).
- `phone_bank_history` only gets a row when kora_banking commits the transfer; reconcile money questions against kora_banking's own ledger ([Banking and jobs](./banking-jobs.md)).
