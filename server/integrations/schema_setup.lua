KoraPhone = KoraPhone or {}
local SchemaSetup = {}
KoraPhone.SchemaSetup = SchemaSetup

-- Creates the phone_* tables declared in server/schema.lua (KoraPhoneSchema) and adds anything missing to
-- existing ones. Returns true when the schema is ready, or false plus a reason.
---@return boolean ready
---@return string|nil reason
function SchemaSetup.run()
    -- Core tables first: the SDK tables reference phone_devices.
    local tables = {}
    for _, schema in ipairs({ KoraPhoneSchema, KoraPhoneSdkSchema or {} }) do
        for _, definition in ipairs(schema) do tables[#tables + 1] = definition end
    end
    local called, reports, err = pcall(Kora.sql.ensureTables, tables)
    if not called then return false, 'schema setup failed: ' .. tostring(reports) end
    if not reports then return false, 'schema setup failed: ' .. tostring(err) end
    local created = 0
    for _, report in ipairs(reports) do
        if report.created then created = created + 1 end
        for _, warning in ipairs(report.warnings or {}) do
            Kora.logging.event('schema.setup_warning', 0, {
                level = 'warn', message = 'Schema setup reported a warning',
                table = tostring(report.table),
                warning = tostring(warning),
            })
        end
    end
    if created > 0 then Kora.logging.event('schema.database_ready', 0, { level = 'info', message = 'Database ready', tablesCreated = created }) end
    return true
end
