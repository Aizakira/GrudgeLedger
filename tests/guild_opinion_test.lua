-- A player hated by guildmates, unknown to you, reads as hated: relation, alert, sheet.
-- Your own opinion always wins over the guild's. Separate clients on the real TOC.
local clients, wire, now = {}, {}, 1800000000
local function client(i,saved)
    local env=setmetatable({_G=false,GrudgeLedgerDB=saved},{__index=_G})
    env._G=env
    env.loadfile=function(p) return setfenv(assert(loadfile(p)),env) end
    local mock=env.loadfile(TEST_WORK.."/tests/addon_mock.lua")()
    local c={env=env,GL=env.GrudgeLedger,g=env.GrudgeLedger.GuildProfiles,m=mock,online=true,
        id="Player-1-c"..i,name="Opinion"..i.."-Realm",guild="Guild"}
    -- These assertions were written with the weights of before 0.42.0; they are pinned here.
    c.GL.SetSetting("grudgeAggression",5) c.GL.SetSetting("grudgeDeath",5) c.GL.SetSetting("grudgeVictory",1)
    clients[i]=c
    mock.units.player={guid=c.id,name="Opinion"..i,surname="Example",guild=c.guild,realm="Realm"}
    env.GetServerTime=function() return now end
    env.GetNormalizedRealmName=function() return "Realm" end
    env.GetNumGuildMembers=function() return #clients end
    env.GetGuildRosterInfo=function(index)
        local p=clients[index]
        local info={[1]=p.name,[17]=p.id}
        return unpack(info,1,17)
    end
    env.UnitIsVisible=function() return true end
    env.C_ChatInfo.RegisterAddonMessagePrefix=function() end
    env.C_ChatInfo.SendAddonMessage=function(prefix,msg,channel)
        wire[#wire+1]={prefix,msg,channel,c.name,c.guild}
        return 0
    end
    env.C_Timer={NewTicker=function(delay,fn) if delay==0.5 then c.tick=fn end; return {Cancel=function() end} end}
    mock.Fire("PLAYER_LOGIN")
    for _,p in ipairs(clients) do if p.online then p.m.Fire("GUILD_ROSTER_UPDATE") end end
    return c
end
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
            for _,p in ipairs(clients) do
                if p.online and p.guild==m[5] then p.m.Fire("CHAT_MSG_ADDON",unpack(m,1,4)) end
            end
        end
    end
    error("guild traffic did not settle")
end

local a,b=client(1),client(2)
flush()
-- B fought the target and shares a testimony of -11 on its card. A has never met it.
local target="Player-1-0bad"
local seen=b.GL.IdentityFromName("Hated","Target",target)
b.GL.RecordAggression(seen,"confirmed",nil,"opinion-attack")
now=now+60
b.GL.RecordPvP(seen,"death","confirmed","opinion","opinion-death",nil,nil,true)
local record=b.GL.Get(seen)
assert(record.reputation<=-10 and b.g.Publish(record))
b.GL.SharedDossiers.ShareSocial(true)
for _=1,4 do now=now+31; b.GL.SharedDossiers.Refresh(); flush() end
local opinion=assert(a.GL.GuildOpinion(target),"A knows the guild's opinion")
assert(opinion.relation=="enemy" and opinion.count==1 and opinion.score<=-10,opinion.relation)
assert(not a.GL.Get("guid:"..target),"the target is not in A's journal")
local identity={guid=target,key="guid:"..target}
assert(a.GL.Relation(identity)=="enemy" and a.GL.RelationSource(identity)=="guildmates")

-- A targets the player: the alert says the guild hates them, without a journal entry.
a.m.units.target={name="Hated",surname="Target",guid=target}
a.GL.Display.OnEvent(nil,"PLAYER_TARGET_CHANGED")
local toast=assert(a.env.GrudgeLedgerNearbyAlert,"an alert is shown")
assert(toast:IsShown() and toast.title:GetText():find("Avis de la guilde",1,true),toast.title:GetText())
assert(not a.GL.Get("guid:"..target),"the alert adds nothing to A's journal")

-- On A's sheet, A's own opinion stays neutral; the guild's pill says enemy.
assert(a.GL.OpenPlayerDossier(target,nil,"Hated Target"))
local sheet=a.env.GrudgeLedgerPlayerDossier
assert(sheet.pills[2].label:GetText():find("^Ennemi"),sheet.pills[2].label:GetText())

-- A's own opinion always wins.
local mine=a.GL.Remember(a.GL.IdentityFromName("Hated","Target",target))
assert(a.GL.Relation(mine)=="enemy" and a.GL.RelationSource(mine)=="guildmates")
assert(a.GL.OpenPlayerDossier(target))
assert(sheet.pills[1].label:GetText():find("^Neutre"),"your pill shows your opinion, not the guild's")
a.GL.SetReaction(a.GL.IdentityFromName("Hated","Target",target),"friend")
assert(a.GL.Relation(mine)=="friend" and a.GL.RelationSource(mine)=="manual")

-- A bad tag on a guild card alone makes a player suspicious.
local other="Player-1-0bae"
local tagged=b.GL.Remember(b.GL.IdentityFromName("Ninja","Looter",other))
local card=assert(b.g.Publish(tagged))
b.g.SetTag(card,"ninja",true)
flush()
local suspicious=assert(a.GL.GuildOpinion(other))
assert(suspicious.relation=="warning" and suspicious.tags==1,suspicious.relation)
-- Withdrawn testimonies stop counting.
b.GL.SharedDossiers.ShareSocial(false)
flush()
assert(not a.GL.GuildOpinion(target) or a.GL.GuildOpinion(target).relation=="neutral","a withdrawn testimony no longer counts")
for _,p in ipairs(clients) do assert(#p.GL.errors==0,p.GL.errors[1] and p.GL.errors[1].text) end
print("PASS guild opinion: unknown player hated by the guild reads as an enemy, alert without journal entry, "
    .."your opinion wins, bad tags make a player suspicious, withdrawn testimonies stop counting")
