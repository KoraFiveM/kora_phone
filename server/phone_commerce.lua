local H=QBPhone.Handsets
H.serviceRequests={}
local function fail(text) return PhoneError(PhoneConstants.Errors.FORBIDDEN,text) end
local function near(src,s)
    if not QBPhone.GetCitizenId(src) or GetPlayerRoutingBucket(src)~=(s.bucket or 0) then return false end
    local ped=GetPlayerPed(src); if not ped or ped==0 then return false end
    local p=GetEntityCoords(ped); local c=s.coords
    return (p.x-c.x)^2+(p.y-c.y)^2+(p.z-c.z)^2 <= (s.distance or 3)^2
end
local function random() return exports[GetCurrentResourceName()]:randomHex(16) end
function H.reconcileReplacement(newId,handsetId)
    local job=MySQL.single.await([[SELECT r.*,s.phone_number FROM phone_sim_replacements r
        JOIN phone_sims s ON s.id=r.new_sim_id WHERE r.new_sim_id=? AND r.handset_id=? AND r.state='prepared']],{newId,handsetId})
    if not job then return false end
    local old=MySQL.single.await('SELECT handset_id FROM phone_sims WHERE id=?',{job.old_sim_id})
    if old and old.handset_id then
        for src,id in pairs(H.selected) do if id==old.handset_id then H.revoke(src,'sim_replaced') end end
    end
    return MySQL.transaction.await({
        {query="UPDATE phone_devices SET phone_number=CONCAT('@',LEFT((SELECT h.id FROM phone_handsets h WHERE h.device_id=phone_devices.id),20)) WHERE phone_number=?",values={job.phone_number}},
        {query="UPDATE phone_sims SET status='revoked',handset_id=NULL WHERE phone_number=? AND id<>?",values={job.phone_number,newId}},
        {query="UPDATE phone_sims SET status='active',handset_id=? WHERE id=?",values={handsetId,newId}},
        {query="UPDATE phone_sim_replacements SET state='complete' WHERE id=?",values={job.id}}
    })
end
local function shopAccess(src,p)
    local s=type(p.shop)=='string' and Config.PhoneServices.shops[p.shop]
    if not s or not near(src,s) then return nil end
    if s.job then
        local player=QBPhone.GetPlayer(src); local j=player and player.job
        if not j or j.name~=s.job or not j.onduty or (j.grade and j.grade.level or 0)<(s.grade or 0) then return nil end
    end
    return s
end
local function activeSessions(accountId,except)
    local rows=MySQL.query.await('SELECT id FROM phone_handsets WHERE account_id=?',{accountId}) or {}
    local ids={}; for _,r in ipairs(rows) do ids[r.id]=true end
    for src,id in pairs(H.selected) do if ids[id] and src~=except then H.revoke(src,'cloud_account_recovered') end end
