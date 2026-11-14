-- Campaign queries use real Core APIs and synthetic data, never saved player files.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local anchor = os.time({ year = 2026, month = 11, day = 12, hour = 12 })
local now, zone, subzone = anchor, "Hurlevent", "Port"
local actor = mock.units.player.guid
GetServerTime = function() return now end
GetRealZoneText = function() return zone end
GetSubZoneText = function() return subzone end
date = os.date
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
local function eq(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function reset()
    GrudgeLedgerDB, now, zone, subzone = nil, anchor, "Hurlevent", "Port"
    mock.units.player.guid = actor
    IsInInstance = function() return false, "none" end
    GL.InitDB()
end
local function person(name, race, class)
    local id = GL.IdentityFromName(name, "Example", "Player-1-" .. name:lower())
    id.race, id.raceName, id.class, id.className = race, race, class, class
    return id
end
local function add(id, kind, confidence, eventId)
    local record = assert(GL.RecordPvP(id, kind, confidence, "synthetic evidence", eventId))
    return record, record.history[#record.history]
end
local function breakdown(options, dimension)
    local rows, map = GL.PvPBreakdown(options, dimension), {}
    local totals = { kills = 0, deaths = 0, correctedKills = 0, correctedDeaths = 0 }
    for _, row in ipairs(rows) do
        map[row.key] = row
        for key in pairs(totals) do totals[key] = totals[key] + row[key] end
    end
    local summary = GL.PersonalStatistics(options)
    for _, key in ipairs({ "kills", "deaths" }) do
        eq(totals[key], summary[key], "breakdown reconciles " .. dimension .. " " .. key)
    end
    return map, totals
end

reset()
eq(GL.Settings().readingScale, 1, "default readable size")
eq(GL.Settings().compactMode, false, "default spacing")
eq(GL.Settings().guideSeen, false, "first-run guide")
assert(GL.SetSetting("guideSeen", true) and GL.SetSetting("compactMode", true))
assert(GL.SetSetting("readingScale", 99))
eq(GL.Settings().readingScale, 1.25, "maximum reading size")
assert(GL.SetSetting("readingScale", 0))
eq(GL.Settings().readingScale, 0.85, "minimum reading size")
assert(not GL.SetSetting("readingScale", "large") and not GL.SetSetting("readingScale", 0/0))
assert(not GL.SetSetting("readingScale", math.huge) and not GL.SetSetting("guideSeen", 1))
GL.InitDB()
eq(GL.Settings().guideSeen, true, "guide completion survives reload")
assert(GL.SetSetting("guideSeen", false))
eq(GL.Settings().guideSeen, false, "guide can replay")
GL.db.settings.readingScale, GL.db.settings.compactMode = -math.huge, "true"
GL.InitDB()
eq(GL.Settings().readingScale, 1, "invalid saved size falls back safely")
eq(GL.Settings().compactMode, false, "invalid saved boolean falls back safely")

reset()
local a, b, c = person("Alpha", "Orc", "WARRIOR"), person("Beta", "Troll", "MAGE"), person("Charlie", "Orc", "WARRIOR")
a.guild = "OldGuild"
zone, subzone = "OldPlace", "OldQuarter"
local record, event = add(a, "kill", "confirmed", "old-fight")
eq(event.opponentName, "Alpha Example", "event name snapshot")
eq(event.race, "Orc", "event race snapshot")
eq(event.class, "WARRIOR", "event class snapshot")
local renamed = GL.IdentityFromName("Newname", "Example", a.guid)
renamed.guild, renamed.race, renamed.class = "NewGuild", "Human", "PALADIN"
now, zone, subzone = anchor + 1, "NewPlace", "NewQuarter"
GL.Remember(renamed)
add(renamed, "kill", "confirmed", "new-fight")
eq(GL.SearchPlayers({ query = "alpha oldguild oldplace" })[1], record, "search retains historical identity, guild and place")
eq(GL.SearchPlayers({ query = "oldquarter" })[1], record, "search includes historical subzone")
eq(#GL.JournalEvents({ query = "oldplace" }), 1, "history search matches the relevant event only")
eq(#GL.JournalEvents({ query = "oldguild" }), 1, "old guild is not attached to later events")
assert(GL.AddNote(renamed, "DisposableNote"))
assert(GL.DeleteNote(renamed, record.notes[1]))
eq(#GL.SearchPlayers({ query = "disposablenote" }), 0, "history does not resurrect deleted notes")
eq(event.race, "Orc", "later identity never rewrites old snapshots")
eq(event.class, "WARRIOR", "later class never rewrites old snapshots")
eq(record.lastEncounterAt, nil, "manual records do not invent encounters")
GL.RecordGroup(renamed, "party-session", zone)
eq(record.lastEncounterAt, nil, "joining a party is not a sighting")
GL.RecordSeen(renamed, true)
eq(record.lastEncounterAt, now, "public sighting time")
eq(record.lastEncounterZone, zone, "public sighting zone")
eq(record.lastEncounterSubzone, subzone, "public sighting subzone")
local encounterAt = now
now, zone, subzone = now + 601, "RemotePlace", "RemoteQuarter"
assert(GL.AddNote(renamed, "Edited from elsewhere"))
eq(record.lastEncounterAt, encounterAt, "note edit cannot impersonate a sighting")
eq(record.lastEncounterZone, "NewPlace", "note edit cannot replace last observed place")
GL.RecordSeen(renamed, false)
eq(record.lastEncounterAt, encounterAt, "metadata refresh is not a sighting")
GL.RecordSeen(renamed, true)
eq(record.encounters.count, 2, "separated actual encounters count")
eq(record.lastEncounterZone, "RemotePlace", "new public observation updates actual place")

reset()
local provisional = GL.IdentityFromName("Merged", "Example")
local live = GL.IdentityFromName("Merged", nil, "Player-1-merge")
GL.Remember(live)
GL.RecordSeen(live, true)
now, zone, subzone = now + 1, "MergePlace", "MergeQuarter"
GL.Remember(provisional)
GL.RecordSeen(provisional, true)
local merged = GL.Remember(GL.IdentityFromName("Merged", "Example", "Player-1-merge"))
eq(merged.lastEncounterAt, now, "identity merge retains latest true observation")
eq(merged.lastEncounterZone, "MergePlace", "identity merge retains its observed place")
merged.lastEncounterAt = "invalid"
GL.InitDB()
eq(merged.lastEncounterAt, now, "legacy observation restored from the last recorded sighting")
eq(merged.lastEncounterZone, nil, "a place without observed time is not presented as a sighting")
merged.encounters.seen, merged.lastEncounterAt = {}, nil
GL.InitDB()
eq(merged.lastEncounterAt, nil, "notes and group timestamps never stand in for an unknown sighting")

reset()
provisional.race, provisional.class = "Orc", "WARRIOR"
live.race, live.class = "Troll", "MAGE"
add(provisional, "kill", "confirmed", "merged-kill")
add(live, "kill", "confirmed", "merged-kill")
GL.Remember(GL.IdentityFromName("Merged", "Example", "Player-1-merge"))
eq(breakdown(nil, "race").Troll.kills, 1, "same victim and event deduplicate after identity merge")
eq(breakdown(nil, "class").MAGE.kills, 1, "merged confirmed snapshot supersedes probable snapshot")

reset()
add(a, "death", "confirmed", "mixed-death")
add(b, "death", "confirmed", "mixed-death")
local races = breakdown(nil, "race")
eq(races.mixed.deaths, 1, "shared mixed-race death remains one death")
eq(races.mixed.label, "Groupe mixte", "mixed group is explicit")
local _, certain = add(c, "death", "confirmed", "mixed-death")
races = breakdown(nil, "race")
eq(races.mixed.deaths, 1, "explicit lethal attribution supersedes probable participants")
eq(races.Orc, nil, "probable mixed group cannot dilute confirmation")
local classes = breakdown(nil, "class")
eq(classes.mixed.deaths, 1, "confirmed class attribution")
assert(GL.VoidPvP(c, certain, true))
eq(certain.voidedByGUID, actor, "manual correction author")
eq(certain.voidedByName, "Testeur Exemple", "manual correction author name")
local totals
races, totals = breakdown(nil, "race")
eq(races.mixed.deaths, 1, "remaining probable evidence stays probable")
eq(races.Orc.correctedDeaths, 1, "manual correction is separate from active counts")
eq(totals.correctedDeaths, 1, "one corrected report")
add(c, "kill", "confirmed", "one-kill")
local unknown = person("Unknown")
local legacyRecord, legacy = add(unknown, "kill", "confirmed")
legacy.actorGUID, legacy.actorName = nil, nil
unknown.race, unknown.class = "Dwarf", "SHAMAN"
GL.Remember(unknown)
GL.InitDB()
races = breakdown({ scope = "legacy" }, "race")
eq(races.unknown.kills, 1, "legacy race is never backfilled from current identity")
eq(legacy.race, nil, "old event remains untouched")
mock.units.player.guid = "Player-1-alt"
add(b, "kill", "confirmed", "other-alt")
eq(breakdown(nil, "race").Troll.kills, 1, "current character scope")
mock.units.player.guid = actor
eq(breakdown(nil, "race").Orc.kills, 1, "switching character invalidates cached result")
breakdown({ scope = "all" }, "race")
local result = GL.PvPBreakdown(nil, "race")
result[1].deaths, result[1].label = 999, "corrupt"
races = breakdown(nil, "race")
assert(not races.corrupt and races.mixed.deaths ~= 999, "caller cannot corrupt cached breakdown")
eq(#GL.PvPBreakdown(nil, "invalid"), 0, "unsupported dimension rejected")

-- Reversing history order cannot select a different race/class for one death.
reset()
local missing = person("Missing")
add(a, "death", "confirmed", "unknown-shared")
local missingRecord, missingEvent = add(missing, "death", "confirmed", "unknown-shared")
eq(breakdown(nil, "race").unknown.deaths, 1, "missing participant identity is explicit")
local oneRecord = GL.Get(a)
oneRecord.history[#oneRecord.history + 1] = missingEvent
missingRecord.history = {}
oneRecord.history[1], oneRecord.history[2] = oneRecord.history[2], oneRecord.history[1]
GL.Emit("CHANGED")
eq(breakdown(nil, "race").unknown.deaths, 1, "unknown categorization is order independent")
assert(GL.VoidPvP(oneRecord, oneRecord.history[1], true))
assert(GL.VoidPvP(oneRecord, oneRecord.history[2], true))
eq(breakdown(nil, "race").unknown.correctedDeaths, 1, "correction rows deduplicate one shared death")
local _, bg = add(b, "kill", "confirmed", "bg-cleanup")
assert(GL.VoidPvP(b, bg, true))
bg.voidReason = "battleground"
GL.Emit("CHANGED")
local _, cleanTotals = breakdown(nil, "race")
eq(cleanTotals.correctedKills, 0, "automatic battleground cleanup is not a manual correction")

reset()
now = anchor - 7 * 86400
add(a, "kill", "confirmed", "week-boundary")
now = anchor + 5
add(b, "kill", "confirmed", "future")
now = os.time({ year = 2025, month = 12, day = 31, hour = 12 })
local oldRecord, oldEvent = add(c, "kill", "confirmed", "prior-year")
now = anchor
assert(GL.VoidPvP(oldRecord, oldEvent, true))
eq(breakdown({ period = "week" }, "race").Orc.kills, 1, "inclusive rolling boundary")
now = anchor + 1
eq(#GL.PvPBreakdown({ period = "week" }, "race"), 0, "rolling cached result expires")
now = anchor
local _, present = breakdown({ period = "year", year = 2026 }, "race")
eq(present.correctedKills, 0, "corrections follow original event period")
eq(breakdown({ period = "year", year = 2025 }, "race").Orc.correctedKills, 1, "historical correction remains in historical year")
breakdown(nil, "race")
now = anchor + 5
eq(breakdown(nil, "race").Troll.kills, 1, "future event becomes eligible without a write")
reset()
zone = "Vallée de Strangleronce"
add(a, "death", "confirmed", "one-death")
add(b, "death", "confirmed", "one-death")
zone = "?"
local _, unknownPlace = add(c, "kill", "confirmed", "unmapped")
zone = "Hurlevent"
GL.RecordSeen(c, true)
local places = breakdown(nil, "zone")
eq(places["Vallée de Strangleronce"].deaths, 1, "confirmed fatal hit wins over other participants")
eq(places.unknown.kills, 1, "new sightings cannot supply an old combat location")
eq(places["Hurlevent"], nil, "peaceful visits never count as combat")
assert(GL.VoidPvP(c, unknownPlace, true))
eq(breakdown(nil, "zone").unknown.correctedKills, 1, "corrected fight is excluded from zone wins")
reset()
zone, subzone = "Zone A", "Dock"
add(a, "death", "confirmed", "shared-zones")
zone, subzone = "Zone B", "Dock"
add(b, "death", "confirmed", "shared-zones")
assert(#GL.PvPBreakdown({zone="Zone A"}, "subzone") == 0, "filtering early must not duplicate a shared death")
local districts = GL.PvPBreakdown({zone="Zone B"}, "subzone")
assert(#districts == 0)
subzone = "Zone B"
add(c, "kill", "confirmed", "generic-zone")
districts = GL.PvPBreakdown({zone="Zone B"}, "subzone")
assert(#districts == 1 and districts[1].key == "unknown")
print("PASS campaign data: validated settings, historical search, observed encounters, identity snapshots, deduplicated race/class PvP, corrections, scopes and periods")
