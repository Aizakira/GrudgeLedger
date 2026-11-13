local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
getmetatable(UIParent).__index.HighlightText = function(self) self.highlighted = true end
function GetBuildInfo() return "1.16.0", "63690", "Nov 1 2026", 16001 end
C_AddOns = { IsAddOnLoaded = function(name) return name == "TidyPlates_ThreatPlates" end }
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
local GL = GrudgeLedger
GL.InitDB()
assert(not GrudgeLedgerCorrections and not GrudgeLedgerDiagnostic, "no automatic popup")
local function button(parent, text)
    for _, child in ipairs(parent.children) do if child.text == text and child.scripts.OnClick then return child end end
    error("missing button " .. text)
end
local function click(frame)
    assert(frame.enabled ~= false, "disabled button")
    assert(frame.scripts.OnClick)(frame, "LeftButton")
end
local first = GL.Identity("target")
local record = GL.Remember(first)
GL.AddNote(first, "PRIVATE note inside journal")
for i = 1, 8 do GL.RecordPvP(first, "death", "probable", "Déduction " .. i, "death" .. i) end
GL.RecordAggression(first, "confirmed", "Preuve directe |cff00ff00", "aggression")
local latest = record.history[#record.history]
local historyLength = #record.history
GL.ShowLedger(record.key)
local function openCorrections()
    click(GrudgeLedgerWindow.tools)
    assert(GrudgeLedgerWindow.toolsMenu:IsShown())
    click(button(GrudgeLedgerWindow.toolsMenu, "Corriger le PvP"))
end
openCorrections()
local history = GrudgeLedgerWindow.historyPage
assert(history.kind == "pvp" and history.total:GetText():find("sur 9",1,true))
assert(not GrudgeLedgerCorrections, "selecting the PvP filter does not prompt or change a counter")
click(history.rows[1].details)
local f = GrudgeLedgerCorrections
assert(f:IsShown() and f.topLevel and f.raised > 0)
assert(f.certainty:GetText() == "Confirmé" and f.proof:GetText():find("||cff00ff00",1,true))
assert(f.who:GetText() == record.fullName and f.event == latest and not latest.voided)
click(f.keep) assert(not f:IsShown() and not latest.voided, "Conserver leaves the event and statistics unchanged")
click(history.next) click(history.next)
assert(history.offset == 6 and history.rows[3].event.evidence == "Déduction 1")
click(history.prev) click(history.prev)
click(history.rows[1].details)
local originalUndo = f.confirm.scripts.OnClick
mock.units.target = { name = "Megumin", surname = "Crimson", guid = "Player-1-megumin" }
local other = GL.SetReaction(GL.Identity("target"), "friend")
GL.RecordPvP(other,"death","confirmed","Autre personne","otherdeath")
GL.ShowLedger(other.key)
click(f.confirm)
assert(latest.voided and record.pvp.aggressions == 0 and #record.history == historyLength)
assert(other.pvp.deaths == 1 and other.reaction == "friend", "selection cannot redirect the pending correction")
originalUndo()
assert(record.pvp.aggressions == 0, "stale callbacks cannot subtract twice")
assert(not GL.RecordAggression(first,"confirmed","same observation","aggression"))
GL.ShowLedger(record.key)
click(GrudgeLedgerWindow.detailTabs.history)
assert(history.rows[1].badge:GetText():find("Annulé",1,true))
click(history.rows[1].details)
assert(not f.confirm.enabled and f.effect:GetText():find("exclu",1,true))
click(f.keep)
assert(#record.notes == 1 and record.notes[1].text == "PRIVATE note inside journal")
GL.ShowLedger(other.key) openCorrections()
click(history.rows[1].details)
originalUndo()
assert(other.pvp.deaths == 1, "stale confirmation cannot mutate a newly presented event")
click(f.confirm)
assert(other.pvp.deaths == 0 and other.reaction == "friend" and other.reputation == 1)
local empty = GL.Remember(GL.IdentityFromName("Nobody","Else","Player-1-empty"))
GL.ShowLedger(empty.key) openCorrections()
assert(history.total:GetText() == "0 événement" and not history.rows[1]:IsShown() and history.rows[1].event == nil)

GL.SetGuildReaction("PRIVATE guild", "enemy", "PRIVATE guild note")
GL.errors = { { text = "PRIVATE raw error Aqua Player-1-aqua" }, { text = "PRIVATE more details" } }
GL.db.settings.unrelatedPrivateSetting = "PRIVATE hidden setting"
mock.cvars.nameplateShowFriendlyPlayers = 0
mock.cvars.nameplateShowEnemies = 1
mock.cvars.nameplateShowAll = "PRIVATE invalid CVar value"
SlashCmdList.GRUDGELEDGER("settings")
click(GrudgeLedgerSettings.tabs.data)
click(button(GrudgeLedgerSettings.pages.data, "Afficher le rapport"))
local d = GrudgeLedgerDiagnostic
local text = d.edit:GetText()
assert(d:IsShown() and d.edit.focus and d.edit.highlighted and d.topLevel)
assert(text:find("Client : 1.16.0", 1, true) and text:find("Build : 63690", 1, true) and text:find("Interface : 16001", 1, true))
assert(text:find("Intégration détectée : Threat Plates", 1, true))
assert(text:find("Erreurs conservées : 2", 1, true))
assert(text:find("markers : oui", 1, true) and text:find("CombatLogGetCurrentEventInfo : non", 1, true))
assert(text:find("nameplateShowFriendlyPlayers : 0", 1, true) and text:find("nameplateShowEnemies : 1", 1, true))
assert(text:find("nameplateShowAll : indisponible", 1, true), "only allowlisted boolean CVar values may be shared")
for _, forbidden in ipairs({ "PRIVATE", "Aqua", "Megumin", "Player-1-", "Déduction", "Autre personne", "Forever", "unrelatedPrivateSetting" }) do
    assert(not text:find(forbidden, 1, true), "diagnostic leaked " .. forbidden)
end
local messageCount = #mock.messages
local raised = d.raised
SlashCmdList.GRUDGELEDGER("debug")
assert(#mock.messages == messageCount and d.raised > raised, "debug opens safe report and never prints raw errors")
d.edit.highlighted = false
click(button(d, "Tout sélectionner"))
assert(d.edit.highlighted)
C_AddOns.IsAddOnLoaded = function() return true, false end
SlashCmdList.GRUDGELEDGER("debug")
assert(d.edit:GetText():find("Intégration détectée : aucune", 1, true), "loading but not loaded is not an active integration")
GetBuildInfo = function() error("PRIVATE API failure") end
C_AddOns, IsAddOnLoaded = nil, nil
GL.Settings().markers = false
SlashCmdList.GRUDGELEDGER("debug")
text = d.edit:GetText()
assert(text:find("Client : indisponible", 1, true) and text:find("markers : non", 1, true))
assert(not text:find("PRIVATE", 1, true) and #GL.errors == 2, "unavailable metadata fails quietly without raw details")
GetBuildInfo = function() return mock.secret, mock.secret, "PRIVATE build date", mock.secret end
SlashCmdList.GRUDGELEDGER("debug")
assert(GrudgeLedgerDiagnostic.edit:GetText():find("Interface : indisponible", 1, true))
assert(#GL.errors == 2, "UI callbacks introduce no errors")
local scheduled, ran
local preparations = 0
GL.PrepareDruidRadar = function()
    preparations = preparations + 1
    return false, "Préparation indisponible en combat."
end
SlashCmdList.GRUDGELEDGER("debug")
assert(preparations == 0, "opening diagnostic never changes the minimap")
click(button(d, "Préparer la minimap"))
assert(preparations == 1 and d:IsShown() and not d.edit.focus and d.radarStatus:GetText():find("en combat", 1, true))
GL.PrepareDruidRadar = function() return true, "Minimap prête. Lance « Validation druide »." end
click(button(d, "Préparer la minimap"))
assert(d:IsShown() and d.radarStatus:GetText():find("prête", 1, true) and not scheduled and not ran, "preparation stays open and never starts a scan")
C_Timer = { After = function(delay, callback) assert(delay == 3); scheduled = callback end }
SlashCmdList.GRUDGELEDGERDRUIDRADAR = function(command) assert(command == "validation"); ran = true end
click(button(d, "Validation druide"))
assert(not d:IsShown() and scheduled and not ran, "hide diagnostic and allow pointer repositioning before test")
scheduled()
assert(ran, "diagnostic invokes the installed druid test")
print("PASS correction/diagnostic UI: paginated immutable events, retained cancellations and manual opinions, empty states, selected safe allowlisted report.")
