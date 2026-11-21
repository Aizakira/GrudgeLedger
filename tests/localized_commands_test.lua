-- Fresh Spanish-language client: exercise localized commands and legacy French macros.
GetLocale = function() return "esMX" end
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL, command = GrudgeLedger, SlashCmdList.GRUDGELEDGER
mock.units.target.guild = "Ennemis"
command("hermandad enemigo")
assert(GL.GetGuildRule("Ennemis", "Forever").reaction == "enemy")
command("vigilar")
local contact = assert(GL.Get(GL.Identity("target")))
assert(contact.reaction == "warning")
command("nota Notes personnelles")
assert(contact.notes[#contact.notes].text == "Notes personnelles")
GL.ShowLedger(contact.key)
local book = GrudgeLedgerWindow
assert(book.detailTitle:GetText() == "Aqua Water" and book.detailGuild:GetText():find("Ennemis", 1, true))
assert(book.detailScroll.fullText:find("Notes personnelles", 1, true))
assert(book.searchHint:GetText() == "Buscar…")
command("resumen") assert(GrudgeLedgerJournal.mode == "summary")
command("historial") assert(GrudgeLedgerJournal.mode == "history")
command("ajustes") assert(GrudgeLedgerSettings:IsShown())
command("help") assert(mock.messages[#mock.messages]:find("Comandos:", 1, true))
command("ami") assert(contact.reaction == "friend", "existing French macros survive locale changes")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS localized book and slash commands: stable guild keys, untouched note and character data, original macros")

-- /gl bug prepares a report the player can paste into a GitHub issue: where and in what situation,
-- the file and line of the last errors, never a player's name or the raw error text.
do
    local GL = GrudgeLedger
    GetSubZoneText = function() return "Gadgetzan" end
    GL.Debug("Core.lua:42: attempt to index field 'Helvard Lamenoire' (a nil value)")
    SlashCmdList.GRUDGELEDGER("bug")
    local text = GrudgeLedgerDiagnostic.edit:GetText()
    -- This file ends in another language than French: the checks do not depend on the wording.
    assert(text:sub(1, 3) == "===" and text:find("Gadgetzan", 1, true) and text:find("Core.lua:42", 1, true), text:sub(1, 400))
    assert(not text:find("Helvard", 1, true), "an error message never leaves with a name")
    assert(GrudgeLedgerDiagnostic.privacy:GetText():find("github.com/Aizakira/GrudgeLedger/issues", 1, true))
    SlashCmdList.GRUDGELEDGER("debug")
    assert(GrudgeLedgerDiagnostic.edit:GetText():sub(1, 13) == "Grudge Ledger", "the plain report is unchanged")
    print("PASS bug report: place, situation and error location, no name, plain report unchanged")
end
