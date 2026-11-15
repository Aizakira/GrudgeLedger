-- Guild bounty records are separate from personal history. Values on the wire are
-- immutable declarations. A guild peer may replay a cached declaration at login.
local GL = GrudgeLedger
local B = {}
GL.Bounties = B
local DAY, GOLD, PREFIX = 86400, 10000, "GLBounty1"
local function guid(s)
    return type(s) == "string" and #s <= 32 and s:match("^Player%-%w+%-%w+$")
end
local function plain(s, limit)
    return type(s) == "string" and #s <= limit and not GL.ContainsControlOrMarkup(s) and not s:find(";",1,true)
end
local function number(s, lo, hi)
    if type(s)~="number" and type(s)~="string" then return end
    local n = tonumber(s)
    return n and n == math.floor(n) and n >= lo and n <= hi and n
end
local groups={solo="s",party="p"}
local shares={winner="w",equal="e"}
local souvenirs={none="n",screenshot="s",video="v"}
local function rules(opts)
    local quota=number(opts.quota or 1,1,99)
    local group,split,media=opts.group or "party",opts.split or "winner",opts.souvenir or "none"
    if not quota or not groups[group] or not shares[split] or not souvenirs[media]
        or group=="solo" and split~="winner" or not plain(opts.note or "",100) then return end
    return quota,groups[group]..shares[split]..souvenirs[media]
end
local function scope()
    if not GL.db or not GetGuildInfo or not GetNormalizedRealmName then return end
    local name, _, _, realm = GL.Safe(GetGuildInfo,"player")
    realm = realm or GL.Safe(GetNormalizedRealmName)
    local me = GL.Clean(UnitGUID("player"),"string")
    name,realm=GL.Clean(name,"string"),GL.Clean(realm,"string")
    if not plain(name,120) or name == "" or not plain(realm,80) or realm == "" or not guid(me) then return end
    GL.db.bountyGuilds = GL.db.bountyGuilds or {}
    local key = realm.."/"..name
    local s = GL.db.bountyGuilds[key] or {events={}, seq=0}
    s.guildKey=key
    GL.db.bountyGuilds[key] = s
    return s, me
