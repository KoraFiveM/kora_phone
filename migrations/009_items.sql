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
