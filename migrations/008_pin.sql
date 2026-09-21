-- Server-side phone PIN. The PIN is never stored: pin_hash = SHA2(salt + optional
-- server pepper + pin, 256), computed inside the database so the PIN never has to be
-- hashed (or logged) by Lua. Applied automatically, once, at resource start (server/integrations/migrations.lua).
ALTER TABLE `phone_devices`
  ADD COLUMN `pin_hash` CHAR(64) NULL AFTER `settings_json`,
  ADD COLUMN `pin_salt` CHAR(32) NULL AFTER `pin_hash`,
  ADD COLUMN `pin_failed_attempts` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `pin_salt`,
  ADD COLUMN `pin_locked_until` INT UNSIGNED NULL AFTER `pin_failed_attempts`;
