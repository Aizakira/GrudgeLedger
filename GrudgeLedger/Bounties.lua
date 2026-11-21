-- Guild bounty records are separate from personal history. Values on the wire are
-- immutable declarations. A guild peer may replay a cached declaration at login.
local GL = GrudgeLedger
local B = {}
GL.Bounties = B
local ML=GL.L or function(s) return s end
local DAY, GOLD = 86400, 10000
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
    if not GL.db or not GetGuildInfo then return end
    local name, _, _, realm = GL.Safe(GetGuildInfo,"player")
    realm = realm or GL.Safe(GetNormalizedRealmName)
    -- Some clients give no normalized realm name: the plain one, without spaces, is the same key.
    if type(realm)~="string" or realm=="" then
        local plainRealm=GL.Clean(GL.Safe(GetRealmName),"string")
        realm=plainRealm and plainRealm:gsub("[%s%-]","") or realm
    end
    local me = GL.Clean(UnitGUID("player"),"string")
    name,realm=GL.Clean(name,"string"),GL.Clean(realm,"string")
    -- Owner report (0.47.1): on his client neither realm name could be read, and no bounty could be
    -- posted. The realm number carried by your own identifier always exists and is the same for
    -- every member of the guild on that realm.
    if (type(realm)~="string" or realm=="" or not plain(realm,80)) and guid(me) then realm=me:match("^Player%-(%w+)%-") end
    -- Says which part cannot be read, for the message shown to the player.
    if not guid(me) then return nil,"player" end
    -- No guild at all is not a reading failure: bounties live in a guild, and the player is told so.
    if (name==nil or name=="") and IsInGuild and GL.Safe(IsInGuild)==false then return nil,"noguild" end
    if not plain(name,120) or name == "" then
        -- The guild exists but its name has not arrived yet: ask the game for it, for the next try.
        local roster=C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
        if type(roster)=="function" then GL.Safe(roster) end
        return nil,"guild"
    end
    if not plain(realm,80) or realm == "" then return nil,"realm" end
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
    if not guid(actor) or not stamp or (not archiving and kind~="V" and stamp < GL.Now()-38*DAY)
        or not number(id,1,9999999999999) then return end
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
        elseif kind=="S" then
            if actor~=owner or detail~="" or not value:match("^Player%-%w+%-%w+:%d+$") then return end
        elseif kind=="X" or kind=="F" then
            if actor~=owner or detail~="" then return end
            if kind=="X" and value~="" or kind=="F" and not value:match("^Player%-%w+%-%w+:%d+$") then return end
        elseif kind=="Y" then
            if not guid(detail) or not number(value,1,1000*GOLD) then return end
        elseif kind=="V" then
            local offset,amount=value:match("^(%d+),(%d+)$")
            if not guid(detail) or actor==detail or not number(offset,0,1000*GOLD)
                or not number(amount,1,1000*GOLD-tonumber(offset)) then return end
        else return end
    end
    return {kind=kind,actor=actor,key=key,time=stamp,order=order,value=value,detail=detail,
        quota=quota,group=group,split=split,souvenir=souvenir,playerLevel=playerLevel,opponentLevel=opponentLevel}
end
local function earlier(a,b)
    return a.time<b.time or a.time==b.time and a.key<b.key
end
local function commitment(o)
    if next(o.paid) or next(o.arrivals) then return 3 end
    return o.winner and 2 or o.first and 1 or 0
