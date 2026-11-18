-- Public character data only. Personal notes, opinions and combat history never
-- enter this payload; guild fight totals keep their existing attribution/opt-in.
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
local pending, requested, responded={}, {}, {}
local active
local function reset(s)
    if active~=s then active=s; pending,requested,responded={},{},{} end
end
function S.Request(target)
    local s,name=allowed(target)
    if not s then return end
    reset(s)
    GL.RequestArmory("guid:"..target,name,target)
    if GL.InspectDossierUnit then GL.InspectDossierUnit(GL.VisiblePortraitUnit({guid=target}),target) end
    if requested[target] and GL.Now()-requested[target]<300 then return end
    if B.SendDossier(s,{"S1;Q;"..target}) then requested[target]=GL.Now() end
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
function S.Receive(s,sender,raw)
    reset(s)
    local target=raw:match("^S1;Q;(Player%-%w+%-%w+)$")
    if target then
        local current,name=allowed(target)
        if current~=s then return end
        -- One response per target per five minutes, shared by simultaneous requesters.
        if responded[target] and GL.Now()-responded[target]<300 then return end
        local fields=localFields(target,name)
        local saved=s.dossiers and s.dossiers[target]
        for k,e in pairs(saved and saved.fields or {}) do merge(fields,k,e.data,e.at,e.source) end
        if not next(fields) then return end
        local selected,body={},nil
        -- ponytail: prioritize usable identity/gear over very large optional histories.
        -- Over-budget sections remain unknown; a paged section protocol can lift this cap.
        for _,key in ipairs({"identity","gear","trees","stats","level","averageItemLevel","honorableKills","pvpRank","reputations","battlegrounds","achievements"}) do
            if fields[key] then
                selected[key]=fields[key]
                local candidate=escape(encode(selected))
                if #candidate<=46080 then body=candidate else selected[key]=nil end
            end
        end
        if not body then return end
        s.dossierSeq=math.max((s.dossierSeq or 0)+1,GL.Now()*1000)
        local total=math.ceil(#body/180)
        local messages={}
        for part=1,total do messages[#messages+1]=table.concat({"S1","P",target,s.dossierSeq,part,total,body:sub((part-1)*180+1,part*180)},";") end
        if B.SendDossier(s,messages) then responded[target]=GL.Now() end
        return
    end
    local id,part,total,body
    target,id,part,total,body=raw:match("^S1;P;(Player%-%w+%-%w+);(%d+);(%d+);(%d+);(.*)$")
    part,total=tonumber(part),tonumber(total)
    if not target or #id>16 or not part or not total or total<1 or total>256 or part<1 or part>total
        or #body>180 or allowed(target)~=s or body:find("[^%w%% .,:_%-]") then return end
    local key=sender..":"..target..":"..id
    local n=0
    for k,v in pairs(pending) do if GL.Now()-v.at>300 then pending[k]=nil else n=n+1 end end
    if not pending[key] then if n>=8 then return end; pending[key]={at=GL.Now(),total=total,parts={},count=0} end
    local p=pending[key]
    if p.total~=total then pending[key]=nil; return end
    if p.parts[part] then if p.parts[part]~=body then pending[key]=nil end; return end
    p.parts[part]=body; p.count=p.count+1
    if p.count~=total then return end
    pending[key]=nil
    local text=table.concat(p.parts)
    local ok,data=pcall(decode,(text:gsub("%%(%x%x)",function(h)return string.char(tonumber(h,16)) end)))
    if not ok or type(data)~="table" then return end
    local result={}
    for k,e in pairs(data) do
        if schema[k] and type(e)=="table" and (e.source=="armory" or e.source=="inspection") then merge(result,k,e.data,e.at,e.source) end
    end
    if not next(result) then return end
    local _,expectedName=allowed(target)
    local publicName=result.identity and result.identity.data.name
    if publicName and publicName:lower()~=expectedName:lower() then return end
    local saved=cache(s,target)
    for k,e in pairs(result) do merge(saved.fields,k,e.data,e.at,e.source) end
    saved.received,saved.sender=GL.Now(),sender
    saved.senderName=B.MemberName(sender)
    GL.Emit("DOSSIER_UPDATED",target)
end
function S.Refresh()
    local s=B.GuildScope()
    reset(s)
    if not s then return end
    for _,card in ipairs(GL.GuildProfiles.List()) do S.Request(card.target) end
    for _,order in pairs(B.List()) do if order.state=="open" then S.Request(order.target) end end
end
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
