local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
getmetatable(UIParent).__index.HighlightText = function(self) self.highlighted = true end
function GetBuildInfo() return "1.16.0", "63690", "Nov 1 2026", 16001 end
C_AddOns = { IsAddOnLoaded = function(name) return name == "TidyPlates_ThreatPlates" end }
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
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
click(button(GrudgeLedgerWindow, "Corriger le PvP"))
local f = GrudgeLedgerCorrections
assert(f:IsShown() and f.topLevel and f.raised > 0)
assert(f.rows[1].title:GetText():find("Agression (confirmé)", 1, true))
assert(f.rows[1].evidence:GetText():find("||cff00ff00", 1, true), "evidence is literal text")
assert(f.total:GetText():find("9 événement(s)", 1, true), "non-PvP history excluded")
local originalUndo = f.rows[1].undo.scripts.OnClick
click(f.next)
assert(f.offset == 6 and f.rows[3].evidence:GetText() == "Déduction 1", "pagination reaches earliest event")
click(button(f, "Précédent"))

-- Changing the game target and the journal selection cannot redirect an open correction.
mock.units.target = { name = "Megumin", surname = "Crimson", guid = "Player-1-megumin" }
local other = GL.SetReaction(GL.Identity("target"), "friend")
GL.RecordPvP(other, "death", "confirmed", "Autre personne", "otherdeath")
GL.ShowLedger(other.key)
originalUndo()
assert(latest.voided and record.pvp.aggressions == 0 and #record.history == historyLength)
assert(other.pvp.deaths == 1 and other.reaction == "friend", "original event remains bound to original person")
assert(f.rows[1].undo.enabled == false and f.rows[1].undo.text == "Annulé")
assert(f.rows[1].title:GetText():find("annulé", 1, true), "voided events remain visible")
originalUndo()
assert(record.pvp.aggressions == 0 and f.status:GetText():find("déjà annulé", 1, true), "stale callbacks cannot subtract twice")
assert(not GL.RecordAggression(first, "confirmed", "same observation", "aggression"), "correction retains event dedup")
GL.ShowLedger(record.key)
assert(GrudgeLedgerWindow.detailText:GetText():find("annulé", 1, true), "main history also annotates cancellation")
assert(#record.notes == 1 and record.notes[1].text == "PRIVATE note inside journal", "notes unaffected")

GL.ShowLedger(other.key)
click(button(GrudgeLedgerWindow, "Corriger le PvP"))
click(f.rows[1].undo)
assert(other.pvp.deaths == 0 and other.reaction == "friend" and other.reputation == 1, "manual opinion unchanged")
local empty = GL.Remember(GL.IdentityFromName("Nobody", "Else", "Player-1-empty"))
GL.ShowLedger(empty.key)
click(button(GrudgeLedgerWindow, "Corriger le PvP"))
assert(f.total:GetText() == "Aucun événement PvP." and not f.rows[1]:IsShown())
assert(not f.rows[1].undo.scripts.OnClick, "empty rows discard stale callbacks")

GL.SetGuildReaction("PRIVATE guild", "enemy", "PRIVATE guild note")
GL.errors = { { text = "PRIVATE raw error Aqua Player-1-aqua" }, { text = "PRIVATE more details" } }
GL.db.settings.unrelatedPrivateSetting = "PRIVATE hidden setting"
SlashCmdList.GRUDGELEDGER("settings")
click(button(GrudgeLedgerSettings, "Diagnostic"))
local d = GrudgeLedgerDiagnostic
local text = d.edit:GetText()
assert(d:IsShown() and d.edit.focus and d.edit.highlighted and d.topLevel)
assert(text:find("Client : 1.16.0", 1, true) and text:find("Build : 63690", 1, true) and text:find("Interface : 16001", 1, true))
assert(text:find("Intégration détectée : Threat Plates", 1, true))
assert(text:find("Erreurs conservées : 2", 1, true))
assert(text:find("markers : oui", 1, true) and text:find("CombatLogGetCurrentEventInfo : non", 1, true))
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
print("PASS correction/diagnostic UI: paginated immutable events, retained cancellations and manual opinions, empty states, selected safe allowlisted report.")
