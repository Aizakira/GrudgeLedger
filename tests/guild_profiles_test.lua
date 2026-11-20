-- Three separate accounts exercise the real TOC, Journal buttons, guild transport and disk reload.
local clients, wire, now = {}, {}, 1800000000
local function client(i,saved)
    local env=setmetatable({_G=false,GrudgeLedgerDB=saved},{__index=_G})
    env._G=env
    env.loadfile=function(p) return setfenv(assert(loadfile(p)),env) end
    local mock=env.loadfile(TEST_WORK.."/tests/addon_mock.lua")()
    local c={env=env,GL=env.GrudgeLedger,g=env.GrudgeLedger.GuildProfiles,m=mock,online=true,
        id="Player-1-a"..i,name="Member"..i.."-Realm",guild="Guild"}
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
    env.C_ChatInfo.SendAddonMessage=function(prefix,msg,channel)
        assert(#msg<=255 and not msg:find("SECRET",1,true))
        if not c.drop or not c.drop(msg) then wire[#wire+1]={prefix,msg,channel,c.name,c.guild} end
        return 0
    end
    env.C_Timer={NewTicker=function(delay,fn) if delay==0.5 then c.tick=fn end; return {Cancel=function() end} end}
    mock.Fire("PLAYER_LOGIN")
    for _,p in ipairs(clients) do if p.online then p.m.Fire("GUILD_ROSTER_UPDATE") end end
    return c
end
-- Answers may wait a few seconds in a client's queue before their first fragment leaves.
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
                if p.online and p.guild==m[5] then
                    for _=1,2 do p.m.Fire("CHAT_MSG_ADDON",unpack(m,1,4)) end
                end
            end
        end
    end
    error("guild traffic did not settle")
end
local function click(b) assert(b:IsVisible() and b:IsEnabled(),b:GetText()); b:GetScript("OnClick")(b) end
local a,b,c=client(1),client(2),client(3)
flush()
assert(a.GL.RevocationDigest("0123456789abcdef0123456789abcdef")=="3eb1bd439947eb762998e566ccc2e099c791118b2f40579cc4f7da2b5061b7f9")
local contact=a.GL.Identity("target")
local record=a.GL.Remember(contact)
assert(record.creatorGUID==a.id and record.creatorAccount==a.GL.db.authorAccount)
a.GL.AddNote(contact,"SECRET")
a.GL.ToggleTag(contact,"reliable")
assert(record.tagHistory[1].actorGUID==a.id and record.tagHistory[1].enabled and record.tagHistory[1].time==now)
assert(record.notes[1].actorAccount==record.creatorAccount)
a.GL.ShowLedger(record.key)
click(a.env.GrudgeLedgerWindow.sharedProfiles)
local window=a.env.GrudgeLedgerGuildProfiles
assert(window.publish:IsVisible() and not window.remove:IsVisible())
click(window.publish)
local first=assert(a.g.ForTarget(contact.guid))
flush()
assert(#b.g.List()==1 and #c.g.List()==1 and not b.GL.Get(contact))
assert(window.remove:IsVisible() and first.owner==a.id)
assert(not b.g.Withdraw(b.g.ForTarget(contact.guid)))
assert(not next(first.opinions),"pre-existing private tags never become guild statements")
click(window.tags[6])
b.GL.OpenGuildProfiles()
local other=b.env.GrudgeLedgerGuildProfiles
click(other.tags[1]); click(other.tags[7])
flush()
click(other.dossier)
assert(b.env.GrudgeLedgerPlayerDossier.guid==contact.guid and not other:IsShown())
click(b.env.GrudgeLedgerPlayerDossier.back)
assert(other:IsShown() and other.subject:GetText()==first.name)
for _,p in ipairs(clients) do
    local hist,counts=p.g.View(p.g.ForTarget(contact.guid))
    assert(#hist==3 and counts.reliable==1 and counts.ninja==1 and counts.unreliable==1)
    for _,v in ipairs(hist) do
        assert(v.time>0 and #v.account==16 and v.authorName and v.actor)
        assert(v.account==(v.actor==a.id and a.GL.db.authorAccount or b.GL.db.authorAccount))
    end
end
click(other.tags[7]);flush()
local hist,counts=a.g.View(first)
assert(#hist==4 and not counts.unreliable and counts.reliable and counts.ninja)
local _,altCounts=a.g.View({opinions={hist[1],hist[2],{actor="Player-2-alt",seq=1,time=now,
    account=b.GL.db.authorAccount,tag="ninja",on=true},{actor=b.id,seq=9,time=now,
    account=b.GL.db.authorAccount,tag="ninja",on=true}}})
assert(altCounts.ninja==1,"two characters on the same account count once per tag")
c.GL.OpenGuildProfiles()
click(c.env.GrudgeLedgerGuildProfiles.hide); flush()
assert(#c.g.List()==0 and #c.g.List(true)==1 and #b.g.List()==1)
local cdb=c.GL.db
c=client(3,cdb);flush()
assert(#c.g.List()==0 and #c.g.List(true)==1,"local withdrawal survives reload and replay")
c.GL.OpenGuildProfiles()
click(c.env.GrudgeLedgerGuildProfiles.mode)
click(c.env.GrudgeLedgerGuildProfiles.hide);flush()
assert(c.g.ForTarget(contact.guid) and #c.g.View(c.g.ForTarget(contact.guid))==4)
c.online=false
local keep=b.GL.Remember(contact)
b.GL.AddNote(contact,"PRIVATE")
local oldScope=c.GL.Bounties.GuildScope()
local publicCopy=c.g.ForTarget(contact.guid)
local oldMsg=table.concat({"J;C",first.target,first.digest,first.time,first.account,first.name},";")
-- Arbitrary withdrawal and an unrelated guild channel cannot remove the authentic card.
b.m.Fire("CHAT_MSG_ADDON","GLBounty1","J;D;"..a.id..";"..first.target..";"..string.rep("0",32),"GUILD",b.name)
a.m.Fire("CHAT_MSG_ADDON","GLBounty1","J;D;"..a.id..";"..first.target..";"..string.rep("0",32),"GUILD",b.name)
assert(a.g.ForTarget(contact.guid)==first)
local pending
a.env.StaticPopup_Show=function(which,_,__,obj) pending=function() a.env.StaticPopupDialogs[which].OnAccept(nil,obj) end end
click(window.remove)
assert(pending and a.g.ForTarget(contact.guid)); pending();flush()
assert(#a.g.List()==0 and #b.g.List()==0 and b.GL.Get(contact)==keep and keep.notes[1].text=="PRIVATE")
a.online=false
c.online=true
c.m.Fire("PLAYER_LOGIN"); flush()
assert(#c.g.List()==0 and oldScope.journal.withdrawn[publicCopy.key],"offline member catches up from a witness, publisher offline")
for _,p in ipairs({b,c}) do p.m.Fire("CHAT_MSG_ADDON","GLBounty1",oldMsg,"GUILD",a.name) end
flush()
assert(#b.g.List()==0 and #c.g.List()==0,"delayed creation cannot resurrect a deleted edition")
-- A member can receive the withdrawal before ever seeing the title, then reload.
local late=client(4)
local token=b.GL.Bounties.GuildScope().journal.withdrawn[first.key]
late.m.Fire("CHAT_MSG_ADDON","GLBounty1","J;D;"..a.id..";"..first.target..";"..token,"GUILD",b.name)
late=client(4,late.GL.db)
late.m.Fire("CHAT_MSG_ADDON","GLBounty1",oldMsg,"GUILD",a.name)
assert(not late.g.ForTarget(contact.guid),"revocation before first creation also survives reload")
a.online=true
a.m.Fire("PLAYER_LOGIN");flush()
assert(not a.g.Withdraw(first))
local fresh=assert(a.g.Publish(record));flush()
assert(fresh.key~=first.key and #b.g.List()==1 and #b.g.View(b.g.List()[1])==0)
local secret=assert(a.GL.Bounties.GuildScope().journal.withdrawn[first.key])
b.m.Fire("CHAT_MSG_ADDON","GLBounty1","J;D;"..a.id..";"..first.target..";"..secret,"GUILD",c.name)
assert(b.g.ForTarget(contact.guid).key==fresh.key)
assert(b.GL.DeleteProfile(keep));flush()
assert(#b.g.List()==0 and #a.g.List()==1)
c.m.units.player.guild="Other";c.guild="Other";c.m.Fire("PLAYER_GUILD_UPDATE");flush()
assert(#c.g.List()==0 and not c.g.Withdraw(fresh))
a.g.SetAuto(true)
local new=a.GL.Remember(a.GL.IdentityFromName("New","Person","Player-1-new"))
a.GL.ToggleTag(new,"leaver");flush()
assert(#a.g.List()==2 and b.g.ForTarget(new.guid) and not c.g.ForTarget(new.guid))
local auto=a.g.ForTarget(new.guid)
local _,automatic=a.g.View(auto);assert(automatic.leaver==1)
-- Another character on the publisher's account can withdraw using its saved capability.
a.m.units.player.guid="Player-1-alt"; assert(a.g.Withdraw(auto))
for _,p in ipairs(clients) do assert(#p.GL.errors==0,p.GL.errors[1] and p.GL.errors[1].text) end
-- Public dossiers travel through the real guild transport without a companion on B/C.
do
    clients,wire={},{}
    local a,b=client(1),client(2)
    flush()
    local identity=a.GL.IdentityFromName("Public","Target","Player-1-abcd")
    local record=a.GL.Remember(identity)
    a.GL.AddNote(identity,"SECRET personal note")
    a.env.GrudgeLedgerArmory={items={{id=100,name="Helmet",ref="item:100",icon=123}},profiles={
        [identity.guid]={updated=now,identity={name="Public Target",raceID=6,sex=2,classFile="DRUID"},
            level=44,gear={head=1},stats={HEALTH=1500},trees={{id="balance",name="Balance",points=1,talents={{762,nil,1}}}},
            honorableKills=12,pvpRank=2,reputations={{name="Faction",standing="Friendly",value=12,max=100}},
            notes="SECRET",history={{kind="death",name="SECRET"}}}}}
    assert(a.g.Publish(record))
    flush()
    for _,peer in ipairs({a,b}) do assert(#peer.GL.errors==0,peer.GL.errors[1] and peer.GL.errors[1].text) end
    local p=assert(b.GL.ArmoryProfile(identity),"shared profile missing")
    assert(p.gear.head.id==100 and p.identity.raceID==6 and p.trees[1].talents[1][3]==1)
    assert(p.honorableKills==12 and p.reputations[1].value==12 and p.stats.HEALTH==1500)
    assert(p.provenance.gear.by==a.id and not p.notes and not p.history and not b.GL.Get(identity))
    assert(b.GL.db.armoryRequests[identity.key.."|public target"],"received cards enqueue the automatic Armory fallback")
    b.GL.OpenPlayerDossier(identity.guid,nil,"Public Target","gear")
    assert(b.env.GrudgeLedgerPlayerDossier.equipment.equipment.buttons[1].itemName=="Helmet")
    assert(#b.GL.errors==0,b.GL.errors[1] and b.GL.errors[1].text)
    -- Local newer data wins, but a missing section still comes from a peer.
    b.env.GrudgeLedgerArmory={profiles={[identity.guid]={updated=now+1,gear={chest={id=200,name="Chest",ref="item:200"}},stats={HEALTH=2000}}}}
    p=b.GL.ArmoryProfile(identity)
    assert(p.stats.HEALTH==2000 and p.gear.head.id==100 and p.gear.chest.id==200 and p.trees[1].points==1)
    -- Reload retains the public cache; a second peer fills data with the original author offline.
    local saved=b.GL.db
    a.online=false
    b=client(2,saved);flush()
    assert(b.GL.ArmoryProfile(identity).gear.head.id==100)
    local c=client(3)
    -- Card editions deliberately require their original author to be online.
    -- Give C its already-received card, then exercise offline dossier relay.
    local scope=c.GL.Bounties.GuildScope()
    local existing=b.GL.Bounties.GuildScope().journal
    scope.journal={cards=existing.cards,hidden={},withdrawn={},secrets={},seq=0}
    c.GL.SharedDossiers.Refresh();flush()
    assert(c.GL.ArmoryProfile(identity).gear.head.id==100)
    -- New partial observations fill another slot without erasing previously received gear.
    a.online=true;now=now+301
    a.env.GrudgeLedgerArmory.profiles[identity.guid].updated=now
    a.env.GrudgeLedgerArmory.profiles[identity.guid].gear={chest={id=300,name="New chest",ref="item:300"}}
    b.GL.SharedDossiers.Refresh();flush()
    p=b.GL.ArmoryProfile(identity)
    assert(p.gear.head.id==100 and p.gear.chest.id==300)
    -- An oversized optional achievement list must not block essential equipment data.
    local huge={}
    for i=1,256 do huge[i]={id=i,name=string.rep("Long public achievement ",40)} end
    a.env.GrudgeLedgerArmory.profiles[identity.guid].achievements=huge
    -- A dropped fragment preserves the last complete snapshot; the next periodic request repairs it.
    now=now+301
    a.env.GrudgeLedgerArmory.profiles[identity.guid].updated=now
    a.env.GrudgeLedgerArmory.profiles[identity.guid].stats={HEALTH=3333}
    a.drop=function(msg)return msg:match("^J;S2;P;[^;]+;[^;]+;[rt];2;") end
    b.GL.SharedDossiers.Refresh();flush()
    assert(b.GL.ArmoryProfile(identity).stats.HEALTH~=3333)
    a.drop=nil;now=now+301
    b.GL.SharedDossiers.Refresh();flush()
    assert(b.GL.ArmoryProfile(identity).stats.HEALTH==3333)
    assert(not b.GL.ArmoryProfile(identity).achievements)
    -- A contract without a shared journal card follows the same automatic path.
    local target="Player-1-abce"
    a.env.GrudgeLedgerArmory.profiles[target]={updated=now,identity={name="Other Target",faction="Horde"},gear={head=1},stats={HEALTH=800}}
    assert(a.GL.Bounties.Post(target,"Other Target",100))
    flush()
    assert(b.GL.ArmoryProfile({guid=target}).gear.head.id==100 and not b.GL.Get("guid:"..target))
    b.GL.SharedDossiers.Observe({guid=target,raceID=2,sex=2,class="HUNTER",level=40})
    assert(b.GL.ArmoryProfile({guid=target}).identity.raceID==2)
    -- Truncated, oversized, unrequested and hostile payloads cannot overwrite the last good snapshot.
    local before=p.gear.chest.id
    for _,msg in ipairs({"S2;P;"..identity.guid..";8;r;1;999;x", "S2;P;"..identity.guid..";9;r;1;1;s8:evilcode",
        "S2;P;Player-1-unknown;9;r;1;1;t0:", "S2;P;"..identity.guid..";9;r;1;1;|Texploit"}) do
        b.m.Fire("CHAT_MSG_ADDON","GLBounty1","J;"..msg,"GUILD",a.name)
    end
    assert(b.GL.ArmoryProfile(identity).gear.chest.id==before)
    -- Visibility and guild boundaries also govern cached dossiers.
    b.g.HideTarget(identity.guid)
    assert(not b.GL.ArmoryProfile(identity))
    b.g.HideTarget(identity.guid,true);flush()
    assert(b.GL.ArmoryProfile(identity))
    b.m.units.player.guild="Elsewhere"; b.guild="Elsewhere"; b.m.Fire("PLAYER_GUILD_UPDATE")
    assert(not b.GL.ArmoryProfile(identity))
    for _,p in ipairs(clients) do assert(#p.GL.errors==0,p.GL.errors[1] and p.GL.errors[1].text) end
end
-- Social testimony is opt-in, attributed to its actual sender and never a personal record.
do
    clients,wire={},{}
    local a,b=client(1),client(2)
    flush()
    local identity=a.GL.IdentityFromName("Social","Target","Player-1-cafe")
    local record=a.GL.RecordAggression(identity,"confirmed","SECRET evidence","social-attack")
    now=now+60
    local _,death=a.GL.RecordPvP(identity,"death","confirmed","SECRET reason","social-death",nil,nil,true)
    a.GL.AddNote(identity,"SECRET personal note")
    assert(record.reputation==-11 and a.g.Publish(record))
    flush()
    assert(#b.GL.SharedDossiers.SocialReports(identity.guid)==0,"social sharing defaults off")
    assert(not next(b.GL.Bounties.GuildScope().socialReports or {}),"never-enabled clients do not send empty social reports")
    a.env.SlashCmdList.GRUDGELEDGER("settings")
    local settings=a.env.GrudgeLedgerSettings
    click(settings.tabs.relations)
    settings.shareSocial:SetChecked(true)
    click(settings.shareSocial)
    assert(a.GL.SharedDossiers.SharingSocial())
    flush()
    local report=assert(b.GL.SharedDossiers.SocialReports(identity.guid)[1])
    assert(report.actor==a.id and report.score==-11 and report.relation=="enemy")
    assert(#report.events==2 and report.events[1].time==death.time and report.events[1].killingBlow==1)
    assert(not report.events[1].evidence and not report.events[1].reason and not b.GL.Get(identity))
    -- Our own opinion and notes remain independent of this testimony.
    local mine=b.GL.Remember(identity)
    b.GL.AddNote(identity,"SECRET my note")
    b.GL.OpenPlayerDossier(identity.guid)
    local dossier=b.env.GrudgeLedgerPlayerDossier
    click(dossier.tabs.relations)
    local rendered={}
    for _,row in ipairs(dossier.rows) do if row:IsShown() then rendered[#rendered+1]=row.caption:GetText().." "..row.amount:GetText() end end
    local content=table.concat(rendered,"\n")
    assert(content:find("-11",1,true) and content:find("Member1",1,true) and content:find("Social Target",1,true),content)
    assert(mine.reputation==0 and #mine.history==0 and mine.notes[1].text=="SECRET my note")
    b=client(2,b.GL.db);flush()
    assert(b.GL.SharedDossiers.SocialReports(identity.guid)[1].score==-11,"testimony survives reload")
    assert(a.GL.VoidPvP(identity,death,false,"SECRET correction"))
    now=now+31; a.GL.SharedDossiers.Refresh(); flush()
    report=b.GL.SharedDossiers.SocialReports(identity.guid)[1]
    assert(report.score==-1 and #report.events==1,"correction replaces the snapshot, including duplicated transport")
    -- Only the author can publish their testimony, even when public data is relayed.
    a.online=false
    local c=client(3)
    local scope=c.GL.Bounties.GuildScope()
    scope.journal={cards=b.GL.Bounties.GuildScope().journal.cards,hidden={},withdrawn={},secrets={},seq=0}
    c.GL.SharedDossiers.Refresh();flush()
    assert(#c.GL.SharedDossiers.SocialReports(identity.guid)==0,"peers cannot impersonate an offline witness")
    a.online=true
    for i=1,40 do now=now+1; a.GL.RecordAggression(identity,"confirmed",nil,"social-extra-"..i) end
    now=now+31
    local old={}
    a.drop=function(msg) if msg:match("^J;S2;P;") then old[#old+1]=msg end; return false end
    a.GL.SharedDossiers.Refresh();flush();a.drop=nil
    assert(#b.GL.SharedDossiers.SocialReports(identity.guid)[1].events==32)
    now=now+31; a.GL.SharedDossiers.ShareSocial(false);flush()
    assert(#b.GL.SharedDossiers.SocialReports(identity.guid)==0,"turning sharing off withdraws the report")
    now=now+11
    for _,msg in ipairs(old) do b.m.Fire("CHAT_MSG_ADDON","GLBounty1",msg,"GUILD",a.name) end
    assert(#b.GL.SharedDossiers.SocialReports(identity.guid)==0,"late packets cannot resurrect withdrawn testimony")
    -- Invalid fields cannot overwrite the last good author sequence or forge another author.
    local target=identity.guid
    local function packet(score)
        local body="t1:s6:socialt5:s2:atn10:"..now.."s5:scoren"..#tostring(score)..":"..score..
            "s8:relations5:enemys6:eventst0:s5:actors11:Player-1-a9"
        return "J;S2;P;"..target..";"..(now*1000)..";t;1;1;"..body
    end
    b.m.Fire("CHAT_MSG_ADDON","GLBounty1",packet(101),"GUILD",a.name)
    assert(#b.GL.SharedDossiers.SocialReports(target)==0)
    b.m.Fire("CHAT_MSG_ADDON","GLBounty1",packet(-3),"GUILD",a.name)
    assert(b.GL.SharedDossiers.SocialReports(target)[1].actor==a.id)
    for _,p in ipairs(clients) do assert(#p.GL.errors==0,p.GL.errors[1] and p.GL.errors[1].text) end
end
print("PASS guild profiles and dossiers: public data, opt-in social facts, provenance, corrections, bounded history, reload, privacy, relay, malformed messages and guild isolation")
