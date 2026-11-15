-- Real book navigation and rows, with synthetic personal, public and guild observations.
local mock=assert(loadfile(TEST_WORK.."/tests/wow_mock.lua"))()
assert(loadfile(TEST_ROOT.."/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT.."/UITheme.lua"))()
assert(loadfile(TEST_ROOT.."/UI.lua"))()
for _,n in ipairs({"Bounties","DossierEquipment","DossierTalentData","DossierTalents","PlayerDossier"}) do assert(loadfile(TEST_ROOT.."/"..n..".lua"))() end
local GL=GrudgeLedger
GL.InitDB()
local guid="Player-1-00AB"
local id=GL.IdentityFromName("Fixture","Keeper",guid)
id.level=19
local record=GL.RecordPvP(id,"kill","confirmed","fixture","once",{opponentLevel=21,playerLevel=20})
GL.RecordSeen(id,true)
local cape={name="Woven mantle",id=50000,icon=130004,level={value=24},armor={value=31},bonus_list={42},
    stats={{type={type="STAMINA"},value=3}},enchantments={{display_string="Enchanted: +2 Nature"}},
    spells={{spell={name="Wind dance"},description=string.rep("Long description\n",40)}}}
GrudgeLedgerArmory={items={{name="Helm",icon=123},{name="Same ID, other variant",id=50000,
    spells={{description=string.rep("Second long effect\n",50)}}},cape},
    profiles={[guid]={gear={back=3,head=1,rightFinger=2},level=29,averageItemLevel=24,updated=1794455000000,
    trees={{name="Restoration",points=4,talents={{334,"Rejuvenation",2,160012}}},{name="Feral",points=0,talents={}}},
    honorableKills=396,pvpRank=0,stats={HEALTH=1721,AGILITY=99,CRITICALSTRIKE=5.629,DAMAGE={11,22}},
    battlegrounds={{name="Arathi",games=3,wins=2,losses=1}},
    reputations={{group="Alliance",name="Forge",standing="Amical",value=1200,max=6000}},achievements={{name="Account champion",accountWide=true,icon=777}}}}}
GL.InitDB()
assert(record.armorySnapshot.gear.back.name=="Woven mantle", "existing contacts keep their gear before first open")
local good = GrudgeLedgerArmory.profiles[guid]
record.class = "DRUID"
GrudgeLedgerArmory.profiles[guid] = {identity={classFile="WARRIOR"}, updated=good.updated+1}
assert(GL.ArmoryProfile(record,true)==record.armorySnapshot, "a conflicting class cannot replace the last known gear")
GrudgeLedgerArmory.profiles[guid] = good
record.class = nil
GrudgeLedgerPortraitIndex={[guid]=true}
mock.units.player.guild="Fixture Guild"
GL.Bounties.GuildFights=function(target) assert(target==guid) return 3,5 end
local returned=false
assert(GL.OpenPlayerDossier(guid,function() returned=true end))
local f=GrudgeLedgerPlayerDossier
local function click(b) b.scripts.OnClick(b,"LeftButton") end
local function all()
    local visible={}
    for _,r in ipairs(f.rows) do if r:IsVisible() then visible[#visible+1]=r.caption:GetText().." "..r.amount:GetText() end end
    return table.concat(visible,"\n")
end
assert(f:IsShown() and f.navigation.ledger.active and f.nameLabel:GetText()==record.fullName)
local summary=f.observed:GetText()
assert(summary:find("Niveau Armurerie : 29",1,true))
assert(summary:find("Niveau adverse au combat : 21",1,true) and summary:find("Votre niveau au combat : 20",1,true))
assert(record.level==19 and record.history[1].combat.opponentLevel==21)
local cells={}
for _,c in ipairs(f.statCells) do if c:IsVisible() then cells[c.label:GetText()]=c.value:GetText() end end
assert(cells.Vie=="1721" and cells["Agilité"]=="99" and cells["Coup critique"]=="5,6 %" and cells["Dégâts"]=="11 – 22")
local eq=f.equipment.equipment
assert(f.equipment:IsVisible() and not f.scroll:IsVisible() and #eq.buttons==19)
local b=eq.buttons[4]
assert(b.itemName=="Woven mantle" and b.item==cape and not b:GetScript("OnClick"))
local details=b.itemDetails(b.item)
for _,s in ipairs({"31","Endurance","Enchanted: +2 Nature","Wind dance","Long description","42","50000"}) do assert(details:find(s,1,true),s) end
assert(eq.buttons[14].itemName=="Same ID, other variant")
click(f.tabs.talents)
assert(not f.equipment:IsVisible() and f.talents:IsVisible() and not f.scroll:IsVisible())
click(f.tabs.pvp)
assert(all():find("396",1,true) and all():find("Rang JcJ 0",1,true) and all():find("Account champion (compte)",1,true))
assert(all():find("Arathi 3 parties · 2 V / 1 D",1,true))
assert(all():find("1 / 0",1,true) and all():find("3 / 5",1,true))
click(f.tabs.reputation)
assert(all():find("Forge Amical · 1200 / 6000",1,true) and not all():find("Arathi",1,true))
click(f.back)
assert(returned and not f:IsShown())
-- Guild-only targets and missing archive rows must never create a personal journal entry.
mock.units.player.guild=nil
local other="Player-42-000B"
assert(GL.OpenPlayerDossier(other,nil,"Other | captain"))
assert(f.nameLabel:GetText()=="Other || captain" and not GL.Get("guid:"..other))
assert(not eq.buttons[4].item and not f.statCells[1]:IsShown() and not f.observed:GetText():find("21",1,true))
GrudgeLedgerArmory.profiles[other]={identity={name="Public name",class="Hunter",race="Orc",faction="Horde",guild="Archive guild"},gear={back=999}}
assert(GL.OpenPlayerDossier(other))
assert(f.nameLabel:GetText()=="Public name" and f.identity:GetText():find("Orc · Hunter · Horde",1,true))
assert(eq.buttons[4].hasVariant and not eq.buttons[4].item)
local known=0
GL.OpenContactBounty=function(g) assert(g==other); known=known+1 end
click(f.bounty); assert(known==1)
click(f.tabs.pvp)
assert(all():find("Aucune rencontre personnelle enregistrée",1,true))
assert(not GL.OpenPlayerDossier("|Tbad"))
-- A same-faction chat contact has no unit token or GUID. Exercise the Journal
-- button, then remove the import module as would happen on the next login.
GetCurrentRegion=function() return 3 end
local named=GL.SetReaction(GL.IdentityFromName("Named","Friend"),"enemy")
local imported={alias=named.key,region="eu",characterHex="2a",level=32,updated=100,
    identity={race="Gnome",class="Mage",faction="Alliance"},stats={HEALTH=123},gear={back=3},
    trees={{name="Frost",points=2,talents={}}}}
GrudgeLedgerArmory.profiles["eu:"..named.key]=imported
GL.SetReaction(named, "enemy")
assert(named.armorySnapshot and named.armorySnapshot.stats.HEALTH==123, "manual opinion saves the loaded profile even with the book closed")
GL.Settings().guideSeen=true
GL.ShowLedger(named.key)
assert(GrudgeLedgerWindow.detailIdentity:GetText():find("Gnome",1,true))
click(GrudgeLedgerWindow.detailTabs.dossier)
assert(f:IsShown() and f.nameLabel:GetText()=="Named Friend" and eq.buttons[4].itemName=="Woven mantle")
assert(GL.Relation(named)=="enemy" and named.armorySnapshot.gear.back.name=="Woven mantle")
local broken={}
for key,value in pairs(imported) do broken[key]=value end
broken.gear={back=999}
GrudgeLedgerArmory.profiles["eu:"..named.key]=broken
assert(GL.ArmoryProfile(named,true)==named.armorySnapshot and GL.ArmoryItem(named,"back").name=="Woven mantle")
GrudgeLedgerArmory.profiles["eu:"..named.key]={alias=named.key,region="eu",characterHex="2a",updated=101,gear={}}
assert(GL.ArmoryProfile(named)==named.armorySnapshot)
GrudgeLedgerArmory=nil
assert(GL.OpenPlayerDossier(named.key) and f.statCells[1].value:GetText()=="123" and eq.buttons[4].itemName=="Woven mantle")
assert(GL.ArmoryProfile(named).trees[1].points==2)
GetCurrentRegion=function() return 1 end
assert(not GL.ArmoryProfile(named))
GetCurrentRegion=function() return 3 end
assert(GL.ArmoryProfile({fullName=named.fullName,guid="Player-9-00002A",armorySnapshot=named.armorySnapshot}))
local promoted=GL.Remember(GL.IdentityFromName("Named","Friend","Player-9-00002B"))
assert(GL.Relation(promoted)=="enemy" and not GL.ArmoryProfile(promoted))
assert(GL.OpenPlayerDossier("Player-42-00CA",nil,"Guild Contact"))
assert(GL.db.armoryRequests["guid:Player-42-00CA|guild contact"]==GL.Now())
assert(not GL.Get("guid:Player-42-00CA"),"requesting a guild dossier must not add it to the journal")
print("PASS dossier: exact item variants, canonical slots, long effects, talents, provenance, private vs guild scores, guild-only identity and return")