end
function H.commerce(actor,p,approved)
    local s=shopAccess(actor,p); if not s then return fail('Visit an authorised shop counter') end
    local target=tonumber(p.target) or actor
    if target%1~=0 or not near(target,s) or (target~=actor and not s.job) then return fail('Customer must be at this counter') end
    if target~=actor and not approved then
        local id=random(); H.serviceRequests[id]={actor=actor,actorCharacter=QBPhone.GetCitizenId(actor),target=target,payload=p,expires=os.time()+30,character=QBPhone.GetCitizenId(target)}
        SetTimeout(31000,function() H.serviceRequests[id]=nil end)
        TriggerClientEvent('qbphone:client:serviceRequest',target,{id=id,label=s.label,operation=p.op})
        return PhoneResult({pending=true})
    end
    local citizenId=QBPhone.GetCitizenId(target)
    if p.op=='buy' then
        if type(p.item)~='string' or not s.prices[p.item] then return fail('Item is unavailable') end
        local stock=exports.qbinventory:shopGet('qbphone:'..p.shop)
        local slot
        for key,i in pairs(stock or {}) do
            if i.name==p.item or (Config.Handsets[p.item] and Config.Handsets[i.name]==Config.Handsets[p.item]) then
                if not slot or (i.info and i.info.handsetId) then slot=i.slot or key end
                if i.info and i.info.handsetId then break end
            end
        end
        if not slot then return fail('Out of stock') end
        if target~=actor then H.purchaseCustomers[target]={shop=p.shop,actor=actor,actorCharacter=QBPhone.GetCitizenId(actor),character=citizenId} end
        local invoked,ok,err=pcall(function() return exports.qbinventory:BuyItem(target,'qbphone:'..p.shop,slot,1) end)
        H.purchaseCustomers[target]=nil
        if not invoked then return fail('Purchase failed; try again') end
        if not ok then return fail(tostring(err)) end
        return PhoneResult({purchased=true})
    elseif p.op=='recoverCloud' then
        if type(p.accountId)~='string' or #p.accountId>64 then return fail('Invalid account') end
        if p.accountId=='' then
            local owned=MySQL.query.await('SELECT id FROM phone_cloud_accounts WHERE owner_citizenid=? ORDER BY created_at LIMIT 10',{citizenId}) or {}
            if #owned~=1 then
                local ids={}; for _,a in ipairs(owned) do ids[#ids+1]=a.id end
                return fail(#owned==0 and 'No cloud account is registered to this character' or 'Choose an account ID: '..table.concat(ids,', '))
            end
            p.accountId=owned[1].id
        end
        return H.accountLock(p.accountId,function()
        local account=MySQL.single.await('SELECT id FROM phone_cloud_accounts WHERE id=? AND owner_citizenid=?',{p.accountId,citizenId})
        if not account then return fail('Account does not belong to this character') end
        if s.recoveryFee>0 and not exports.qbcore:removeMoney(target,'bank',s.recoveryFee,'phone account recovery',true) then return fail('Insufficient bank funds') end
        local code=exports[GetCurrentResourceName()]:randomHex(32)
        activeSessions(account.id,target)
        local ok=MySQL.transaction.await({
            {query='UPDATE phone_cloud_accounts SET recovery_hash=SHA2(?,256),revision=revision+1 WHERE id=?',values={code,account.id}},
            {query='UPDATE phone_handsets SET account_id=NULL,cloud_revision=0 WHERE account_id=?',values={account.id}}
        })
        if not ok then
            if s.recoveryFee>0 then exports.qbcore:addMoney(target,'bank',s.recoveryFee,'phone recovery refund',true) end
            return fail('Recovery failed; your fee was refunded')
        end
        return PhoneResult({accountId=account.id,recoveryCode=code})
        end)
    elseif p.op=='replaceSim' then
        local number=PhoneValidation.phoneNumber(p.number)
        if not number then return fail('Enter your existing phone number') end
        local old=MySQL.single.await("SELECT * FROM phone_sims WHERE phone_number=? AND owner_citizenid=? AND status<>'revoked' ORDER BY (status='active') DESC,(handset_id IS NOT NULL) DESC,created_at,id LIMIT 1",{number,citizenId})
        if not old then return fail('That subscription does not belong to this character') end
        local d,err=H.require(target); if not d then return err end
        -- Install replacement into the selected handset. An unrelated SIM must be removed first.
        if d.sim and d.sim.id~=old.id then return fail('Remove the other SIM before replacing this subscription') end
        local item
        local player=QBPhone.GetPlayer(target)
        for _,i in pairs(player.items or {}) do if i.info and i.info.handsetId==d.handsetId then item=i; break end end
        if not item then return fail('Handset is no longer held') end
        local newId=random()
        -- Prepare the new SIM as blocked. Metadata commits before activation, so crashes fail closed.
        MySQL.insert.await("INSERT INTO phone_sims(id,phone_number,owner_citizenid,status) VALUES(?,?,?,'blocked')",{newId,number,citizenId})
        MySQL.insert.await('INSERT INTO phone_sim_replacements(id,old_sim_id,new_sim_id,handset_id,citizenid) VALUES(?,?,?,?,?)',
            {random(),old.id,newId,d.handsetId,citizenId})
        local ok,reason=exports.qbinventory:PhoneItemTransaction(target,{op='replaceSim',handsetSlot=item.slot,handsetId=d.handsetId,
            simId=item.info.phoneSimId or '',newSimId=newId,fee=s.replacementFee})
        if not ok then
            MySQL.update.await("UPDATE phone_sim_replacements SET state='cancelled' WHERE new_sim_id=?",{newId})
            return fail(tostring(reason))
        end
        if old.handset_id then
            for src,id in pairs(H.selected) do if id==old.handset_id then H.revoke(src,'sim_replaced') end end
        end
        local committed=H.reconcileReplacement(newId,d.handsetId)
        if not committed then return fail('Replacement is pending; reopen this handset to retry activation without another fee') end
        H.selected[target]=d.handsetId; H.current(target,false)
        return PhoneResult({number=number,replaced=true})
    elseif p.op=='resell' then
        local slot=tonumber(p.slot)
        if not slot or slot%1~=0 or not exports[GetCurrentResourceName()]:CanResellHandset(target,slot) then return fail('Factory reset and remove the SIM before resale') end
        local item=exports.qbcore:getItemBySlot(target,slot)
        local price=s.prices[item.name] or s.prices.phone_standard
        if not price then return fail('This shop does not buy that handset') end
        local ok,reason=exports.qbinventory:PhoneItemTransaction(target,{op='resell',handsetSlot=slot,handsetId=item.info.handsetId,
            payout=math.floor(price*(s.resalePercent or 50)/100),shopId='qbphone:'..p.shop,salePrice=price})
        if not ok then return fail(tostring(reason)) end
        return PhoneResult({sold=true})
    end
    return fail('Unknown shop service')
end
function H.consent(src,p)
    local request=type(p.id)=='string' and H.serviceRequests[p.id]
    if not request or request.target~=src then return fail('Service request expired') end
    H.serviceRequests[p.id]=nil
    if p.accept~=true then return PhoneResult({declined=true}) end
    if request.expires<os.time() or request.character~=QBPhone.GetCitizenId(src)
        or request.actorCharacter~=QBPhone.GetCitizenId(request.actor) then return fail('Service request expired') end
    local result=H.commerce(request.actor,request.payload,true)
    TriggerClientEvent('qbphone:client:serviceResult',src,result)
    return result
end
local originalAction=H.action
function H.action(src,p)
    if p.op=='buy' or p.op=='recoverCloud' or p.op=='replaceSim' or p.op=='resell' then
        return H.commerce(src,p)
    elseif p.op=='consent' then return H.consent(src,p) end
    if p.op=='status' and not H.current(src,true) then
        local shops={}
        for id,s in pairs(Config.PhoneServices.shops) do if near(src,s) then shops[#shops+1]={id=id,label=s.label,prices=s.prices,business=s.job~=nil} end end
        return PhoneResult({handset={id='',model='standard'},cellular=false,number='',phones={},sims={},hotspots={},shops=shops,simSwap=Config.SimSwap,
            accounts=MySQL.query.await('SELECT id FROM phone_cloud_accounts WHERE owner_citizenid=? ORDER BY created_at',{QBPhone.GetCitizenId(src)}) or {}})
    end
    local result=originalAction(src,p)
    if p.op=='status' and result.ok then
        result.data.accounts=MySQL.query.await('SELECT id FROM phone_cloud_accounts WHERE owner_citizenid=? ORDER BY created_at',{QBPhone.GetCitizenId(src)}) or {}
    end
    return result
end
