QBPhone = QBPhone or {}
local SchemaSetup = {}
QBPhone.SchemaSetup = SchemaSetup

-- Creates the phone_* tables declared in server/schema.lua (QBPhoneSchema) on a fresh database.
-- Nothing is converted or imported. Returns true when the schema is ready, or false plus a reason.
function SchemaSetup.run()
    local called, reports, err = pcall(Kora.sql.ensureTables, QBPhoneSchema)
    if not called then return false, 'schema setup failed: ' .. tostring(reports) end
    if not reports then return false, 'schema setup failed: ' .. tostring(err) end
    local created = 0
    for _, report in ipairs(reports) do
        if report.created then created = created + 1 end
        for _, warning in ipairs(report.warnings or {}) do
            print(('[qbphone] schema warning (%s): %s'):format(tostring(report.table), tostring(warning)))
        end
    end
    if created > 0 then print(('[qbphone] database ready (%d tables created)'):format(created)) end
    return true
end
