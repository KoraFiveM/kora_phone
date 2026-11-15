KoraPhone = KoraPhone or {}
local SchemaSetup = {}
KoraPhone.SchemaSetup = SchemaSetup

-- Creates the phone_* tables declared in server/schema.lua (KoraPhoneSchema) on a fresh database.
-- Nothing is converted or imported. Returns true when the schema is ready, or false plus a reason.
function SchemaSetup.run()
    local called, reports, err = pcall(Kora.sql.ensureTables, KoraPhoneSchema)
    if not called then return false, 'schema setup failed: ' .. tostring(reports) end
    if not reports then return false, 'schema setup failed: ' .. tostring(err) end
    local created = 0
    for _, report in ipairs(reports) do
        if report.created then created = created + 1 end
        for _, warning in ipairs(report.warnings or {}) do
            Kora.logging.warn('schema.setup_warning','Schema setup reported a warning',{table=tostring(report.table),warning=tostring(warning)})
        end
    end
    if created > 0 then Kora.logging.info('schema.database_ready','Database ready',{tablesCreated=created}) end
    return true
end