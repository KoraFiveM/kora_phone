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

