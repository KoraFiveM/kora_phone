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

