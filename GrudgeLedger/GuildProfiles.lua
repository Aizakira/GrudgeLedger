-- Shared editions and opinions are deliberately independent of personal contacts.
local GL, B = GrudgeLedger, GrudgeLedger.Bounties
local G = { choices = {} }
GL.GuildProfiles = G
local known = {}
for _,choice in ipairs(GL.TagChoices) do
    G.choices[#G.choices+1]=choice
    known[choice[1]]=true
end
G.choices[#G.choices+1]={"unreliable","Peu fiable"}
known.unreliable=true

local function guid(s) return type(s)=="string" and #s<=32 and s:match("^Player%-%w+%-%w+$") end
local function hex(s,n) return type(s)=="string" and #s==n and s:match("^[0-9a-f]+$") end
-- One vote per account, but an identifier of its own in each guild: the same account in two
-- guilds can no longer be linked through its cards (audit 0.12.0, step D).
-- The guild key (realm/name) as 16 hex digits, the form the digest accepts.
local function guildHex(key)
    local a,b=7,131
    for i=1,#key do
        a=(a*31+key:byte(i))%4294967291
        b=(b*37+key:byte(i))%4294967279
    end
    return ("%08x%08x"):format(a,b)
end
local function guildAccount(s,account)
    if not hex(account,16) or type(s.guildKey)~="string" or not GL.RevocationDigest then return end
    local digest=GL.RevocationDigest(account..guildHex(s.guildKey))
    return digest and digest:sub(1,16)
end
-- This account's identifier in the current guild.
function G.Account()
    local s=B.GuildScope()
    local _,_,account=GL.Author()
    return s and guildAccount(s,account)
end
local function title(s) return type(s)=="string" and #s>0 and #s<=64 and not s:find("[;|%c]") end
local function positive(s,max)
    local n=tonumber(s)
    return n and n>=1 and n<=max and n==math.floor(n) and n
end
local function state(s)
    s.journal = s.journal or {cards={}, hidden={}, withdrawn={}, secrets={}, seq=0}
    return s.journal
end
local function flags(s)
    local j=state(s)
    if not j.byTarget then
        j.byTarget={}
        for key,c in pairs(j.cards) do
            if c.name then
                j.byTarget[c.target]=j.byTarget[c.target] or {}
                j.byTarget[c.target][key]=true
            end
        end
    end
    return j
end
local function newest(a,b) return a.time>b.time or a.time==b.time and a.key>b.key end
local function cardKey(owner,target,digest) return owner..":"..target..":"..digest end
local function changed() GL.Emit("GUILD_PROFILES") end
local function current(card)
    local s,me=B.GuildScope()
    if s and card and state(s).cards[card.key]==card and card.name then return s,me end
end
-- A catch-up gathers its messages in "gathered" and sends them as one batch after the urgent
-- messages (0.60.1): hundreds of cards and opinions no longer delay a claim or a payment.
local gathered
local function emit(s,text)
    if gathered then
        gathered[#gathered+1]="J;"..text
    else
        B.SendJournal(s,text)
    end
end
local function sendCreate(s,c)
    emit(s,table.concat({"C",c.target,c.digest,c.time,c.account,c.name},";"))
end
local function sendTag(s,c,e)
    emit(s,table.concat({"T",c.owner,c.target,c.digest,e.seq,e.time,e.account,e.tag,e.on and "1" or "0"},";"))
end
local function sendDelete(s,owner,target,secret)
    emit(s,table.concat({"D",owner,target,secret},";"))
end
local function find(s,target)
    local j=flags(s)
    local first
    for key in pairs(j.byTarget[target] or {}) do
        local c=j.cards[key]
        if not first or newest(first,c) then first=c end
    end
    return first
end
function G.ForTarget(target)
    local s=B.GuildScope()
    if s and target and not state(s).hidden[target] then return find(s,target) end
end
function G.List(hidden)
    local s=B.GuildScope()
    local out={}
    if s then
        local j=state(s)
        for _,c in pairs(j.cards) do
            if c.name and (j.hidden[c.target]==true)==(hidden==true) then out[#out+1]=c end
        end
    end
    table.sort(out,function(a,b) return a.name<b.name or a.name==b.name and a.key<b.key end)
    return out
end
function G.SetAuto(enabled)
    local s=B.GuildScope()
    if s then state(s).auto=enabled==true; changed() end
end
function G.Auto()
    local s=B.GuildScope()
    return s and s.journal and s.journal.auto==true
end
-- ponytail: buffer at most 512 opinions that arrived before their publication.
-- Receiving the real card requests a replay if the buffer filled.
local early=setmetatable({},{__mode="k"})
local function pending(s)
    if not early[s] then early[s]={n=0,cards={}} end
    return early[s]
end
local function takePending(s,key)
    local p=early[s]
    local c=p and p.cards[key]
    if c then
        for _ in pairs(c.opinions) do p.n=p.n-1 end
        p.cards[key]=nil
    end
    return c
end
function G.HideTarget(target,restore)
    local s=B.GuildScope()
    if not s or not guid(target) then return end
    local j=state(s)
    j.hidden[target]=not restore or nil
    if not restore and early[s] then
        for key,c in pairs(early[s].cards) do
            if c.target==target then takePending(s,key) end
        end
    end
    for _,c in pairs(j.cards) do
        if c.target==target then
            if restore then
                B.SendJournal(s,"V;"..c.key)
            else
                for key,e in pairs(c.opinions) do
                    if not e.localEdit then c.opinions[key]=nil end
                end
            end
        end
    end
    changed()
    return true
end

-- Bounds against a member who would fill every book of the guild (audit 24/11): far above what an
-- honest member ever reaches, and counted per member so that nobody pushes the others' cards out.
local CARDS_PER_MEMBER,CARDS_KEPT,OPINIONS_PER_ACTOR=300,3000,40
local function owned(map,owner)
    local mine,all=0,0
    for key in pairs(map) do
        all=all+1
        if key:sub(1,#owner+1)==owner..":" then mine=mine+1 end
    end
    return mine,all
end
local function publish(s,owner,target,digest,at,account,name,authorName)
    local j=flags(s)
    local key=cardKey(owner,target,digest)
    if j.withdrawn[key] then return end
    if j.cards[key] then return end
    local mine,all=owned(j.cards,owner)
    if mine>=CARDS_PER_MEMBER or all>=CARDS_KEPT then return end
    local c=takePending(s,key) or {key=key,owner=owner,target=target,digest=digest,opinions={}}
    c.name,c.time,c.account,c.authorName=name,at,account,authorName
    j.cards[key]=c
    j.byTarget[target]=j.byTarget[target] or {}
    j.byTarget[target][key]=true
    if not j.hidden[target] then GL.RequestArmory("guid:"..target,name,target) end
    return c
end
function G.Publish(record)
    local s,me=B.GuildScope()
    if not s or not record or not guid(record.guid) or not title(record.fullName) then return end
    local actor,author,account=GL.Author()
    account=guildAccount(s,account)
    if actor~=me or not hex(account,16) then return end
    local j=state(s)
    local existing=find(s,record.guid)
    if existing then return existing end
    local parts={}
    for i=1,8 do parts[i]=("%04x"):format(math.random(0,65535)) end
    GL.db.journalEdition=(GL.db.journalEdition or 0)+1
    local token=GL.RevocationDigest(table.concat(parts)..("%08x"):format(GL.db.journalEdition)):sub(1,32)
    local digest=GL.RevocationDigest(token):sub(1,32)
    local c=publish(s,me,record.guid,digest,GL.Now(),account,record.fullName,author)
    if c then
        j.hidden[c.target]=nil
        j.secrets[c.key]=token
        sendCreate(s,c)
        changed()
    end
    return c
end
function G.Observe(record)
    local s,me=B.GuildScope()
    if not s or not s.journal or not s.journal.auto or record.creatorGUID~=me then return end
    local j=s.journal
    if not j.hidden[record.guid] and not (j.retired and j.retired[record.guid]) and not find(s,record.guid) then
        return G.Publish(record)
    end
end
function G.Owns(card)
    local s=current(card)
    return s and state(s).secrets[card.key]~=nil
end
local function withdraw(s,owner,target,key,token)
    local j=flags(s)
    if j.withdrawn[key] then return end
    -- A withdrawal of a card this book holds always passes; random tokens for unknown cards are bounded.
    if not j.cards[key] then
        local mine,all=owned(j.withdrawn,owner)
        if mine>=CARDS_PER_MEMBER or all>=CARDS_KEPT then return end
    end
    j.withdrawn[key]=token
    takePending(s,key)
    if j.cards[key] and j.cards[key].name then
        j.retired=j.retired or {}
        j.retired[target]=true
    end
    j.secrets[key],j.cards[key]=nil,nil
    if j.byTarget[target] then
        j.byTarget[target][key]=nil
        if not next(j.byTarget[target]) then j.byTarget[target]=nil end
    end
    changed()
    return true
end
function G.Withdraw(card)
    local s=current(card)
    if not s then return end
    local token=state(s).secrets[card.key]
    if not token then return end
    if withdraw(s,card.owner,card.target,card.key,token) then
        sendDelete(s,card.owner,card.target,token)
        return true
    end
end
local function put(c,actor,name,seq,at,account,tag,on)
    local key=actor..":"..seq
    if c.opinions[key] then return end
    -- A person's votes on one card: the latest forty are kept (audit 24/11).
    local theirs={}
    for k,e in pairs(c.opinions) do if e.actor==actor then theirs[#theirs+1]={k=k,seq=e.seq} end end
    if #theirs>=OPINIONS_PER_ACTOR then
        table.sort(theirs,function(a,b) return a.seq<b.seq end)
        if seq<theirs[1].seq then return end
        c.opinions[theirs[1].k]=nil
    end
    c.opinions[key]={actor=actor,authorName=name,seq=seq,time=at,account=account,tag=tag,on=on}
    return true
end
function G.View(c)
    local history,latest,counts={},{},{}
    for _,e in pairs(c and c.opinions or {}) do
        history[#history+1]=e
        local key=e.actor..":"..e.tag
        if not latest[key] or latest[key].seq<e.seq then latest[key]=e end
    end
    table.sort(history,function(a,b)
        if a.time~=b.time then return a.time>b.time end
        if a.actor~=b.actor then return a.actor<b.actor end
        return a.seq>b.seq
    end)
    -- One vote per account: the latest of its characters decides (owner, 24/11). A tag removed
    -- from a second character used to stay counted because the first one still said yes.
    local byAccount={}
    for _,e in pairs(latest) do
        local vote=e.account..":"..e.tag
        local kept=byAccount[vote]
        if not kept or e.time>kept.time or e.time==kept.time and e.seq>kept.seq then byAccount[vote]=e end
    end
    for _,e in pairs(byAccount) do
        if e.on then counts[e.tag]=(counts[e.tag] or 0)+1 end
    end
    return history,counts,latest,byAccount
end
function G.SetTag(c,tag,on)
    local s,me=current(c)
    if not s or state(s).hidden[c.target] or not known[tag] or type(on)~="boolean" then return end
    local actor,name,account=GL.Author()
    account=guildAccount(s,account)
    if actor~=me or not hex(account,16) then return end
    local _,_,latest,byAccount=G.View(c)
    -- What this account last said, whichever of its characters said it.
    local old=byAccount[account..":"..tag] or latest[me..":"..tag]
    if (old and old.on or false)==on then return end
    local j=state(s)
    j.seq=math.max(j.seq,old and old.seq or 0)+1
    put(c,me,name,j.seq,GL.Now(),account,tag,on)
    local event=c.opinions[me..":"..j.seq]
    event.localEdit=true
    sendTag(s,c,event)
    changed()
    return true
end
function G.PersonalTag(record,tag,on)
    if G.Auto() then
        local s=B.GuildScope()
        local j=state(s)
        if not record.guid or j.hidden[record.guid] then return end
        local c=G.ForTarget(record.guid)
        if not c and on and not (j.retired and j.retired[record.guid]) then c=G.Publish(record) end
        if c then G.SetTag(c,tag,on) end
    end
end

-- Accept new attributions only from the character identified by WoW's guild roster.
-- A withdrawal alone can be relayed: its preimage was private to the account that published.
function G.Receive(s,me,sender,raw)
    local f={}
    for v in (raw..";"):gmatch("(.-);") do f[#f+1]=v end
    local j=state(s)
    local kind=f[1]
    if kind=="V" and #f==2 then
        local owner,target,digest=f[2]:match("^([^:]+):([^:]+):([^:]+)$")
        if not (guid(owner) and guid(target) and hex(digest,32)) then return end
        local token=j.withdrawn[f[2]]
        if token then sendDelete(s,owner,target,token); return end
        local c=j.cards[f[2]]
        if c then
            if c.owner==me and c.name and j.secrets[c.key] then sendCreate(s,c) end
            for _,e in pairs(c.opinions) do if e.actor==me then sendTag(s,c,e) end end
        end
    elseif kind=="C" and #f==6 then
        local target,digest,at,account,name=unpack(f,2)
        at=positive(at,GL.Now()+60)
        if not(guid(target) and hex(digest,32) and at and hex(account,16) and title(name)) then return end
        local key=cardKey(sender,target,digest)

        if j.withdrawn[key] then
            j.retired=j.retired or {}
            j.retired[target]=true
            sendDelete(s,sender,target,j.withdrawn[key])
            return
        end
        if publish(s,sender,target,digest,at,account,name,B.MemberName(sender) or sender) then
            if not j.hidden[target] then B.SendJournal(s,"V;"..key) end
            changed()
        end
    elseif kind=="D" and #f==4 then
        local owner,target,token=unpack(f,2)
        if not(guid(owner) and guid(target) and hex(token,32)) then return end
        local key=cardKey(owner,target,GL.RevocationDigest(token):sub(1,32))
        -- This can precede C, even across a logout. A different token names a different edition.
        withdraw(s,owner,target,key,token)
    elseif kind=="T" and #f==9 then
        local owner,target,digest,seq,at,account,tag,flag=unpack(f,2)
        seq,at=positive(seq,9007199254740991),positive(at,GL.Now()+60)
        if not(guid(owner) and guid(target) and hex(digest,32) and seq and at and hex(account,16)
            and known[tag] and (flag=="1" or flag=="0")) then return end
        local key=cardKey(owner,target,digest)
        if j.withdrawn[key] or j.hidden[target] then return end
        local c=j.cards[key]
        if not c then
            local p=pending(s)
            if p.n>=512 then return end
            c=p.cards[key] or {key=key,owner=owner,target=target,digest=digest,opinions={}}
            p.cards[key]=c
            if put(c,sender,B.MemberName(sender) or sender,seq,at,account,tag,flag=="1") then p.n=p.n+1 end
        elseif put(c,sender,B.MemberName(sender) or sender,seq,at,account,tag,flag=="1") then changed() end
    end
end
function G.CatchUp(s,me,joining)
    local j=s.journal
    if not j then return end
    -- One batch waiting at most, and one leaving: a third request is covered by the one waiting.
    local T=GL.Transport
    local first,second=T.State(s,"journal:own"),T.State(s,"journal:own:2")
    local key=(first==nil and second~="queued" and "journal:own") or (second==nil and first~="queued" and "journal:own:2") or nil
    if not key then return end
    gathered={}
    for cardKey,token in pairs(j.withdrawn) do
        local owner,target=cardKey:match("^([^:]+):([^:]+):")
        if joining or owner==me then sendDelete(s,owner,target,token) end
    end
    for _,c in pairs(j.cards) do
        if not j.hidden[c.target] then GL.RequestArmory("guid:"..c.target,c.name,c.target) end
        if joining and (c.owner~=me or not j.secrets[c.key]) then emit(s,"V;"..c.key) end
        if c.owner==me and c.name and j.secrets[c.key] then sendCreate(s,c) end
        for _,e in pairs(c.opinions) do
            if e.actor==me then sendTag(s,c,e) end
        end
    end
    local batch=gathered
    gathered=nil
    local _,queued=T.Pending(s)
    while #batch>math.max(0,480-queued) do batch[#batch]=nil end
    if #batch>0 then T.SendBatch(s,batch,{key=key,delay=joining and 2 or 3+math.random(0,5)}) end
end
