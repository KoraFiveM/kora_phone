-- Read-only data preflight; run after schema setup and before identity conversion.
QBPhone.MigrationReport={}
local Report=QBPhone.MigrationReport
function Report.run()
    local report={version=1,createdAt=os.time(),blocking=0,issues={},unclaimed={},providerObjects='Not checked: verify provider objects during live acceptance'}
    local function issue(code,record,id,detail,blocking)
        report.issues[#report.issues+1]={code=code,record=record,id=id,detail=detail,blocking=blocking==true}
        if blocking then report.blocking=report.blocking+1 end
    end
    local legacy=MySQL.query.await([[SELECT d.*,(p.citizenid IS NOT NULL) AS character_exists
        FROM phone_devices d LEFT JOIN phone_handsets h ON h.device_id=d.id
        LEFT JOIN players p ON p.citizenid=d.owner_citizenid AND p.deleted_at IS NULL WHERE h.id IS NULL]]) or {}
    for _,d in ipairs(legacy) do
        if not (d.character_exists==1 or d.character_exists==true) then
            issue('unresolved_owner','device',d.id,'Registering character is absent from players: '..tostring(d.owner_citizenid),true)
        end
        if not PhoneValidation.phoneNumber(d.phone_number) then issue('invalid_number','device',d.id,'Legacy subscription number is invalid',true) end
        local valid=type(d.settings_json)=='table'
        if type(d.settings_json)=='string' then
            local ok,value=pcall(json.decode,d.settings_json); valid=ok and type(value)=='table' and d.settings_json:match('^%s*{')~=nil
        end
        if not valid then issue('invalid_settings','device',d.id,'Settings must decode to an object',true) end
    end
    local contacts=MySQL.query.await('SELECT id,phone_number FROM phone_contacts') or {}
    for _,c in ipairs(contacts) do
        if not PhoneValidation.phoneNumber(c.phone_number) then issue('invalid_contact','contact',c.id,'Contact number is invalid; content is retained for review',false) end
    end
    local media=MySQL.query.await('SELECT id,owner_device_id,storage_provider,storage_key,public_url FROM phone_media') or {}
    for _,m in ipairs(media) do
        if type(m.storage_key)~='string' or m.storage_key=='' or type(m.public_url)~='string' or m.public_url=='' then
            issue('missing_media_reference','media',m.id,'Provider key or public URL is missing',false)
        end
    end
    report.unclaimed=MySQL.query.await('SELECT device_id,citizenid,handset_id,account_id FROM phone_legacy_claims WHERE claimed_at IS NULL ORDER BY device_id') or {}
    report.legacyDevices=#legacy
    return report
end
function Report.save(report)
    return SaveResourceFile(GetCurrentResourceName(),'migration-report.json',json.encode(report),-1)
end
RegisterCommand('phonepreflight',function(src)
    if src~=0 then return end
    local ok,report=pcall(Report.run)
    if not ok then print('[qbphone] preflight failed: '..tostring(report)); return end
    local saved=Report.save(report)
    print(('[qbphone] preflight: %d blocking, %d issues; migration-report.json saved=%s'):format(report.blocking,#report.issues,tostring(saved)))
end,true)