end
local function view(s,archiving)
    local orders,events={},{}
    for _,raw in pairs(s.events) do
        local e=unpackEvent(raw,archiving)
        if e then
            if e.kind=="O" or e.kind=="A" or e.kind=="N" then
                orders[e.key]={id=e.key,seq=tonumber(e.key:match(":(%d+)$")),owner=e.actor,target=e.order,name=e.detail,at=e.time,
                    custom=e.kind=="N",quota=e.quota or 1,group=e.group or "party",
                    split=e.split or "equal",souvenir=e.souvenir or "none",progress={},
                    guildKey=s.guildKey,expires=e.time+(e.kind=="A" and 3 or 7)*DAY,auto=e.kind=="A",
                    pot={[e.actor]=tonumber(e.value)},paid={},receipts={},arrivals={}}
            else events[#events+1]=e end
        end
    end
    -- A payer can settle an old debt after its guild event log has rotated away.
    local history=GL.db.bountyHistory and GL.db.bountyHistory[GL.Safe(UnitGUID,"player")]
    for id,item in pairs(history or {}) do
        if not orders[id] and item.guildKey==s.guildKey and (item.winner or item.priorWinner)
            and (item.state=="fulfilled" or item.state=="sent" or item.state=="paid" and not item.arrivals or item.state=="superseded")
            and item.at<GL.Now()-38*DAY then
            local o={}
            for k,v in pairs(item) do o[k]=v end
            o.closed,o.archived=item.supersededBy and "superseded" or "fulfilled",true
            o.paid,o.receipts,o.arrivals={},{},{}
            for k,v in pairs(item.paid) do o.paid[k]=v end
            for k in pairs(item.receipts or {}) do o.receipts[k]=true end
            for pair,amounts in pairs(item.arrivals or {}) do
                o.arrivals[pair]={}
                for start,amount in pairs(amounts) do o.arrivals[pair][start]=amount end
            end
            orders[id]=o
        end
    end
    table.sort(events,earlier)
    -- Only the issuer finalizes a hunter. Claims received in their absence survive reconnects.
    for _,e in ipairs(events) do
        local o=orders[e.order]
        if o and e.time>=o.at and e.time<=o.expires and not o.closed then
            if e.kind=="S" then o.after=e.value
            elseif (not o.custom and e.kind=="K") or (o.custom and e.kind=="H"
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
            elseif e.kind=="X" and not o.first then
                o.closed,o.endedAt,o.endedKey="withdrawn",e.time,e.key
            end
        end
    end
    for _,e in ipairs(events) do
        local o=orders[e.order]
        if o and e.kind=="F" and o.claims and o.claims[e.value] and not o.winner and o.closed~="withdrawn" then
            o.winner=o.claims[e.value]; o.closed="fulfilled"
            o.endedAt,o.endedKey=math.max(e.time,o.winner.time),e.key
        end
    end
    for _,e in ipairs(events) do
        local o=orders[e.order]
        if o and not o.archived and e.kind=="P" and e.time>=o.at and e.time<=o.expires and (not o.winner or e.time<=o.winner.time) then
            o.pot[e.actor]=math.min(1000*GOLD,(o.pot[e.actor] or 0)+tonumber(e.value))
        elseif o and (o.winner or o.priorWinner) and e.kind=="Y" and e.time>=(o.winner or o.priorWinner).time and not o.receipts[e.key] then
            local k=e.actor.."/"..e.detail
            if B.Share(o,e.actor,e.detail)>0 then
                o.paid[k]=(o.paid[k] or 0)+tonumber(e.value)
                o.receipts[e.key]=true
            end
        end
    end
    -- A mailbox receipt can reach the guild before the pledge or the sender's
    -- acknowledgement. Resolve against the final shares, independent of wire order.
    for _,e in ipairs(events) do
        local o=orders[e.order]
        if e.kind=="V" and o and (o.winner or o.priorWinner) and e.time>=(o.winner or o.priorWinner).time then
            local start,amount=e.value:match("^(%d+),(%d+)$")
            start,amount=tonumber(start),tonumber(amount)
            if start+amount<=B.Share(o,e.detail,e.actor) then
                local pair=e.detail.."/"..e.actor
                local ranges=o.arrivals[pair] or {}
                ranges[start]=math.max(ranges[start] or 0,amount)
                o.arrivals[pair]=ranges
            end
        end
    end
    -- Two disconnected issuers may each have seen an empty board. Resolve once for
    -- all readers (tracking, combat, mail and history), using the immutable log.
    local publications={}
    for _,o in pairs(orders) do
        if not o.archived then publications[#publications+1]=o end
    end
    table.sort(publications,function(a,b)
        if a.at~=b.at then return a.at<b.at end
        if a.seq~=b.seq then return a.seq<b.seq end
        return a.id<b.id
    end)
    local active={}
    for _,o in ipairs(publications) do
        local prior=active[o.target]
        local finish=prior and (prior.endedAt or (not prior.first and prior.expires) or math.huge)
        local old=history and history[o.id]
        local known=old and old.supersededBy
        if known and (not orders[known] or orders[known].archived) then
            -- The other publication rotated first. Never resurrect the player's old debt.
            o.supersededBy,o.closed,o.priorWinner,o.winner=known,"superseded",o.winner,nil
        elseif not prior or finish<o.at or finish==o.at and prior.endedKey and (
            prior.owner==o.owner and tonumber(prior.endedKey:match(":(%d+)$"))<tonumber(o.id:match(":(%d+)$"))
            or o.after==prior.id) then
            active[o.target]=o
        else
            -- Preserve an already settled/awarded contract when an older posting
            -- arrives late. Equal commitments keep the first publication (GUID tie-break).
            local kept,lost=prior,o
            if commitment(o)>commitment(prior) then kept,lost=o,prior end
            active[o.target]=kept
            lost.supersededBy,lost.closed=kept.id,"superseded"
            lost.priorWinner,lost.winner=lost.winner,nil
        end
    end
    for _,o in pairs(orders) do
        -- A superseded historical payment stays auditable, with no new obligation.
        if o.supersededBy then
            while orders[o.supersededBy] and orders[o.supersededBy].supersededBy do
                o.supersededBy=orders[o.supersededBy].supersededBy
            end
        end
        if o.winner and not o.supersededBy then
            local due,awaiting=0,0
            for payer in pairs(o.pot) do
                for hunter in (o.winner.actor..","..o.winner.detail):gmatch("[^,]+") do
                    local toSend,toReceive=B.Payment(o,payer,hunter)
                    due,awaiting=due+toSend,awaiting+toReceive
                end
            end
            o.closed=awaiting==0 and "paid" or due==0 and "sent" or "fulfilled"
        end
        o.state=o.closed or (o.first and "claimed") or (GL.Now()>o.expires and "expired") or "open"
    end
    return orders
end
function B.Progress(o,hunter)
    hunter=hunter or GL.Safe(UnitGUID,"player")
    return o and not o.supersededBy and o.progress and o.progress[hunter] or 0
end
local roster,addresses={},{}
local function remember(orders,me)
    if not guid(me) then return end
    local all=GL.db.bountyHistory or {}
    GL.db.bountyHistory=all
    local history=all[me] or {}
    all[me]=history
    for id,o in pairs(orders) do
        if o.state=="open" or o.state=="claimed" then
            GL.RequestArmory("guid:"..o.target,o.name,o.target)
        end
        local w=o.winner
        local completed=w or o.priorWinner
        local mine=o.owner==me or o.pot[me]~=nil or (o.progress and (o.progress[me] or 0)>0) or history[id]~=nil
        if completed then
            for h in completed.detail:gmatch("[^,]+") do if h==me then mine=true end end
        end
        if mine and (w or o.state=="withdrawn" or o.state=="expired" or o.state=="superseded") then
            local previous=history[id]
            local progress=B.Progress(o,me)
            local payerNames=previous and previous.payerNames or {}
            for payer in pairs(o.pot) do
                if addresses[payer] then payerNames[payer]=addresses[payer] end
            end
            local copy={id=id,owner=o.owner,target=o.target,name=o.name,at=o.at,expires=o.expires,auto=o.auto,
                quota=o.quota,group=o.group,split=o.split,souvenir=o.souvenir,note=o.note,state=o.state,
                winner=w,priorWinner=o.priorWinner,pot=o.pot,paid=o.paid,progress={[me]=progress},guildKey=o.guildKey,supersededBy=o.supersededBy,
                arrivals=o.arrivals,payerNames=payerNames,receipts=o.state~="paid" and o.receipts or nil}
            copy.replacementNotified=previous and previous.replacementNotified
            history[id]=copy
            if o.supersededBy and o.owner==me and not copy.replacementNotified and GL.Print then
                copy.replacementNotified=true
                GL.Print(ML("Prime remplacée pour %s. Consultez le contrat retenu dans votre historique."):format(o.name))
            elseif w and not o.supersededBy and (not previous or not previous.winner) and GL.Print then
                if me==o.owner then
                    GL.Print(ML("Prime accomplie : %s."):format(o.name).." "..(o.state=="paid" and ML("Aucun versement en attente.") or ML("Consultez les parts dans Primes » Mon historique.")))
                elseif w.actor==me then GL.Print(ML("Prime accomplie : %s."):format(o.name)) end
            end
        elseif history[id] and history[id].state=="superseded" then history[id]=nil end
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
        local saved=remember(orders,me) or {}
        local result={}
        for id,o in pairs(saved) do result[id]=o end
        for id,o in pairs(orders) do
            if o.state=="claimed" and (o.owner==me or o.pot[me] or o.first.actor==me
                or (","..o.first.detail..","):find(","..me..",",1,true)) then result[id]=o end
        end
        return result,expires
    end
    return GL.db and GL.db.bountyHistory and GL.db.bountyHistory[GL.Safe(UnitGUID,"player")] or {}
end
-- A compact record per target, so the sheet keeps its bounty dossier after the
-- 38-day rotation of guild events. Each member keeps the copy of what they saw.
local MAX_RECORD_ORDERS, MAX_RECORD_TARGETS = 30, 400
local function compact(o)
    local total=0
    for _,amount in pairs(o.pot) do
        total=total+amount
    end
    local w=o.winner
    return {at=o.at,owner=o.owner,pot=total,state=o.state,endedAt=o.endedAt,expires=o.expires,quota=o.quota,
        hunter=w and w.actor,helpers=w and w.detail~="" and w.detail or nil,killedAt=w and w.time}
end
local function trim(map,limit,date)
    local keys={}
    for key in pairs(map) do
        keys[#keys+1]=key
    end
    if #keys<=limit then
        return
    end
    table.sort(keys,function(a,b) return date(map[a])>date(map[b]) end)
    for i=limit+1,#keys do
        map[keys[i]]=nil
    end
end
local function archive(s,orders)
    s.bountyRecords=s.bountyRecords or {}
    local records=s.bountyRecords
    for id,o in pairs(orders) do
        local r=records[o.target]
        if o.supersededBy then
            if r then
                r.orders[id]=nil
            end
        elseif not o.archived and guid(o.target) then
            r=r or {orders={}}
            r.name,r.at=o.name,math.max(r.at or 0,o.at)
            r.orders[id]=compact(o)
            records[o.target]=r
            trim(r.orders,MAX_RECORD_ORDERS,function(c) return c.at end)
        end
    end
    trim(records,MAX_RECORD_TARGETS,function(r) return r.at or 0 end)
end
-- The bounty dossier of one target: live orders first, then what was archived.
function B.TargetRecord(target)
    local s=scope()
    local result={orders={},count=0,promised=0,killed=0,expired=0,withdrawn=0,completed=0,honored=0}
    if not s or not guid(target) then
        return result
    end
    local entries={}
    local saved=s.bountyRecords and s.bountyRecords[target]
    for id,c in pairs(saved and saved.orders or {}) do
        entries[id]=c
    end
    for id,o in pairs(view(s)) do
        if o.target==target and not o.archived then
            entries[id]=not o.supersededBy and compact(o) or nil
        end
    end
    for id,c in pairs(entries) do
        local e={id=id}
        for k,v in pairs(c) do
            e[k]=v
        end
        if e.state=="open" and e.expires and GL.Now()>e.expires then
            e.state="expired"
        end
        result.orders[#result.orders+1]=e
        result.count,result.promised=result.count+1,result.promised+(e.pot or 0)
        if e.hunter then
            result.killed=result.killed+1
        end
        if e.state=="expired" or e.state=="withdrawn" then
            result[e.state]=result[e.state]+1
        end
        if e.state=="paid" or e.state=="sent" or e.state=="fulfilled" then
            result.completed=result.completed+1
            result.honored=result.honored+(e.state=="paid" and 1 or 0)
        end
    end
    table.sort(result.orders,function(a,b) return a.at>b.at end)
    return result
end
function B.List()
    local s=scope()
    return s and view(s) or {}
end
-- Gross amount to mail, followed by the share a contributing hunter keeps.
function B.Share(o,payer,hunter)
    local w=o and (o.winner or o.priorWinner)
    if not w then return 0,0 end
    local n,member=1,w.actor==hunter
    for h in w.detail:gmatch("[^,]+") do n=n+1; member=member or h==hunter end
    if not member then return 0,0 end
    local sum=o.pot[payer] or 0
    local share=math.floor(sum/n)+(hunter==w.actor and sum%n or 0)
    if payer==hunter then return 0,share end
    return share,0
end
function B.Payment(o,payer,hunter)
    local share=B.Share(o,payer,hunter)
    if share==0 then return 0,0,0 end
    local pair=payer.."/"..hunter
    local sent=(o.paid or {})[pair] or 0
    local arrived,covered,dispatched=0,0,sent
    local ranges=o.arrivals and o.arrivals[pair]
    if ranges then
        local starts={}
        for start in pairs(ranges) do starts[#starts+1]=start end
        table.sort(starts)
        for _,start in ipairs(starts) do
            local last=math.min(share,start+ranges[start])
            arrived=arrived+math.max(0,last-math.max(start,covered))
            dispatched=dispatched+math.max(0,last-math.max(start,covered,sent))
            covered=math.max(covered,last)
        end
    end
    if o.supersededBy then return 0,math.max(0,math.min(share,sent)-arrived),arrived end
    return math.max(0,share-dispatched), math.max(0,share-arrived), arrived
end
function B.Due(o,payer,hunter)
    local due=B.Payment(o,payer,hunter)
    return due
end
local joined, openTargets, indexedScope
local reconcileInbox
local draft,pending,hooked,selectedOrder
local pendingRefresh={}
local function changed(s,me)
    if pendingRefresh[s] then return end
    local function refresh()
        pendingRefresh[s]=nil
        if scope()~=s then return end
        local orders=view(s)
        remember(orders,me)
        archive(s,orders)
        local uncertain=s.mailUncertain and s.mailUncertain[me]
        if uncertain and uncertain.offset then
            local o=orders[uncertain.id] or GL.db.bountyHistory[me][uncertain.id]
            local ranges=o and o.arrivals and o.arrivals[me.."/"..uncertain.hunter]
            if ranges and (ranges[uncertain.offset] or 0)>=uncertain.amount then
                s.mailUncertain[me]=nil
                if pending and pending.closed then pending=nil end
            end
        end
        reconcileInbox(s,me,orders)
        if GL.Emit then GL.Emit("BOUNTIES_CHANGED") end
    end
    if C_Timer and C_Timer.After then
        pendingRefresh[s]=true
        C_Timer.After(0,refresh)
    else refresh() end
end
local function schedule(s,msg)
    GL.Transport.Send(s,msg)
end
B.GuildScope = scope
function B.SendJournal(s, message)
    schedule(s, "J;" .. message)
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
-- Sharing with the guild is on unless the member switched it off (0.51.0): the addon is about
-- sharing, and nobody should have to tick boxes for it to work. Only an explicit "false" stops it.
local function shared(consent,me)
    return not (type(consent)=="table" and consent[me]==false)
end
B.Shared=shared
local function countFight(target,index)
    local s,me=scope()
    if not (s and shared(s.shareFights,me) and guid(target)) then return end
    local totals=s.scores and s.scores[target] and s.scores[target][me] or {0,0}
    local wins,losses=totals[1],totals[2]
    if index==1 then wins=wins+1 else losses=losses+1 end
    mergeScore(s,me,target,wins,losses)
    schedule(s,scoreMessage(me,target,wins,losses))
end
function B.ShareFights(enabled)
    local s,me=scope()
    if s then s.shareFights=s.shareFights or {}; s.shareFights[me]=enabled==true; return true end
end
function B.Sharing()
    local s,me=scope()
    return (s and shared(s.shareFights,me))==true, (s and shared(s.shareDeaths,me))==true
end
function B.GuildFights(target)
    local s=scope()
    local wins,losses=0,0
    for _,n in pairs(s and s.scores and s.scores[target] or {}) do
        wins=wins+n[1]; losses=losses+n[2]
    end
    return wins,losses
end
local function record(s,me,kind,order,value,detail,deferRefresh)
    if not s then return nil,"guild" end
    local seq=math.max(s.seq+1,GL.Now()*1000)
    local raw=table.concat({kind,me,seq,GL.Now(),order,value,detail},";")
    local e=unpackEvent(raw)
    if not e then return nil,"invalid" end
    openTargets=nil
    s.seq=seq; s.events[e.key]=raw
    if s==scope() then
        schedule(s,raw)
        if kind~="D" and not deferRefresh then changed(s,me) end
    else
        remember(view(s,true),me)
        if GL.Emit then GL.Emit("BOUNTIES_CHANGED") end
    end
    return e.key
end
local function declare(kind,order,value,detail)
    local s,me=scope()
    return record(s,me,kind,order,value,detail)
end
function GL.BountyTargetEligible(record)
    if type(record)~="table" or not guid(record.guid) or record.guid==GL.Safe(UnitGUID,"player") then return false end
    local mine=UnitFactionGroup and GL.Clean(GL.Safe(UnitFactionGroup,"player"),"string")
    local faction=record.faction
    if not faction and GL.ArmoryProfile then
        local profile=GL.ArmoryProfile(record)
        faction=profile and profile.identity and profile.identity.faction
    end
    if faction=="Horda" then faction="Horde" elseif faction=="Alianza" then faction="Alliance" end
    return not ((mine=="Horde" or mine=="Alliance") and faction==mine)
end
function B.Post(target,name,copper,opts)
    local s,me=scope()
    -- The third value says which check refused, so the window can tell the player what to do.
    if not s then return nil,"invalid","scope:"..tostring(me) end
    if not guid(target) then return nil,"invalid","target" end
    if target==me then return nil,"invalid","self" end
    if not plain(name,64) or name=="" then return nil,"invalid","name" end
    if not number(copper,0,1000*GOLD) then return nil,"invalid","amount" end
    local candidate=GL.Get and GL.Get("guid:"..target) or {guid=target}
    if not candidate.faction and UnitFactionGroup and GL.Safe(UnitGUID,"target")==target then
        candidate={guid=target,faction=GL.Clean(GL.Safe(UnitFactionGroup,"target"),"string")}
    end
    if not GL.BountyTargetEligible(candidate) then return nil,"ally" end
    local count,previous=0,nil
    for _,o in pairs(view(s)) do
        if o.state=="open" or o.state=="claimed" then
            if o.target==target then return nil,"duplicate" end
            if o.owner==me then count=count+1 end
        elseif o.target==target and o.endedAt==GL.Now() and not o.supersededBy
            and (not previous or o.seq>previous.seq) then
            previous=o
        end
    end
    if count>=10 then return nil,"limit" end
    local kind,value
    if type(opts)=="table" then
        local quota,flags=rules(opts)
        if not quota then return nil,"invalid","rules" end
        -- Legacy clients ignore N/H, so a one-kill claim cannot close a multi-kill order.
        kind,value="N",copper..","..quota..","..flags
    elseif opts==nil or type(opts)=="boolean" then kind,value=opts and "A" or "O",copper
    else return nil,"invalid" end
    -- The game clock has one-second precision. Record an observed foreign close
    -- only for that ambiguous second; disconnected simultaneous posts lack this link.
    if previous then s.seq=math.max(s.seq,math.min(previous.seq,GL.Now()*1000+999)) end
    local successor=previous and previous.owner~=me
    local id,err=record(s,me,kind,target,value,name,successor)
    if id and successor then declare("S",id,previous.id,"") end
    if id and type(opts)=="table" and opts.note and opts.note~="" then declare("U",id,"0",opts.note) end
    return id,err
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
    if GL.GuildMap then GL.GuildMap.Fight("k",target) end
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
    if s then s.shareDeaths=s.shareDeaths or {}; s.shareDeaths[me]=enabled==true; return true end
end
function B.Death(target,name)
    if GL.GuildMap then GL.GuildMap.Fight("d",target,name) end
    countFight(target,2)
    local s,me=scope()
    if s and shared(s.shareDeaths,me) and guid(target) and plain(name,64) then
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
    if msg:sub(1,2)=="J;" then
        -- S1 is the 0.12.0 dossier protocol. Members still on it are ignored on purpose.
        if msg:sub(3,5)=="S1;" then
            return
        end
        if msg:sub(3,5)=="S2;" then
            if sender~=me and GL.SharedDossiers then GL.SharedDossiers.Receive(s,sender,msg:sub(3)) end
            return
        end
        if sender~=me and GL.GuildProfiles then GL.GuildProfiles.Receive(s,me,sender,msg:sub(3)) end
        return
    end
    if msg=="Q" then
        if budget.lastQ and now-budget.lastQ<10 then return end
        budget.lastQ=now
        if sender~=me and GL.GuildProfiles then GL.GuildProfiles.CatchUp(s,me) end
        if sender~=me and GL.GuildMap then GL.GuildMap.CatchUp(s,me,sender,false) end
        for target,scores in pairs(s.scores or {}) do
            for actor,n in pairs(scores) do schedule(s,"R;"..scoreMessage(actor,target,n[1],n[2])) end
        end
        for _,raw in pairs(s.events) do
            local e=unpackEvent(raw)
            if e and (e.time>=now-38*DAY or e.actor==me) then schedule(s,"R;"..raw) end
        end
        return
    end
    if sender~=me and GL.GuildMap then GL.GuildMap.Heard(sender) end
    local relay=msg:sub(1,2)=="R;"
    local raw=relay and msg:sub(3) or msg
    -- The version each member runs (GuildMap.lua, 0.58.0).
    if raw:sub(1,4)=="GLV;" then
        if GL.GuildMap then GL.GuildMap.Version(s,me,sender,raw:sub(5),relay) end
        return
    end
    -- Places of fights for the guild vision of the map (GuildMap.lua).
    if raw=="MQ" or raw=="MX" or raw:sub(1,2)=="M;" then
        if GL.GuildMap then GL.GuildMap.Receive(s,me,sender,raw,relay) end
        return
    end
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
    if e.kind=="V" and e.time<now-38*DAY then
        local archive=GL.db.bountyHistory and GL.db.bountyHistory[me]
        local o=archive and archive[e.order]
        if not o or o.guildKey~=s.guildKey or (o.state=="paid" and o.arrivals) then return end
    end
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
local function mailAddress(name)
    if name:find("-",1,true) then return name end
    return name.."-"..GetNormalizedRealmName()
end
local checkingInbox=false
reconcileInbox=function(current,me,orders)
    local inbox=GL.db.bountyInbox and GL.db.bountyInbox[me]
    if checkingInbox or not inbox or not next(inbox) then return end
    checkingInbox=true
    local history=GL.db.bountyHistory and GL.db.bountyHistory[me] or {}
    if current and not orders then orders=view(current) end
    for key,mail in pairs(inbox) do
        local archived=history[mail.id]
        local o=orders and orders[mail.id] or archived
        if o and (o.winner or o.priorWinner) then
            local guild=GL.db.bountyGuilds[o.guildKey]
            local payer
            for id in pairs(o.pot) do
                local name=guild==current and addresses[id] or nil
                name=name or (archived and archived.payerNames and archived.payerNames[id])
                if name and mailAddress(name)==mail.sender then payer=id; break end
            end
            if payer and guild and mail.offset+mail.amount<=B.Share(o,payer,me) then
                local seen=o.arrivals and o.arrivals[payer.."/"..me]
                inbox[key]=nil
                if not seen or (seen[mail.offset] or 0)<mail.amount then
                    if not record(guild,me,"V",mail.id,mail.offset..","..mail.amount,payer) then inbox[key]=mail end
                end
            end
        end
        if mail.at and mail.at<GL.Now()-38*DAY then inbox[key]=nil end
    end
    checkingInbox=false
end
local function scanInbox()
    if not GL.db or not GetInboxNumItems or not GetInboxHeaderInfo then return end
    local me=GL.Safe(UnitGUID,"player")
    if not guid(me) then return end
    local count=GL.Safe(GetInboxNumItems) or 0
    local current=scope()
    local saved=GL.db.bountyHistory and GL.db.bountyHistory[me] or {}
    local buffered=GL.db.bountyInbox and GL.db.bountyInbox[me] or {}
    local queuedHeaders=0
    for _ in pairs(buffered) do queuedHeaders=queuedHeaders+1 end
    local orders
    for index=1,count do
        local _,_,sender,subject,money,cod,_,_,_,returned=GetInboxHeaderInfo(index)
        sender,subject=GL.Clean(sender,"string"),GL.Clean(subject,"string")
        money,cod=GL.Clean(money,"number"),GL.Clean(cod,"number")
        if sender and plain(sender,100) and subject and cod==0 and number(money,1,1000*GOLD)
            and not GL.Clean(returned,"boolean") then
            local owner,seq,start=subject:match("^%[GL:(Player%-%w+%-%w+):(%d+)/(%d+)%]")
            local offset=number(start,0,1000*GOLD-money)
            if guid(owner) and number(seq,1,9999999999999) and offset then
                local id,address=owner..":"..seq,mailAddress(sender)
                local key=id.."/"..address.."/"..start
                if not orders then orders=current and view(current) or {} end
                local o=orders[id] or saved[id]
                local payer=roster[address] or roster[sender]
                local validShare=o and payer and offset+money<=B.Share(o,payer,me)
                -- Hold a bounded number of unverified headers while guild records catch up.
                if validShare or buffered[key] or queuedHeaders<128 then
                    if not buffered[key] then queuedHeaders=queuedHeaders+1 end
                    buffered[key]={id=id,sender=address,offset=offset,at=GL.Now(),
                        amount=math.max(money,buffered[key] and buffered[key].amount or 0)}
                    GL.db.bountyInbox=GL.db.bountyInbox or {}
                    GL.db.bountyInbox[me]=buffered
                end
            end
        end
    end
    reconcileInbox(current,me,orders)
end
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
            s.mailUncertain[me]={id=draft.id,hunter=draft.hunter,amount=draft.amount,offset=draft.offset}
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
    local offset=B.Share(o,me,to)-due
    SendMailSubjectEditBox:SetText(("[GL:%s/%d] %s"):format(picked,offset,o.name))
    MoneyInputFrame_SetCopper(SendMailMoney,due)
    draft={guild=s,id=picked,hunter=to,amount=due,offset=offset,to=addresses[to],subject=SendMailSubjectEditBox:GetText()}
    return picked,to,due
end
-- Native send success may arrive after a different contract won an offline
-- collision. Record money actually sent against its original tagged contract.
local function acknowledgeMail(s,me,mail)
    local o=view(s)[mail.id]
    if not o then return end
    if o.supersededBy then
        local share=B.Share(o,me,mail.hunter)
        if not mail.offset or mail.offset+mail.amount>share then return end
        local sent=(o.paid or {})[me.."/"..mail.hunter] or 0
        local amount=math.min(mail.amount,mail.offset+mail.amount-sent)
        if amount<=0 then return true end
        return record(s,me,"Y",mail.id,amount,mail.hunter)
    end
    local remaining=B.Due(o,me,mail.hunter)
    return remaining==0 or B.ConfirmPayment(mail.id,mail.hunter,math.min(remaining,mail.amount))
end
-- A reload can lose the acknowledgement after the gold has left. Never retry
-- that share until the payer has checked their sent mail or the recipient.
function B.ReconcileMail(wasSent)
    local s,me=scope()
    local t=s and s.mailUncertain and s.mailUncertain[me]
    if not t or type(wasSent)~="boolean" then return end
    if pending and not pending.closed and GL.Now()-pending.at<60 then return end
    pending=nil
    if wasSent and not acknowledgeMail(s,me,t) then return end
    s.mailUncertain[me]=nil
    return true
end
local payButton,cycleButton
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
                if why=="draft" then GL.Print(ML("Le courrier en cours a été conservé."))
                elseif why=="funds" then GL.Print(ML("Fonds insuffisants."))
                elseif why=="pending" then GL.Print(ML("Vérifiez le dernier courrier avant de reprendre le règlement."))
                else GL.Print(ML("Paiement indisponible. Vérifiez la prime et la boîte aux lettres.")) end
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
    local verbs={list="liste",lista="liste",mail="courrier",correo="courrier",nota="note",
        renew="renouveler",renovar="renouveler",pay="regler",pagar="regler"}
    local confirmations={sent=true,envoye=true,enviado=true,unsent=false,nonenvoye=false,noenviado=false}
    local states={open=ML("En cours"),claimed=ML("En attente de synchronisation"),
        fulfilled=ML("Prime faite · règlement en attente"),sent=ML("Courrier en transit"),paid=ML("Payée"),
        withdrawn=ML("Retirée"),expired=ML("Expirée"),superseded=ML("Prime remplacée")}
    SlashCmdList.GLBOUNTY=function(input)
        local action,id,arg=(input or ""):match("^%s*(%S*)%s*(%S*)%s*(.-)%s*$")
        action=verbs[action:lower()] or action:lower()
        local ok,reason
        if action=="" and GL.OpenBounties then GL.OpenBounties();return
        elseif action=="courrier" and confirmations[id:lower()]~=nil then
            ok=B.ReconcileMail(confirmations[id:lower()]); if ok and MailFrame and MailFrame:IsShown() then showPayment() end
            if not ok then GL.Print(ML("Aucun envoi incertain à vérifier.")) end
            return
        elseif action=="courrier" then ok,reason=B.PrepareMail(id~="" and id or nil,arg~="" and arg or nil)
        elseif action=="note" then ok,reason=B.Update(id,arg,false)
        elseif action=="renouveler" then ok,reason=B.Update(id,arg~="" and arg or nil,true)
        elseif action=="regler" then
            local h,n=arg:match("^(%S+)%s+(%d+)$")
            ok,reason=B.ConfirmPayment(id,h,tonumber(n))
        elseif action=="liste" then
            for key,o in pairs(B.List()) do GL.Print(o.name.." : "..key.." ("..states[o.state]..")") end
            return
        else GL.Print(ML("/glprime liste | courrier [contrat] [GUID] | note <contrat> <texte> | renouveler <contrat> [texte] | regler <contrat> <GUID> <cuivre>")); return end
        if not ok then
            local reasons={mailbox=ML("Ouvrez l’onglet d’envoi de courrier."),draft=ML("Un brouillon est déjà en cours."),
                pending=ML("Un envoi est en cours."),funds=ML("Fonds insuffisants."),no_payable_recipient=ML("Aucun bénéficiaire payable identifié dans la guilde."),
                guild=ML("Guilde indisponible."),invalid=ML("Contrat ou note non valide."),limit=ML("Durée maximale atteinte.")}
            GL.Print(reasons[reason] or ML("Action impossible."))
        elseif action=="courrier" then GL.Print(ML("Brouillon prêt. Vérifiez le destinataire et le montant avant l’envoi."))
        else GL.Print(ML("Contrat mis à jour.")) end
    end
end
local function join()
    local s,me=scope()
    if s and (not lastPrune or GL.Now()-lastPrune>=3600) then
        local everything=view(s,true)
        remember(everything,me)
        archive(s,everything)
        for k,raw in pairs(s.events) do
            local e=unpackEvent(raw)
            -- Keep the recipient's own receipts available to payers who return after rotation.
            if not e or (e.kind=="V" and e.time<GL.Now()-38*DAY and not GL.db.bountyHistory[e.actor]) then s.events[k]=nil end
        end
        lastPrune=GL.Now()
    end
    if s and not next(roster) then joined,openTargets=nil,nil; return end
    if s~=joined then
        budgets={}
        joined,openTargets=s,nil
        if s then
            finalize(s,me)
            schedule(s,"Q")
            if GL.GuildMap then GL.GuildMap.Announce(s) end
            if GL.GuildProfiles then GL.GuildProfiles.CatchUp(s,me,true) end
            for _,raw in pairs(s.events) do
                local e=unpackEvent(raw)
                if e and e.actor==UnitGUID("player") then schedule(s,raw) end
            end
        end
    end
end
for _,event in ipairs({"MAIL_SHOW","MAIL_INBOX_UPDATE","MAIL_SEND_SUCCESS","MAIL_FAILED","MAIL_CLOSED"}) do frame:RegisterEvent(event) end
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
GL.Transport.OnReceive(function(msg,sender)
    if not GetGuildRosterInfo or not GetNumGuildMembers then return end
    sender=GL.Clean(sender,"string")
    if sender and roster[sender] then receive(GL.Clean(msg,"string"),roster[sender]) end
end)
frame:SetScript("OnEvent",function(_,event)
    if event=="MAIL_INBOX_UPDATE" then scanInbox(); return end
    if event=="MAIL_SHOW" then
        scanInbox()
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
        if sent and s==sent.guild and acknowledgeMail(s,me,sent) then
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
    if not GL.Transport.Available() then return end
    if event=="PLAYER_LOGIN" then
        joined=nil
    end
    refreshRoster()
    join()
    if GL.GuildMap then GL.GuildMap.Join() end
    if GL.db then reconcileInbox(scope(),GL.Safe(UnitGUID,"player")) end
end)
GL.On("BOUNTY_KILL",B.Kill)
GL.On("BOUNTY_DEATH",B.Death)