end
local function unpackEvent(raw,archiving)
    if type(raw) ~= "string" or #raw > 250 then return end
    local f = {}
    for v in (raw..";"):gmatch("(.-);") do f[#f+1]=v end
    if #f~=7 then return end
    local kind,actor,id,stamp,order,value,detail=unpack(f)
    if not id:match("^%d+$") then return end
    stamp=number(stamp,1,GL.Now()+60)
    if not guid(actor) or not stamp or (not archiving and stamp < GL.Now()-38*DAY) or not number(id,1,9999999999999) then return end
    local key=actor..":"..id
    local quota,group,split,souvenir,playerLevel,opponentLevel
    if kind=="N" then
        local copper,q,g,p,m=value:match("^(%d+),(%d+),([sp])([we])([nsv])$")
        quota=number(q,1,99)
        if not quota or not number(copper,0,1000*GOLD) or g=="s" and p~="w"
            or not guid(order) or not plain(detail,64) or detail=="" then return end
        value=copper
        group=g=="s" and "solo" or "party"
        split=p=="w" and "winner" or "equal"
        souvenir=m=="s" and "screenshot" or m=="v" and "video" or "none"
    elseif kind=="O" or kind=="A" then
        if not guid(order) or not number(value,0,1000*GOLD) or not plain(detail,64) or detail=="" then return end
        if kind=="A" and value~="0" then return end
    elseif kind=="D" then
        if not guid(order) or value~="" or not plain(detail,64) or stamp<GL.Now()-7200 then return end
    else
        local owner,seq=order:match("^([^:]+):(%d+)$")
        if not guid(owner) or not number(seq,1,9999999999999) then return end
        if kind=="P" then
            if not number(value,1,1000*GOLD) or detail~="" then return end
        elseif kind=="K" or kind=="H" then
            if kind=="H" then
                local flag,p,t=value:match("^([01]),(%d+),(%d+)$")
                if flag then
                    p,t=number(p,0,1000),number(t,0,1000)
                    if not p or not t then return end
                    value,playerLevel,opponentLevel=flag,p>0 and p or nil,t>0 and t or nil
                end
            end
            if (kind=="K" and value~="") or (kind=="H" and value~="0" and value~="1")
                or not plain(detail,140) then return end
            local seen,count={[actor]=true},0
            if detail~="" then
                for helper in (detail..","):gmatch("(.-),") do
                    if not guid(helper) or seen[helper] then return end
                    count=count+1; seen[helper]=true
                end
                if count>4 then return end
            end
        elseif kind=="U" then
            if actor~=owner or (value~="0" and value~="1") or not plain(detail,100) then return end
        elseif kind=="X" or kind=="F" then
            if actor~=owner or detail~="" then return end
            if kind=="X" and value~="" or kind=="F" and not value:match("^Player%-%w+%-%w+:%d+$") then return end
        elseif kind=="Y" then
            if not guid(detail) or not number(value,1,1000*GOLD) then return end
        else return end
    end
    return {kind=kind,actor=actor,key=key,time=stamp,order=order,value=value,detail=detail,
        quota=quota,group=group,split=split,souvenir=souvenir,playerLevel=playerLevel,opponentLevel=opponentLevel}
end
local function earlier(a,b)
    return a.time<b.time or a.time==b.time and a.key<b.key
end
local function view(s,archiving)
    local orders,events={},{}
    for _,raw in pairs(s.events) do
        local e=unpackEvent(raw,archiving)
        if e then
            if e.kind=="O" or e.kind=="A" or e.kind=="N" then
                orders[e.key]={id=e.key,owner=e.actor,target=e.order,name=e.detail,at=e.time,
                    custom=e.kind=="N",quota=e.quota or 1,group=e.group or "party",
                    split=e.split or "equal",souvenir=e.souvenir or "none",progress={},
                    guildKey=s.guildKey,expires=e.time+(e.kind=="A" and 3 or 7)*DAY,auto=e.kind=="A",
                    pot={[e.actor]=tonumber(e.value)},paid={},receipts={}}
            else events[#events+1]=e end
        end
    end
    -- A payer can settle an old debt after its guild event log has rotated away.
    local history=GL.db.bountyHistory and GL.db.bountyHistory[GL.Safe(UnitGUID,"player")]
    for id,item in pairs(history or {}) do
        if not orders[id] and item.guildKey==s.guildKey and item.state=="fulfilled" and item.winner
            and item.at<GL.Now()-38*DAY then
            local o={}
            for k,v in pairs(item) do o[k]=v end
            o.closed,o.archived="fulfilled",true
            o.paid,o.receipts={},{}
            for k,v in pairs(item.paid) do o.paid[k]=v end
            for k in pairs(item.receipts or {}) do o.receipts[k]=true end
            orders[id]=o
        end
    end
    table.sort(events,earlier)
    -- Only the issuer finalizes a hunter. Claims received in their absence survive reconnects.
    for _,e in ipairs(events) do
        local o=orders[e.order]
        if o and e.time>=o.at and e.time<=o.expires and not o.closed then
            if (not o.custom and e.kind=="K") or (o.custom and e.kind=="H"
                and (o.group=="party" or e.value=="0") and (o.split=="equal" or e.detail=="")
                and (e.value=="1" or e.detail=="")) then
                local wins=(o.progress[e.actor] or 0)+1
                o.progress[e.actor]=math.min(wins,o.quota)
                if wins==o.quota then
                    o.claims=o.claims or {}; o.claims[e.key]=e
                    o.first=o.first or e
                end
            elseif e.kind=="U" and (not o.first or e.time==o.at) then
                o.note=e.detail
                -- Leave at least seven days of history before the 38-day archive cutoff.
                if e.value=="1" then o.expires=math.min(o.at+31*DAY,e.time+(o.auto and 3 or 7)*DAY) end
            elseif e.kind=="X" and not o.first then o.closed="withdrawn"

            end
        end
    end
    for _,e in ipairs(events) do
        local o=orders[e.order]
        if o and e.kind=="F" and o.claims and o.claims[e.value] and not o.winner and o.closed~="withdrawn" then
            o.winner=o.claims[e.value]; o.closed="fulfilled"
        end
    end
    for _,e in ipairs(events) do
        local o=orders[e.order]
        if o and not o.archived and e.kind=="P" and e.time>=o.at and e.time<=o.expires and (not o.winner or e.time<=o.winner.time) then
            o.pot[e.actor]=math.min(1000*GOLD,(o.pot[e.actor] or 0)+tonumber(e.value))
        elseif o and o.winner and e.kind=="Y" and e.time>=o.winner.time and not o.receipts[e.key] then
            local k=e.actor.."/"..e.detail
            o.paid[k]=(o.paid[k] or 0)+tonumber(e.value)
            o.receipts[e.key]=true
        end
    end
    for _,o in pairs(orders) do
        if o.winner then
            local outstanding=false
            for payer in pairs(o.pot) do
                if B.Due(o,payer,o.winner.actor)>0 then outstanding=true end
                for h in o.winner.detail:gmatch("[^,]+") do
                    if B.Due(o,payer,h)>0 then outstanding=true end
                end
            end
            if not outstanding then o.closed="paid" end
        end
        o.state=o.closed or (o.first and "claimed") or (GL.Now()>o.expires and "expired") or "open"
    end
    return orders
end
function B.Progress(o,hunter)
    hunter=hunter or GL.Safe(UnitGUID,"player")
    return o and o.progress and o.progress[hunter] or 0
end
local function remember(orders,me)
    if not guid(me) then return end
    local all=GL.db.bountyHistory or {}
    GL.db.bountyHistory=all
    local history=all[me] or {}
    all[me]=history
    for id,o in pairs(orders) do
        local w=o.winner
        local mine=o.owner==me or o.pot[me]~=nil or B.Progress(o,me)>0
        if w then
            for h in w.detail:gmatch("[^,]+") do if h==me then mine=true end end
        end
        if mine and (w or o.state=="withdrawn" or o.state=="expired") then
            local previous=history[id]
            local progress=B.Progress(o,me)
            local copy={id=id,owner=o.owner,target=o.target,name=o.name,at=o.at,expires=o.expires,auto=o.auto,
                quota=o.quota,group=o.group,split=o.split,souvenir=o.souvenir,note=o.note,state=o.state,
                winner=w,pot=o.pot,paid=o.paid,progress={[me]=progress},guildKey=o.guildKey,
                receipts=o.state=="fulfilled" and o.receipts or nil}
            history[id]=copy
            if w and (not previous or not previous.winner) and GL.Print then
                if me==o.owner then
                    GL.Print("Prime accomplie : "..o.name..". "..(o.state=="paid" and "Aucun versement en attente." or "Consultez les parts dans Primes → Mon historique."))
                elseif w.actor==me then GL.Print("Prime accomplie : "..o.name..".") end
            end
        end
    end
    return history
end
function B.History()
    local s,me=scope()
    if s then
        local orders,expires=view(s),nil
        for _,o in pairs(orders) do
            if o.state=="open" and (not expires or o.expires<expires) then expires=o.expires end
        end
        return remember(orders,me) or {},expires
    end
    return GL.db and GL.db.bountyHistory and GL.db.bountyHistory[GL.Safe(UnitGUID,"player")] or {}
end
function B.List()
    local s=scope()
    return s and view(s) or {}
end
-- Gross amount to mail, followed by the share a contributing hunter keeps.
function B.Share(o,payer,hunter)
    if not o or not o.winner then return 0,0 end
    local w=o.winner
    local n,member=1,w.actor==hunter
    for h in w.detail:gmatch("[^,]+") do n=n+1; member=member or h==hunter end
    if not member then return 0,0 end
    local sum=o.pot[payer] or 0
    local share=math.floor(sum/n)+(hunter==w.actor and sum%n or 0)
    if payer==hunter then return 0,share end
    return share,0
end
function B.Due(o,payer,hunter)
    local share=B.Share(o,payer,hunter)
    if share==0 then return 0 end
    return math.max(0,share-(o.paid[payer.."/"..hunter] or 0))
end
local queue,queued,active={}, {},nil
local joined, openTargets, lastAlert, indexedScope
local roster,addresses={},{}
local pendingRefresh={}
local function changed(s,me)
    if pendingRefresh[s] then return end
    local function refresh()
        pendingRefresh[s]=nil
        if scope()~=s then return end
        remember(view(s),me)
        if GL.Emit then GL.Emit("BOUNTIES_CHANGED") end
    end
    if C_Timer and C_Timer.After then
        pendingRefresh[s]=true
        C_Timer.After(0,refresh)
    else refresh() end
end
local function schedule(s,msg)
    if active~=s then active,queue,queued=s,{},{} end
    if not queued[msg] then queue[#queue+1]=msg; queued[msg]=true end
end
-- Per-member cumulative totals survive replay and offline catch-up.
local function mergeScore(s,actor,target,wins,losses)
    s.scores=s.scores or {}
    local scores=s.scores[target] or {}
    s.scores[target]=scores
    local old=scores[actor] or {0,0}
    scores[actor]={math.max(old[1],wins),math.max(old[2],losses)}
end
local function scoreMessage(actor,target,wins,losses)
    return table.concat({"G",actor,target,wins,losses},";")
end
local function countFight(target,index)
    local s,me=scope()
    if not (s and s.shareFights and s.shareFights[me] and guid(target)) then return end
    local totals=s.scores and s.scores[target] and s.scores[target][me] or {0,0}
    local wins,losses=totals[1],totals[2]
    if index==1 then wins=wins+1 else losses=losses+1 end
    mergeScore(s,me,target,wins,losses)
    schedule(s,scoreMessage(me,target,wins,losses))
end
function B.ShareFights(enabled)
    local s,me=scope()
    if s then s.shareFights=s.shareFights or {}; s.shareFights[me]=enabled==true end
end
function B.GuildFights(target)
    local s=scope()
    local wins,losses=0,0
    for _,n in pairs(s and s.scores and s.scores[target] or {}) do
        wins=wins+n[1]; losses=losses+n[2]
    end
    return wins,losses
end
local function declare(kind,order,value,detail)
    local s,me=scope()
    if not s then return nil,"guild" end
    local seq=math.max(s.seq+1,GL.Now()*1000)
    local raw=table.concat({kind,me,seq,GL.Now(),order,value,detail},";")
    local e=unpackEvent(raw)
    if not e then return nil,"invalid" end
    openTargets=nil
    s.seq=seq; s.events[e.key]=raw; schedule(s,raw)
    if kind~="D" then changed(s,me) end
    return e.key
end
function B.Post(target,name,copper,opts)
    local s,me=scope()
    if not s or not guid(target) or target==me or not plain(name,64) or name=="" or not number(copper,0,1000*GOLD) then return nil,"invalid" end
    local count=0
    for _,o in pairs(view(s)) do
        if o.state=="open" or o.state=="claimed" then
            if o.target==target then return nil,"duplicate" end
            if o.owner==me then count=count+1 end
        end
    end
    if count>=10 then return nil,"limit" end
    if type(opts)=="table" then
        local quota,flags=rules(opts)
        if not quota then return nil,"invalid" end
        -- Legacy clients ignore N/H, so a one-kill claim cannot close a multi-kill order.
        local id,err=declare("N",target,copper..","..quota..","..flags,name)
        if id and opts.note and opts.note~="" then declare("U",id,"0",opts.note) end
        return id,err
    end
    if opts~=nil and type(opts)~="boolean" then return nil,"invalid" end
    return declare(opts and "A" or "O",target,copper,name)
end
function B.Pledge(id,copper)
    local s,me=scope()
    local o=s and view(s)[id]
    if not o or o.state~="open" or not number(copper,1,1000*GOLD) or (o.pot[me] or 0)+copper>1000*GOLD then return nil,"invalid" end
    return declare("P",id,copper,"")
end
function B.Update(id,note,renew)
    local s,me=scope()
    local o=s and view(s)[id]
    if not o or o.owner~=me or o.state~="open" then return nil,"invalid" end
    if renew and o.expires>=o.at+31*DAY then return nil,"limit" end
    if note~=nil and not plain(note,100) then return nil,"invalid" end
    return declare("U",id,renew and "1" or "0",note==nil and (o.note or "") or note)
end
-- Reposting creates a fresh contract; other members' pledges stay with the old one.
function B.CanRepost(o)
    local s,me=scope()
    return s and o and o.state=="expired" and o.owner==me and o.guildKey==s.guildKey
end
function B.OpenFor(target)
    if not guid(target) then return end
    local s=scope()
    if not s then return end
    if not openTargets or indexedScope~=s then
        openTargets={}
        indexedScope=s
        for _,o in pairs(view(s)) do
            if o.state=="open" or o.state=="claimed" then openTargets[o.target]=o end
        end
    end
    local o=openTargets[target]
    if o and (o.state=="claimed" or GL.Now()<=o.expires) then return o end
end
function B.Observe(target)
    if not joined then return end
    local o=B.OpenFor(target)
    if not o or o.state~="open" then return end
    local now=GL.Now()
    if now<=o.expires and (not lastAlert[o.id] or now-lastAlert[o.id]>=120) then
        lastAlert[o.id]=now
        GL.Print("Prime de guilde : "..o.name..(o.note and o.note~="" and " — "..o.note or ""))
    end
end
function B.Withdraw(id)
    local s,me=scope()
    local o=s and view(s)[id]
    if not o or o.owner~=me or o.state~="open" then return nil,"invalid" end
    return declare("X",id,"","")
end
function B.ConfirmPayment(id,hunter,copper)
    local s,me=scope()
    if not s or not guid(hunter) or not number(copper,1,B.Due(view(s)[id],me,hunter)) then return nil,"invalid" end
    return declare("Y",id,copper,hunter)
end
local function helpers(guildOnly)
    local out,seen={},{}
    local raid=GL.Safe(IsInRaid)
    for i=1,GL.Safe(GetNumGroupMembers) or 0 do
        local u=(raid and "raid" or "party")..i
        if GL.Safe(UnitExists,u) and GL.Safe(UnitIsUnit,u,"player")~=true and GL.Safe(UnitIsVisible,u) then
            local h=GL.Safe(UnitGUID,u)
            if guid(h) and not seen[h] and (not guildOnly or addresses[h]) then out[#out+1]=h; seen[h]=true end
            if #out==4 then break end
        end
    end
    return table.concat(out,",")
end
local function finalize(s,me)
    for id,o in pairs(view(s)) do
        if o.owner==me and o.state=="claimed" then declare("F",id,o.first.key,"") end
    end
end
function B.Kill(target,combat)
    countFight(target,1)
    local s,me=scope()
    if not s then return end
    if s==joined and openTargets and not openTargets[target] then return end
    local owned
    for id,o in pairs(view(s)) do
        if o.target==target and o.state=="open" then
            local claim
            if o.custom then
                local count=GL.Safe(GetNumGroupMembers)
                if count and GL.Safe(IsInRaid)~=true and count<=5 and (o.group=="party" or count==0) then
                    local flag=count>0 and "1" or "0"
                    local p=combat and number(combat.playerLevel,1,1000)
                    local t=combat and number(combat.opponentLevel,1,1000)
                    if p or t then flag=flag..","..(p or 0)..","..(t or 0) end
                    claim=declare("H",id,flag,o.split=="equal" and helpers(true) or "")
                end
            else claim=declare("K",id,"",helpers()) end
            if claim and o.owner==me then owned=true end
        end
    end
    if owned then finalize(s,me) end
end
local function autoOrder(s,me,target,name)
    local victims,distinct,mine={},0,0
    for _,raw in pairs(s.events) do
        local e=unpackEvent(raw)
        if e and e.order==target then
            if e.kind=="A" and GL.Now()-e.time<DAY then return end
            if e.kind=="D" then
                if not victims[e.actor] then victims[e.actor]=true; distinct=distinct+1 end
                if e.actor==me and GL.Now()-e.time<=1800 then mine=mine+1 end
            end
        end
    end
    if distinct>=3 or mine>=3 then B.Post(target,name,0,true) end
end
function B.ShareDeaths(enabled)
    local s,me=scope()
    if s then s.shareDeaths=s.shareDeaths or {}; s.shareDeaths[me]=enabled==true end
end
function B.Death(target,name)
    countFight(target,2)
    local s,me=scope()
    if s and s.shareDeaths and s.shareDeaths[me] and guid(target) and plain(name,64) then
        if declare("D",target,"",name) then autoOrder(s,me,target,name) end
    end
end
local budgets={}
local function receive(msg,sender)
    local s,me=scope()
    if not s or type(msg)~="string" or #msg>255 or GL.ContainsControlOrMarkup(msg) or not sender then return end
    local now=GL.Now()
    local budget=budgets[sender]
    if not budget or now-budget.at>=10 then budget={at=now,n=0,lastQ=budget and budget.lastQ}; budgets[sender]=budget end
    budget.n=budget.n+1
    if budget.n>45 then return end
    if msg=="Q" then
        if budget.lastQ and now-budget.lastQ<10 then return end
        budget.lastQ=now
        for target,scores in pairs(s.scores or {}) do
            for actor,n in pairs(scores) do schedule(s,"R;"..scoreMessage(actor,target,n[1],n[2])) end
        end
        for _,raw in pairs(s.events) do if unpackEvent(raw) then schedule(s,"R;"..raw) end end
        return
    end
    local relay=msg:sub(1,2)=="R;"
    local raw=relay and msg:sub(3) or msg
    if raw:sub(1,2)=="G;" then
        local actor,target,wins,losses=raw:match("^G;([^;]+);([^;]+);(%d+);(%d+)$")
        wins,losses=number(wins,0,10000000),number(losses,0,10000000)
        if guid(actor) and guid(target) and wins and losses and actor~=me and (relay or actor==sender) then
            mergeScore(s,actor,target,wins,losses)
        end
        return
    end
    local e=unpackEvent(raw)
    if not e or s.events[e.key] then return end
    if not relay and e.actor~=sender then return end
    -- Relays are guild testimony, never an instruction to send gold or alter personal records.
    if e.actor==me then return end
    openTargets=nil
    s.events[e.key]=raw
    if (e.kind=="K" or e.kind=="H") and e.order:match("^([^:]+)")==me then finalize(s,me) end
    if e.kind~="D" then changed(s,me) end
end
local frame=CreateFrame("Frame")
local lastPrune
local function refreshRoster()
    roster,addresses={},{}
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    for i=1,GetNumGuildMembers() do
        local name,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,id=GetGuildRosterInfo(i)
        name,id=GL.Clean(name,"string"),GL.Clean(id,"string")
        if name and guid(id) then
            roster[name]=id; addresses[id]=name
            if not name:find("-") then roster[name.."-"..GetNormalizedRealmName()]=id end
        end
    end
end
function B.MemberName(id)
    local r=guid(id) and GL.Get and GL.Get("guid:"..id)
    return addresses[id] or (r and (r.fullName or r.name))
end
local draft,pending,hooked,selectedOrder
local function noItems()
    for i=1,ATTACHMENTS_MAX_SEND or 12 do
        if (HasSendMailItem and HasSendMailItem(i)) or GetSendMailItem(i) then return false end
    end
    return true
end
local function onSend(to,subject)
    -- A new unrelated native send makes the old acknowledgement ambiguous.
    -- Keep its durable marker for reconciliation, never credit that mail.
    if pending then pending,draft=nil,nil; return end
    if not pending and draft and to==draft.to and subject==draft.subject and SendMailSendMoneyButton:GetChecked()
        and MoneyInputFrame_GetCopper(SendMailMoney)==draft.amount and noItems() then
        pending=draft; pending.at=GL.Now()
        local s,me=scope()
        if s==draft.guild then
            s.mailUncertain=s.mailUncertain or {}
            s.mailUncertain[me]={id=draft.id,hunter=draft.hunter,amount=draft.amount}
        end
    end
    draft=nil
end
local function nextDebt(s,me,id,hunter)
    local orders=view(s)
    local picked,to,due
    for key,o in pairs(orders) do
        if (not id or id==key) and o.winner then
            for h in (o.winner.actor..","..o.winner.detail):gmatch("[^,]+") do
                local n=B.Due(o,me,h)
                if (not hunter or hunter==h) and n>0 and addresses[h] and
                    (not picked or key<picked or key==picked and h<to) then picked,to,due=key,h,n end
            end
        end
    end
    return picked,to,due,orders[picked]
end
-- Open the native Send Mail tab first. Never overwrite a draft or send gold.
function B.PrepareMail(id,hunter,expectedAmount)
    local s,me=scope()
    if not s or joined~=s then return nil,"guild" end
    if MailFrame and MailFrame:IsShown() and MailFrameTab2 and SendMailFrame and not SendMailFrame:IsShown() then MailFrameTab2:Click() end
    if not (SendMailFrame and SendMailFrame:IsShown() and SendMailNameEditBox and SendMailSubjectEditBox
        and SendMailBodyEditBox and SendMailMoney and MoneyInputFrame_SetCopper and MoneyInputFrame_GetCopper
        and GetSendMailItem and SendMailSendMoneyButton and SendMailRadioButton_OnClick and hooksecurefunc and SendMail) then return nil,"mailbox" end
    if SendMailNameEditBox:GetText()~="" or SendMailSubjectEditBox:GetText()~="" or SendMailBodyEditBox:GetText()~=""
        or MoneyInputFrame_GetCopper(SendMailMoney)~=0 or not SendMailSendMoneyButton:GetChecked() then return nil,"draft" end
    if not noItems() then return nil,"draft" end
    if pending or (s.mailUncertain and s.mailUncertain[me]) then return nil,"pending" end
    local picked,to,due,o=nextDebt(s,me,id,hunter)
    if not picked then return nil,"no_payable_recipient" end
    if expectedAmount and expectedAmount~=due then return nil,"changed" end
    if GetMoney and GetMoney()<due then return nil,"funds" end
    if not hooked then hooksecurefunc("SendMail",onSend); hooked=true end
    SendMailRadioButton_OnClick(1)
    SendMailNameEditBox:SetText(addresses[to])
    SendMailSubjectEditBox:SetText("Prime : "..o.name)
    MoneyInputFrame_SetCopper(SendMailMoney,due)
    draft={guild=s,id=picked,hunter=to,amount=due,to=addresses[to],subject=SendMailSubjectEditBox:GetText()}
    return picked,to,due
end
-- A reload can lose the acknowledgement after the gold has left. Never retry
-- that share until the payer has checked their sent mail or the recipient.
function B.ReconcileMail(wasSent)
    local s,me=scope()
    local t=s and s.mailUncertain and s.mailUncertain[me]
    if not t or type(wasSent)~="boolean" then return end
    if pending and not pending.closed and GL.Now()-pending.at<60 then return end
    pending=nil
    if wasSent then
        local remaining=B.Due(B.List()[t.id],me,t.hunter)
        if remaining>0 and not B.ConfirmPayment(t.id,t.hunter,math.min(remaining,t.amount)) then return end
    end
    s.mailUncertain[me]=nil
    return true
end
local payButton,cycleButton
local ML=GL.L or function(s) return s end
local function payable(s,me)
    local ids,orders={},view(s)
    for key,o in pairs(orders) do
        if o.winner then
            for h in (o.winner.actor..","..o.winner.detail):gmatch("[^,]+") do
                if B.Due(o,me,h)>0 then ids[#ids+1]=key; break end
            end
        end
    end
    table.sort(ids)
    return ids,orders
end
local function showPayment()
    local s,me=scope()
    local ids,orders={},{}
    if s and joined==s then ids,orders=payable(s,me) end
    if not ids[1] or not MailFrame or not SendMailMailButton then
        if payButton then payButton:Hide() end
        if cycleButton then cycleButton:Hide() end
        return
    end
    local index=1
    for i,id in ipairs(ids) do if id==selectedOrder then index=i; break end end
    selectedOrder=ids[index]
    if not payButton then
        payButton=CreateFrame("Button",nil,MailFrame,"UIPanelButtonTemplate")
        payButton:SetPoint("BOTTOMLEFT",MailFrame,"TOPLEFT",8,2)
        payButton:SetHeight(32)
        payButton:SetClampedToScreen(true)
        payButton:SetScript("OnClick",function(self)
            if draft and draft.id==self.order and SendMailNameEditBox:GetText()==draft.to
                and SendMailSubjectEditBox:GetText()==draft.subject and MoneyInputFrame_GetCopper(SendMailMoney)==draft.amount then return end
            local ok,why=B.PrepareMail(self.order)
            if not ok then
                if why=="draft" then GL.Print("Le courrier en cours a été conservé.")
                elseif why=="funds" then GL.Print("Fonds insuffisants.")
                elseif why=="pending" then GL.Print(ML("Vérifiez le dernier courrier avant de reprendre le règlement."))
                else GL.Print("Paiement indisponible. Vérifiez la prime et la boîte aux lettres.") end
                showPayment()
                return
            end
            GL.Print(ML("Courrier préparé. Vérifiez la part puis cliquez sur Envoyer."))
        end)
    end
    payButton.order=selectedOrder
    payButton:SetText(ML("Régler la prime : %s"):format(orders[selectedOrder].name))
    payButton:SetWidth(math.max(200,payButton:GetFontString():GetStringWidth()+28))
    payButton:Show()
    if #ids>1 then
        if not cycleButton then
            cycleButton=CreateFrame("Button",nil,MailFrame,"UIPanelButtonTemplate")
            cycleButton:SetPoint("LEFT",payButton,"RIGHT",3,0)
            cycleButton:SetSize(100,28)
        end
        cycleButton:SetText(ML("Autre prime").." ›")
        cycleButton:SetScript("OnClick",function()
            if pending or (draft and SendMailNameEditBox:GetText()~="") then
                GL.Print(ML("Terminez ou effacez le courrier en cours.")); return
            end
            selectedOrder=ids[index%#ids+1];showPayment()
        end)
        cycleButton:Show()
    elseif cycleButton then cycleButton:Hide() end
end
if SlashCmdList then
    SLASH_GLBOUNTY1="/glprime"
    SlashCmdList.GLBOUNTY=function(input)
        local action,id,arg=(input or ""):match("^%s*(%S*)%s*(%S*)%s*(.-)%s*$")
        local ok,reason
        if action=="" and GL.OpenBounties then GL.OpenBounties();return
        elseif action=="courrier" and (id=="envoye" or id=="nonenvoye") then
            ok=B.ReconcileMail(id=="envoye"); if ok and MailFrame and MailFrame:IsShown() then showPayment() end
            if not ok then GL.Print(ML("Aucun envoi incertain à vérifier.")) end
            return
        elseif action=="courrier" then ok,reason=B.PrepareMail(id~="" and id or nil,arg~="" and arg or nil)
        elseif action=="note" then ok,reason=B.Update(id,arg,false)
        elseif action=="renouveler" then ok,reason=B.Update(id,arg~="" and arg or nil,true)
        elseif action=="regler" then
            local h,n=arg:match("^(%S+)%s+(%d+)$")
            ok,reason=B.ConfirmPayment(id,h,tonumber(n))
        elseif action=="liste" then
            for key,o in pairs(B.List()) do GL.Print(o.name.." : "..key.." ("..o.state..")") end
            return
        else GL.Print("/glprime liste | courrier [contrat] [GUID] | note <contrat> <texte> | renouveler <contrat> [texte] | regler <contrat> <GUID> <cuivre>"); return end
        if not ok then
            local reasons={mailbox="Ouvrez l’onglet d’envoi de courrier.",draft="Un brouillon est déjà en cours.",
                pending="Un envoi est en cours.",funds="Fonds insuffisants.",no_payable_recipient="Aucun bénéficiaire payable identifié dans la guilde.",
                guild="Guilde indisponible.",invalid="Contrat ou note non valide.",limit="Durée maximale atteinte."}
            GL.Print(reasons[reason] or "Action impossible.")
        elseif action=="courrier" then GL.Print("Brouillon prêt. Vérifiez le destinataire et le montant avant l’envoi.")
        else GL.Print("Contrat mis à jour.") end
    end
end
local function join()
    local s,me=scope()
    if s and (not lastPrune or GL.Now()-lastPrune>=3600) then
        remember(view(s,true),me)
        for k,raw in pairs(s.events) do if not unpackEvent(raw) then s.events[k]=nil end end
        lastPrune=GL.Now()
    end
    if s and not next(roster) then joined,openTargets,lastAlert=nil,nil,{}; return end
    if s~=joined then
        budgets={}
        joined,openTargets,lastAlert=s,nil,{}
        if s then
            finalize(s,me)
            schedule(s,"Q")
            for _,raw in pairs(s.events) do
                local e=unpackEvent(raw)
                if e and e.actor==UnitGUID("player") then schedule(s,raw) end
            end
        end
    end
end
for _,event in ipairs({"MAIL_SHOW","MAIL_SEND_SUCCESS","MAIL_FAILED","MAIL_CLOSED"}) do frame:RegisterEvent(event) end
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent",function(_,event,prefix,msg,channel,sender)
    if event=="MAIL_SHOW" then
        local s,me=scope()
        if s and s.mailUncertain and s.mailUncertain[me] then
            GL.Print(ML("Courrier incertain : vérifiez l’envoi puis /glprime courrier envoye ou /glprime courrier nonenvoye."))
        end
        showPayment();return
    end
    if event=="MAIL_SEND_SUCCESS" then
        local sent=pending
        pending=nil
        local s,me=scope()
        if sent and s==sent.guild and B.ConfirmPayment(sent.id,sent.hunter,sent.amount) then
            if s.mailUncertain then s.mailUncertain[me]=nil end
            local function advance()
                if not MailFrame or not MailFrame:IsShown() or scope()~=s then return end
                if nextDebt(s,me,sent.id) then
                    selectedOrder=sent.id
                    B.PrepareMail(sent.id)
                end
                showPayment()
            end
            if C_Timer and C_Timer.After then C_Timer.After(0,advance) else advance() end
            return
        end
        if MailFrame and MailFrame:IsShown() then showPayment() end
        return
    elseif event=="MAIL_CLOSED" then
        if pending then pending.closed=true end
        draft,selectedOrder=nil,nil; return
    elseif event=="MAIL_FAILED" then
        local s,me=scope()
        if pending and pending.guild==s then
            s.mailUncertain[me]=nil
            draft=pending
        end
        pending=nil
        if MailFrame and MailFrame:IsShown() then showPayment() end
        return
    end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage and C_Timer and C_Timer.NewTicker) then return end
    if event=="PLAYER_LOGIN" then
        joined=nil
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        C_Timer.NewTicker(0.5,function()
            if #queue==0 then return end
            local s=scope()
            if s and s==active then
                local text=queue[1]
                local ok,result=pcall(C_ChatInfo.SendAddonMessage,PREFIX,text,"GUILD")
                if not ok or (result~=nil and Enum and Enum.SendAddonMessageResult and result==Enum.SendAddonMessageResult.AddonMessageThrottle) then return end
                table.remove(queue,1); queued[text]=nil
            end
        end)
    elseif event=="CHAT_MSG_ADDON" then
        if prefix~=PREFIX or channel~="GUILD" or not GetGuildRosterInfo or not GetNumGuildMembers then return end
        sender=GL.Clean(sender,"string")
        if sender and roster[sender] then receive(GL.Clean(msg,"string"),roster[sender]) end
        return
    end
    refreshRoster()
    join()
end)
GL.On("BOUNTY_KILL",B.Kill)
GL.On("BOUNTY_DEATH",B.Death)
