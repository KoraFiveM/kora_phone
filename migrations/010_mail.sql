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
