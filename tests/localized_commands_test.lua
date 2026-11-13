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
assert(book.detailTitle:GetText() == "Aqua Water" and book.detailGuild:GetText() == "Ennemis")
assert(book.detailText:GetText():find("Notes personnelles", 1, true))
assert(book.searchHint:GetText() == "Nombre, hermandad, nota…")
command("resumen") assert(GrudgeLedgerJournal.mode == "summary")
command("historial") assert(GrudgeLedgerJournal.mode == "history")
command("ajustes") assert(GrudgeLedgerSettings:IsShown())
command("help") assert(mock.messages[#mock.messages]:find("Comandos:", 1, true))
command("ami") assert(contact.reaction == "friend", "existing French macros survive locale changes")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS localized book and slash commands: stable guild keys, untouched note and character data, original macros")
