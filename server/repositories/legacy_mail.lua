QBPhone.Repositories=QBPhone.Repositories or {}
local Mail={}
QBPhone.Repositories.LegacyMail=Mail
function Mail.insert(citizenId,mail)
    return MySQL.insert.await([[INSERT INTO phone_legacy_mail(citizenid,sender,subject,body,button_json)
        VALUES(?,?,?,?,NULLIF(?,''))]],{citizenId,mail.sender,mail.subject,mail.message,mail.button and json.encode(mail.button) or ''})
end
function Mail.list(citizenId,limit,cursor)
    return MySQL.query.await([[SELECT id,sender AS peer,subject,body,UNIX_TIMESTAMP(created_at) AS createdAt,
        (read_at IS NULL) AS unread,(button_json IS NOT NULL) AS hasAction
        FROM phone_legacy_mail WHERE citizenid=? AND deleted_at IS NULL AND id<? ORDER BY id DESC LIMIT ?]],
        {citizenId,cursor or 9007199254740991,limit}) or {}
end
function Mail.markRead(citizenId,id)
    return MySQL.update.await([[UPDATE phone_legacy_mail SET read_at=COALESCE(read_at,CURRENT_TIMESTAMP)
        WHERE id=? AND citizenid=? AND deleted_at IS NULL]],{id,citizenId})
end
function Mail.delete(citizenId,id)
    return (tonumber(MySQL.update.await([[UPDATE phone_legacy_mail SET deleted_at=CURRENT_TIMESTAMP,button_json=NULL
        WHERE id=? AND citizenid=? AND deleted_at IS NULL]],{id,citizenId})) or 0)>0
end
function Mail.clearButton(citizenId,id)
    return (tonumber(MySQL.update.await([[UPDATE phone_legacy_mail SET button_json=NULL
        WHERE id=? AND citizenid=? AND deleted_at IS NULL AND button_json IS NOT NULL]],{id,citizenId})) or 0)>0
end
function Mail.takeButton(citizenId,id)
    local row=MySQL.single.await([[SELECT button_json FROM phone_legacy_mail
        WHERE id=? AND citizenid=? AND deleted_at IS NULL]],{id,citizenId})
    if not row or not row.button_json then return nil end
    local ok,button=pcall(json.decode,row.button_json)
    if not ok or type(button)~='table' or type(button.buttonEvent)~='string' then return nil end
    return Mail.clearButton(citizenId,id) and button or nil
end
function Mail.activity(citizenId,limit,cursor)
    return MySQL.query.await([[SELECT id,title,message,UNIX_TIMESTAMP(created_at) AS createdAt
        FROM phone_legacy_transactions WHERE citizenid=? AND id<? ORDER BY id DESC LIMIT ?]],
        {citizenId,cursor or 9007199254740991,limit}) or {}
end

-- Adopt the upstream legacy mail extension when present; original rows remain untouched.
function Mail.import()
    -- Fail startup clearly if a manually managed database has not installed migration 013.
    MySQL.scalar.await('SELECT id FROM phone_legacy_mail LIMIT 1')
    MySQL.scalar.await('SELECT id FROM phone_legacy_transactions LIMIT 1')
    local columns=tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='phone_mail'
        AND COLUMN_NAME IN ('recipient_citizenid','legacy_sender','legacy_button')]])) or 0
    if columns~=3 then return 0 end
    return MySQL.update.await([[INSERT IGNORE INTO phone_legacy_mail
        (legacy_source_id,citizenid,sender,subject,body,button_json,read_at,deleted_at,created_at)
        SELECT id,recipient_citizenid,legacy_sender,subject,body,legacy_button,read_at,
            CASE WHEN recipient_deleted=1 THEN CURRENT_TIMESTAMP ELSE NULL END,created_at
        FROM phone_mail WHERE recipient_citizenid IS NOT NULL AND legacy_sender IS NOT NULL]])
end
