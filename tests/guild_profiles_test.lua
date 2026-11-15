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
        wire[#wire+1]={prefix,msg,channel,c.name,c.guild}
        return 0
    end
    env.C_Timer={NewTicker=function(delay,fn) if delay==0.5 then c.tick=fn end; return {Cancel=function() end} end}
    mock.Fire("PLAYER_LOGIN")
    for _,p in ipairs(clients) do if p.online then p.m.Fire("GUILD_ROSTER_UPDATE") end end
    return c
end
local function flush()
    for _=1,400 do
        now=now+1
        for _,p in ipairs(clients) do if p.online then p.tick() end end
        if #wire==0 then return end
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
print("PASS guild profiles: private attribution, journal actions, disagreements, withdrawals, reloads, offline witnesses, replay, re-publication and guild isolation")
