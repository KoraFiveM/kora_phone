-- Flash posts and chat messages can carry a photo or video from phone_media (uploaded through the
-- media provider, see docs/media-storage.md). Applied automatically, once, at resource start (server/integrations/migrations.lua).
ALTER TABLE `phone_social_posts`
  ADD COLUMN `media_id` BIGINT UNSIGNED NULL AFTER `body`,
  ADD KEY `idx_phone_social_posts_media` (`media_id`),
  ADD CONSTRAINT `fk_phone_social_posts_media` FOREIGN KEY (`media_id`) REFERENCES `phone_media` (`id`) ON DELETE SET NULL;

ALTER TABLE `phone_messages`
  MODIFY COLUMN `message_type` ENUM('text','image','video','location','system') NOT NULL DEFAULT 'text';
