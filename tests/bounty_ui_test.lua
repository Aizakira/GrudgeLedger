-- Exercise the published UI entry points with real engine records and native-frame fixtures.
local mock=assert(loadfile(TEST_WORK.."/tests/wow_mock.lua"))()
local now=1800000000
GetServerTime=function() return now end
GetNormalizedRealmName=function() return "Realm" end
mock.units.player.guild="Test Guild"
for _,name in ipairs({"Core","UITheme","UI","Bounties","DossierEquipment","PlayerDossier","BountyUI"}) do
    assert(loadfile(TEST_ROOT.."/"..name..".lua"))("GrudgeLedger")
end
local GL=GrudgeLedger
GL.InitDB()
local function click(b)
    assert(b:IsVisible() and b:IsEnabled(),"unavailable button: "..b:GetText())
    b:GetScript("OnClick")(b,"LeftButton")
end
local function add(n)
    local p=GL.IdentityFromName(n,"Example","Player-42-"..n)
    p.level,p.race,p.class=53,"Tauren","DRUID"
    GL.Remember(p)
    return p
end
local a,b=add("Alpha"),add("Beta")
assert(GL.Bounties.Post(b.guid,b.fullName,10000))
local f=GL.OpenBounties()
click(f.new); f.search:SetText("Alpha")
assert(f.count==1 and f.rows[1].raceIcon and not f.target)
click(f.rows[1])
assert(not GrudgeLedgerPlayerDossier and f.rows[1].selected:IsShown() and f.form:IsVisible())
assert(f.form:IsShown() and f.target.guid==a.guid and f.form.quota:GetText()=="1")
assert(not f.form.equal:IsEnabled())
f.form.gold:SetText("120"); f.form.quota:SetText("3"); f.form.note:SetText("Screenshot for the guild.")
for _,pair in ipairs(f.form.options) do
    if pair.value=="party" or pair.value=="equal" or pair.value=="screenshot" then click(pair.control) end
end
click(f.form.publish)
local o=f.order
assert(o and o.target==a.guid and o.quota==3 and o.group=="party" and o.split=="equal" and o.souvenir=="screenshot")
assert(o.pot[o.owner]==1200000 and o.note=="Screenshot for the guild.")
assert(f.detail.progress:GetText():find("0/3",1,true) and not f.form:IsShown())
click(f.tools.pledge); f.editor.field:SetText("3"); click(f.editor.ok)
assert(f.order.pot[o.owner]==1230000)
click(f.tools.note); f.editor.field:SetText("New instructions"); click(f.editor.ok)
assert(f.detail.note:GetText()=="New instructions")
now=now+60; click(f.tools.renew); assert(f.order.expires>o.expires)
f.search:SetText("BeTa"); assert(f.count==1 and f.order.target==b.guid)
click(f.rows[1])
assert(f:IsShown() and f.order.target==b.guid and not f.detail.dossier)
click(f.detail.face)
assert(not f:IsShown() and GrudgeLedgerPlayerDossier:IsShown())
local dossier=GrudgeLedgerPlayerDossier
dossier.onReturn()
assert(f.search:GetText()=="BeTa" and f.order.target==b.guid and f:IsShown())
f.search:SetText(""); click(f.tools.pin)
click(f.filter); click(f.filterChoices[2])
assert(f.count==1 and f.order.target==b.guid)
click(f.new)
f.search:SetText("Alpha")
assert(f.count==1)
click(f.rows[1]); assert(f.target.guid==a.guid)
f.form.gold:SetText("1"); f.form.quota:SetText("100"); click(f.form.publish)
assert(f.form:IsShown() and f.feedback:GetText():find("99",1,true))
f.form.quota:SetText("1"); click(f.form.publish)
assert(f.form:IsShown() and f.feedback:GetText():find("déjà",1,true))
click(f.form.cancel)
GL.OpenBounties(a.guid,"view"); click(f.tools.withdraw); click(f.editor.cancel)
assert(f.order.state=="open")
click(f.tools.withdraw); click(f.editor.ok)
assert(f.tab=="history" and f.order.target==a.guid and f.order.state=="withdrawn")
click(f.activeTab)
assert(f.order.target==b.guid and f.count==1)
mock.units.player.guild=nil
mock.Fire("PLAYER_GUILD_UPDATE"); f:GetScript("OnUpdate")(f,0.016)
assert(not f.order and f.empty:GetText():find("guilde",1,true))
click(f.historyTab); assert(f.order.target==a.guid and f.order.state=="withdrawn")
mock.units.player.guild="Test Guild"
mock.units.party1={guid="Player-77-Helper",name="Helper",surname="Example"}
GetNumGroupMembers=function() return 2 end
UnitIsVisible=function(unit) return UnitExists(unit) end
GL.Bounties.Kill(b.guid)
GL.OpenBounties(b.guid,"view")
assert(f.order.state=="fulfilled" and f.tab=="history" and f.detail.kicker:GetText():find("Prime faite",1,true))
assert(f.detail.people[2].guid=="Player-77-Helper" and f.detail.payment:GetText():find("50 pa",1,true))
click(f.filter); click(f.filterChoices[4]); assert(f.count==1)
assert(GL.Bounties.ConfirmPayment(f.order.id,"Player-77-Helper",5000))
f:GetScript("OnUpdate")(f,0.016)
assert(f.count==0 and not f.detail:IsShown())
click(f.filter); click(f.filterChoices[5]); assert(f.order.state=="paid" and f.count==1)
for i=1,8 do
    local person=add("Test"..i); assert(GL.Bounties.Post(person.guid,person.fullName,0))
