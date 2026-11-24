-- Follow the personal reward through each real book view, including an anonymous receipt.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
date = os.date
IsInInstance = function() return false, "none" end
for _, file in ipairs({"Core.lua", "UITheme.lua", "UI.lua"}) do
    assert(loadfile(TEST_ROOT .. "/" .. file))("GrudgeLedger")
end
local GL = GrudgeLedger
GL.InitDB()
local function click(control)
    assert(control:IsEnabled())
    control:GetScript("OnClick")(control, "LeftButton")
end
local function contains(control, text)
    assert(control:GetText():find(text, 1, true), control:GetText())
end
-- The detailed tables (23/11): the honour is a key figure of the left column, its detail in the lead.
GL.ShowJournal("summary")
local book = GrudgeLedgerJournal
local function tally(caption)
    for _, line in ipairs(GL.HonorTally()) do if line[1] == caption then return line end end
end
assert(tally("Honneur reçu")[2] == 0)
local id = GL.IdentityFromName("Alpha", "Example", "Player-1-alpha")
local actor = mock.units.player.guid
mock.units.player.guid = "Player-1-alt"
assert(GL.RecordHonor(id, 100))
mock.units.player.guid = actor
local zero = assert(GL.RecordHonor(id, 0))
GL.ShowJournal("summary")
assert(tally("Honneur reçu")[2] == 0)
local receipt = assert(GL.RecordHonor(id, 31))
local unknown = assert(GL.RecordHonor(nil, 12))
GL.ShowJournal("summary")
assert(tally("Honneur reçu")[2] == 43)
contains(book.lead, "3 gains · Gain maximal : 31 · Sans adversaire identifié : 12")
assert(tally("Victoires")[2] == 0)
click(book.scopeButton)
assert(tally("Honneur reçu")[2] == 143)
click(book.scopeButton)
assert(tally("Honneur reçu")[2] == 0)
click(book.scopeButton)
click(book.periodButton)
assert(book.period == "week")
tally("Honneur reçu")[3]()
assert(book.mode == "history" and book.kind == "honor" and book.period == "week" and book.scope == "character")
local seen = {}
for _, row in ipairs(book.rows) do
    if row:IsShown() then
        local e = row.item.event
        seen[e] = true
        contains(row.action, "Honneur reçu : +" .. e.honor)
        if e == unknown then
            contains(row.name, "Adversaire non identifié")
            click(row)
            local detail = GrudgeLedgerCorrections
            assert(detail:IsShown() and detail.event == e and not detail.attest and not detail.confirm:IsShown())
            contains(detail.proof, "Plusieurs joueurs")
            assert(not detail.raceIcon:IsShown())
            click(detail.keep)
        end
    end
end
assert(seen[receipt] and seen[zero] and seen[unknown] and not book.rows[4]:IsShown())
click(book.tabs.year)
assert(book.annual.metrics.honor:GetText() == "43")
contains(book.annual.coverage, "0 fait de combat")
click(book.copyAnnual)
assert(book.annualText:find("Honneur reçu : 43", 1, true) and not book.annualText:find("Alpha", 1, true))
click(book.annual.events)
assert(book.kind == "pvp" and book.rows[1].item.event.kind == "honor")
click(book.tabs.story)
contains(book.storyText, "Honneur reçu : 43")
contains(book.storyText, "3 gains")
GL.ShowLedger(id.key)
local ledger = GrudgeLedgerWindow
-- The Face-à-face page left the Journal in 0.38.0; its filter of the detailed history remains.
local duel = GL.ContactMatchup(GL.Get(id.key))
assert(duel.honor == 31 and duel.honorAwards == 2 and duel.bestHonor == 31 and duel.kills == 0)
click(ledger.detailTabs.history)
click(ledger.historyPage.options.matchup)
local history = ledger.historyPage
assert(history.rows[1].event == receipt and history.rows[2].event == zero and not history.rows[3]:IsShown())
click(history.rows[1].details)
assert(GrudgeLedgerCorrections.event == receipt and GrudgeLedgerCorrections.raceIcon:IsShown())
click(GrudgeLedgerCorrections.keep)
for _, kind in ipairs({"pvp", "honor"}) do
    click(history.options[kind])
    contains(history.rows[1].title, "+31")
    assert(history.rows[3].event.honor == 100 and history.rows[3].hint:GetText() ~= "")
end
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS honor in the journal: scoped totals, zero and absent receipts, anonymous and named details, filters, year, copy and story")
