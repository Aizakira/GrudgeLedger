-- Public character data plus separately opted-in, author-attributed social snapshots.
-- Notes, free-text reasons and combat logs never enter the wire payload.
local GL, B = GrudgeLedger, GrudgeLedger.Bounties
local S = {}
GL.SharedDossiers = S
local slots = {"head","neck","shoulder","shirt","chest","waist","leg","foot","wrist","hand","leftfinger","rightfinger","lefttrinket","righttrinket","back","weapon","offhand","ranged","tabard"}
local aliases={finger1="leftfinger",finger2="rightfinger",trinket1="lefttrinket",trinket2="righttrinket",mainhand="weapon",legs="leg",feet="foot",hands="hand",shoulders="shoulder",wrists="wrist",shield="offhand"}
local value = {value="n",name="s",display_string="s"}
local item = {id="n",ref="s",name="s",icon="n",level=value,quality={type="s",name="s"}}
local schema = {
    identity={name="s",race="s",raceID="n",sex="n",class="s",classFile="s",faction="s",guild="s"},
    gear={}, stats={_map="v"}, level="n",averageItemLevel="n",honorableKills="n",pvpRank="v",
    trees={_list={id="v",name="s",points="n",talents={_list={[1]="n",[2]="s",[3]="n",[4]="n",[5]="s"}}}},
    reputations={_list={name="s",standing="v",value="n",max="n",group="s"}},
    battlegrounds={_list={name="s",games="n",wins="n",losses="n"}},
    achievements={_list={id="n",name="s",accountWide="flag",icon="n"}},
}
for _,slot in ipairs(slots) do schema.gear[slot]=item end
local function resolvedGear(data)
    local gear={}
    for slot,v in pairs(data or {}) do
        local key=type(slot)=="string" and slot:lower():gsub("[^%a%d]","")
        if key then gear[aliases[key] or key]=type(v)=="table" and v or (GrudgeLedgerArmory and GrudgeLedgerArmory.items and GrudgeLedgerArmory.items[v]) end
    end
    return gear
end
local function clean(v, rule, depth)
    depth=depth or 0
    if rule=="flag" then
        if v==true or v==1 then return 1 end
    elseif rule=="n" then
        if type(v)=="number" and v==v and v>=0 and v<=1e15 then return v end
    elseif rule=="s" then
        if type(v)=="string" and #v<=1024 and not v:find("[|%c]") then return v end
    elseif rule=="v" then
        return clean(v,"n") or clean(v,"s") or clean(v,value,depth+1) or clean(v,{[1]="n",[2]="n"},depth+1)
    elseif type(rule)=="table" and type(v)=="table" and depth<8 then
        local out,n={},0
        for k,x in pairs(v) do
            local r=rule[k]
            if rule._list and type(k)=="number" and k>=1 and k<=256 and k==math.floor(k) then r=rule._list end
            if rule._map and type(k)=="string" and #k<=40 and k:match("^[A-Z_]+$") then r=rule._map end
            if r then
                local c=clean(x,r,depth+1)
                if c~=nil then out[k]=c; n=n+1 end
            end
        end
        if n>0 then return out end
    end
end
local function stamp(at)
    at=tonumber(at)
    if at and at>=1e11 then at=at/1000 end
    if at and at>0 and at<=GL.Now()+60 then return math.floor(at) end
end
local function allowed(target)
    if type(target)~="string" or #target>32 or not target:match("^Player%-%w+%-%w+$") then return end
    local s=B.GuildScope()
    if not s or (s.journal and s.journal.hidden[target]) then return end
    local card=GL.GuildProfiles.ForTarget(target)
    local order=B.OpenFor(target)
    if card or (order and order.state=="open") then return s,(card and card.name or order.name) end
end
local relations={friend=true,warning=true,enemy=true,neutral=true}
local socialKinds={kill=true,death=true,aggression=true,reputation=true,reaction=true,grouped=true,group=true,trade=true}
local function signed(v)
    if type(v)=="number" and v==math.floor(v) and v>=-100 and v<=100 then return v end
