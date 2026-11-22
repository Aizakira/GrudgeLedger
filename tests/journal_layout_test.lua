-- Journal layout (0.33.0), from the owner's review of the main page: four quick views with their
-- count, every other filter in one panel, no tab bar on the right page (the tabs duplicated the
-- sheet), the story in the summary, the detailed history and the notes under "Autres actions".
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local function click(b) b.scripts.OnClick(b, "LeftButton") end
local methods = getmetatable(UIParent).__index
local setPoint = methods.SetPoint
function methods:SetPoint(...)
    setPoint(self, ...)
    self.anchor = { ... }
end
local id = GL.IdentityFromName("Layout", "Example", "Player-9-0A01")
GL.RecordAggression(id, "confirmed", nil, "layout-a")
GL.RecordPvP(id, "death", "confirmed", "Direct", "layout-d")
GL.AddNote(id, "Une note personnelle")
local friend = GL.SetReaction(GL.IdentityFromName("Kind", "Example", "Player-9-0A02"), "friend")
local record = GL.Get(id)
GL.ShowLedger(record.key)
local f = GrudgeLedgerWindow
assert(f.referenceSkin and f:GetWidth() == 960 and f:GetHeight() == 744, "the window includes the longer ribbon footer")
assert(f.bookSurface:GetWidth() == 960 and f.bookSurface:GetHeight() == 720, "the book painting preserves the reference aspect ratio")
assert(f.search.referenceSkin and f.rows[1]:GetWidth() == 255)
assert(f.rows[1].selection.texture:find("JournalReferenceSelected", 1, true))
assert(f.metrics.deaths.skin.texture:find("JournalReferenceStats", 1, true))

-- One button names the list and its count; each click shows the next list (0.39.0).
assert(f.viewCycle:GetText() == "Tous · 2" and not f.viewCycle.active and f.openFilters:GetText() == "Filtres", f.viewCycle:GetText())
click(f.viewCycle)
assert(f.viewCycle:GetText() == "À régler · 1" and f.viewCycle.active and f.rows[1].key == record.key and not f.rows[2]:IsShown())
click(f.viewCycle)
assert(f.viewCycle:GetText() == "Amis · 1", f.viewCycle:GetText())
assert(f.rows[1].key == friend.key and f.openFilters:GetText() == "Filtres · 1")
-- The panel holds the other filters and stays open while choosing; a quick view closes it.
click(f.openFilters)
assert(f.filterPanel:IsShown())
click(f.filters.enemy)
assert(f.filterPanel:IsShown() and f.rows[1].key == record.key and f.viewCycle:GetText() == "Sélection · 1", f.viewCycle:GetText())
-- The order of the list is chosen in the panel. From a custom selection the button returns to
-- everyone, closes the panel and puts the other filters back; two more clicks reach "Signalés".
assert(f.sort.parent == f.filterPanel)
click(f.viewCycle)
assert(not f.filterPanel:IsShown() and f.rows[2]:IsShown() and f.viewCycle:GetText() == "Tous · 2")
f.ShowView("any")
assert(f.viewCycle:GetText() == "Signalés · 0" and not f.rows[1]:IsShown())
click(f.viewCycle)
assert(f.viewCycle:GetText() == "Tous · 2")

-- Both hanging bookmarks use the existing quick view, including its filter/menu reset.
click(f.openFilters)
click(f.bookmarks.friend)
assert(not f.filterPanel:IsShown() and f.viewKey == "friend" and f.rows[1].key == friend.key)
assert(f.bookmarks.friend.active and not f.bookmarks.debt.active)
assert(f.bookmarks.friend.skin.texture:match("JournalBookmarkFriendActive$"))
click(f.bookmarks.debt)
assert(f.viewKey == "debt" and f.rows[1].key == record.key and not f.rows[2]:IsShown())
assert(f.bookmarks.debt.active and not f.bookmarks.friend.active)
assert(f.bookmarks.debt.skin.texture:match("JournalBookmarkDebtActive$"))
click(f.filters.enemy)
assert(not f.bookmarks.friend.active and not f.bookmarks.debt.active, "a custom filter must not claim a bookmark is selected")
for _, bookmark in pairs(f.bookmarks) do
    assert(not bookmark.caption:IsShown() and bookmark.caption:GetText() ~= "", "the small ribbons use a tooltip, not tiny lettering")
    local ratio = bookmark:GetWidth() / bookmark:GetHeight()
    assert(ratio > 0.47 and ratio < 0.51, "preserve the curved fabric proportions from the whole-book study")
    assert(f.bookmarkCover:GetFrameLevel() > bookmark:GetFrameLevel(), "leather must cover the fabric attachment")
    assert(-f.bookmarkCover.anchor[3] <= -bookmark.anchor[3], "the rolled fabric root must not peek above the foreground leather")
    local edgeBottom = 664 -- Physical leather edge; the sampled overlay also includes its translucent shadow.
    assert(-f.bookmarkCover.anchor[3] + f.bookmarkCover:GetHeight() == 690,
        "the foreground book sample includes the shadow cast by the leather onto the ribbon")
    assert(f.bookmarkCover.skin.texCoord[3] == 620 / 720 and f.bookmarkCover.skin.texCoord[4] == 690 / 720)
    local visible = -bookmark.anchor[3] + bookmark:GetHeight() - edgeBottom
    assert(-bookmark.anchor[3] < edgeBottom and visible >= 70 and visible <= 80,
        "the root stays behind the cover while 70 to 80 units of fabric hang below the physical leather edge")
    assert(-bookmark.anchor[3] + bookmark:GetHeight() <= f:GetHeight(), "the bookmark remains clickable inside the book window")
