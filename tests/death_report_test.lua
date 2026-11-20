-- Death report (study, section 7): damage by source and spell, killing blow, length of the fight,
-- our own specialization at the fight, and a text export for an AI without any player name.
local mock=assert(loadfile(TEST_WORK.."/tests/addon_mock.lua"))()
local GL=GrudgeLedger
local now=1794400000
time=function() return now end
GetServerTime=function() return now end
local D=GL.DeathReport
local me=mock.units.player.guid
local id=GL.IdentityFromName("Narcis","Ombreame","Player-9-00DD")
id.class,id.className="WARLOCK","Démoniste"
local guid=id.guid

-- Our talents, first with the older signature (name, icon, points).
GetNumTalentTabs=function() return 3 end
GetTalentTabInfo=function(i) return ({"Arcanes","Feu","Givre"})[i],"icon",({0,5,31})[i] end
local rows={
    {kind="SPELL_DAMAGE",at=100,src=guid,dst=me,spell="Corruption",amount=300},
    {kind="SWING_DAMAGE",at=102,src=guid,dst=me,amount=120},
    {kind="SPELL_DAMAGE",at=101,src=me,dst=guid,spell="Éclair de givre",amount=250},
    {kind="SPELL_DAMAGE",at=103,src="Player-1-friend",dst=me,from="Complice",spell="Frappe",amount=200},
    {kind="SPELL_DAMAGE",at=105,src=guid,dst=me,spell="Trait de l'ombre",amount=380,fatal=true},
}
local record,death=GL.RecordPvP(id,"death","confirmed","fixture","death-1",
    {healthPct=85,opponents=2,opponentLevel=38,playerLevel=36},{live=rows})
assert(death and death.build.me.spec=="0/5/31" and death.build.me.specName=="Givre","our specialization is kept")

local text=assert(D.Text(death,guid,"Narcis Ombreame"))
for _,part in ipairs({"Rapport de mort","Durée : 5 s · vie au début : 85 % · adversaires : 2","Dégâts reçus : 1000",
    "  Narcis Ombreame : 800 (Trait de l'ombre 380, Corruption 300, Attaque de mêlée 120)","  Complice : 200 (Frappe 200)",
    "Coup fatal : Trait de l'ombre 380 par Narcis Ombreame","ne sont pas relevés"}) do
    assert(text:find(part,1,true),part.."\n"..text)
end
assert(not text:find("250",1,true),"our own damage is not damage received")

-- A second death, without a blow-by-blow, and a kill that is not exported.
GetTalentTabInfo=function(i) return 100+i,({"Arcanes","Feu","Givre"})[i],"desc","icon",({31,0,0})[i] end
now=now+3600
local _,second=GL.RecordPvP(id,"death","confirmed","fixture","death-2",{opponentLevel=39,playerLevel=37})
assert(second.build.me.specName=="Arcanes","the newer GetTalentTabInfo signature is read too")
assert(D.Text(second,guid,"Narcis"):find("Aucun déroulé enregistré",1,true))
now=now+60
GL.RecordPvP(id,"kill","confirmed","fixture","kill-1",{opponentLevel=39,playerLevel=37})

local export,count=D.Export()
assert(count==2,"two deaths, the kill is left out")
assert(not export:find("Narcis",1,true) and not export:find("Ombreame",1,true) and not export:find("Complice",1,true),
    "the export names no player")
for _,part in ipairs({"Question : ","Morts : 2 · tueurs par classe : Démoniste 2","1. ","2. ","Tueur : Démoniste",
    "Moi : niv. 42","le tueur : 800","autre joueur : 200","Coup fatal : Trait de l'ombre 380 par le tueur",
    "Aucun déroulé enregistré pour ce combat.","Mon personnage : niv. 42 · Arcanes 31/0/0"}) do
    assert(export:find(part,1,true),part.."\n"..export)
end
assert(export:find("2. ",1,true)>export:find("1. ",1,true))

-- The fight detail shows the report; the sheet and the Bilan offer the export.
GL.InspectEvent(record,death)
local detail=GrudgeLedgerCorrections
assert(detail:IsShown() and detail.proof:GetText():find("Rapport de mort",1,true),detail.proof:GetText())
detail:Hide()
local function click(b) b.scripts.OnClick(b,"LeftButton") end
assert(GL.OpenPlayerDossier(guid,nil,nil,"combat"))
local f=GrudgeLedgerPlayerDossier
-- The export is a quiet row action under the dated fights, not a large button.
local export
for _,r in ipairs(f.rows) do
    if r:IsVisible() and r.amount:GetText()=="Exporter" then export=r end
end
assert(export and export.caption:GetText():find("pour une IA",1,true))
click(export)
local w=GrudgeLedgerDeathExport
assert(w:IsShown() and w.box:GetText()==D.Export(guid) and w.box.highlighted==w.box:GetText() and w.box.focus)
w:Hide()
assert(GL.OpenPlayerDossier("Player-9-00EE",nil,"Nobody","combat"))
for _,r in ipairs(f.rows) do
    assert(not (r:IsVisible() and r.amount:GetText()=="Exporter"),"no export without deaths")
end
GL.ShowJournal("summary")
assert(GrudgeLedgerJournal.exportDeaths:IsShown())
GL.ShowJournal("history")
assert(not GrudgeLedgerJournal.exportDeaths:IsShown())
assert(#GL.errors==0,(GL.errors[1] or {}).text)
print("PASS death report: damage by source and spell, killing blow, duration, our specialization (both signatures), "
    .."export without player names, detail window, sheet and Bilan buttons")
