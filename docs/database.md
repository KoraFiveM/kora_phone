---
title: Database
sidebar_position: 13
---

# Database

`server/schema.lua` declares the tables (`KoraPhoneSchema`) and `server/integrations/schema_setup.lua` applies them with `Kora.sql.ensureTables` after `kora_sql` is ready. Only missing tables, columns, indexes and keys are added; nothing is altered or dropped. If the database is not ready within `Config.Server.DatabaseReadyTimeoutMs`, or setup fails, the resource stops itself. Collation is `utf8mb4_unicode_ci`. There is no SQL file to import and no migration of data from another phone.

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
| `phone_items` | Notes, alarms and Sound stations | `device_id`, `kind` (`note`, `alarm`, `station`), `item_key`, `payload` |
| `phone_mailboxes`, `phone_threads` | Per-handset message copies and thread index | `device_id`, `peer_number`, `sender_number`, `body`, `request_id`, `is_read`, `is_outgoing` |
| `phone_conversations`, `phone_conversation_members`, `phone_messages`, `phone_message_deletions` | Older conversation tables, still read for legacy groups and message media | `type`, `direct_key`, `message_type` |
| `phone_calls`, `phone_call_hidden` | Call history and per-handset hidden calls | `caller_number_snapshot`, `callee_number_snapshot`, `status`, `voice_channel`, `started_at` |
| `phone_media`, `phone_gallery_links` | Uploaded media and which handsets show them | `owner_device_id`, `storage_provider`, `storage_key`, `public_url`, `mime_type`, `byte_size`, `width`, `height`, `checksum`, `deleted_at` |
| `phone_mail` | Device-to-device mail | `sender_device_id`, `recipient_device_id`, `subject`, `body`, `client_request_id`, `read_at`, `sender_deleted`, `recipient_deleted` |
| `phone_legacy_mail` | Character-owned system mail (qb-phone compat) | `citizenid`, `sender`, `subject`, `body`, `button_json`, `read_at`, `deleted_at` |
| `phone_legacy_transactions` | Character-owned transaction notes | `citizenid`, `title`, `message` |
| `phone_economy_audit` | Wallet transfer audit | `sender_citizenid`, `recipient_citizenid`, `amount`, `status`, `client_request_id` |
| `phone_blocks` | Device-level blocks | `blocker_device_id`, `blocked_device_id` |
| `phone_social_profiles`, `phone_social_posts`, `phone_social_comments`, `phone_social_likes`, `phone_social_follows` | Pulse and Flash data | `handle`, `display_name`, `bio`, `body`, `media_id`, `client_request_id` |
| `phone_market_listings` | Market listings | `title`, `description`, `category`, `price`, `client_request_id`, `status` |
| `phone_reports`, `phone_moderation_audit` | Reports and moderator actions | `target_type`, `reason`, `details`, `snapshot_json`, `status`; `actor_citizenid`, `action`, `metadata_json` |
| `phone_legacy_claims`, `phone_migration_issues` | Declared in the schema and referenced only by handset bookkeeping code | `citizenid`, `account_id`; `issue_key`, `detail` |

## Reads of other tables

The Garage app reads `Config.Server.Garage.Table` (default `player_vehicles`, columns vehicle, plate, garage, state, fuel). The Property app reads the tables and columns named in `Config.Server.Property` (defaults follow qb-houses: `player_houses`, `houselocations`). Both are read only. See [Configuration](./configuration.md).

## Operational notes

- Back up all `phone_*` tables together with inventories and `kora_inventory` shop stock; never restore the phone tables alone ([Handsets, SIMs and cloud](./three-handsets.md)).
- Media rows are soft-deleted first; see [Media storage](./media-storage.md).
- Review old `phone_economy_audit` rows with status `pending` or `manual_review` ([Banking and jobs](./banking-jobs.md)).
