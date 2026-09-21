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
