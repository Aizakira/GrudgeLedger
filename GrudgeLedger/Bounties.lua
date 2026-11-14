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
    GL.db.bountyGuilds[key] = s
    return s, me
end
local function unpackEvent(raw)
    if type(raw) ~= "string" or #raw > 250 then return end
    local f = {}
    for v in (raw..";"):gmatch("(.-);") do f[#f+1]=v end
    if #f~=7 then return end
    local kind,actor,id,stamp,order,value,detail=unpack(f)
    if not id:match("^%d+$") then return end
    stamp=number(stamp,1,GL.Now()+60)
    if not guid(actor) or not stamp or stamp < GL.Now()-38*DAY or not number(id,1,9999999999999) then return end
    local key=actor..":"..id
    if kind=="O" or kind=="A" then
        if not guid(order) or not number(value,0,1000*GOLD) or not plain(detail,64) or detail=="" then return end
        if kind=="A" and value~="0" then return end
    elseif kind=="D" then
        if not guid(order) or value~="" or not plain(detail,64) or stamp<GL.Now()-7200 then return end
    else
        local owner,seq=order:match("^([^:]+):(%d+)$")
        if not guid(owner) or not number(seq,1,9999999999999) then return end
        if kind=="P" then
            if not number(value,1,1000*GOLD) or detail~="" then return end
        elseif kind=="K" then
            if value~="" or not plain(detail,140) then return end
            local seen,count={[actor]=true},0
            if detail~="" then
                for helper in (detail..","):gmatch("(.-),") do
                    if not guid(helper) or seen[helper] then return end
                    count=count+1; seen[helper]=true
                end
                if count>4 then return end
            end
        elseif kind=="X" or kind=="F" then
            if actor~=owner or detail~="" then return end
            if kind=="X" and value~="" or kind=="F" and not value:match("^Player%-%w+%-%w+:%d+$") then return end
        elseif kind=="Y" then
            if not guid(detail) or not number(value,1,1000*GOLD) then return end
        else return end
    end
    return {kind=kind,actor=actor,key=key,time=stamp,order=order,value=value,detail=detail}
end
local function earlier(a,b)
    return a.time<b.time or a.time==b.time and a.key<b.key
end
local function view(s)
    local orders,events={},{}
    for _,raw in pairs(s.events) do
        local e=unpackEvent(raw)
        if e then
            if e.kind=="O" or e.kind=="A" then
                orders[e.key]={id=e.key,owner=e.actor,target=e.order,name=e.detail,at=e.time,
                    expires=e.time+(e.kind=="A" and 3 or 7)*DAY,auto=e.kind=="A",pot={[e.actor]=tonumber(e.value)},paid={}}
            else events[#events+1]=e end
        end
    end
    table.sort(events,earlier)
    -- Only the issuer finalizes a hunter. Claims received in their absence survive reconnects.
    for _,e in ipairs(events) do
        local o=orders[e.order]
        if o and e.time>=o.at and e.time<=o.expires and not o.closed then
            if e.kind=="K" then
                o.claims=o.claims or {}; o.claims[e.key]=e
                o.first=o.first or e
            elseif e.kind=="X" then o.closed="withdrawn"

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
        if o and e.kind=="P" and e.time>=o.at and e.time<=o.expires and (not o.winner or e.time<=o.winner.time) then
            o.pot[e.actor]=math.min(1000*GOLD,(o.pot[e.actor] or 0)+tonumber(e.value))
        elseif o and e.kind=="Y" then
            local k=e.actor.."/"..e.detail
            o.paid[k]=(o.paid[k] or 0)+tonumber(e.value)
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
function B.List()
    local s=scope()
    return s and view(s) or {}
end
function B.Due(o,payer,hunter)
    if not o or not o.winner or payer==hunter then return 0 end
    local w=o.winner
    local n,member=1,w.actor==hunter
    for h in w.detail:gmatch("[^,]+") do n=n+1; member=member or h==hunter end
    if not member then return 0 end
    local sum=o.pot[payer] or 0
    local share=math.floor(sum/n)+(hunter==w.actor and sum%n or 0)
    return math.max(0,share-(o.paid[payer.."/"..hunter] or 0))
end
local queue,queued,active={}, {},nil
local function schedule(s,msg)
    if active~=s then active,queue,queued=s,{},{} end
    if not queued[msg] then queue[#queue+1]=msg; queued[msg]=true end
end
local function declare(kind,order,value,detail)
    local s,me=scope()
    if not s then return nil,"guild" end
    local seq=math.max(s.seq+1,GL.Now()*1000)
    local raw=table.concat({kind,me,seq,GL.Now(),order,value,detail},";")
    local e=unpackEvent(raw)
    if not e then return nil,"invalid" end
    s.seq=seq; s.events[e.key]=raw; schedule(s,raw)
    return e.key
end
function B.Post(target,name,copper,auto)
    local s,me=scope()
    if not s or not guid(target) or target==me or not plain(name,64) or name=="" or not number(copper,0,1000*GOLD) then return nil,"invalid" end
    local count=0
    for _,o in pairs(view(s)) do
        if o.state=="open" or o.state=="claimed" then
            if o.target==target and (auto or o.owner==me) then return nil,"duplicate" end
            if o.owner==me then count=count+1 end
        end
    end
    if count>=10 then return nil,"limit" end
    return declare(auto and "A" or "O",target,copper,name)
end
function B.Pledge(id,copper)
    local s,me=scope()
    local o=s and view(s)[id]
    if not o or o.state~="open" or not number(copper,1,1000*GOLD) or (o.pot[me] or 0)+copper>1000*GOLD then return nil,"invalid" end
    return declare("P",id,copper,"")
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
local function helpers()
    local out,seen={},{}
    local raid=IsInRaid()
    for i=1,GetNumGroupMembers() do
        local u=(raid and "raid" or "party")..i
        if UnitExists(u) and not UnitIsUnit(u,"player") and UnitIsVisible(u) then
            local h=UnitGUID(u)
            if guid(h) and not seen[h] then out[#out+1]=h; seen[h]=true end
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
function B.Kill(target)
    local s,me=scope()
    if not s then return end
    for id,o in pairs(view(s)) do
        if o.target==target and o.state=="open" then declare("K",id,"",helpers()) end
    end
    finalize(s,me)
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
        for _,raw in pairs(s.events) do if unpackEvent(raw) then schedule(s,"R;"..raw) end end
        return
    end
    local relay=msg:sub(1,2)=="R;"
    local raw=relay and msg:sub(3) or msg
    local e=unpackEvent(raw)
    if not e or s.events[e.key] then return end
    if not relay and e.actor~=sender then return end
    -- Relays are guild testimony, never an instruction to send gold or alter personal records.
    if e.actor==me then return end
    s.events[e.key]=raw
    if (e.kind=="K" and e.order:match("^([^:]+)")==me) or e.actor==me then finalize(s,me) end
end
local frame=CreateFrame("Frame")
local joined, lastPrune
local roster={}
local function refreshRoster()
    roster={}
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    for i=1,GetNumGuildMembers() do
        local name,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,id=GetGuildRosterInfo(i)
        name,id=GL.Clean(name,"string"),GL.Clean(id,"string")
        if name and guid(id) then
            roster[name]=id
            if not name:find("-") then roster[name.."-"..GetNormalizedRealmName()]=id end
        end
    end
end
local function join()
    local s=scope()
    if s and (not lastPrune or GL.Now()-lastPrune>=3600) then
        for k,raw in pairs(s.events) do if not unpackEvent(raw) then s.events[k]=nil end end
        lastPrune=GL.Now()
    end
    if s and not next(roster) then return end
    if s~=joined then
        budgets={}
        joined=s
        if s then
            schedule(s,"Q")
            for _,raw in pairs(s.events) do
                local e=unpackEvent(raw)
                if e and e.actor==UnitGUID("player") then schedule(s,raw) end
            end
        end
    end
end
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent",function(_,event,prefix,msg,channel,sender)
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
