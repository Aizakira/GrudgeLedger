-- Exercise the real Core/UI together; synthetic records only, no live game input.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local now = os.time({ year = 2026, month = 11, day = 12, hour = 12 })
GetServerTime = function() return now end
date = os.date
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
local GL = GrudgeLedger
GL.InitDB()
local selfGUID = mock.units.player.guid
local function click(control)
    assert(control.enabled ~= false, "cannot click a disabled control")
    control.scripts.OnClick(control, "LeftButton")
end
local function person(name, faction)
    local id = GL.IdentityFromName(name, "Example", "Player-1-" .. name)
    id.faction, id.guild = faction or "Horde", "Golden Library"
    return id
end
local a, b = person("Alpha"), person("Beta", "Alliance")
local ra = GL.RecordPvP(a, "death", "confirmed", "fixture", "own-death")
GL.RecordPvP(a, "kill", "probable", "fixture", "own-kill")
GL.RecordPvP(a, "death", "confirmed", "corrected fixture", "voided")
GL.VoidPvP(ra, ra.history[#ra.history])
GL.SetReaction(b, "friend") GL.RecordSeen(b, true)
GL.AddNote(b, "Excellent dungeon companion")
local rb, note = GL.Get(b), GL.Get(b).notes[1]
mock.units.player.guid = "Player-1-alt"
mock.units.player.name = "Autre"
GL.RecordPvP(a, "kill", "confirmed", "fixture", "alt-kill")
mock.units.player.guid, mock.units.player.name = selfGUID, "Testeur"
GL.RecordPvP(a, "death", "confirmed", "legacy", "legacy-death")
local legacy = ra.history[#ra.history]
legacy.actorGUID, legacy.actorName = nil, nil
GL.InitDB()

GL.ShowJournal("summary")
local f = GrudgeLedgerJournal
assert(f.summary:IsShown() and not f.history:IsShown())
assert(f.metrics.deaths.value:GetText() == "1" and f.metrics.kills.value:GetText() == "0")
assert(f.metrics.probableKills.value:GetText() == "1" and f.metrics.probableKills.qualifier:GetText() == "probable", "probable wins stay separate")
assert(f.coverage:GetText():find("1 sans auteur connu", 1, true))
assert(f.recaps.mostDeaths.record == ra and not f.recaps.mostKilled.record)
assert(f.podium:IsShown() and f.podium.rows[1].record == ra and not f.podium.rows[2]:IsShown())
click(f.dimensionButtons.race)
assert(f.breakdownRows[1].kills:GetText() == "0 / 1" and f.breakdownRows[1].deaths:GetText() == "1 / 0",
    "breakdown must agree with the scoped summary and keep probable facts distinct")
assert(f.breakdownInfo:GetText():find("1 rapport annulé", 1, true))
click(f.dimensionButtons.zone)
assert(f.dimension == "zone" and f.breakdown:IsShown() and f.breakdownRows[1].name:GetText() ~= "")
local area = f.breakdownRows[1].name:GetText()
click(f.breakdownRows[1])
assert(f.zoneKey == area and f.zoneBack:IsShown() and f.breakdownLabel:GetText() == area)
click(f.zoneBack)
assert(not f.zoneKey and not f.zoneBack:IsShown())
click(f.dimensionButtons.class)
assert(f.dimension == "class" and f.breakdownRows[1]:IsShown())
assert(not f.search:IsShown() and not f.kindButton:IsShown(), "history controls must not imply they affect the summary")
click(f.scopeButton)
assert(f.scope == "all" and f.metrics.kills.value:GetText() == "1" and f.metrics.deaths.value:GetText() == "2")
click(f.scopeButton)
assert(f.scope == "legacy" and f.metrics.deaths.value:GetText() == "1")
click(f.scopeButton)
f.year = nil GL.ShowJournal("summary")
assert(not f.yearButton:GetText():find("nil", 1, true))
click(f.periodButtons.year) assert(f.yearButton.enabled)
click(f.periodButtons.week) assert(not f.yearButton.enabled)
click(f.periodButtons.all)
click(f.tabs.year)
assert(f.annual:IsShown() and f.annual.metrics.deaths:GetText() == "1" and f.annual.metrics.kills:GetText() == "0")
assert(f.yearButton.enabled and not f.periodButtons.week:IsShown() and f.annual.recaps.mostDeaths.record == ra)
click(f.copyAnnual)
assert(f.cardCopy.children[1].highlighted == f.annualText)
assert(f.cardCopy:IsShown() and f.annualText:find("1 mort", 1, true) and not f.annualText:find("Alpha", 1, true)
    and not f.annualText:find("Golden Library", 1, true) and not f.annualText:find("dungeon", 1, true))
f.year = 2025 GL.ShowJournal("year")
assert(not f.cardCopy:IsShown(), "a previous selection must not remain available as the new year's copy")
assert(f.annual.metrics.deaths:GetText() == "0" and f.annual.coverage:GetText():find("Aucun fait PvP", 1, true) and not f.annual.recaps.mostDeaths.enabled)
f.year = 2026 GL.ShowJournal("year")
click(f.annual.events)
assert(f.mode == "history" and f.period == "year" and f.kind == "pvp" and f.scope == "character")
click(f.reset)
click(f.tabs.story)
assert(f.story:IsShown() and not f.summary:IsShown() and not f.history:IsShown())
assert(f.storyText:GetText():find("remporté 0 victoire confirmée", 1, true), "story must use the selected character, not account totals")
click(f.scopeButton)
assert(f.storyText:GetText():find("remporté 1 victoire confirmée et subi 2 morts confirmées", 1, true))
f.storyScroll:SetVerticalScroll(100000)
click(f.periodButtons.week)
assert(f.storyScroll:GetVerticalScroll() <= math.max(0, f.storyBody:GetHeight() - f.storyScroll:GetHeight()))
click(f.scopeButton) click(f.scopeButton) click(f.periodButtons.all)

click(f.tabs.history)
assert(f.search:IsShown() and f.kindButton.enabled and not f.summary:IsShown())
local before = f.total:GetText()
f.search:SetText("dungeon")
assert(f.total:GetText() == before, "large history is not searched on every keystroke")
f.search.scripts.OnEnterPressed(f.search)
assert(f.rows[1].item.record == rb and f.rows[1].item.event.kind == "note" and not f.rows[2]:IsShown())
f.search:SetText("") click(f.searchButton)
click(f.kindButton)
assert(f.kind == "pvp")
local corrected
for _, row in ipairs(f.rows) do
    if row.item and row.item.event.voided then corrected = row end
end
assert(corrected and corrected.action:GetText():find("exclu des compteurs", 1, true), "corrections remain readable in the chronicle")
click(corrected.details)
assert(GrudgeLedgerCorrections.event == corrected.item.event and not GrudgeLedgerCorrections.confirm:IsEnabled())
click(GrudgeLedgerCorrections.keep)
click(f.scopeButton)
local alt
for _, row in ipairs(f.rows) do
    if row.item and row.item.event.actorGUID == "Player-1-alt" then alt = row end
end
assert(alt and alt.meta:GetText():find("Autre Exemple", 1, true), "account history identifies the actor")
click(f.rows[1])
assert(not f:IsShown() and GrudgeLedgerWindow:IsShown())

-- Every chronicle page remains bounded, including the final partial page.
for i = 1, 10 do now = now + 1 GL.AddNote(b, "Page note " .. i) end
GL.ShowJournal("history")
while f.kind ~= "all" do click(f.kindButton) end
assert(f.next.enabled)
local first = f.rows[1].item.event
click(f.next) assert(f.previous.enabled and f.rows[1].item.event ~= first)
while f.next.enabled do click(f.next) end
assert(f.rows[1].item and not f.next.enabled)
f.search:SetText("nothing matches this") click(f.searchButton)
assert(not f.rows[1]:IsShown() and not f.previous.enabled and not f.next.enabled)

-- Rich search composes with notes-only, and display/sort choices persist.
GL.ShowLedger(b.key)
local ledger = GrudgeLedgerWindow
GL.SetSetting("guideSeen", false)
GL.ShowLedger()
assert(GrudgeLedgerGuide:IsShown() and GL.Settings().guideSeen, "first opening offers the guide once")
GrudgeLedgerGuide:Hide()
GL.ShowLedger()
assert(not GrudgeLedgerGuide:IsShown(), "later openings do not interrupt the journal")
GL.ShowLedger(ra.key)
click(ledger.detailTabs.matchup)
assert(ledger.detailScroll:IsShown() and not ledger.tools:IsShown())
assert(ledger.detailText:GetText():find("0 victoire   ·   1 défaite", 1, true),
    "face-to-face excludes the other character, unknown author, probable and corrected outcomes")
do
    local opponent = person("Rematch")
    local start = now
    local contact = GL.RecordPvP(opponent, "death", "confirmed", nil, "first")
    now = start + 180
    GL.RecordPvP(opponent, "death", "confirmed", nil, "second")
    now = start + 600
    GL.RecordPvP(opponent, "kill", "confirmed", nil, "revenge")
    now = start + 601
    GL.RecordPvP(opponent, "kill", "confirmed", nil, "another")
    local last = contact.history[#contact.history]
    table.insert(contact.history, 1, last) -- duplicate upon legacy identity merge
    local balance = GL.AutomaticBalance(contact)
    local m = GL.ContactMatchup(contact)
    assert(m.kills == 2 and m.deaths == 2 and m.run == 2 and m.lastKind == "kill")
    assert(m.recent[1] == last and #m.recent == 4 and m.closeDeaths.eventId == "second" and m.comeback.eventId == "revenge")
    assert(GL.AutomaticBalance(contact) == balance and balance == -18)
    assert(GL.VoidPvP(contact, last))
    assert(GL.ContactMatchup(contact).run == 1, "correcting an event takes effect on the next read")
end
click(ledger.detailTabs.summary)
assert(ledger.reactions[GL.Relation(ra)].active and not ledger.reactions.neutral.active,
    "automatic PvP danger must select the real dangerous relation, not neutral")
click(ledger.reactions.friend)
assert(GL.RelationSource(ra) == "manual" and ledger.reactions.friend.active)
click(ledger.reactions.neutral)
assert(GL.RelationSource(ra) == "pvp" and ledger.reactions[GL.Relation(ra)].active,
    "Automatic removes a manual override and restores the outstanding PvP debt")
local historicalNeutral = GL.Remember(person("HistoricalNeutral"))
historicalNeutral.reaction, historicalNeutral.reactionSource = "neutral", "manual"
historicalNeutral.reputation, historicalNeutral.pvp.deaths = -10, 1
GL.ShowLedger(historicalNeutral.key)
assert(GL.Relation(historicalNeutral) == "neutral" and ledger.reactions.neutral.active,
    "an existing explicit neutral override stays visible and is not rewritten by viewing")
GL.ShowLedger(b.key)
ledger.search:SetText("Golden dungeon")
ledger.search.scripts.OnEnterPressed(ledger.search)
assert(ledger.rows[1].key == b.key and not ledger.rows[2]:IsShown())
click(ledger.notesOnly)
assert(ledger.rows[1].key == b.key)
click(ledger.detail)
assert(GL.Settings().listDetail == "guild" and ledger.rows[1].identity:GetText() == "Golden Library")
click(ledger.sort) assert(GL.Settings().listSort == "name")
click(ledger.factions.Horde)
assert(not ledger.rows[1]:IsShown())
click(ledger.reset)
assert(ledger.search:GetText() == "" and ledger.query == "" and ledger.filters.all.active and ledger.factions.all.active)
assert(not ledger.notesOnly.active and GL.Settings().listSort == "name" and GL.Settings().listDetail == "guild",
    "reset clears search filters without discarding display preferences")
GL.SetSetting("listSort", "reputation")
now = now + 1 GL.RecordPvP(a, "death", "confirmed", "witness", "chronology-test")
assert(ledger.rows[1].key == a.key and ledger.sort:GetText() == "Dernière interaction" and not ledger.sort:IsEnabled())
ledger.search:SetText("Golden")
assert(ledger.rows[1].key == a.key and not ledger.sort:IsEnabled(), "typing alone preserves chronology")
click(ledger.searchButton)
assert(ledger.sort:IsEnabled() and ledger.sort:GetText() == "Réputation" and ledger.rows[1].key ~= a.key)
ledger.search:SetText(" ")
assert(ledger.query == "" and ledger.rows[1].key == a.key and not ledger.sort:IsEnabled(), "clearing text immediately restores chronology")
now = now + 601 GL.RecordSeen(b, true)
assert(ledger.rows[1].key == b.key, "new direct visit reorders an already open journal")
now = now + 1
local visible = UnitIsVisible
UnitIsVisible = function(unit) return unit == "target" end
click(ledger.addTarget)
local added = GL.Get(GL.Identity("target"))
assert(added and ledger.rows[1].key == added.key, "adding a visible target starts its first encounter")
UnitIsVisible = visible
for i = 1, 12 do GL.SetReaction(person("AAAA" .. i), "enemy") end
GL.ShowLedger(b.key)
local found
for _, row in ipairs(ledger.rows) do if row:IsShown() and row.key == b.key then found = true end end
assert(found, "opening a specific record jumps to its actual page")
click(ledger.settingsButton)
for _, category in ipairs({ "appearance", "alerts", "relations", "shortcuts", "data" }) do
    GrudgeLedgerSettings:SelectCategory(category)
    for key, panel in pairs(GrudgeLedgerSettings.pages) do assert(panel:IsShown() == (key == category)) end
end
GrudgeLedgerSettings:SelectCategory("alerts")
assert(not GL.Settings().partyWarnings and not GrudgeLedgerSettings.checks.partyWarnings:GetChecked())
GrudgeLedgerSettings.checks.partyWarnings:SetChecked(true)
click(GrudgeLedgerSettings.checks.partyWarnings)
assert(GL.Settings().partyWarnings)

-- Editing keeps the original object and count; drafts cannot cross identities.
local count = #rb.notes
GL.EditNote(rb, note)
local n = GrudgeLedgerNote
assert(n.parent == ledger and ledger.detailTab == "notes" and n.rows[1].note == note,
    "opening an existing note jumps to its page in the selected player's book")
click(n.previous)
local picked = n.rows[1].note
click(n.rows[1]) n.edit:SetText("Temporary revision")
assert(n.draft:GetText():find("non enregistré",1,true))
click(n.rows[2]) click(n.rows[1])
assert(n.edit:GetText() == "Temporary revision" and n.selectedNote == picked, "switching dated notes preserves their individual drafts")
click(n.cancel)
assert(n.edit:GetText() == picked.text and n.draft:GetText() == "", "Cancel discards just this edit")
GL.EditNote(rb,note)
n.edit:SetText("Updated dungeon memory") click(n.save)
assert(#rb.notes == count and rb.notes[1] == note and note.text == "Updated dungeon memory")
GL.EditNote(rb, note) n.edit:SetText("Unfinished edit") n:Hide()
GL.EditNote(rb, note) assert(n.edit:GetText() == "Unfinished edit")
click(n.new) n.edit:SetText("New draft") n:Hide()
GL.EditNote(ra) assert(n.edit:GetText() == "")
GL.EditNote(rb) assert(n.edit:GetText() == "New draft")
GL.EditNote(rb, note)
click(n.remove) assert(#rb.notes == count, "deletion requires confirmation")
n.edit:SetText("Changing text cancels deletion")
click(n.remove) assert(#rb.notes == count)
click(n.remove) assert(#rb.notes == count - 1 and n.selectedNote == nil)
GL.EditNote(rb, rb.notes[1])
local stale = n.selectedNote
assert(GL.DeleteNote(rb, stale))
n.edit:SetText("Stale update") click(n.save)
assert(n:IsShown() and n.error:GetText() ~= "" and #rb.notes == count - 2,
    "an outdated editor cannot overwrite a different note")
click(n.new) n.edit:SetText("  ") click(n.save)
assert(n:IsShown() and n.error:GetText() ~= "", "empty notes are rejected without closing the draft")
local formatDate = date
date = function(format, at) return format == "%Y" and "?" or formatDate(format, at) end
f.year = nil
GL.ShowJournal("year")
assert(f.annual.period:GetText() == "Année inconnue" and not f.yearButton:IsEnabled())
date = formatDate
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS journal UI: scoped evidence, legacy/alt labels, bounded submitted search, correction audit, paging, configurable index, opt-in warning, stable note editing/deletion/drafts")
