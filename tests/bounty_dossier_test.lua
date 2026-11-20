-- Bounty dossier per target (study, section 8): kept after the 38-day rotation of guild events,
-- shown in the sheet, and the guild's opinions member by member in Relations.
local mock=assert(loadfile(TEST_WORK.."/tests/addon_mock.lua"))()
local GL=GrudgeLedger
local now=1794400000
time=function() return now end
GetServerTime=function() return now end
GetNormalizedRealmName=function() return "Forever" end
mock.units.player.guild="Fixture Guild"
local B=GL.Bounties
local me=mock.units.player.guid
local target="Player-9-00F1"
local DAY=86400

-- A first contract, filled by us and honored, then a second one that expires.
assert(B.Post(target,"Wanted Rogue",600000))
local r=B.TargetRecord(target)
assert(r.count==1 and r.orders[1].state=="open" and r.promised==600000,"a live order is in the dossier")
now=now+2*3600
B.Kill(target)
r=B.TargetRecord(target)
assert(r.killed==1 and r.orders[1].hunter==me and r.orders[1].killedAt==now,"the hunter and the date are kept")
assert(r.completed==1 and r.honored==1 and r.orders[1].state=="paid",r.orders[1].state)
now=now+60
assert(B.Post(target,"Wanted Rogue",0))
now=now+8*DAY
r=B.TargetRecord(target)
assert(r.count==2 and r.expired==1 and r.orders[1].state=="expired","an unfilled order expires")

-- The guild log rotates away after 38 days: the dossier survives.
local scope=B.GuildScope()
assert(scope.bountyRecords and scope.bountyRecords[target],"the compact record is saved in the guild space")
scope.events={}
now=now+40*DAY
r=B.TargetRecord(target)
assert(r.count==2 and r.killed==1 and r.expired==1 and r.honored==1,"the dossier outlives the event log")
assert(r.orders[2].state=="paid" and r.orders[1].state=="expired")

-- Another member's opinion and fights; our own score stays out of the guild rows.
GL.SharedDossiers.SocialReports=function(guid)
    if guid~=target then return {} end
    return {{actor="Player-1-ally",score=-11,relation="enemy",authorName="Ally Member",at=now,events={}}}
end
scope.scores=scope.scores or {}
scope.scores[target]={["Player-1-ally"]={0,4},[me]={1,0}}
local memberName=B.MemberName
B.MemberName=function(id) return id=="Player-1-ally" and "Ally Member" or memberName(id) end

local function click(b) b.scripts.OnClick(b,"LeftButton") end
assert(GL.OpenPlayerDossier(target,nil,"Wanted Rogue","combat"))
local f=GrudgeLedgerPlayerDossier
local function all()
    local visible={}
    for _,row in ipairs(f.rows) do
        if row:IsVisible() then visible[#visible+1]=row.caption:GetText().." "..row.amount:GetText() end
    end
    return table.concat(visible,"\n")
end
assert(all():find("Mis à prix 2 fois · 60 PO promis",1,true),all())
assert(all():find("Tué 1 fois · 1 expirée · contrats honorés 1/1",1,true),all())
assert(all():find("en 2 h · payée",1,true) and all():find("expirée sans victoire",1,true),all())
click(f.tabs.overview)
assert(all():find("Mis à prix 2 fois",1,true) and all():find("Aucune prime ouverte.",1,true),all())
assert(f.verdict:GetText():find("Guilde : -11 · 1 avis",1,true),f.verdict:GetText())

click(f.tabs.relations)
assert(f.filters.all:IsVisible() and f.filters.mine:IsVisible())
assert(all():find("Ally Member -11 · Ennemi · 0 V / 4 D",1,true),all())
assert(all():find("Total de la guilde -11 · 1 avis",1,true),all())
assert(all():find("Mise à prix créée",1,true),"old orders stay in the dated timeline")
click(f.filters.guild)
assert(not all():find("Mise à prix créée",1,true),"our own orders are not guild testimonies")
click(f.filters.mine)
assert(all():find("Mise à prix créée",1,true))
click(f.tabs.combat)
assert(not f.filters.all:IsVisible())
assert(#GL.errors==0,(GL.errors[1] or {}).text)
print("PASS bounty dossier: per-target record kept after rotation, filled, honored and expired counts, "
    .."sheet summary, guild opinions per member, Relations filter")
