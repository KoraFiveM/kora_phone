-- Delivery copies are owned by a handset, not by whoever later acquires its number.
local M=QBPhone.Services.Messaging
local function fail(text) return PhoneError(PhoneConstants.Errors.INVALID_INPUT,text) end
local function thread(device,id)
    return MySQL.single.await('SELECT * FROM phone_threads WHERE id=? AND device_id=?',{tonumber(id) or 0,device.id})
end
local function ensure(device,number)
    MySQL.update.await('INSERT IGNORE INTO phone_threads(device_id,peer_number) VALUES(?,?)',{device.id,number})
    return MySQL.single.await('SELECT * FROM phone_threads WHERE device_id=? AND peer_number=?',{device.id,number})
end
local function conversation(t)
    local latest=MySQL.single.await('SELECT id,body,UNIX_TIMESTAMP(created_at) AS at FROM phone_mailboxes WHERE device_id=? AND peer_number=? ORDER BY id DESC LIMIT 1',{t.device_id,t.peer_number})
    return {id=t.id,type='direct',peerPhoneNumber=t.peer_number,title=t.peer_number:sub(1,7)=='@group:' and 'Archived group' or nil,
        lastMessageId=latest and latest.id,lastMessagePreview=latest and latest.body,lastMessageAt=latest and latest.at,
        unreadCount=tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM phone_mailboxes WHERE device_id=? AND peer_number=? AND is_read=0',{t.device_id,t.peer_number})) or 0}
end
local function message(id,device,t)
    local m=MySQL.single.await([[SELECT b.id,b.body,b.is_outgoing,b.media_id AS mediaId,b.sender_number AS senderNumber,
        UNIX_TIMESTAMP(b.created_at) AS createdAt,m.public_url AS mediaUrl,m.mime_type AS mediaMime
        FROM phone_mailboxes b LEFT JOIN phone_media m ON m.id=b.media_id WHERE b.id=? AND b.device_id=?]],{id,device.id})
    if m then m.conversationId=t.id; m.isMine=m.is_outgoing==1 or m.is_outgoing==true; m.is_outgoing=nil; m.messageType=m.mediaId and 'image' or 'text' end
    return m
end
function M.startDirect(src,p)
    local d,e=QBPhone.Permissions.requireDevice(src); if not d then return e end
    local number,err=PhoneValidation.phoneNumber(p.to); if not number then return fail(err) end
    if not d.cellular then return fail('Insert an active SIM to start a conversation') end
    if number==d.phoneNumber then return fail('Cannot message your own number') end
    return PhoneResult(conversation(ensure(d,number)))
end
function M.listConversations(src,p)
    local d,e=QBPhone.Permissions.requireDevice(src); if not d then return e end
    local page,validationError=PhoneValidation.page(p)
    if not page then return fail(validationError) end
    local cursorId
    if p.cursorId~=nil then
        if not page.cursor then return fail('cursor is required with cursorId') end
        cursorId,validationError=PhoneValidation.integer(p.cursorId,'cursorId',1)
        if not cursorId then return fail(validationError) end
    end
    local cursorSql=''
    local params={d.id}
    if page.cursor and cursorId then
        cursorSql=' AND (COALESCE(b.id,t.id)<? OR (COALESCE(b.id,t.id)=? AND t.id<?))'
        params[#params+1]=page.cursor;params[#params+1]=page.cursor;params[#params+1]=cursorId
    elseif page.cursor then cursorSql=' AND COALESCE(b.id,t.id)<?';params[#params+1]=page.cursor end
    params[#params+1]=page.limit
    local threads=MySQL.query.await([[SELECT t.*,b.id AS lastMessageId,b.body AS lastMessagePreview,
        UNIX_TIMESTAMP(b.created_at) AS lastMessageAt,m.mime_type AS lastMediaMime,COALESCE(b.id,t.id) AS sortId,
        (SELECT COUNT(*) FROM phone_mailboxes unread WHERE unread.device_id=t.device_id
            AND unread.peer_number=t.peer_number AND unread.is_read=0) AS unreadCount
        FROM phone_threads t LEFT JOIN phone_mailboxes b ON b.id=(SELECT MAX(latest.id)
            FROM phone_mailboxes latest WHERE latest.device_id=t.device_id AND latest.peer_number=t.peer_number)
        LEFT JOIN phone_media m ON m.id=b.media_id WHERE t.device_id=?]]..cursorSql..[[
        ORDER BY COALESCE(b.id,t.id) DESC,t.id DESC LIMIT ?]],params) or {}
    local results={}
    for _,t in ipairs(threads) do
        results[#results+1]={id=t.id,type='direct',peerPhoneNumber=t.peer_number,
            title=t.peer_number:sub(1,7)=='@group:' and 'Archived group' or nil,
            lastMessageId=t.lastMessageId,lastMessagePreview=t.lastMessagePreview,lastMessageAt=t.lastMessageAt,
            sortId=tonumber(t.sortId or t.lastMessageId or t.id),lastMediaMime=t.lastMediaMime,unreadCount=tonumber(t.unreadCount) or 0}
    end
    local last=#results==page.limit and results[#results] or nil
    return PhoneResult({items=results,nextCursor=last and last.sortId,nextCursorId=last and last.id})
end
function M.list(src,p)
    local d,e=QBPhone.Permissions.requireDevice(src); if not d then return e end
    local t=thread(d,p.conversationId); if not t then return fail('Conversation not found') end
    local limit=math.min(100,math.max(1,tonumber(p.limit) or 50))
    local items=MySQL.query.await([[SELECT b.id,b.body,b.is_outgoing,b.media_id AS mediaId,b.sender_number AS senderNumber,
        UNIX_TIMESTAMP(b.created_at) AS createdAt,m.public_url AS mediaUrl,m.mime_type AS mediaMime
        FROM phone_mailboxes b LEFT JOIN phone_media m ON m.id=b.media_id
        WHERE b.device_id=? AND b.peer_number=? AND b.id<? ORDER BY b.id DESC LIMIT ?]],
        {d.id,t.peer_number,tonumber(p.cursor) or 9007199254740991,limit}) or {}
    for _,m in ipairs(items) do
        m.conversationId=t.id; m.isMine=m.is_outgoing==1 or m.is_outgoing==true
        m.is_outgoing=nil; m.messageType=m.mediaId and 'image' or 'text'
    end
    return PhoneResult({items=items,nextCursor=#items==limit and items[#items].id or nil})
end
function M.send(src,p)
    local d,e=QBPhone.Permissions.requireDevice(src); if not d then return e end
    if not d.cellular then return fail('An active SIM is required to send texts') end
    local contract,err=PhoneContracts.message(p); if not contract then return fail(err) end
    local t=contract.conversationId and thread(d,contract.conversationId)
    local number=t and t.peer_number or contract.to
    number=PhoneValidation.phoneNumber(number)
    if not number then return fail('Archived group history is read-only') end
    local recipient=QBPhone.Repositories.Phones.findByNumber(number)
    if not recipient or number==d.phoneNumber then return fail('That number is unavailable') end
    if QBPhone.Repositories.Blocks.isEitherBlocked(d.id,recipient.id) then return fail('Messaging is unavailable for this contact') end
    t=t or ensure(d,number)
    local other=ensure(recipient,d.phoneNumber)
    local mediaId=tonumber(contract.mediaId) or 0
    if mediaId~=0 and not QBPhone.Repositories.Media.findOwned(d.id,mediaId) then return fail('Media not found') end
    local key=tostring(contract.clientRequestId)
    local existing=MySQL.single.await('SELECT * FROM phone_mailboxes WHERE device_id=? AND request_id=?',{d.id,key})
    if existing then
        if existing.body~=contract.body or existing.peer_number~=number or (tonumber(existing.media_id) or 0)~=mediaId then return fail('Message request already used') end
        local saved=message(existing.id,d,t); saved.replayed=true; return PhoneResult(saved)
    end
    local ok=MySQL.transaction.await({
        {query='INSERT INTO phone_mailboxes(device_id,peer_number,sender_number,body,media_id,request_id,is_read,is_outgoing) VALUES(?,?,?,?,NULLIF(?,0),?,1,1)',values={d.id,number,d.phoneNumber,contract.body,mediaId,key}},
        {query='INSERT INTO phone_mailboxes(device_id,peer_number,sender_number,body,media_id,request_id,is_outgoing) VALUES(?,?,?,?,NULLIF(?,0),?,0)',values={recipient.id,d.phoneNumber,d.phoneNumber,contract.body,mediaId,'recv:'..d.id..':'..key}}
    })
    if not ok then return fail('Message could not be delivered') end
    local sent=MySQL.scalar.await('SELECT id FROM phone_mailboxes WHERE device_id=? AND request_id=?',{d.id,key})
    local target=QBPhone.Sessions.sourceByNumber(number)
    if target then
        local incoming=MySQL.scalar.await('SELECT id FROM phone_mailboxes WHERE device_id=? AND request_id=?',{recipient.id,'recv:'..d.id..':'..key})
        local delivered=message(incoming,recipient,other)
        delivered.deviceId=tostring(recipient.id)
        TriggerClientEvent('qbphone:client:messages:new',target,delivered)
        SetTimeout(1500,function() if QBPhone.Handsets.selected[target] then QBPhone.Handsets.locked(target,QBPhone.Handsets.backup,{}) end end)
    end
    return PhoneResult(message(sent,d,t))
end
function M.markRead(src,p)
    local d,e=QBPhone.Permissions.requireDevice(src); if not d then return e end
    local t=thread(d,p.conversationId); if not t then return fail('Conversation not found') end
    MySQL.update.await('UPDATE phone_mailboxes SET is_read=1 WHERE device_id=? AND peer_number=?',{d.id,t.peer_number})
    return PhoneResult(true)
end
function M.deleteForSelf(src,p)
    local d,e=QBPhone.Permissions.requireDevice(src); if not d then return e end
    MySQL.update.await('DELETE FROM phone_mailboxes WHERE device_id=? AND id=?',{d.id,tonumber(p.messageId) or 0})
    return PhoneResult(true)
end
-- Groups are preserved as readable archives; new group/social features are outside the launch apps.
local function groupDeferred() return fail('New group chats are not available in this release') end
M.createGroup=groupDeferred; M.addMember=groupDeferred; M.leaveGroup=groupDeferred

local Media=QBPhone.Repositories.Media
local columns=[[m.id,m.owner_device_id AS ownerDeviceId,m.storage_provider AS storageProvider,m.storage_key AS storageKey,
    m.public_url AS publicUrl,m.mime_type AS mimeType,m.byte_size AS byteSize,m.width,m.height,UNIX_TIMESTAMP(m.created_at) AS createdAt]]
function Media.findOwned(deviceId,mediaId)
    return MySQL.single.await('SELECT '..columns..[[ FROM phone_media m WHERE m.id=? AND
        ((m.owner_device_id=? AND m.deleted_at IS NULL) OR EXISTS(SELECT 1 FROM phone_gallery_links l WHERE l.device_id=? AND l.media_id=m.id))]],{mediaId,deviceId,deviceId})
end
function Media.listOwned(deviceId,limit,cursor)
    return MySQL.query.await('SELECT '..columns..[[ FROM phone_media m WHERE m.id<? AND (m.mime_type LIKE 'image/%' OR m.mime_type LIKE 'video/%') AND
        ((m.owner_device_id=? AND m.deleted_at IS NULL) OR EXISTS(SELECT 1 FROM phone_gallery_links l WHERE l.device_id=? AND l.media_id=m.id)) ORDER BY m.id DESC LIMIT ?]],
        {cursor or 9007199254740991,deviceId,deviceId,limit}) or {}
end
local oldReferences=Media.referenceCount
function Media.referenceCount(id)
    return oldReferences(id)+(tonumber(MySQL.scalar.await([[SELECT
        (SELECT COUNT(*) FROM phone_cloud_media WHERE media_id=?) +
        (SELECT COUNT(*) FROM phone_gallery_links WHERE media_id=?) +
        (SELECT COUNT(*) FROM phone_mailboxes WHERE media_id=?)]],{id,id,id})) or 0)
end
function Media.softDelete(deviceId,id)
    if not Media.findOwned(deviceId,id) then return false end
    MySQL.update.await('DELETE FROM phone_gallery_links WHERE device_id=? AND media_id=?',{deviceId,id})
    MySQL.update.await('UPDATE phone_media SET deleted_at=CURRENT_TIMESTAMP WHERE id=? AND owner_device_id=?',{id,deviceId})
    return true
end
function Media.expiredDeleted(hours,limit)
    return MySQL.query.await('SELECT '..columns..[[ FROM phone_media m
        WHERE m.deleted_at IS NOT NULL AND m.deleted_at<DATE_SUB(CURRENT_TIMESTAMP,INTERVAL ? HOUR)
        AND NOT EXISTS(SELECT 1 FROM phone_cloud_media c WHERE c.media_id=m.id)
        AND NOT EXISTS(SELECT 1 FROM phone_gallery_links l WHERE l.media_id=m.id)
        AND NOT EXISTS(SELECT 1 FROM phone_mailboxes b WHERE b.media_id=m.id)
        AND NOT EXISTS(SELECT 1 FROM phone_contacts c WHERE c.avatar_media_id=m.id)
        AND NOT EXISTS(SELECT 1 FROM phone_messages b WHERE b.media_id=m.id)
        AND NOT EXISTS(SELECT 1 FROM phone_social_posts p WHERE p.media_id=m.id)
        ORDER BY m.deleted_at LIMIT ?]],{hours,limit}) or {}
end
