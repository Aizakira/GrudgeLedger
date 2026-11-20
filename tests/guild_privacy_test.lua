-- Step D of the 0.12.0 audit, with separate clients on the real TOC and guild transport:
-- problem 8 (answers reveal the personal journal), problem 9 (unchecking then logging out
-- leaves testimonies behind), and an account identifier that linked characters across guilds.
local clients, wire, now = {}, {}, 1800000000
local function client(i,saved,guild)
    local env=setmetatable({_G=false,GrudgeLedgerDB=saved},{__index=_G})
    env._G=env
    env.loadfile=function(p) return setfenv(assert(loadfile(p)),env) end
    local mock=env.loadfile(TEST_WORK.."/tests/addon_mock.lua")()
    local c={env=env,GL=env.GrudgeLedger,g=env.GrudgeLedger.GuildProfiles,m=mock,online=true,
        id="Player-1-b"..i,name="Privacy"..i.."-Realm",guild=guild or "Guild"}
    clients[i]=c
    mock.units.player={guid=c.id,name="Privacy"..i,surname="Example",guild=c.guild,realm="Realm"}
    env.GetServerTime=function() return now end
    env.GetNormalizedRealmName=function() return "Realm" end
    env.GetNumGuildMembers=function() return #clients end
    env.GetGuildRosterInfo=function(index)
        local p=clients[index]
        local info={[1]=p.name,[17]=p.id}
        return unpack(info,1,17)
    end
    env.C_ChatInfo.RegisterAddonMessagePrefix=function() end
    env.C_ChatInfo.SendAddonMessage=function(prefix,msg,channel)
        assert(#msg<=255)
        wire[#wire+1]={prefix,msg,channel,c.name,c.guild,c}
        return 0
    end
    env.C_Timer={NewTicker=function(delay,fn) if delay==0.5 then c.tick=fn end; return {Cancel=function() end} end}
    mock.Fire("PLAYER_LOGIN")
    for _,p in ipairs(clients) do if p.online then p.m.Fire("GUILD_ROSTER_UPDATE") end end
    return c
end
local sent={}
local function waiting()
    for _,p in ipairs(clients) do
        local scope=p.online and p.GL.Bounties.GuildScope()
        if scope then
            local urgent,bulk=p.GL.Transport.Pending(scope)
            if urgent+bulk>0 then return true end
        end
    end
    return false
end
local function flush()
    for _=1,400 do
        now=now+1
        for _,p in ipairs(clients) do if p.online then p.tick() end end
        if #wire==0 and not waiting() then return end
        local packets=wire; wire={}
        for i=#packets,1,-1 do
            local m=packets[i]
            sent[#sent+1]={from=m[6],msg=m[2]}
            for _,p in ipairs(clients) do
                if p.online and p.guild==m[5] then p.m.Fire("CHAT_MSG_ADDON",unpack(m,1,4)) end
            end
        end
    end
    error("guild traffic did not settle")
end
local function from(c,pattern)
    local n=0
    for _,s in ipairs(sent) do if s.from==c and s.msg:find(pattern) then n=n+1 end end
    return n
end

local a,b=client(1),client(2)
flush()

-- Problem 8: B knows the target from its own journal (level, guild, a private note), shares
-- nothing, and has no Armory snapshot or inspection of it. A publishes the target's card.
local target=b.GL.IdentityFromName("Quiet","Target","Player-1-0d0d")
target.level,target.guild=37,"Secret Guild"
local mine=b.GL.Remember(target)
b.GL.RecordSeen(target,true)
b.GL.AddNote(target,"private note")
assert(mine.lastSeen and mine.level==37)
local forA=a.GL.Remember(a.GL.IdentityFromName("Quiet","Target","Player-1-0d0d"))
sent={}
assert(a.g.Publish(forA))
flush()
assert(from(b,"^J;S2;P;")==0,"B sends no dossier: nothing public to answer with")
local saved=a.GL.Bounties.GuildScope().dossiers
local dossier=saved and saved[target.guid]
for key,field in pairs(dossier and dossier.fields or {}) do
    assert(field.by~=b.id,"A holds no field observed by B: "..key)
end

-- Problem 9: A shares its testimony on four targets, unchecks, then logs out.
local targets={}
for i=1,4 do
    local id=a.GL.IdentityFromName("Witness","Target"..i,"Player-1-0e0"..i)
    local record=a.GL.RecordAggression(id,"confirmed",nil,"privacy-"..i)
    assert(a.g.Publish(record))
    targets[i]=id.guid
end
flush()
a.GL.SharedDossiers.ShareSocial(true)
for _=1,5 do now=now+31; a.GL.SharedDossiers.Refresh(); flush() end
local function visible(p)
    local n=0
    for _,guid in ipairs(targets) do n=n+#p.GL.SharedDossiers.SocialReports(guid) end
    return n
end
assert(visible(b)==4,"four testimonies before unchecking: "..visible(b))
-- C is away when A unchecks.
local c=client(3)
c.GL.Bounties.GuildScope().socialReports=b.GL.Bounties.GuildScope().socialReports and {} or nil
for k,v in pairs(b.GL.Bounties.GuildScope().socialReports or {}) do
    local copy={}
    for key,value in pairs(v) do copy[key]=value end
    c.GL.Bounties.GuildScope().socialReports[k]=copy
end
c.GL.Bounties.GuildScope().journal=b.GL.Bounties.GuildScope().journal
assert(visible(c)==4)
c.online=false
sent={}
a.GL.SharedDossiers.ShareSocial(false)
flush()
a.online=false
assert(from(a,"^J;S2;W;%d+$")==1,"one withdrawal message, sent at once")
assert(visible(b)==0,"every testimony is withdrawn at once: "..visible(b))
now=now+600
b=client(2,b.GL.db)
flush()
assert(visible(b)==0,"still withdrawn after B reloads")
-- C comes back; A logs in again with sharing still unchecked: the withdrawal is sent again.
c.online=true
a=client(1,a.GL.db)
flush()
assert(visible(c)==0,"a member away at the time receives the withdrawal at the next login: "..visible(c))

-- Account identifier: one per guild, never the raw one.
local first=a.g.Account()
assert(first and #first==16 and first~=a.GL.db.authorAccount)
local other=client(4,a.GL.db,"Other Guild")
assert(other.g.Account()~=first and other.g.Account()~=a.GL.db.authorAccount,"another guild, another identifier")
for _,s in ipairs(sent) do
    assert(not s.msg:find(a.GL.db.authorAccount,1,true),"the raw account identifier never travels")
end
for _,p in ipairs(clients) do assert(#p.GL.errors==0,p.GL.errors[1] and p.GL.errors[1].text) end
print("PASS guild privacy: no personal journal in answers, one immediate withdrawal replayed at login, per-guild account identifier")
