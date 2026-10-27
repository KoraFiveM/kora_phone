CREATE TABLE IF NOT EXISTS phone_cloud_accounts (
 id VARCHAR(64) NOT NULL PRIMARY KEY, owner_citizenid VARCHAR(64) NOT NULL,
 recovery_hash CHAR(64) NOT NULL, snapshot_json LONGTEXT NULL, revision INT NOT NULL DEFAULT 0,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY cloud_owner (owner_citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_handsets (
 id VARCHAR(64) NOT NULL PRIMARY KEY, model VARCHAR(12) NOT NULL,
 device_id BIGINT UNSIGNED NOT NULL UNIQUE, account_id VARCHAR(64) NULL,
 face_citizenid VARCHAR(64) NULL, pin_kdf VARCHAR(200) NULL,
 is_reset TINYINT NOT NULL DEFAULT 0, cloud_revision INT NOT NULL DEFAULT 0,
 FOREIGN KEY (device_id) REFERENCES phone_devices(id),
 FOREIGN KEY (account_id) REFERENCES phone_cloud_accounts(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_sims (
 id VARCHAR(64) NOT NULL PRIMARY KEY, phone_number VARCHAR(24) NOT NULL,
 owner_citizenid VARCHAR(64) NOT NULL, status ENUM('active','blocked','revoked') NOT NULL DEFAULT 'active',
 active_number VARCHAR(24) GENERATED ALWAYS AS (CASE WHEN status='active' THEN phone_number ELSE NULL END) STORED UNIQUE,
 handset_id VARCHAR(64) NULL UNIQUE, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY sim_number (phone_number,status), FOREIGN KEY (handset_id) REFERENCES phone_handsets(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_legacy_claims (
 device_id BIGINT UNSIGNED NOT NULL PRIMARY KEY, citizenid VARCHAR(64) NOT NULL,
 handset_id VARCHAR(64) NULL UNIQUE, account_id VARCHAR(64) NOT NULL,
 claimed_at TIMESTAMP NULL, KEY legacy_character (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_mailboxes (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, device_id BIGINT UNSIGNED NOT NULL,
 peer_number VARCHAR(24) NOT NULL, sender_number VARCHAR(24) NOT NULL,
 body TEXT NOT NULL, media_id BIGINT UNSIGNED NULL, request_id VARCHAR(100) NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, is_read TINYINT NOT NULL DEFAULT 0, is_outgoing TINYINT NOT NULL DEFAULT 0,
 UNIQUE KEY delivery_once (device_id,request_id), KEY mailbox_thread (device_id,peer_number,id),
 FOREIGN KEY (device_id) REFERENCES phone_devices(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_threads (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, device_id BIGINT UNSIGNED NOT NULL,
 peer_number VARCHAR(24) NOT NULL, UNIQUE KEY own_thread (device_id,peer_number),
 FOREIGN KEY (device_id) REFERENCES phone_devices(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_migration_issues (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, device_id BIGINT UNSIGNED NULL,
 issue_key VARCHAR(160) NOT NULL UNIQUE, detail TEXT NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_gallery_links (
 device_id BIGINT UNSIGNED NOT NULL, media_id BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY(device_id,media_id), FOREIGN KEY(device_id) REFERENCES phone_devices(id),
 FOREIGN KEY(media_id) REFERENCES phone_media(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_cloud_media (
 account_id VARCHAR(64) NOT NULL, media_id BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY(account_id,media_id), FOREIGN KEY(account_id) REFERENCES phone_cloud_accounts(id),
 FOREIGN KEY(media_id) REFERENCES phone_media(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_upgrade_state (
 name VARCHAR(64) NOT NULL PRIMARY KEY, completed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_call_hidden (
 device_id BIGINT UNSIGNED NOT NULL, call_id CHAR(36) NOT NULL,
 PRIMARY KEY(device_id,call_id), FOREIGN KEY(device_id) REFERENCES phone_devices(id),
 FOREIGN KEY(call_id) REFERENCES phone_calls(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS phone_sim_replacements (
 id VARCHAR(64) NOT NULL PRIMARY KEY, old_sim_id VARCHAR(64) NOT NULL,
 new_sim_id VARCHAR(64) NOT NULL UNIQUE, handset_id VARCHAR(64) NOT NULL,
 citizenid VARCHAR(64) NOT NULL, state ENUM('prepared','complete','cancelled') NOT NULL DEFAULT 'prepared',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
