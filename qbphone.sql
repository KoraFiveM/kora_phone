-- QBPhone master SQL — fresh installations only.
-- Import this file once into a database with no existing phone_* tables.
-- Existing Stevie/QBPhone databases: do not import this file; start qbphone
-- with Config.Server.AutoMigrate=true to apply/resume tracked upgrades.
-- Leave AutoMigrate enabled after a fresh import so startup adopts schema history.
-- This installs schema only. Identity/data conversion and preflight run on startup.

-- Source: migrations/001_initial.sql
CREATE TABLE IF NOT EXISTS `phone_devices` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_citizenid` VARCHAR(64) NOT NULL,
  `phone_number` VARCHAR(24) NOT NULL,
  `label` VARCHAR(64) NOT NULL DEFAULT 'Personal',
  `settings_json` JSON NOT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_devices_number` (`phone_number`),
  KEY `idx_phone_devices_owner_active` (`owner_citizenid`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_contacts` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_device_id` BIGINT UNSIGNED NOT NULL,
  `display_name` VARCHAR(64) NOT NULL,
  `phone_number` VARCHAR(24) NOT NULL,
  `avatar_media_id` BIGINT UNSIGNED NULL,
  `is_favorite` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_contacts_owner_number` (`owner_device_id`, `phone_number`),
  CONSTRAINT `fk_phone_contacts_owner` FOREIGN KEY (`owner_device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_conversations` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `type` ENUM('direct','group') NOT NULL,
  `title` VARCHAR(80) NULL,
  `created_by_device_id` BIGINT UNSIGNED NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_phone_conversations_creator` FOREIGN KEY (`created_by_device_id`) REFERENCES `phone_devices` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_conversation_members` (
  `conversation_id` BIGINT UNSIGNED NOT NULL,
  `device_id` BIGINT UNSIGNED NOT NULL,
  `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `left_at` TIMESTAMP NULL,
  `last_read_message_id` BIGINT UNSIGNED NULL,
  `is_muted` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`conversation_id`, `device_id`),
  KEY `idx_phone_members_device` (`device_id`, `left_at`),
  CONSTRAINT `fk_phone_members_conversation` FOREIGN KEY (`conversation_id`) REFERENCES `phone_conversations` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_phone_members_device` FOREIGN KEY (`device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_messages` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `conversation_id` BIGINT UNSIGNED NOT NULL,
  `sender_device_id` BIGINT UNSIGNED NOT NULL,
  `message_type` ENUM('text','image','location','system') NOT NULL DEFAULT 'text',
  `body` TEXT NULL,
  `media_id` BIGINT UNSIGNED NULL,
  `reply_to_id` BIGINT UNSIGNED NULL,
  `client_request_id` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `edited_at` TIMESTAMP NULL,
  `deleted_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_messages_idempotency` (`sender_device_id`, `client_request_id`),
  KEY `idx_phone_messages_conversation_id` (`conversation_id`, `id`),
  CONSTRAINT `fk_phone_messages_conversation` FOREIGN KEY (`conversation_id`) REFERENCES `phone_conversations` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_phone_messages_sender` FOREIGN KEY (`sender_device_id`) REFERENCES `phone_devices` (`id`),
  CONSTRAINT `fk_phone_messages_reply` FOREIGN KEY (`reply_to_id`) REFERENCES `phone_messages` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source: migrations/002_indexes.sql
ALTER TABLE `phone_conversations`
  ADD INDEX `idx_phone_conversations_updated` (`updated_at`, `id`);

