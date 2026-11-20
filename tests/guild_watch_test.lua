-- Guild watch (0.30.0): a member who sees an enemy tells the guild where; the others are alerted
-- when that player matters to them, or when a guildmate's enemy is in their own zone.
-- Sending is opt-in and off by default. Separate clients on the real TOC.
local clients, wire, now = {}, {}, 1800000000
local watched = {}
local function client(i,saved)
    local env=setmetatable({_G=false,GrudgeLedgerDB=saved},{__index=_G})
    env._G=env
    env.loadfile=function(p) return setfenv(assert(loadfile(p)),env) end
    local mock=env.loadfile(TEST_WORK.."/tests/addon_mock.lua")()
    local c={env=env,GL=env.GrudgeLedger,g=env.GrudgeLedger.GuildProfiles,m=mock,online=true,
        id="Player-1-c"..i,name="Opinion"..i.."-Realm",guild="Guild"}
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
    env.C_Map={GetBestMapForUnit=function() return c.map or 1444 end}
    env.GetRealZoneText=function() return c.zone or "Féralas" end
    env.C_ChatInfo.RegisterAddonMessagePrefix=function() end
    env.C_ChatInfo.SendAddonMessage=function(prefix,msg,channel)
        wire[#wire+1]={prefix,msg,channel,c.name,c.guild}
        if msg:find(";S2;V;",1,true) then watched[#watched+1]=msg end
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

local a,b,c=client(1),client(2),client(3)
flush()
local function sent() return #watched end
local function see(client,guid,name,surname)
    client.m.units.target={name=name,surname=surname,guid=guid}
    client.GL.Display.OnEvent(nil,"PLAYER_TARGET_CHANGED")
end
-- The target is an enemy of B and of A; C has never met them.
local target="Player-1-0f0e"
for _,member in ipairs({a,b}) do
    member.GL.RecordAggression(member.GL.IdentityFromName("Sneaky","Rogue",target),"confirmed",nil,"watch-attack")
end
now=now+300
-- Off by default: B sees the enemy, nothing leaves.
assert(not b.GL.SharedDossiers.SharingSightings())
see(b,target,"Sneaky","Rogue")
flush()
assert(sent()==0,"sending is opt-in")
assert(not a.GL.SharedDossiers.WatchSighting(target))
-- B opts in: one message, with the map, the relation and the escaped name and zone.
b.GL.SharedDossiers.ShareSightings(true)
now=now+200
a.map,c.map=17,17
see(b,target,"Sneaky","Rogue")
flush()
assert(sent()==1,sent())
local message=watched[1]
assert(message:find(";S2;V;"..target..";1444;e;Sneaky Rogue;F%C3%A9ralas",1,true),message)
-- Seeing the same player again within two minutes sends nothing more.
see(b,target,"Sneaky","Rogue")
flush()
assert(sent()==1,"one report per player every two minutes")
-- A holds this player as an enemy: alerted wherever A is.
local sight=assert(a.GL.SharedDossiers.WatchSighting(target),"A received the sighting")
assert(sight.zone=="Féralas" and sight.name=="Sneaky Rogue" and sight.relation=="enemy" and sight.actor==b.id)
local toast=assert(a.env.GrudgeLedgerNearbyAlert,"A is alerted")
assert(toast:IsShown() and toast.title:GetText()=="Repéré par la guilde · Ennemi",toast.title:GetText())
assert(toast.name:GetText()=="Sneaky Rogue" and toast.note:GetText():find("Féralas",1,true),toast.note:GetText())
assert(a.GL.SharedDossiers.GuildSighting(target).actor==b.id,"the sheet's last guild encounter uses it")
-- C never met them and is elsewhere: informed, not alerted, and nothing enters C's journal.
assert(c.GL.SharedDossiers.WatchSighting(target) and not c.GL.Get("guid:"..target))
assert(not (c.env.GrudgeLedgerNearbyAlert and c.env.GrudgeLedgerNearbyAlert:IsShown()),"no alert for a stranger far away")
-- In B's zone, a guildmate's enemy is worth a warning, even unknown to C.
c.map=1444
now=now+130
see(b,target,"Sneaky","Rogue")
flush()
local warned=assert(c.env.GrudgeLedgerNearbyAlert,"C is warned in the same zone")
assert(warned:IsShown() and warned.note:GetText():find("dans votre zone",1,true),warned.note:GetText())
assert(not c.GL.Get("guid:"..target),"still nothing in C's journal")
-- The alert can be switched off; malformed reports are ignored.
toast:Hide()
assert(a.GL.SetSetting("guildSightings",false))
now=now+130
see(b,target,"Sneaky","Rogue")
flush()
assert(not toast:IsShown(),"guild alerts switched off")
local scope=a.GL.Bounties.GuildScope()
a.GL.SharedDossiers.Receive(scope,b.id,"S2;V;"..target..";1444;x;Bad;Zone")
a.GL.SharedDossiers.Receive(scope,b.id,"S2;V;not-a-player;1444;e;Bad;Zone")
a.GL.SharedDossiers.Receive(scope,b.id,"S2;V;"..target..";1444;e;Bad|cff;Zone")
assert(a.GL.SharedDossiers.WatchSighting(target).name=="Sneaky Rogue","malformed reports change nothing")
-- Call for help: C never opted into the automatic watch, sees the enemy and clicks "Appeler la guilde".
-- Every member is alerted, wherever they are.
assert(a.GL.SetSetting("guildSightings",true))
c.GL.RecordAggression(c.GL.IdentityFromName("Sneaky","Rogue",target),"confirmed",nil,"help-attack")
assert(not c.GL.SharedDossiers.SharingSightings())
now=now+400
a.map,c.map=17,1444
see(c,target,"Sneaky","Rogue")
local own=assert(c.env.GrudgeLedgerNearbyAlert)
assert(own:IsShown() and own.help:IsShown(),"the alert offers the call for help")
local before=#watched
own.help.scripts.OnClick(own.help,"LeftButton")
flush()
assert(#watched==before+1 and watched[#watched]:find(";1444;h;",1,true),watched[#watched])
assert(own.help.label:GetText()=="Guilde prévenue")
local called=a.GL.SharedDossiers.WatchSighting(target)
assert(called and called.help and called.actor==c.id)
assert(toast:IsShown() and toast.title:GetText():find("^Appel à l’aide de "),toast.title:GetText())

-- The revenge moment: A kills the player who owed them.
toast:Hide()
local owed=a.GL.Debt(a.GL.Get("guid:"..target))
assert(owed==5,owed)
a.GL.RecordPvP(a.GL.IdentityFromName("Sneaky","Rogue",target),"kill","confirmed","Direct","revenge-kill")
assert(toast:IsShown() and toast.title:GetText()=="Revanche" and toast.note:GetText()=="Dette de 5 ramenée à 4.",toast.note:GetText())
for i=1,4 do
    a.GL.RecordPvP(a.GL.IdentityFromName("Sneaky","Rogue",target),"kill","confirmed","Direct","revenge-kill-"..i)
end
assert(toast.title:GetText()=="Compte réglé" and toast.note:GetText()=="Sa dette de 1 est effacée.",toast.note:GetText())
-- Pre-merge review: text from the network never carries a formatting code into an alert.
local other="Player-1-0f0f"
a.GL.SharedDossiers.Receive(scope,b.id,"S2;V;"..other..";1444;e;%7CTbad%7Ct;Zone%7Ccff")
local escaped=assert(a.GL.SharedDossiers.WatchSighting(other))
assert(escaped.name=="||Tbad||t" and escaped.zone=="Zone||cff",escaped.name)
-- A member cannot flood the guild: one call for help per member every thirty seconds.
a.GL.SharedDossiers.Receive(scope,b.id,"S2;V;"..other..";1444;h;First;Zone")
local firstCall=a.GL.SharedDossiers.WatchSighting(other)
assert(firstCall.help and firstCall.name=="First")
now=now+5
a.GL.SharedDossiers.Receive(scope,b.id,"S2;V;"..other..";1444;h;Second;Zone")
assert(a.GL.SharedDossiers.WatchSighting(other).name=="First","a second call within thirty seconds is ignored")
now=now+31
a.GL.SharedDossiers.Receive(scope,b.id,"S2;V;"..other..";1444;h;Third;Zone")
assert(a.GL.SharedDossiers.WatchSighting(other).name=="Third")
for _,p in ipairs(clients) do assert(#p.GL.errors==0,p.GL.errors[1] and p.GL.errors[1].text) end
print("PASS guild watch: opt-in sending, one report per player per two minutes, alert for your enemies anywhere, "
    .."warning for a guildmate's enemy in your zone, nothing saved in the journal, alert switch, malformed reports ignored, call for help reaches everyone, revenge and settled banners")
