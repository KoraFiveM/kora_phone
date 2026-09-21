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

