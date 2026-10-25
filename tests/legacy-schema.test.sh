#!/usr/bin/env bash
# Run only against an empty disposable schema on a separate MariaDB socket.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${QBPHONE_TEST_SOCKET:?Set the disposable MariaDB socket}"
: "${QBPHONE_TEST_DATABASE:?Set an empty disposable schema name}"
case "$QBPHONE_TEST_DATABASE" in qbc_compat_*|qbphone_test_*) ;; *) echo 'Refusing a non-test schema' >&2; exit 1;; esac
[[ "$QBPHONE_TEST_DATABASE" =~ ^[a-zA-Z0-9_]+$ ]] || exit 1
mysql_cmd=("${QBPHONE_TEST_MYSQL:-mysql}" --no-defaults --socket="$QBPHONE_TEST_SOCKET" --user=root --batch --skip-column-names "$QBPHONE_TEST_DATABASE")
[[ "$("${mysql_cmd[@]}" -e 'SHOW TABLES' | wc -l)" -eq 0 ]] || { echo 'Schema must be empty' >&2; exit 1; }
for file in migrations/*.sql; do
    [[ "$file" == 'migrations/012_legacy_qb_phone.sql' ]] && break
    "${mysql_cmd[@]}" < "$file"
done
"${mysql_cmd[@]}" <<'SQL'
INSERT INTO phone_devices (id, owner_citizenid, phone_number, settings_json) VALUES (9001, 'LEGACY_A', '5550009001', '{}'), (9002, 'LEGACY_B', '5550009002', '{}');
INSERT INTO phone_mail (id, sender_device_id, recipient_device_id, subject, body, client_request_id) VALUES (9001, 9001, 9002, 'Existing subject', 'Existing body', 'legacy-regression');
SQL
"${mysql_cmd[@]}" < migrations/012_legacy_qb_phone.sql
assert_sql() {
    local actual
    actual="$("${mysql_cmd[@]}" -e "$1")"
    [[ "$actual" == "$2" ]] || { echo "FAIL: expected $2, got $actual" >&2; exit 1; }
}
assert_sql "SELECT COUNT(*) FROM phone_mail WHERE id=9001 AND sender_device_id=9001 AND recipient_device_id=9002 AND subject='Existing subject' AND body='Existing body' AND client_request_id='legacy-regression' AND legacy_sender IS NULL" 1
assert_sql "SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='phone_mail' AND REFERENCED_TABLE_NAME='phone_devices'" 2
"${mysql_cmd[@]}" <<'SQL'
INSERT INTO phone_mail (id, recipient_citizenid, legacy_sender, subject, body, legacy_button, sender_deleted) VALUES (9002, 'OFFLINE_CID', 'Job Office', 'Delivery', 'Deliver this', '{"buttonEvent":"test:accept"}', 1);
INSERT INTO phone_devices (id, owner_citizenid, phone_number, settings_json) VALUES (9003, 'OFFLINE_CID', '5550009003', '{}');
INSERT INTO phone_legacy_transactions (citizenid, title, message) VALUES ('OFFLINE_CID', 'Credit', 'Informational note');
SQL
assert_sql "SELECT COUNT(*) FROM phone_mail m LEFT JOIN phone_devices p ON p.id=m.sender_device_id WHERE (m.recipient_device_id=9003 OR m.recipient_citizenid='OFFLINE_CID') AND m.recipient_deleted=0 AND COALESCE(m.legacy_sender,p.phone_number)='Job Office'" 1
assert_sql "SELECT COUNT(*) FROM phone_mail WHERE (recipient_device_id=9002 OR recipient_citizenid='LEGACY_B') AND recipient_deleted=0" 1
assert_sql "SELECT COUNT(*) FROM phone_mail WHERE sender_device_id=9001 AND sender_deleted=0" 1
assert_sql "SELECT COUNT(*) FROM phone_mail WHERE sender_device_id=9003 AND sender_deleted=0" 0
assert_sql "UPDATE phone_mail SET legacy_button=NULL WHERE id=9002 AND recipient_citizenid='WRONG' AND legacy_button IS NOT NULL; SELECT ROW_COUNT()" 0
assert_sql "UPDATE phone_mail SET legacy_button=NULL WHERE id=9002 AND recipient_citizenid='OFFLINE_CID' AND legacy_button IS NOT NULL; SELECT ROW_COUNT()" 1
assert_sql "UPDATE phone_mail SET legacy_button=NULL WHERE id=9002 AND recipient_citizenid='OFFLINE_CID' AND legacy_button IS NOT NULL; SELECT ROW_COUNT()" 0
assert_sql "SELECT COUNT(*) FROM phone_legacy_transactions WHERE citizenid='OFFLINE_CID' AND title='Credit'" 1
echo 'PASS legacy schema: existing rows/FKs preserved; offline mail, ownership, one-use actions and notes persist'
