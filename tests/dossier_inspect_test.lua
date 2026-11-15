-- A fresh opponent, delayed inspect, open journal, then loss of the original unit token.
local mock=assert(loadfile(TEST_WORK.."/tests/wow_mock.lua"))()
local now,requests,callbacks=1000,0,{}
GetServerTime=function() return now end
C_Timer={After=function(delay,fn) callbacks[#callbacks+1]={at=now+delay,fn=fn} end}
local function advance(seconds)
    for _=1,seconds do
        now=now+1
        for i=#callbacks,1,-1 do
            if callbacks[i].at<=now then table.remove(callbacks,i).fn() end
        end
    end
end
local target=mock.units.target
target.guid="Player-9-00AB"
local guid=target.guid
UnitIsVisible=UnitExists
UnitHealthMax=function() return 1933 end
UnitPowerType=function() return 0,"MANA" end
UnitPowerMax=function() return 1894 end
UnitArmor=function() return 0,mock.secret end
CanInspect=function() return true end
NotifyInspect=function(unit) assert(UnitGUID(unit)==guid); requests=requests+1 end
GetInventorySlotInfo=function(name) if name=="HeadSlot" then return 1,123 end end
local link="|cff0070dd|Hitem:42:9:-12|h[Heaume]|h|r"
local ready=false
GetCurrentRegion=function() return 3 end
GetLocale=function() return "frFR" end
GetInventoryItemLink=function(_,id) if ready and id==1 then return link end end
C_PaperDollInfo={GetInspectItemLevel=function() return 33 end}
for _,name in ipairs({"Core","UITheme","UI","DossierEquipment","DossierTalentData","DossierTalents","DossierInspect","PlayerDossier"}) do
    assert(loadfile(TEST_ROOT.."/"..name..".lua"))("GrudgeLedger")
end
local GL=GrudgeLedger
GL.InitDB()
local node=GL.DossierTalentData.MAGE[1].nodes[1]
Constants={TraitConsts={INSPECT_TRAIT_CONFIG_ID=-1}}
C_Traits={
    HasValidInspectData=function() return true end,
    GetConfigInfo=function(id) assert(id==-1); return {treeIDs={77}} end,
    GetTreeNodes=function() return {2} end,
    GetNodeInfo=function() return {activeEntry={entryID=3},ranksPurchased=2} end,
    GetEntryInfo=function() return {definitionID=node[1]} end,
}
GL.VisiblePortraitUnit=function(record)
    if UnitGUID("target")==record.guid then return "target" end
end
local identity=GL.Identity("target")
GL.InspectDossierUnit("target",guid)
assert(requests==1 and not GL.Get(identity),"precombat capture must not create contacts")
local record=GL.RecordPvP(identity,"death","confirmed","fixture","hit")
assert(record.inspection.stats.HEALTH==1933 and record.inspection.stats.MANA==1894 and not record.inspection.stats.ARMOR)
assert(GL.OpenPlayerDossier(guid))
local f=GrudgeLedgerPlayerDossier
assert(f.source:GetText():find("Inspection en cours",1,true))
assert(f.armoryURL=="https://worldofwarcraft.blizzard.com/fr-fr/forever/eu/armory/character/aqua-water")
mock.Fire("INSPECT_READY","Player-9-00CD")
assert(not record.inspection.trees and requests==1)
advance(3)
assert(requests==2,"dropped inspect must retry while the target is valid")
ready=true
advance(1)
mock.Fire("INSPECT_READY",guid)
assert(record.inspection.gear[1]==link and record.inspection.trees[1].points==2)
assert(f.source:GetText():find("Inspection en jeu",1,true) and f.ilvl:GetText():find("33",1,true))
local head=f.equipment.equipment.buttons[1]
assert(head.itemName=="Heaume" and head.inspectedLink==link,"open sheet must repaint without reopening")
local inserted
IsModifiedClick=function() return true end
ChatEdit_InsertLink=function(v) inserted=v end
head:GetScript("OnClick")(head,"LeftButton")
assert(inserted==link,"native item variant must survive")
mock.units.target=nil
advance(30)
assert(requests==2 and GL.OpenPlayerDossier(guid) and head.itemName=="Heaume")
local other="Player-9-00EF"
mock.units.target={name="Other",surname="Player",guid=other}
CanInspect=function() return false end
assert(GL.OpenPlayerDossier(other))
assert(not GL.Get("guid:"..other) and head.inspectedLink==link,"visible cached links work without inspect permission")
mock.units.target=nil
assert(GL.OpenPlayerDossier("Player-9-0010") and not head.inspectedLink)
assert(not f.source:GetText():find("en cours",1,true),"unreachable players must not be shown as loading")
-- A new website snapshot supersedes an older inspection.
GrudgeLedgerArmory={items={{name="Armory helm"}},profiles={[guid]={gear={head=1},updated=1794455000000}}}
assert(GL.OpenPlayerDossier(guid) and not head.inspectedLink and head.itemName=="Armory helm")
-- A GUID-only kill starts an inspect while visible. A reused nameplate must never fill its victim's page.
local late="Player-9-000A"
mock.units.target={name="Late",surname="Arrival",guid=late}
CanInspect=function() return true end
NotifyInspect=function() requests=requests+1 end
ready=false
local lateRecord=GL.RecordPvP(GL.Identity("target"),"death","confirmed","fixture","late")
assert(requests==3 and lateRecord.inspection.stats.HEALTH==1933)
mock.units.target={name="Next",surname="Opponent",guid="Player-9-000B"}
ready=true
mock.Fire("INSPECT_READY",late)
advance(9)
assert(not lateRecord.inspection.trees and not lateRecord.inspection.gear and requests==3)
print("PASS dossier inspect: first contact, native gear/stats/talents visible at simulated t+4s after one lost reply, cached/out-of-range cases")
