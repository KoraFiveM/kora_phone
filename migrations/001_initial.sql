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