end
GL.OpenBounties()
assert(f.count==8 and f.next:IsEnabled() and not f.prev:IsEnabled()); click(f.next)
assert(f.offset==2 and not f.next:IsEnabled())
click(f.prev); assert(f.offset==0)
-- Expiry moves an issued order to history. Repost keeps rules and the issuer's own pledge only.
local fresh=f.order
assert(fresh and fresh.state=="open"); GL.OpenBounties(a.guid,"create")
f.form.gold:SetText("120"); f.form.quota:SetText("3"); f.form.note:SetText("Keep a screenshot")
for _,pair in ipairs(f.form.options) do
    if pair.value=="party" or pair.value=="equal" or pair.value=="screenshot" then click(pair.control) end
end
click(f.form.publish)
local old=f.order
local issuer=mock.units.player.guid
mock.units.player.guid="Player-77-Partner"; assert(GL.Bounties.Pledge(old.id,50000))
mock.units.player.guid=issuer
click(f.historyTab); f.search:SetText("Alpha")
assert(f.count==1 and f.order.id~=old.id)
now=old.expires+1
f:GetScript("OnUpdate")(f,1.1)
assert(f.count==2,"history must gain expired contracts while it stays open")
click(f.activeTab); f.search:SetText("Alpha"); assert(f.count==0)
click(f.historyTab); f.search:SetText("Alpha")
for _,r in ipairs(f.rows) do if r.entry and r.entry.id==old.id then click(r); break end end
assert(f.order.id==old.id and f.order.state=="expired" and f.detail.repost:IsVisible())
click(f.detail.repost); click(f.form.cancel)
assert(f.tab=="history" and f.order.id==old.id)
click(f.detail.repost)
assert(f.form:IsVisible() and f.target.guid==a.guid and f.form.gold:GetText()=="120" and f.form.quota:GetText()=="3")
assert(f.draft.group=="party" and f.draft.split=="equal" and f.draft.souvenir=="screenshot" and f.form.note:GetText()=="Keep a screenshot")
click(f.form.publish)
assert(f.order.id~=old.id and f.order.state=="open" and f.order.pot[issuer]==1200000 and not f.order.pot["Player-77-Partner"])
assert(GL.Bounties.History()[old.id].state=="expired" and GL.Bounties.Progress(f.order)==0)
print("PASS bounty UI: create, target and dossier return, rules, contribution, search, paging, update, hunt finished, history, payout states and guild change")
