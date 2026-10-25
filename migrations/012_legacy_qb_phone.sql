-- Named system mail can arrive before its recipient has provisioned a device.
-- Existing device-to-device rows and foreign keys are retained.
ALTER TABLE phone_mail MODIFY sender_device_id BIGINT UNSIGNED NULL;
ALTER TABLE phone_mail MODIFY recipient_device_id BIGINT UNSIGNED NULL;
ALTER TABLE phone_mail ADD COLUMN recipient_citizenid VARCHAR(64) NULL;
ALTER TABLE phone_mail ADD COLUMN legacy_sender VARCHAR(100) NULL;
ALTER TABLE phone_mail ADD COLUMN legacy_button LONGTEXT NULL;
CREATE INDEX idx_phone_mail_citizen ON phone_mail (recipient_citizenid, recipient_deleted, id);
CREATE TABLE IF NOT EXISTS phone_legacy_transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(64) NOT NULL,
  title VARCHAR(100) NOT NULL,
  message VARCHAR(1000) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id), KEY idx_phone_legacy_transactions_owner (citizenid, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