-- Source: migrations/003_calls.sql
CREATE TABLE IF NOT EXISTS `phone_calls` (
  `id` CHAR(36) NOT NULL,
  `caller_device_id` BIGINT UNSIGNED NOT NULL,
  `callee_device_id` BIGINT UNSIGNED NOT NULL,
  `caller_number_snapshot` VARCHAR(24) NOT NULL,
  `callee_number_snapshot` VARCHAR(24) NOT NULL,
  `status` ENUM('ringing','active','ended','rejected','missed','cancelled') NOT NULL,
  `voice_channel` INT UNSIGNED NOT NULL,
  `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `answered_at` TIMESTAMP NULL,
  `ended_at` TIMESTAMP NULL,
  `ended_reason` VARCHAR(48) NULL,
  PRIMARY KEY (`id`),
  KEY `idx_phone_calls_caller_history` (`caller_device_id`, `started_at`, `id`),
  KEY `idx_phone_calls_callee_history` (`callee_device_id`, `started_at`, `id`),
  KEY `idx_phone_calls_unfinished` (`status`, `started_at`),
  CONSTRAINT `fk_phone_calls_caller` FOREIGN KEY (`caller_device_id`) REFERENCES `phone_devices` (`id`),
  CONSTRAINT `fk_phone_calls_callee` FOREIGN KEY (`callee_device_id`) REFERENCES `phone_devices` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source: migrations/004_media.sql
CREATE TABLE IF NOT EXISTS `phone_media` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_device_id` BIGINT UNSIGNED NOT NULL,
  `storage_provider` VARCHAR(32) NOT NULL,
  `storage_key` VARCHAR(512) NOT NULL,
  `public_url` VARCHAR(2048) NOT NULL,
  `mime_type` VARCHAR(64) NOT NULL,
  `byte_size` BIGINT UNSIGNED NOT NULL,
  `width` INT UNSIGNED NULL,
  `height` INT UNSIGNED NULL,
  `checksum` VARCHAR(128) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_media_provider_key` (`storage_provider`, `storage_key`),
  KEY `idx_phone_media_owner_page` (`owner_device_id`, `deleted_at`, `id`),
  CONSTRAINT `fk_phone_media_owner` FOREIGN KEY (`owner_device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `phone_contacts`
  ADD CONSTRAINT `fk_phone_contacts_avatar_media`
  FOREIGN KEY (`avatar_media_id`) REFERENCES `phone_media` (`id`) ON DELETE SET NULL;

ALTER TABLE `phone_messages`
  ADD CONSTRAINT `fk_phone_messages_media`
  FOREIGN KEY (`media_id`) REFERENCES `phone_media` (`id`) ON DELETE SET NULL;

-- Source: migrations/005_economy_audit.sql
CREATE TABLE IF NOT EXISTS `phone_economy_audit` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sender_device_id` BIGINT UNSIGNED NOT NULL,
  `recipient_device_id` BIGINT UNSIGNED NOT NULL,
  `sender_citizenid` VARCHAR(64) NOT NULL,
  `recipient_citizenid` VARCHAR(64) NOT NULL,
  `amount` BIGINT UNSIGNED NOT NULL,
  `status` ENUM('pending','completed','rejected','rolled_back','manual_review') NOT NULL DEFAULT 'pending',
  `client_request_id` VARCHAR(64) NOT NULL,
  `failure_code` VARCHAR(48) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_economy_idempotency` (`sender_citizenid`, `client_request_id`),
  KEY `idx_phone_economy_sender_device` (`sender_device_id`, `id`),
  KEY `idx_phone_economy_recipient_device` (`recipient_device_id`, `id`),
  KEY `idx_phone_economy_status` (`status`, `created_at`),
  CONSTRAINT `fk_phone_economy_sender_device` FOREIGN KEY (`sender_device_id`) REFERENCES `phone_devices` (`id`),
  CONSTRAINT `fk_phone_economy_recipient_device` FOREIGN KEY (`recipient_device_id`) REFERENCES `phone_devices` (`id`),
  CONSTRAINT `chk_phone_economy_positive_amount` CHECK (`amount` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source: migrations/006_community.sql
CREATE TABLE IF NOT EXISTS `phone_social_profiles` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `device_id` BIGINT UNSIGNED NOT NULL,
  `handle` VARCHAR(24) NOT NULL,
  `display_name` VARCHAR(64) NOT NULL,
  `bio` VARCHAR(280) NOT NULL DEFAULT '',
  `avatar_media_id` BIGINT UNSIGNED NULL,
  `is_private` TINYINT(1) NOT NULL DEFAULT 0,
  `is_suspended` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_social_profile_device` (`device_id`),
  UNIQUE KEY `uq_phone_social_profile_handle` (`handle`),
  CONSTRAINT `fk_phone_social_profile_device` FOREIGN KEY (`device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_social_posts` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `author_profile_id` BIGINT UNSIGNED NOT NULL,
  `body` VARCHAR(5000) NOT NULL,
  `client_request_id` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_social_post_request` (`author_profile_id`, `client_request_id`),
  KEY `idx_phone_social_posts_feed` (`deleted_at`, `id`),
  CONSTRAINT `fk_phone_social_post_author` FOREIGN KEY (`author_profile_id`) REFERENCES `phone_social_profiles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_social_comments` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id` BIGINT UNSIGNED NOT NULL,
  `author_profile_id` BIGINT UNSIGNED NOT NULL,
  `body` VARCHAR(1000) NOT NULL,
  `client_request_id` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `deleted_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_social_comment_request` (`author_profile_id`, `client_request_id`),
  KEY `idx_phone_social_comments_post` (`post_id`, `deleted_at`, `id`),
  CONSTRAINT `fk_phone_social_comment_post` FOREIGN KEY (`post_id`) REFERENCES `phone_social_posts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_phone_social_comment_author` FOREIGN KEY (`author_profile_id`) REFERENCES `phone_social_profiles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_social_likes` (
  `post_id` BIGINT UNSIGNED NOT NULL,
  `profile_id` BIGINT UNSIGNED NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`post_id`, `profile_id`),
  CONSTRAINT `fk_phone_social_like_post` FOREIGN KEY (`post_id`) REFERENCES `phone_social_posts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_phone_social_like_profile` FOREIGN KEY (`profile_id`) REFERENCES `phone_social_profiles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_social_follows` (
  `follower_profile_id` BIGINT UNSIGNED NOT NULL,
  `following_profile_id` BIGINT UNSIGNED NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`follower_profile_id`, `following_profile_id`),
  CONSTRAINT `fk_phone_social_follow_follower` FOREIGN KEY (`follower_profile_id`) REFERENCES `phone_social_profiles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_phone_social_follow_following` FOREIGN KEY (`following_profile_id`) REFERENCES `phone_social_profiles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_blocks` (
  `blocker_device_id` BIGINT UNSIGNED NOT NULL,
  `blocked_device_id` BIGINT UNSIGNED NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`blocker_device_id`, `blocked_device_id`),
  CONSTRAINT `fk_phone_block_blocker` FOREIGN KEY (`blocker_device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_phone_block_blocked` FOREIGN KEY (`blocked_device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_market_listings` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_device_id` BIGINT UNSIGNED NOT NULL,
  `title` VARCHAR(80) NOT NULL,
  `description` VARCHAR(2000) NOT NULL DEFAULT '',
  `category` ENUM('vehicle','property','electronics','services','other') NOT NULL DEFAULT 'other',
  `price` BIGINT UNSIGNED NOT NULL,
  `client_request_id` VARCHAR(64) NOT NULL,
  `status` ENUM('active','sold','removed') NOT NULL DEFAULT 'active',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_market_request` (`owner_device_id`, `client_request_id`),
  KEY `idx_phone_market_feed` (`status`, `id`),
  CONSTRAINT `fk_phone_market_owner` FOREIGN KEY (`owner_device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_reports` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reporter_device_id` BIGINT UNSIGNED NOT NULL,
  `target_type` ENUM('profile','post','comment','listing') NOT NULL,
  `target_id` BIGINT UNSIGNED NOT NULL,
  `reason` ENUM('spam','harassment','scam','illegal','other') NOT NULL,
  `details` VARCHAR(1000) NOT NULL DEFAULT '',
  `snapshot_json` JSON NOT NULL,
  `status` ENUM('open','reviewing','resolved','dismissed') NOT NULL DEFAULT 'open',
  `assigned_citizenid` VARCHAR(64) NULL,
  `resolution_note` VARCHAR(1000) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_report_repeat` (`reporter_device_id`, `target_type`, `target_id`),
  KEY `idx_phone_reports_queue` (`status`, `id`),
  CONSTRAINT `fk_phone_report_reporter` FOREIGN KEY (`reporter_device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `phone_moderation_audit` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_citizenid` VARCHAR(64) NOT NULL,
  `action` VARCHAR(48) NOT NULL,
  `target_type` VARCHAR(24) NOT NULL,
  `target_id` BIGINT UNSIGNED NOT NULL,
  `reason` VARCHAR(1000) NOT NULL,
  `metadata_json` JSON NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_phone_moderation_audit_target` (`target_type`, `target_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source: migrations/007_messaging.sql
ALTER TABLE `phone_conversations`
  ADD COLUMN `direct_key` VARCHAR(64) NULL AFTER `title`,
  ADD UNIQUE KEY `uq_phone_conversations_direct_key` (`direct_key`);

CREATE TABLE IF NOT EXISTS `phone_message_deletions` (
  `message_id` BIGINT UNSIGNED NOT NULL,
  `device_id` BIGINT UNSIGNED NOT NULL,
  `deleted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`message_id`, `device_id`),
  KEY `idx_phone_message_deletions_device` (`device_id`, `message_id`),
  CONSTRAINT `fk_phone_message_deletions_message` FOREIGN KEY (`message_id`) REFERENCES `phone_messages` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_phone_message_deletions_device` FOREIGN KEY (`device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source: migrations/008_pin.sql
-- Server-side phone PIN. The PIN is never stored: pin_hash = SHA2(salt + optional
-- server pepper + pin, 256), computed inside the database so the PIN never has to be
-- hashed (or logged) by Lua. Applied automatically, once, at resource start (server/integrations/migrations.lua).
ALTER TABLE `phone_devices`
  ADD COLUMN `pin_hash` CHAR(64) NULL AFTER `settings_json`,
  ADD COLUMN `pin_salt` CHAR(32) NULL AFTER `pin_hash`,
  ADD COLUMN `pin_failed_attempts` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `pin_salt`,
  ADD COLUMN `pin_locked_until` INT UNSIGNED NULL AFTER `pin_failed_attempts`;

-- Source: migrations/009_items.sql
-- Per-phone notes, alarms and music stations. One small table keyed by (device, kind, item id):
-- the payload is validated JSON written only by the server. Applied automatically, once, at resource start (server/integrations/migrations.lua).
CREATE TABLE IF NOT EXISTS `phone_items` (
  `device_id` BIGINT UNSIGNED NOT NULL,
  `kind` ENUM('note','alarm','station') NOT NULL,
  `item_key` VARCHAR(64) NOT NULL,
  `payload` TEXT NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`device_id`, `kind`, `item_key`),
  KEY `idx_phone_items_updated` (`device_id`, `kind`, `updated_at`),
  CONSTRAINT `fk_phone_items_device` FOREIGN KEY (`device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source: migrations/010_mail.sql
-- Phone mail: subject + body between two phones. Each side deletes its own copy.
-- Applied automatically, once, at resource start (server/integrations/migrations.lua).
CREATE TABLE IF NOT EXISTS `phone_mail` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sender_device_id` BIGINT UNSIGNED NOT NULL,
  `recipient_device_id` BIGINT UNSIGNED NOT NULL,
  `subject` VARCHAR(120) NOT NULL,
  `body` TEXT NOT NULL,
  `client_request_id` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `read_at` TIMESTAMP NULL,
  `sender_deleted` TINYINT(1) NOT NULL DEFAULT 0,
  `recipient_deleted` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_phone_mail_idempotency` (`sender_device_id`, `client_request_id`),
  KEY `idx_phone_mail_inbox` (`recipient_device_id`, `recipient_deleted`, `id`),
  KEY `idx_phone_mail_sent` (`sender_device_id`, `sender_deleted`, `id`),
  CONSTRAINT `fk_phone_mail_sender` FOREIGN KEY (`sender_device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_phone_mail_recipient` FOREIGN KEY (`recipient_device_id`) REFERENCES `phone_devices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source: migrations/011_media_posts.sql
-- Flash posts and chat messages can carry a photo or video from phone_media (uploaded through the
-- media provider, see docs/media-storage.md). Applied automatically, once, at resource start (server/integrations/migrations.lua).
ALTER TABLE `phone_social_posts`
  ADD COLUMN `media_id` BIGINT UNSIGNED NULL AFTER `body`,
  ADD KEY `idx_phone_social_posts_media` (`media_id`),
  ADD CONSTRAINT `fk_phone_social_posts_media` FOREIGN KEY (`media_id`) REFERENCES `phone_media` (`id`) ON DELETE SET NULL;

ALTER TABLE `phone_messages`
  MODIFY COLUMN `message_type` ENUM('text','image','video','location','system') NOT NULL DEFAULT 'text';

-- Source: migrations/012_handsets.sql
CREATE TABLE IF NOT EXISTS phone_cloud_accounts (
 id VARCHAR(64) NOT NULL PRIMARY KEY, owner_citizenid VARCHAR(64) NOT NULL,
 recovery_hash CHAR(64) NOT NULL, snapshot_json LONGTEXT NULL, revision INT NOT NULL DEFAULT 0,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY cloud_owner (owner_citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_handsets (
 id VARCHAR(64) NOT NULL PRIMARY KEY, model VARCHAR(12) NOT NULL,
 device_id BIGINT UNSIGNED NOT NULL UNIQUE, account_id VARCHAR(64) NULL,
 face_citizenid VARCHAR(64) NULL, pin_kdf VARCHAR(200) NULL,
 is_reset TINYINT NOT NULL DEFAULT 0, cloud_revision INT NOT NULL DEFAULT 0,
 FOREIGN KEY (device_id) REFERENCES phone_devices(id),
 FOREIGN KEY (account_id) REFERENCES phone_cloud_accounts(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_sims (
 id VARCHAR(64) NOT NULL PRIMARY KEY, phone_number VARCHAR(24) NOT NULL,
 owner_citizenid VARCHAR(64) NOT NULL, status ENUM('active','blocked','revoked') NOT NULL DEFAULT 'active',
 active_number VARCHAR(24) GENERATED ALWAYS AS (CASE WHEN status='active' THEN phone_number ELSE NULL END) STORED UNIQUE,
 handset_id VARCHAR(64) NULL UNIQUE, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY sim_number (phone_number,status), FOREIGN KEY (handset_id) REFERENCES phone_handsets(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_legacy_claims (
 device_id BIGINT UNSIGNED NOT NULL PRIMARY KEY, citizenid VARCHAR(64) NOT NULL,
 handset_id VARCHAR(64) NULL UNIQUE, account_id VARCHAR(64) NOT NULL,
 claimed_at TIMESTAMP NULL, KEY legacy_character (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_mailboxes (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, device_id BIGINT UNSIGNED NOT NULL,
 peer_number VARCHAR(24) NOT NULL, sender_number VARCHAR(24) NOT NULL,
 body TEXT NOT NULL, media_id BIGINT UNSIGNED NULL, request_id VARCHAR(100) NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, is_read TINYINT NOT NULL DEFAULT 0, is_outgoing TINYINT NOT NULL DEFAULT 0,
 UNIQUE KEY delivery_once (device_id,request_id), KEY mailbox_thread (device_id,peer_number,id),
 FOREIGN KEY (device_id) REFERENCES phone_devices(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_threads (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, device_id BIGINT UNSIGNED NOT NULL,
 peer_number VARCHAR(24) NOT NULL, UNIQUE KEY own_thread (device_id,peer_number),
 FOREIGN KEY (device_id) REFERENCES phone_devices(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_migration_issues (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, device_id BIGINT UNSIGNED NULL,
 issue_key VARCHAR(160) NOT NULL UNIQUE, detail TEXT NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_gallery_links (
 device_id BIGINT UNSIGNED NOT NULL, media_id BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY(device_id,media_id), FOREIGN KEY(device_id) REFERENCES phone_devices(id),
 FOREIGN KEY(media_id) REFERENCES phone_media(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_cloud_media (
 account_id VARCHAR(64) NOT NULL, media_id BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY(account_id,media_id), FOREIGN KEY(account_id) REFERENCES phone_cloud_accounts(id),
 FOREIGN KEY(media_id) REFERENCES phone_media(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_upgrade_state (
 name VARCHAR(64) NOT NULL PRIMARY KEY, completed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_call_hidden (
 device_id BIGINT UNSIGNED NOT NULL, call_id CHAR(36) NOT NULL,
 PRIMARY KEY(device_id,call_id), FOREIGN KEY(device_id) REFERENCES phone_devices(id),
 FOREIGN KEY(call_id) REFERENCES phone_calls(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_sim_replacements (
 id VARCHAR(64) NOT NULL PRIMARY KEY, old_sim_id VARCHAR(64) NOT NULL,
 new_sim_id VARCHAR(64) NOT NULL UNIQUE, handset_id VARCHAR(64) NOT NULL,
 citizenid VARCHAR(64) NOT NULL, state ENUM('prepared','complete','cancelled') NOT NULL DEFAULT 'prepared',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source: migrations/013_legacy_qb_phone.sql
-- Character-owned integration mail stays separate from physical handset content.
CREATE TABLE IF NOT EXISTS phone_legacy_mail (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 legacy_source_id BIGINT UNSIGNED NULL UNIQUE,
 citizenid VARCHAR(64) NOT NULL, sender VARCHAR(100) NOT NULL,
 subject VARCHAR(120) NOT NULL, body TEXT NOT NULL, button_json LONGTEXT NULL,
 read_at TIMESTAMP NULL, deleted_at TIMESTAMP NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY legacy_mail_owner (citizenid,deleted_at,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_legacy_transactions (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 citizenid VARCHAR(64) NOT NULL, title VARCHAR(100) NOT NULL, message VARCHAR(1000) NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY legacy_transactions_owner (citizenid,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
