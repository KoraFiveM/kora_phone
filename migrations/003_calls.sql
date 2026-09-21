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

