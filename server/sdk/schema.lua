local NULL = Kora.sql.NULL

-- Declared here, passed to Kora.sql.ensureTables by server/integrations/schema_setup.lua after the core tables.
KoraPhoneSdkSchema = {
    {
        name = 'phone_app_storage', collate = 'utf8mb4_unicode_ci',
        columns = {
            { name = 'device_id', type = 'bigint', unsigned = true },
            { name = 'app_id', type = 'varchar(32)' },
            { name = 'key', type = 'varchar(64)' },
            { name = 'value', type = 'json' },
            { name = 'updated_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' }, on_update = 'CURRENT_TIMESTAMP' },
        },
        primary = { 'device_id', 'app_id', 'key' },
        indexes = {
            { name = 'idx_phone_app_storage_app', columns = { 'app_id' } },
        },
        foreign = {
            { name = 'fk_phone_app_storage_device', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
}
