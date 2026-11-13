-- Real Core APIs, synthetic identities only: no game state or private SavedVariables.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local now = os.time({ year = 2026, month = 11, day = 12, hour = 12 })
local selfGUID = mock.units.player.guid
GetServerTime = function() return now end
date = os.date
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
local function reset()
    GrudgeLedgerDB = nil
    mock.units.player.guid = selfGUID
    IsInInstance = function() return false, "none" end
    GL.InitDB()
end
local function person(name, guid)
    return GL.IdentityFromName(name, "Example", "Player-1-" .. (guid or name:lower()))
end
local function add(id, kind, confidence, eventId)
    local record = assert(GL.RecordPvP(id, kind, confidence, "synthetic evidence", eventId))
    return record, record.history[#record.history]
end
local function eq(actual, expected, description)
    assert(actual == expected, description .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

reset()
local a, b, c = person("Alpha"), person("Beta"), person("Charlie")
local ra, ea = add(a, "death", "probable", "shared-death")
local rb, eb = add(b, "death", "confirmed", "shared-death")
local rc, ec = add(c, "death", "probable", "shared-death")
eq(ea.actorGUID, selfGUID, "new events have an author GUID")
eq(ea.actorName, "Testeur Exemple", "new events have an author name")
local stats = GL.PersonalStatistics()
eq(stats.deaths, 1, "three aggressors count as one own death")
eq(stats.probableDeaths, 0, "confirmed evidence supersedes probable participants")
eq(stats.mostDeaths.record, rb, "confirmed opponent ranking")
eq(#stats.topDeaths, 1, "probable participants never enter the podium")
stats.topDeaths[1].value = 888
eq(GL.PersonalStatistics().topDeaths[1].value, 1, "the podium returned to UI must not mutate the cache")
stats.deaths, stats.mostDeaths.value = 999, 999
eq(GL.PersonalStatistics().deaths, 1, "returned stats cannot corrupt cached totals")
eq(GL.PersonalStatistics().mostDeaths.value, 1, "returned rankings cannot corrupt cache")
assert(GL.VoidPvP(rb, eb, true))
eq(GL.PersonalStatistics().probableDeaths, 1, "silent correction invalidates summary cache")
eq(GL.PersonalStatistics().deaths, 0, "corrected confirmation is excluded")
eq(#GL.JournalEvents({ kind = "pvp" }), 3, "chronicle retains corrected evidence for audit")
eq(#GL.PersonalStatistics().topDeaths, 0, "corrected deaths are removed from the podium")
assert(GL.VoidPvP(ra, ea, true) and GL.VoidPvP(rc, ec, true))
eq(GL.PersonalStatistics().events, 0, "voided events excluded from every total")

-- The same ID in separate own characters is not the same personal fight.
add(a, "kill", "confirmed", "alt-shared-id")
mock.units.player.guid = "Player-1-alt"
add(b, "kill", "confirmed", "alt-shared-id")
eq(GL.PersonalStatistics().kills, 1, "current alt only")
eq(GL.PersonalStatistics({ scope = "all" }).kills, 2, "account includes both actors")
mock.units.player.guid = selfGUID
eq(GL.PersonalStatistics().kills, 1, "switching character does not reuse another summary")

-- Legacy entries are readable but never assigned to the character currently logged in.
local _, oldOne = add(a, "kill", "confirmed")
local _, oldTwo = add(a, "kill", "confirmed")
oldOne.actorGUID, oldOne.actorName, oldTwo.actorGUID, oldTwo.actorName = nil, nil, nil, nil
GL.InitDB()
eq(oldOne.actorGUID, nil, "loading does not backfill legacy authors")
eq(GL.PersonalStatistics().kills, 1, "legacy is not current character history")
eq(GL.PersonalStatistics().unknownActorEvents, 2, "legacy attribution limitation is visible")
local oldStats = GL.PersonalStatistics({ scope = "legacy" })
eq(oldStats.kills, 2, "same-time unlinked legacy events remain separate")
eq(oldStats.unlinkedEvents, 2, "missing IDs are reported")
eq(GL.PersonalStatistics({ scope = "all" }).kills, 4, "account includes explicit legacy subtotal")
eq(#GL.JournalEvents({ scope = "legacy" }), 2, "legacy chronicle filter")

-- Provisional/live records can hold the same report before identity reconciliation.
reset()
local provisional = GL.IdentityFromName("Merged", "Example")
local liveWithoutSurname = GL.IdentityFromName("Merged", nil, "Player-1-merge")
local rp = add(provisional, "kill", "probable", "merge-kill")
local rl = add(liveWithoutSurname, "kill", "confirmed", "merge-kill")
rp.partyPresence = { [selfGUID] = { seenAt = 30, attemptAt = 10 } }
rl.partyPresence = { [selfGUID] = { seenAt = 20, attemptAt = 40 } }
GL.PersonalStatistics()
local merged = GL.Remember(GL.IdentityFromName("Merged", "Example", "Player-1-merge"))
local mergedStats = GL.PersonalStatistics()
eq(mergedStats.kills, 1, "same actor/victim/report counted once after merge")
eq(mergedStats.probableKills, 0, "merged confirmation wins")
eq(mergedStats.mostKilled.value, 1, "opponent ranking also deduplicated")
eq(merged.partyPresence[selfGUID].seenAt, 30, "merge preserves latest party sighting")
eq(merged.partyPresence[selfGUID].attemptAt, 40, "merge preserves latest chat attempt")

reset()
local anchor = now
local function at(when, eventId)
    now = when
    add(a, "kill", "confirmed", eventId)
end
at(anchor - 7 * 86400, "week-boundary")
at(anchor - 7 * 86400 - 1, "week-outside")
at(anchor - 30 * 86400, "month-boundary")
at(anchor - 30 * 86400 - 1, "month-outside")
at(os.time({ year = 2025, month = 12, day = 31, hour = 12 }), "prior-year")
at(anchor + 5, "future")
now = anchor
eq(GL.PersonalStatistics({ period = "week" }).kills, 1, "rolling seven-day inclusive boundary")
eq(GL.PersonalStatistics({ period = "month" }).kills, 3, "rolling thirty-day inclusive boundary")
eq(GL.PersonalStatistics({ period = "year", year = 2026 }).kills, 4, "selected calendar year")
eq(GL.PersonalStatistics({ period = "year", year = 2025 }).kills, 1, "historical calendar year")
eq(GL.PersonalStatistics().kills, 5, "future-dated events excluded even from all-time")
eq(#GL.JournalEvents(), 5, "chronicle excludes future timestamps")
eq(GL.JournalYears()[2], 2025, "available prior year")
now = anchor + 1
eq(GL.PersonalStatistics({ period = "week" }).kills, 0, "rolling cache expires at boundary")
now = anchor
GL.PersonalStatistics()
now = anchor + 5
eq(GL.PersonalStatistics().kills, 6, "all-time cache expires when a future entry becomes eligible")

reset()
assert(GL.AddNote(a, "Oldword great dungeon"))
local record = GL.Get(a)
local note = record.notes[1]
local originalTime, originalActor = note.time, note.actorGUID
eq(#GL.SearchPlayers({ query = "great alpha" }), 1, "search AND across note and player")
eq(#GL.JournalEvents({ query = "oldword", kind = "notes" }), 1, "note appears in global chronicle")
assert(not GL.UpdateNote(a, note, "  ") and not GL.UpdateNote(a, note, string.rep("x", 2001)))
assert(not GL.UpdateNote(a, { text = note.text, time = note.time }, "forged"), "note object must belong to record")
assert(not GL.UpdateNote(b, note, "foreign") and not GL.DeleteNote(b, note), "cross-record mutation rejected")
now = now + 10
assert(GL.UpdateNote(a, note, "Newword friendly player"))
eq(note.time, originalTime, "editing preserves note creation date")
eq(note.actorGUID, originalActor, "editing preserves provenance")
eq(note.updatedAt, now, "editing records update time")
eq(#GL.SearchPlayers({ query = "oldword" }), 0, "search loses overwritten note text")
eq(#GL.JournalEvents({ query = "oldword" }), 0, "chronicle cache loses overwritten text")
eq(#GL.JournalEvents({ query = "newword" }), 1, "updated note visible")
assert(GL.JournalEvents({ kind = "notes" })[1].event.note == note, "virtual note retains edit/delete reference")
assert(GL.DeleteNote(a, note))
eq(#GL.SearchPlayers({ notesOnly = true }), 0, "notes-only updates after deletion")
eq(#GL.JournalEvents({ kind = "notes" }), 0, "deleted notes are not resurrected in history")
assert(not GL.DeleteNote(a, note), "double deletion rejected")
GL.InitDB()
eq(#GL.JournalEvents({ query = "newword" }), 0, "deleted text stays absent after reload")

reset()
local ia = person("Alpha") ia.guild, ia.className, ia.faction = "Moon Circle", "Druide", "Alliance"
local ib = person("Beta") ib.guild, ib.className, ib.faction = "Red Hands", "Mage", "Horde"
local iaRecord = GL.SetReaction(ia, "friend")
local ibRecord = GL.SetReaction(ib, "enemy")
local icRecord = GL.Remember(c)
assert(GL.AddNote(ia, "100% helpful") and GL.AddNote(ib, "Trouble in Strangleronce"))
eq(GL.SearchPlayers({ query = "moon druide 100%" })[1], iaRecord, "multi-field plain-text search")
eq(#GL.SearchPlayers({ query = "moon trouble" }), 0, "all search terms required")
eq(GL.SearchPlayers({ relation = "enemy", faction = "Horde", notesOnly = true })[1], ibRecord, "combined relation/faction/note filters")
eq(GL.SearchPlayers({ faction = "unknown" })[1], icRecord, "unknown faction filter")
eq(GL.SearchPlayers({ sort = "name" })[1], iaRecord, "alphabetical sorting")
eq(GL.SearchPlayers({ sort = "reputation" })[1], iaRecord, "reputation sorting")
add(b, "kill", "confirmed", "sort-kill")
add(c, "death", "confirmed", "sort-death")
eq(GL.SearchPlayers({ sort = "kills" })[1], ibRecord, "confirmed kill sorting")
eq(GL.SearchPlayers({ sort = "deaths" })[1], icRecord, "confirmed death sorting")
GL.RecordSeen(ia, true)
eq(GL.SearchPlayers({ sort = "encounters" })[1], iaRecord, "lifetime encounter sorting")
now = now + 1
GL.RecordSeen(ib, true)
eq(GL.SearchPlayers({ sort = "recent" })[1], ibRecord, "recent sighting sorting reads live metadata")
now = now + 30
GL.AddNote(ia, "Updated after coming home")
eq(GL.SearchPlayers({ sort = "recent" })[1], ibRecord, "editing a contact cannot promote it above a more recent encounter")
local grouped = GL.Remember(person("GroupOnly"))
grouped.groupCount, grouped.history = 1, { { kind = "grouped", time = now } }
eq(#GL.SearchPlayers(), 3, "group-only records do not pollute list")
eq(#GL.SearchPlayers({ selectedKey = grouped.key }), 4, "explicitly selected group-only record stays reachable")
assert(GL.SetSetting("listSort", "deaths") and GL.SetSetting("listDetail", "notes"))
assert(not GL.SetSetting("listSort", "nonsense") and not GL.SetSetting("listDetail", "nonsense"))
eq(GL.Settings().partyWarnings, false, "chat warnings require opt-in")

reset()
add(a, "death", "confirmed", "tenacious-death1")
add(a, "death", "confirmed", "tenacious-death2")
for i = 1, 19 do add(a, "kill", "confirmed", "repayment" .. i) end
eq(GL.Get(a).reputation, -1, "two deaths still negative after nineteen victories")
eq(GL.Relation(GL.Get(a)), "warning", "danger persists until exactly zero")
add(a, "kill", "confirmed", "repayment20")
eq(GL.Get(a).reputation, 0, "twenty victories repay two deaths")
add(a, "kill", "confirmed", "repayment21")
eq(GL.Relation(GL.Get(a)), "neutral", "victories never create friendship")
IsInInstance = function() return true, "pvp" end
assert(not GL.RecordPvP(b, "death", "confirmed", "battleground", "bg-death"))
eq(GL.PersonalStatistics().deaths, 2, "battleground deaths never enter personal journal")
reset()
local rivals = {person("Zulu"), person("Alpha"), person("Delta"), person("Bravo")}
for i, rival in ipairs(rivals) do
    for n = 1, i == 1 and 3 or 2 do add(rival, "death", "confirmed", i .. "-" .. n) end
end
local podium = GL.PersonalStatistics().topDeaths
eq(#podium, 3, "podium has at most three positions")
eq(podium[1].record.key, rivals[1].key, "most confirmed deaths rank first")
eq(podium[2].record.key, rivals[2].key, "stable key breaks a tie")
eq(podium[3].record.key, rivals[4].key, "fourth ranked player stays off the podium")
print("PASS journal data: provenance, alt/legacy scopes, shared deaths, merge dedup, corrections, periods, cache invalidation, note CRUD, rich search/sort and tenacious PvP score")
