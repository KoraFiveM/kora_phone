-- Character-owned integration mail stays separate from physical handset content.
CREATE TABLE IF NOT EXISTS phone_legacy_mail (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 legacy_source_id BIGINT UNSIGNED NULL UNIQUE,
 citizenid VARCHAR(64) NOT NULL, sender VARCHAR(100) NOT NULL,
 subject VARCHAR(120) NOT NULL, body TEXT NOT NULL, button_json LONGTEXT NULL,
 read_at TIMESTAMP NULL, deleted_at TIMESTAMP NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY legacy_mail_owner (citizenid,deleted_at,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_legacy_transactions (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 citizenid VARCHAR(64) NOT NULL, title VARCHAR(100) NOT NULL, message VARCHAR(1000) NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY legacy_transactions_owner (citizenid,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