end
local function socialEvent(e)
    if type(e)~="table" or not socialKinds[e.kind] or not stamp(e.time) then return end
    local zone=clean(e.zone,"s")
    local out={kind=e.kind,time=stamp(e.time),zone=zone and #zone<=128 and zone or nil,delta=signed(e.delta)}
    if relations[e.reaction] then out.reaction=e.reaction end
    if e.killingBlow==true or e.killingBlow==1 then out.killingBlow=1 end
    return out
end
function S.SharingSocial()
    local s,me=B.GuildScope()
    return s and s.shareSocial and s.shareSocial[me]==true or false
end
local function ownSocial(target)
    local r=GL.Get("guid:"..target)
    if not S.SharingSocial() then
        local s,me=B.GuildScope()
        if s and s.shareSocial and s.shareSocial[me]==false then return {removed=1,at=GL.Now()} end
        return
    end
    if not r then return end
    local me=GL.Author()
    local events={}
    -- ponytail: share the latest 32 structured facts, not entire private journals.
    -- A paged history protocol is the upgrade path if guild use needs older facts.
    for i=#r.history,1,-1 do
        local e=r.history[i]
        if e.actorGUID==me and not e.voided and e.voidReason~="battleground" then
            local item=socialEvent(e)
            if item then events[#events+1]=item; if #events==32 then break end end
        end
    end
    return {at=GL.Now(),score=signed(r.reputation) or 0,relation=GL.Relation(r),events=events}
end
local function receiveSocial(s,sender,target,seq,data)
    if type(data)~="table" or not stamp(data.at) or not seq then return false end
    local report={actor=sender,target=target,seq=seq,at=stamp(data.at),received=GL.Now(),authorName=B.MemberName(sender)}
    if data.removed==1 then report.removed=true
    else
        if not signed(data.score) or not relations[data.relation] or type(data.events)~="table" then return false end
        report.score,report.relation,report.events=data.score,data.relation,{}
        local n=0
        for i,e in pairs(data.events) do
            if type(i)~="number" or i<1 or i>32 or i~=math.floor(i) then return false end
            local item=socialEvent(e)
            if not item or item.time>report.at then return false end
            report.events[i]=item; n=n+1
        end
        if n~=#report.events then return false end
    end
    s.socialReports=s.socialReports or {}
    local key=sender..":"..target
    local old=s.socialReports[key]
    if old and seq<=old.seq then return false end
    if not old then
        -- ponytail: cap all authors/targets together at 256 reports per guild.
        local n,oldest=0,nil
        for k,v in pairs(s.socialReports) do n=n+1; if not oldest or v.received<s.socialReports[oldest].received then oldest=k end end
        if n>=256 then s.socialReports[oldest]=nil end
    end
    s.socialReports[key]=report
    return true
end
function S.SocialReports(target)
    local s=allowed(target)
    local out={}
    for _,r in pairs(s and s.socialReports or {}) do
        if r.target==target and not r.removed then out[#out+1]=r end
    end
    table.sort(out,function(a,b)return a.actor<b.actor end)
    return out
end
local function merge(fields,key,data,at,source)
    data=clean(data,schema[key]); at=stamp(at)
    if not data or not at then return end
    if key=="trees" then
        for _,tree in ipairs(data) do
            if not tree.points then return end
            for _,talent in ipairs(tree.talents or {}) do if not talent[1] or not talent[3] then return end end
        end
    end
    local old=fields[key]
    if not old or at>old.at then
        -- A partial equipment/identity/stats observation fills gaps without erasing known slots.
        if old and (key=="gear" or key=="identity" or key=="stats") then
            for k,v in pairs(old.data) do if data[k]==nil then data[k]=v end end
        end
        fields[key]={data=data,at=at,source=source}
    elseif key=="gear" or key=="identity" or key=="stats" then
        for k,v in pairs(data) do if old.data[k]==nil then old.data[k]=v end end
    end
end
local function localFields(target,name)
    local record=GL.Get("guid:"..target) or {guid=target,fullName=name}
    local p=GL.ArmoryProfile(record,false,true) or {}
    local fields={}
    for key in pairs(schema) do
        local data=p[key]
        if key=="gear" and type(data)=="table" then
            data=resolvedGear(data)
        end
        merge(fields,key,data,p[key.."At"] or p.updated,"armory")
    end
    local inspected=GL.DossierInspection and GL.DossierInspection(record) or record.inspection
    if inspected then
        local gear={}
        for slot,link in pairs(inspected.gear or {}) do
            local ref=type(link)=="string" and link:match("|H(item:[%d:%-]+)|h")
            if slots[slot] and ref then
                gear[slots[slot]]={id=tonumber(ref:match("item:(%d+)")),ref=ref,name=link:match("|h%[(.-)%]|h"),
                    icon=GL.Safe(C_Item and C_Item.GetItemIconByID or GetItemIcon,ref)}
            end
        end
        merge(fields,"gear",gear,inspected.gearAt,"inspection")
        merge(fields,"trees",inspected.trees,inspected.talentsAt,"inspection")
        merge(fields,"stats",inspected.stats,inspected.statsAt,"inspection")
    end
    local identity={name=name,race=record.raceName,raceID=record.raceID,sex=record.sex,
        classFile=record.class,faction=record.faction,guild=record.guild}
    merge(fields,"identity",identity,record.lastSeen,"inspection")
    merge(fields,"level",record.level,record.lastSeen,"inspection")
    return fields
end
local function cache(s,target)
    s.dossiers=s.dossiers or {}
    if not s.dossiers[target] then
        -- ponytail: 256 public dossiers per guild; evict least recently received.
        -- Add a user storage policy only if real guild usage exceeds this ceiling.
        local n,oldest=0,nil
        for k,v in pairs(s.dossiers) do n=n+1; if not oldest or v.received<s.dossiers[oldest].received then oldest=k end end
        if n>=256 then s.dossiers[oldest]=nil end
        s.dossiers[target]={fields={},received=GL.Now()}
    end
    return s.dossiers[target]
end
function S.Merge(record,original)
    local s=allowed(record.guid)
    local saved=s and s.dossiers and s.dossiers[record.guid]
    if not saved then return original end
    local result={}
    for k,v in pairs(original or {}) do result[k]=v end
    local at=stamp(original and original.updated) or 0
    local used=false
    for key,entry in pairs(saved.fields) do
        local own=stamp(original and original[key.."At"]) or at
        local fill=key=="gear" or key=="stats" or key=="identity"
        if fill then
            local first,second=result[key],entry.data
            if key=="gear" then first=resolvedGear(first) end
            for k in pairs(second) do if not first or first[k]==nil then used=true end end
            if entry.at>own then first,second=second,first end
            local combined={}
            for k,v in pairs(second or {}) do combined[k]=v end
            for k,v in pairs(first or {}) do combined[k]=v end
            result[key]=combined
        end
        if result[key]==nil or (type(result[key])=="table" and not next(result[key])) or entry.at>own then
            if not fill then result[key]=entry.data end
            result[key.."At"]=entry.at; used=true
        elseif fill and not original then
            result[key.."At"]=entry.at; used=true
        end
    end
    if used then result.sharedSource=saved.sender; result.sharedName=saved.senderName; result.sharedAt=saved.received end
    return result
end

-- Length-prefixed data, never Lua source. Percent escaping keeps addon messages
-- free of markup/control bytes. Decoder work, nesting and payload size are bounded.
local function encode(v)
    local t=type(v)
    if t=="string" or t=="number" then local s=tostring(v); return (t=="string" and "s" or "n")..#s..":"..s end
    local keys={}; for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
    local out={"t"..#keys..":"}
    for _,k in ipairs(keys) do out[#out+1]=encode(k); out[#out+1]=encode(v[k]) end
    return table.concat(out)
end
local function decode(text)
    local pos,nodes=1,0
    local function read(depth)
        nodes=nodes+1; assert(nodes<=8192 and depth<=10)
        local first,last,kind,count=text:find("([snt])(%d+):",pos)
        local after=last and last+1
        assert(first==pos)
        assert(after and after-pos<=8 and text:sub(pos,pos)==kind)
        count=tonumber(count); pos=after
        if kind=="t" then
            assert(count<=1024); local out={}
            for _=1,count do
                local k=read(depth+1); assert(type(k)=="string" or type(k)=="number")
                assert(out[k]==nil); out[k]=read(depth+1)
            end
            return out
        end
        assert(count<=2048 and pos+count-1<=#text)
        local s=text:sub(pos,pos+count-1); pos=pos+count
        if kind=="n" then local n=tonumber(s); assert(n and n==n and math.abs(n)<=1e15); return n end
        return s
    end
    local data=read(0); assert(pos==#text+1); return data
end
local function escape(text) return (text:gsub("[^%w .,:_%-]",function(c)return ("%%%02X"):format(c:byte()) end)) end
-- Protocol S2 (0.13.0). The 0.12.0 protocol S1 is ignored on purpose: members on
-- different versions do not exchange dossiers (owner decision, 19 November 2026).
local Transport = GL.Transport
local PROTOCOL = "S2"
local FRAGMENT = 180
-- Freshness travels with each request, in this order, one Unix time per field (0 when unknown).
local stampKeys = {"identity","gear","trees","stats","level","averageItemLevel","honorableKills","pvpRank",
    "reputations","battlegrounds","achievements"}
-- A request costs one message and is answered only with fresher data, so it may repeat every five minutes.
local REQUEST_INTERVAL = 300
-- One public answer per target per minute bounds what repeated requests can make us broadcast.
local ANSWER_INTERVAL = 60
-- Answers wait 0 to 7 seconds, different for each member, so the first one to start silences the others.
local ANSWER_SPREAD = 8
-- An unchanged testimony is broadcast again at most every 30 minutes; changes are pushed within 30 seconds.
local SOCIAL_REPEAT = 1800
-- Eight senders may be mid-transfer at once; a transfer silent for two minutes is abandoned.
local INCOMING = {slots=8, idle=120}
local requested, answered, socialSent, dirty = {}, {}, {}, {}
local incoming = Transport.Reassembler(INCOMING)
local lastPush = 0
local active
local function reset(s)
    if active == s then
        return
    end
    active = s
    requested = {}
    answered = {}
    socialSent = {}
    dirty = {}
    incoming = Transport.Reassembler(INCOMING)
    lastPush = 0
end
local function knownFields(s,target,name)
    local fields = localFields(target,name)
    local saved = s.dossiers and s.dossiers[target]
    for k,e in pairs(saved and saved.fields or {}) do
        merge(fields,k,e.data,e.at,e.source)
    end
    return fields
end
local function stampList(fields)
    local out = {}
    for i,key in ipairs(stampKeys) do
        out[i] = fields[key] and fields[key].at or 0
    end
    return table.concat(out,",")
end
local function parseStamps(text)
    local out = {}
    for value in (text..","):gmatch("(%d*),") do
        if #value < 1 or #value > 10 then
            return nil
        end
        out[#out+1] = tonumber(value)
    end
    if #out ~= #stampKeys then
        return nil
    end
    return out
end
local function answerDelay(target)
    local seed = (GL.Safe(UnitGUID,"player") or "")..target
    local sum = 0
    for i = 1, #seed do
        sum = (sum * 31 + seed:byte(i)) % 65521
    end
    return sum % ANSWER_SPREAD
end
local function socialSignature(report)
    local copy = {}
    for k,v in pairs(report) do
        if k ~= "at" then
            copy[k] = v
        end
    end
    return encode(copy)
end
local function noteSocial(target,report)
    if report then
        socialSent[target] = {signature=socialSignature(report), at=GL.Now()}
    end
end
local function socialDue(target,report)
    local last = socialSent[target]
    if not report then
        return false
    end
    return not last or last.signature ~= socialSignature(report) or GL.Now() - last.at >= SOCIAL_REPEAT
end
-- nature "r": an answer carrying public data, which silences other members' identical answers.
-- nature "t": the sender's own testimony alone.
local function send(s,target,fields,nature,delay)
    local selected,body = {},nil
    for _,key in ipairs({"social",unpack(stampKeys)}) do
        if fields[key] then
            selected[key] = fields[key]
            local candidate = escape(encode(selected))
            if #candidate <= 46080 then
                body = candidate
            else
                selected[key] = nil
            end
        end
    end
    if not body then
        return false
    end
    s.dossierSeq = math.max((s.dossierSeq or 0) + 1, GL.Now() * 1000)
    local parts = Transport.Split(body,FRAGMENT)
    local messages = {}
    for part,chunk in ipairs(parts) do
        messages[part] = table.concat({"J",PROTOCOL,"P",target,s.dossierSeq,nature,part,#parts,chunk},";")
    end
    return Transport.SendBatch(s,messages,{key=PROTOCOL..nature..target,delay=delay})
end
function S.ShareSocial(enabled)
    local s,me=B.GuildScope()
    if not s or not me then return end
    reset(s)
    s.shareSocial=s.shareSocial or {}; s.shareSocial[me]=enabled==true
    for _,card in ipairs(GL.GuildProfiles.List()) do dirty[card.target]=true end
    for _,order in pairs(B.List()) do if order.state=="open" then dirty[order.target]=true end end
    S.Refresh()
    GL.Emit("DOSSIER_UPDATED")
end
function S.Request(target)
    local s,name=allowed(target)
    if not s then return end
    reset(s)
    GL.RequestArmory("guid:"..target,name,target)
    if GL.InspectDossierUnit then GL.InspectDossierUnit(GL.VisiblePortraitUnit({guid=target}),target) end
    local last = requested[target]
    if last and GL.Now() - last < REQUEST_INTERVAL then
        return
    end
    local message = table.concat({"J",PROTOCOL,"Q",target,stampList(knownFields(s,target,name))},";")
    if Transport.SendBatch(s,{message}) then
        requested[target] = GL.Now()
    end
end
function S.Observe(identity)
    local s,name=allowed(identity.guid)
    if not s then return end
    local saved=cache(s,identity.guid)
    merge(saved.fields,"identity",{name=name,race=identity.raceName,raceID=identity.raceID,sex=identity.sex,
        classFile=identity.class,faction=identity.faction,guild=identity.guild},GL.Now(),"inspection")
    merge(saved.fields,"level",identity.level,GL.Now(),"inspection")
    saved.received,saved.sender=GL.Now(),GL.Safe(UnitGUID,"player")
    S.Request(identity.guid)
end
local function answer(s,target,theirs)
    local current,name = allowed(target)
    if current ~= s then
        return
    end
    -- An answer still waiting to leave already serves this requester.
    if Transport.State(s,PROTOCOL.."r"..target) == "queued" then
        return
    end
    local fields = knownFields(s,target,name)
    local fresh = {}
    for i,key in ipairs(stampKeys) do
        if fields[key] and fields[key].at > theirs[i] then
            fresh[key] = fields[key]
        end
    end
    -- Only our own social snapshot travels; public observations may be relayed.
    local social = ownSocial(target)
    if next(fresh) then
        local last = answered[target]
        if last and GL.Now() - last < ANSWER_INTERVAL then
            return
        end
        fresh.social = social
        if send(s,target,fresh,"r",answerDelay(target)) then
            answered[target] = GL.Now()
            noteSocial(target,social)
        end
    elseif socialDue(target,social) then
        if send(s,target,{social=social},"t",answerDelay(target)) then
            noteSocial(target,social)
        end
    end
end
local function receiveTransfer(s,sender,target,id,text)
    local ok,data=pcall(decode,(text:gsub("%%(%x%x)",function(h)return string.char(tonumber(h,16)) end)))
    if not ok or type(data)~="table" then return end
    local result={}
    for k,e in pairs(data) do
        if schema[k] and type(e)=="table" and (e.source=="armory" or e.source=="inspection") then merge(result,k,e.data,e.at,e.source) end
    end
    local _,expectedName=allowed(target)
    local publicName=result.identity and result.identity.data.name
    if publicName and publicName:lower()~=expectedName:lower() then return end
    local changed=receiveSocial(s,sender,target,tonumber(id),data.social)
    if next(result) then
        local saved=cache(s,target)
        for k,e in pairs(result) do merge(saved.fields,k,e.data,e.at,e.source) end
        saved.received,saved.sender=GL.Now(),sender
        saved.senderName=B.MemberName(sender); changed=true
    end
    if changed then GL.Emit("DOSSIER_UPDATED",target) end
end
function S.Receive(s,sender,raw)
    reset(s)
    local target,stamps = raw:match("^S2;Q;(Player%-%w+%-%w+);([%d,]+)$")
    if target then
        local theirs = parseStamps(stamps)
        if theirs then
            answer(s,target,theirs)
        end
        return
    end
    local id,nature,part,total,body
    target,id,nature,part,total,body = raw:match("^S2;P;(Player%-%w+%-%w+);(%d+);([rt]);(%d+);(%d+);(.*)$")
    part = tonumber(part)
    total = tonumber(total)
    if not target or #id > 16 or not part or not total or total < 1 or total > 256 or part < 1 or part > total
        or #body > FRAGMENT or allowed(target) ~= s or body:find("[^%w%% .,:_%-]") then
        return
    end
    -- Another member already answers with public data: our identical answer would only repeat it.
    if part == 1 and nature == "r" and Transport.Cancel(s,PROTOCOL.."r"..target) then
        answered[target] = nil
        socialSent[target] = nil
    end
    local text = incoming.Add(sender,id,part,total,body)
    if text then
        receiveTransfer(s,sender,target,id,text)
    end
end
function S.Refresh()
    local s=B.GuildScope()
    reset(s)
    if not s then return end
    -- ponytail: push one changed testimony every 30 seconds at most.
    if GL.Now()-lastPush>=30 then
        for target in pairs(dirty) do
            if allowed(target)~=s then dirty[target]=nil
            else
                local report=ownSocial(target)
                if not report then
                    dirty[target]=nil
                elseif send(s,target,{social=report},"t") then
                    dirty[target]=nil
                    lastPush=GL.Now()
                    noteSocial(target,report)
                end
                break
            end
        end
    end
    for _,card in ipairs(GL.GuildProfiles.List()) do S.Request(card.target) end
    for _,order in pairs(B.List()) do if order.state=="open" then S.Request(order.target) end end
end
GL.On("CHANGED",function(record)
    local s=B.GuildScope(); reset(s)
    if s and record and record.guid and S.SharingSocial() and allowed(record.guid)==s then dirty[record.guid]=true end
end)
GL.On("GUILD_PROFILES",S.Refresh)
GL.On("BOUNTIES_CHANGED",S.Refresh)
local frame=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_GUILD_UPDATE","GUILD_ROSTER_UPDATE","PLAYER_ENTERING_WORLD"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function() S.Refresh() end)
frame:SetScript("OnUpdate",function(self,delta)
    self.elapsed=(self.elapsed or 0)+delta
    if self.elapsed<30 then return end
    self.elapsed=0; S.Refresh()
end)