end

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
-- Reflow runs after refresh/settings as well as at construction; neither density can cover pagination.
for i = 1, 13 do GL.SetReaction(GL.IdentityFromName("LayoutExtra" .. i, "Example", "Player-9-B" .. i), "enemy") end
GL.ShowLedger(record.key)
for _, compact in ipairs({ true, false }) do
    GL.SetSetting("compactMode", compact)
    assert(f.pageSize == (compact and 11 or 7))
    for i = 1, f.pageSize do
        local row = f.rows[i]
        assert(row.anchor[2] >= 74 and row.anchor[2] + row:GetWidth() <= 345, "list rows stay on the leather")
        assert(-row.anchor[3] + row:GetHeight() <= -f.previous.anchor[3], "list rows must end before pagination")
        assert(row.relation.anchor[2] + row.relation:GetWidth() < row:GetWidth(), "relationship labels stay inside the row")
    end
    assert(f.storyHeading.anchor[3] == -389 and f.detailScroll.anchor[2] == 367 and f.detailScroll.anchor[3] == -412,
        "refresh must preserve the separate story heading and text positions")
    assert(-f.detailScroll.anchor[3] + f.detailScroll:GetHeight() < -f.actions[1].anchor[3], "story pagination clears the actions")
end
-- A longer story spans pages instead of hiding a sentence or a personal note; arrows and wheel update headings.
local originalStory, sentences = GL.CharacterInsights.Story, {}
for i = 1, 9 do sentences[i] = "Phrase intégrale numéro " .. i .. ", à conserver dans le livre." end
GL.CharacterInsights.Story = function() return sentences end
GL.AddNote(record, "Note conservée après le récit")
GL.ShowLedger(record.key)
local view = f.detailScroll
assert(view.storyPageCount > 1 and f.storyHeading:GetText() == "Votre histoire" and not f.encounterHeading:IsShown())
while view.page < view.storyPageCount do click(view.next) end
assert(not f.encounterHeading:IsShown() and not f.encounterRule:IsShown(), "no heading is shown without the text it titles")
view.scripts.OnMouseWheel(view, -1)
assert(f.storyHeading:GetText() == "Dernière rencontre" and not f.encounterHeading:IsShown())
click(view.prev)
assert(f.storyHeading:GetText() == "Votre histoire" and not f.encounterHeading:IsShown())
-- The renderer measured this combined explanation on two lines; the native measurement controls layout.
local originalBalance = GL.AutomaticBalance
local contextHeight = f.scoreContext.GetStringHeight
GL.AutomaticBalance = function() return 0, 5, 0 end
function f.scoreContext:GetStringHeight()
    return self:GetText():find("Vous menez", 1, true) and math.ceil(26 * (GL.Settings().readingScale or 1)) or contextHeight(self)
end
GL.SetReaction(record, "enemy")
for _, scale in ipairs({ 1, 1.25 }) do
    GL.SetSetting("readingScale", scale)
    assert(f.scoreContext:GetText():find("Avis personnel prioritaire", 1, true) and f.scoreContext:GetText():find("Vous menez", 1, true))
    assert(f.scoreContext:GetHeight() > 17 and f.scoreContext:GetHeight() >= f.scoreContext:GetStringHeight())
    local contextBottom = -f.counters.anchor[3] - f.scoreContext.anchor[3] + f.scoreContext:GetHeight()
    assert(-f.storyHeading.anchor[3] >= contextBottom + 4, "the complete balance explanation clears the story heading")
    assert(-view.anchor[3] >= -f.storyHeading.anchor[3] + math.ceil(23 * scale), "the story starts below its resized heading")
    local rendered = table.concat(view.pages, "\n")
    for _, sentence in ipairs(sentences) do
        local first, last = rendered:find(sentence, 1, true)
        assert(first and not rendered:find(sentence, last + 1, true), "each story sentence is preserved exactly once")
    end
    assert(rendered:find("Note conservée après le récit", 1, true), "personal notes remain available after the story")
    assert(view.fullText:find("Votre histoire", 1, true) and view.fullText:find("Dernière rencontre", 1, true))
    assert(-view.anchor[3] >= 389 + math.ceil(23 * scale), "large reading leaves space below the bold heading")
end
GL.AutomaticBalance = originalBalance
f.scoreContext.GetStringHeight = contextHeight
GL.CharacterInsights.Story = originalStory
GL.SetSetting("readingScale", 1)
GL.SetReaction(record, "neutral")
GL.ShowLedger(record.key)
assert(f.scoreContext:GetText() == "" and f.storyHeading.anchor[3] == -389, "empty context restores the reference position")
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS journal layout: quick views with counts, one filter panel, no tab bar, story in the summary, "
    .. "history and notes with a way back, hanging bookmark states and both reference list densities")
