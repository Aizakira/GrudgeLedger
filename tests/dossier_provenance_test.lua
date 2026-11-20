-- Fiche fiable (audit 0.12.0, problems 5, 7 and 10): who observed each field, when each piece
-- was seen, and an inspection without a journal entry kept after a reload.
local clients, wire, now = {}, {}, 1800000000
local function client(i,saved)
    local env=setmetatable({_G=false,GrudgeLedgerDB=saved},{__index=_G})
    env._G=env
    env.loadfile=function(p) return setfenv(assert(loadfile(p)),env) end
    local mock=env.loadfile(TEST_WORK.."/tests/addon_mock.lua")()
    local c={env=env,GL=env.GrudgeLedger,g=env.GrudgeLedger.GuildProfiles,m=mock,online=true,
        id="Player-1-a"..i,name="Member"..i.."-Realm",guild="Guild",sent=0,log={}}
    clients[i]=c
    mock.units.player={guid=c.id,name="Member"..i,surname="Example",guild=c.guild,realm="Realm"}
    env.GetServerTime=function() return now end
    env.GetNormalizedRealmName=function() return "Realm" end
    env.GetNumGuildMembers=function() return #clients end
    env.GetGuildRosterInfo=function(index)
        local p=clients[index]
        local info={[1]=p.name,[17]=p.id}
        return unpack(info,1,17)
    end
    env.C_ChatInfo.RegisterAddonMessagePrefix=function() end
    env.C_ChatInfo.InChatMessagingLockdown=function() return c.lockdown==true end
    env.C_ChatInfo.SendAddonMessage=function(prefix,msg,channel)
        assert(#msg<=255,"addon message over 255 bytes")
        if c.answer then
            local code=c.answer(msg)
            if code~=0 then return code end
        end
        c.sent=c.sent+1
        c.log[#c.log+1]=msg
        wire[#wire+1]={prefix,msg,channel,c.name,c.guild}
        return 0
    end
    env.C_Timer={NewTicker=function(delay,fn) if delay==0.5 then c.tick=fn end; return {Cancel=function() end} end}
    mock.Fire("PLAYER_LOGIN")
    for _,p in ipairs(clients) do if p.online then p.m.Fire("GUILD_ROSTER_UPDATE") end end
    return c
end
local function deliver()
    local packets=wire
    wire={}
    for _,m in ipairs(packets) do
        for _,p in ipairs(clients) do
            if p.online and p.guild==m[5] then p.m.Fire("CHAT_MSG_ADDON",unpack(m,1,4)) end
        end
    end
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
-- One simulated second: every online client may send one message, as the game allows after its burst.
local function second()
    now=now+1
    for _,p in ipairs(clients) do if p.online then p.tick() end end
    deliver()
end
local function flush(limit)
    for step=1,limit or 2000 do
        second()
        if #wire==0 and not waiting() then return step end
    end
    error("guild traffic did not settle")
end
-- The module refreshes every 30 seconds on each client.
local function noErrors()
    for _,p in ipairs(clients) do assert(#p.GL.errors==0,p.GL.errors[1] and p.GL.errors[1].text) end
end
local function armory(c,target,name,at,gear,identity,stats)
    c.env.GrudgeLedgerArmory=c.env.GrudgeLedgerArmory or {items={},profiles={}}
    local items=c.env.GrudgeLedgerArmory.items
    local slots={}
    for slot,piece in pairs(gear) do
        items[#items+1]={id=piece.id,name=piece.name,ref="item:"..piece.id,icon=123}
        slots[slot]=#items
    end
    c.env.GrudgeLedgerArmory.profiles[target]={updated=at,identity=identity,level=44,gear=slots,stats=stats}
end
local function profile(c,guid) return c.GL.ArmoryProfile({guid=guid}) end

-- 1. Provenance (problem 5): B keeps A as the observer of A's equipment, even after seeing the target.
do
    local a,b=client(1),client(2)
    flush()
    local identity=a.GL.IdentityFromName("Public","Target","Player-1-abcd")
    local record=a.GL.Remember(identity)
    local t1=now
    armory(a,identity.guid,"Public Target",t1,{head={id=100,name="Helmet"},chest={id=200,name="Old chest"}},
        {name="Public Target",raceID=6,sex=2,classFile="DRUID",guild="Old Guild"},{HEALTH=1500,MANA=900})
    assert(a.g.Publish(record))
    flush()
    local p=profile(b,identity.guid)
    assert(p and p.gear.head.id==100,"B received the equipment")
    local gear=assert(p.provenance and p.provenance.gear,"each field carries its provenance")
    assert(gear.by==a.id and gear.source=="armory" and gear.at==t1,"A's Armory snapshot, dated when A took it")
    -- B sees the target in the world: B observes identity and level, not the equipment.
    now=now+60
    b.GL.SharedDossiers.Observe({guid=identity.guid,raceID=6,sex=2,class="DRUID",level=44})
    gear=profile(b,identity.guid).provenance.gear
    assert(gear.by==a.id,"seeing the target does not make B the source of A's equipment")
    -- The dossier header names the observer and the date.
    b.GL.OpenPlayerDossier(identity.guid,nil,nil,"gear")
    local label=b.env.GrudgeLedgerPlayerDossier.source:GetText()
    assert(label:find("Member1",1,true) and label:find("/",1,true),label)
    assert(not label:find("Member2",1,true),label)

    -- 2. Old pieces keep their own date (problem 7). Three days later, a snapshot without helmet or guild.
    now=now+3*86400
    local t2=now
    armory(a,identity.guid,"Public Target",t2,{chest={id=300,name="New chest"}},{name="Public Target",raceID=6,sex=2,classFile="DRUID"},
        {HEALTH=1700})
    b.GL.SharedDossiers.Refresh()
    flush()
    p=profile(b,identity.guid)
    assert(p.gear.chest.id==300 and p.gear.head.id==100,"the older helmet stays known")
    assert(p.dates and p.dates.gear,"pieces carry their own dates")
    assert(p.dates.gear.chest==t2,"the new chest is dated by the new snapshot")
    assert(p.dates.gear.head==t1,"the helmet keeps the date it was seen, not the new snapshot's")
    assert(p.dates.identity.guild==t1 and p.dates.stats.MANA==t1 and p.dates.stats.HEALTH==t2)
    -- The equipment tab marks the helmet as seen before the latest snapshot.
    b.GL.OpenPlayerDossier(identity.guid,nil,nil,"gear")
    local view=b.env.GrudgeLedgerPlayerDossier.equipment.equipment
    local marked={}
    for _,button in ipairs(view.buttons) do if button.seenAt then marked[#marked+1]=button.seenAt end end
    assert(#marked==1 and marked[1]==t1,"only the helmet is marked, with its own date")
    -- C receives the relayed dossier from B while A is away: A stays the observer, B the relay.
    a.online=false
    local c=client(3)
    local scope=c.GL.Bounties.GuildScope()
    scope.journal={cards=b.GL.Bounties.GuildScope().journal.cards,hidden={},withdrawn={},secrets={},seq=0}
    c.GL.SharedDossiers.Refresh()
    flush()
    p=profile(c,identity.guid)
    assert(p and p.provenance.gear.by==a.id and p.provenance.gear.via==b.id,"relayed: observed by A, received from B")
    assert(p.dates.gear.head==t1)
    noErrors()
end

-- 3. An inspection of a bounty target without a journal entry survives a reload (problem 10).
do
    clients,wire={},{}
    local a,b=client(1),client(2)
    flush()
    local target="Player-1-beef"
    assert(a.GL.Bounties.Post(target,"Other Target",100))
    flush()
    assert(not b.GL.Get("guid:"..target),"B has no journal entry for the target")
    local seenAt=now
    b.GL.Emit("DOSSIER_INSPECTED",target,{gear={[1]="|cff0070dd|Hitem:42:9:-12|h[Heaume]|h|r"},gearAt=seenAt,
        stats={HEALTH=1933},statsAt=seenAt})
    local saved=b.GL.db
    b=client(2,saved)
    flush()
    local p=profile(b,target)
    assert(p and p.gear and p.gear.head and p.gear.head.id==42,"the inspected helmet is still known after reload")
    assert(p.provenance.gear.source=="inspection" and p.provenance.gear.by==b.id and p.provenance.gear.at==seenAt)
    noErrors()
end
print("PASS dossier provenance: observer and date per field, own sighting is not a source, relay kept apart, "
    .."old pieces keep their date, inspection without journal entry kept after reload")
