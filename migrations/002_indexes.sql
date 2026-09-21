ALTER TABLE `phone_conversations`
  ADD INDEX `idx_phone_conversations_updated` (`updated_at`, `id`);

