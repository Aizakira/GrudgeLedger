-- Guild dossier synchronisation (audit 0.12.0, problems 1 to 4) with several real clients.
-- Scenarios adapted from the audit annexes: v2_join, v3_traffic and v5_slots.
-- The transport is simulated: one message per client per tick, no loss unless a test drops it.
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
local function run(seconds,start)
    for _=1,seconds do
        second()
        if (now-start)%30==0 then
            for _,p in ipairs(clients) do if p.online then p.GL.SharedDossiers.Refresh() end end
        end
    end
end
local function holds(c,target)
    local s=c.GL.Bounties.GuildScope()
    local saved=s and s.dossiers and s.dossiers[target]
    return saved~=nil and saved.fields.gear~=nil
end
local function noErrors()
    for _,p in ipairs(clients) do assert(#p.GL.errors==0,p.GL.errors[1] and p.GL.errors[1].text) end
end
local function answers(c,target)
    local n=0
    for _,msg in ipairs(c.log) do
        if msg:find("^J;S2;P;"..target:gsub("%-","%%-")..";%d+;r;1;") then n=n+1 end
    end
    return n
end
local function armory(c,target,name)
    c.env.GrudgeLedgerArmory=c.env.GrudgeLedgerArmory or {items={},profiles={}}
    local items=c.env.GrudgeLedgerArmory.items
    items[#items+1]={id=100+#items,name="Helmet",ref="item:"..(100+#items),icon=123}
    c.env.GrudgeLedgerArmory.profiles[target]={updated=now,identity={name=name,raceID=6,sex=2,classFile="DRUID",faction="Horde"},
        level=44,gear={head=#items},stats={HEALTH=1500}}
end

-- 1. Late joiner (audit problem 1). A and B already share the dossier; C logs in an hour later.
do
    local a,b=client(1),client(2)
    flush()
    local identity=a.GL.IdentityFromName("Public","Target","Player-1-abcd")
    local record=a.GL.Remember(identity)
    armory(a,identity.guid,"Public Target")
    assert(a.g.Publish(record))
    flush()
    assert(holds(b,identity.guid),"B receives the dossier with the card")
    now=now+3600
    local c=client(3)
    local start=now
    local got
    for _=1,20 do
        run(30,start)
        if holds(c,identity.guid) then got=now-start; break end
    end
    assert(got and got<=60,"late joiner waited "..tostring(got).." s for equipment (0.12.0: about 320 s)")
    -- A single member answers: the first fragment of one answer silences the other holder.
    assert(answers(a,identity.guid)+answers(b,identity.guid)==2,"one answer for B, one for C")
    noErrors()
end

-- Same late joiner with a bounty instead of a guild card.
do
    clients,wire={},{}
    local a,b=client(1),client(2)
    flush()
    local target="Player-1-beef"
    armory(a,target,"Other Target")
    assert(a.GL.Bounties.Post(target,"Other Target",100))
    flush()
    assert(holds(b,target))
    now=now+3600
    local c=client(3)
    local start=now
    local got
    for _=1,20 do
        run(30,start)
        if holds(c,target) then got=now-start; break end
    end
    assert(c.GL.Bounties.OpenFor(target),"C sees the bounty")
    assert(got and got<=60,"late joiner waited "..tostring(got).." s for the bounty dossier")
    noErrors()
end

-- 2. Traffic (audit problem 2): five clients, eight shared targets, one message per second each.
do
    clients,wire={},{}
    local N,T=5,8
    for i=1,N do client(i) end
    flush()
    local a=clients[1]
    local targets={}
    for i=1,T do
        local guid=("Player-1-%04x"):format(i)
        local identity=a.GL.IdentityFromName("Cible","Exemple"..i,guid)
        local record=a.GL.Remember(identity)
        armory(a,guid,"Cible Exemple"..i)
        -- A realistic dossier: talents and long reputation lists make it dozens of fragments.
        local p=a.env.GrudgeLedgerArmory.profiles[guid]
        p.trees={}
        for t=1,3 do
            local talents={}
            for k=1,15 do talents[k]={1000+t*100+k,"Talent très utile n°"..k,k%5+1,136000+k} end
            p.trees[t]={id="tree"..t,name="Spécialisation "..t,points=17,talents=talents}
        end
        p.reputations={}
        for k=1,25 do p.reputations[k]={name="Faction d’exemple "..k,standing="Honoré",value=3000+k,max=12000,group="Royaumes de l’Est"} end
        assert(a.g.Publish(record))
        targets[i]=guid
    end
    local function complete()
        local n=0
        for i=2,N do
            for _,g in ipairs(targets) do if holds(clients[i],g) then n=n+1 end end
        end
        return n
    end
    local function total()
        local n=0
        for _,p in ipairs(clients) do n=n+p.sent end
        return n
    end
    local start=now
    local done
    for minute=1,20 do
        run(60,start)
        if complete()==(N-1)*T then done=minute; break end
    end
    assert(done,"only "..complete().." of "..((N-1)*T).." dossiers after 20 minutes (0.12.0: 24 of 32, never more)")
    -- Once everyone is complete, only the periodic requests remain: one per client and target every 5 minutes.
    run(300,start)
    local before=total()
    run(600,start)
    local quiet=total()-before
    assert(quiet<=2*N*T+N,"steady traffic of "..quiet.." messages in 10 minutes (0.12.0: about 3000)")
    noErrors()
end

-- 3. Orphan fragments (audit problem 3) cannot block a valid transfer.
do
    clients,wire={},{}
    local a,b,c=client(1),client(2),client(3)
    flush()
    local identity=a.GL.IdentityFromName("Public","Target","Player-1-abcd")
    local record=a.GL.Remember(identity)
    armory(a,identity.guid,"Public Target")
    assert(a.g.Publish(record))
    -- Hold A's fragments back so B starts without the dossier.
    a.answer=function(msg) if msg:find("^J;S2;P;") then return 9 end return 0 end
    flush()
    a.answer=nil
    assert(#b.g.List()==1 and not holds(b,identity.guid))
    local function orphans(part)
        for i=1,8 do
            local msg="J;S2;P;"..identity.guid..";"..(now*1000+i)..";r;"..part..";2;x"
            b.m.Fire("CHAT_MSG_ADDON","GLBounty1",msg,"GUILD",c.name)
        end
    end
    now=now+301
    orphans(2)
    orphans(1)
    for _,p in ipairs(clients) do p.GL.SharedDossiers.Refresh() end
    flush()
    assert(holds(b,identity.guid),"eight orphan fragments from one member no longer block reception")
    noErrors()
end

-- 4. Refused sends (audit problem 4) and the lockdown guard.
do
    clients,wire={},{}
    local a,b=client(1),client(2)
    flush()
    local target="Player-1-f00d"
    -- Each temporary refusal (prefix limit 3, channel limit 8, general error 9, lockdown 11) is answered once.
    local refusals={3,8,9,11}
    a.answer=function()
        return table.remove(refusals,1) or 0
    end
    assert(a.GL.Bounties.Post(target,"Refused Target",100))
    flush()
    assert(#refusals==0 and b.GL.Bounties.OpenFor(target),"the bounty arrives after four refusals")
    a.answer=nil
    -- While the game reports a messaging lockdown, nothing leaves and nothing is lost.
    a.lockdown=true
    local sent=a.sent
    assert(a.GL.Bounties.Post("Player-1-f00e","Second Target",100))
    for _=1,10 do second() end
    assert(a.sent==sent and not b.GL.Bounties.OpenFor("Player-1-f00e"))
    a.lockdown=false
    flush()
    assert(b.GL.Bounties.OpenFor("Player-1-f00e"),"queued bounty leaves after the lockdown")
    -- A message the game always refuses with a general error is dropped after three attempts.
    a.answer=function(msg) if msg:find("Dropped Target",1,true) then return 9 end return 0 end
    assert(a.GL.Bounties.Post("Player-1-f00f","Dropped Target",100))
    local urgent=a.GL.Transport.Pending(a.GL.Bounties.GuildScope())
    for _=1,6 do second() end
    assert(a.GL.Transport.Pending(a.GL.Bounties.GuildScope())<urgent,"the refused message does not block the queue")
    a.answer=nil
    flush()
    noErrors()
end

-- Bounty events overtake dossier fragments already waiting in the queue.
do
    clients,wire={},{}
    local a,b=client(1),client(2)
    flush()
    local scope=a.GL.Bounties.GuildScope()
    local filler={}
    for i=1,40 do filler[i]="J;S2;Q;Player-1-0000;0,0,0,0,0,0,0,0,0,0,"..i end
    assert(a.GL.Transport.SendBatch(scope,filler))
    second()
    assert(a.GL.Bounties.Post("Player-1-cafe","Urgent Target",100))
    second()
    second()
    assert(b.GL.Bounties.OpenFor("Player-1-cafe"),"the bounty leaves before 38 waiting fragments")
    flush()
    noErrors()
end

-- Members still on 0.12.0 (protocol S1) are ignored, without errors.
do
    clients,wire={},{}
    local a,b=client(1),client(2)
    flush()
    local identity=a.GL.IdentityFromName("Public","Target","Player-1-abcd")
    local record=a.GL.Remember(identity)
    armory(a,identity.guid,"Public Target")
    assert(a.g.Publish(record))
    flush()
    local sent=a.sent
    a.m.Fire("CHAT_MSG_ADDON","GLBounty1","J;S1;Q;"..identity.guid,"GUILD",b.name)
    flush()
    assert(a.sent==sent,"an S1 request gets no answer")
    a.m.Fire("CHAT_MSG_ADDON","GLBounty1","J;S1;P;"..identity.guid..";1;1;1;t0:","GUILD",b.name)
    noErrors()
end
print("PASS guild sync: late joiner served within a minute, one answer per request, bounded steady traffic, "
    .."orphan fragments, refused sends and lockdown, bounty priority, 0.12.0 protocol ignored")
