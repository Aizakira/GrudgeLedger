-- Journal layout (0.33.0), from the owner's review of the main page: four quick views with their
-- count, every other filter in one panel, no tab bar on the right page (the tabs duplicated the
-- sheet), the story in the summary, the detailed history and the notes under "Autres actions".
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local function click(b) b.scripts.OnClick(b, "LeftButton") end
local id = GL.IdentityFromName("Layout", "Example", "Player-9-0A01")
GL.RecordAggression(id, "confirmed", nil, "layout-a")
GL.RecordPvP(id, "death", "confirmed", "Direct", "layout-d")
GL.AddNote(id, "Une note personnelle")
local friend = GL.SetReaction(GL.IdentityFromName("Kind", "Example", "Player-9-0A02"), "friend")
local record = GL.Get(id)
GL.ShowLedger(record.key)
local f = GrudgeLedgerWindow

-- Quick views and their counts.
assert(f.views.all:GetText() == "Tous 2" and f.views.debt:GetText() == "À régler 1", f.views.all:GetText())
assert(f.views.friend:GetText() == "Amis 1" and f.views.any:GetText() == "Signalés 0")
assert(f.views.all.active and f.openFilters:GetText() == "Filtres")
click(f.views.debt)
assert(f.views.debt.active and not f.views.all.active and f.rows[1].key == record.key and not f.rows[2]:IsShown())
click(f.views.friend)
assert(f.rows[1].key == friend.key and f.openFilters:GetText() == "Filtres · 1")
-- The panel holds the other filters and stays open while choosing; a quick view closes it.
click(f.openFilters)
assert(f.filterPanel:IsShown())
click(f.filters.enemy)
assert(f.filterPanel:IsShown() and f.rows[1].key == record.key and not f.views.friend.active)
click(f.views.all)
assert(not f.filterPanel:IsShown() and f.rows[2]:IsShown())

-- The right page has no tab bar; the summary tells the story.
GL.ShowLedger(record.key)
for key, tab in pairs(f.detailTabs) do assert(not tab:IsShown(), key .. " tab is hidden") end
assert(not f.backToSummary:IsShown() and f.openSheet:IsShown())
local summary = f.detailScroll.fullText
assert(summary:find("Votre histoire", 1, true) and summary:find("Il vous a tué 1 fois", 1, true), summary)
assert(summary:find("Une note personnelle", 1, true))
assert(f.detailGuild:GetText() == "Guilde non renseignée")
-- The detailed history and the notes open from "Autres actions", with a way back.
click(f.openHistory)
assert(f.historyPage:IsShown() and f.backToSummary:IsShown() and not f.openSheet:IsShown())
click(f.backToSummary)
assert(not f.historyPage:IsShown() and f.detailScroll:IsShown() and not f.backToSummary:IsShown())
click(f.openNotes)
assert(f.backToSummary:IsShown() and not f.detailScroll:IsShown())
click(f.backToSummary)
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS journal layout: quick views with counts, one filter panel, no tab bar, story in the summary, "
    .. "history and notes from the actions menu with a way back")
