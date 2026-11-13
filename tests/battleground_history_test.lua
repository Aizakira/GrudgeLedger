local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
local zone = "Bassin Arathi"
GetRealZoneText = function() return zone end
local function identity(name, guild)
    local id = GL.IdentityFromName(name, "Example", "Player-1-" .. name)
    id.guild, id.realm = guild, "Forever"
    return id
end
-- Build a pre-pause save through the public recording functions (no instance API).
local onlyID = identity("BattlegroundOnly", "Match Guild")
local only
for _, confidence in ipairs({ "confirmed", "probable" }) do
    only = GL.RecordAggression(onlyID, confidence, "Original evidence", "hit-" .. confidence)
    GL.RecordPvP(onlyID, "death", confidence, "Original evidence", "death-" .. confidence)
    GL.RecordPvP(onlyID, "kill", confidence, "Original evidence", "kill-" .. confidence)
end
GL.RecordSeen(onlyID, true)
local first = only.history[1]
local originalTime, originalID = first.time, first.eventId
GL.db.aliases["another-alias"] = only.key
assert(only.reputation < 0 and #only.history == 6)

local mixedID = identity("Mixed", "Shared Guild")
zone = "Warsong Gulch"
local mixed = GL.RecordPvP(mixedID, "death", "probable", "Match evidence", "mixed-bg")
local bgDeath = mixed.history[1]
zone = "Vallée de Strangleronce"
GL.RecordPvP(mixedID, "death", "confirmed", "Outdoor evidence", "mixed-world")
GL.RecordAggression(mixedID, "confirmed", "Outdoor evidence", "mixed-hit")
GL.AdjustReputation(mixedID, -1, "Personal gesture", "emote")
local outdoorDeath = mixed.history[2]

zone = "Goulet des Chanteguerres"
local noted = GL.RecordPvP(identity("Noted"), "death", "confirmed", "Match evidence", "noted-bg")
GL.AddNote(noted, "Keep my personal note")
local manual = GL.SetReaction(identity("Manual"), "enemy")
GL.RecordPvP(manual, "death", "confirmed", "Match evidence", "manual-bg")
local positive = GL.AdjustReputation(identity("Positive"), 1, "KISS", "emote")
GL.RecordPvP(positive, "death", "confirmed", "Match evidence", "positive-bg")
local unknown = GL.RecordPvP(identity("Unknown"), "death", "confirmed", "Unlocated evidence", "unknown")
unknown.history[1].zone = nil
zone = "Hautes-terres Arathies"
local world = GL.RecordPvP(identity("Outdoor"), "death", "confirmed", "World evidence", "world")
zone = "Arathi Basin"
local counters = GL.RecordPvP(identity("UnexplainedCounters"), "death", "confirmed", "Match evidence", "counters")
counters.pvp.deaths = 2 -- one older event has no surviving location
local corrected = GL.RecordPvP(identity("Corrected"), "death", "confirmed", "Match evidence", "corrected")
assert(GL.VoidPvP(corrected, corrected.history[1]))
local correctionTime = corrected.history[1].voidedAt
local ambiguous = GL.RecordPvP(identity("Ambiguous"), "death", "confirmed", "Match evidence", "ambiguous")
ambiguous.history[1].confidence = "unknown"
GL.SetGuildReaction("Match Guild", "warning", "Keep explicit guild rule")

GL.db.battlegroundCleanupVersion = nil
local changes, ready = 0, 0
GL.On("CHANGED", function() changes = changes + 1 end)
GL.On("READY", function() ready = ready + 1 end)
GL.InitDB()
assert(changes == 0 and ready == 1, "migration must not trigger observations against a partially migrated DB")
assert(not GL.Get(onlyID) and not GL.Get(onlyID.alias) and not GL.db.aliases["another-alias"])
assert(#GL.db.battlegroundArchive == 2 and not GL.Get(corrected))
local archived = {}
for _, record in ipairs(GL.db.battlegroundArchive) do archived[record.key] = record end
assert(archived[only.key] == only and #only.history == 6 and only.encounters.count == 1)
for _, value in pairs(only.pvp) do assert(value == 0, "all six counter types must be reversed") end
assert(first.voided and first.voidReason == "battleground" and first.time == originalTime and first.eventId == originalID)
assert(first.evidence == "Original evidence" and first.zone == "Bassin Arathi")
assert(corrected.history[1].voidedAt == correctionTime and not corrected.history[1].voidReason, "do not reapply a previous correction")
assert(GL.Get(mixedID) == mixed and mixed.reputation == -12 and GL.Relation(mixed) == "enemy")
assert(mixed.pvp.probableDeaths == 0 and mixed.pvp.deaths == 1 and mixed.pvp.aggressions == 1)
assert(bgDeath.voided and bgDeath.voidReason == "battleground" and not outdoorDeath.voided and #mixed.history == 4)
assert(GL.Get(noted) == noted and noted.notes[1].text == "Keep my personal note" and noted.reputation == 0)
assert(GL.Get(manual) == manual and manual.reputation == -10 and manual.reactionSource == "manual")
assert(GL.Get(positive) == positive and positive.reputation == 1 and GL.Relation(positive) == "friend")
assert(unknown.pvp.deaths == 1 and not unknown.history[1].voided)
assert(world.pvp.deaths == 1 and not world.history[1].voided, "outdoor Arathi must not match a battleground")
assert(GL.Get(counters) == counters and counters.pvp.deaths == 1 and counters.reputation == -10)
assert(GL.Get(ambiguous) == ambiguous and ambiguous.pvp.deaths == 1 and not ambiguous.history[1].voided)
assert(GL.GetGuildRule("Match Guild").note == "Keep explicit guild rule")
for _, stat in ipairs(GL.GuildStatistics()) do
    if stat.name == "Match Guild" then
        assert(stat.members == 0 and stat.probableDeaths == 0 and stat.deaths == 0 and stat.aggressions == 0 and stat.kills == 0)
    elseif stat.name == "Shared Guild" then
        assert(stat.members == 1 and stat.deaths == 1 and stat.probableDeaths == 0 and stat.aggressions == 1)
    end
end
for _, stat in ipairs(GL.PlayerStatistics("grudge")) do assert(stat.record ~= only) end
assert(#GL.PlayerStatistics("probableDeaths") == 0)
local messageCount = #mock.messages
GL.InitDB()
assert(#GL.db.battlegroundArchive == 2 and #mock.messages == messageCount and mixed.reputation == -12)
assert(counters.pvp.deaths == 1 and changes == 0, "reloading must never subtract twice")
assert(not GL.RecordPvP(mixedID, "death", "probable", "Duplicate", "mixed-bg"), "voided evidence still deduplicates")

-- Returning outdoors starts a fresh record instead of resurrecting the match debt.
zone = "Vallée de Strangleronce"
local fresh = GL.RecordAggression(onlyID, "confirmed", "New outdoor attack", "fresh-hit")
assert(fresh ~= only and fresh.reputation == -1 and #fresh.history == 1 and GL.Get(onlyID.alias) == fresh)
assert(#only.history == 6 and #GL.db.battlegroundArchive == 2 and changes == 1)

-- Mixed histories explain the exclusion in both journal and correction UI.
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
GL.ShowLedger(mixed.key)
GrudgeLedgerWindow.detailTabs.history.scripts.OnClick(GrudgeLedgerWindow.detailTabs.history, "LeftButton")
assert(GrudgeLedgerWindow.detailText:GetText():find("champ de bataille, non comptabilisé", 1, true))
GrudgeLedgerWindow.tools.scripts.OnClick()
for _, child in ipairs(GrudgeLedgerWindow.toolsMenu.children) do
    if child.text == "Corriger le PvP" then child.scripts.OnClick(child, "LeftButton") end
end
local row = GrudgeLedgerCorrections.rows[3]
assert(row.title:GetText():find("champ de bataille, exclu", 1, true) and row.undo.enabled == false)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)

-- Archives are ordinary private SavedVariables, with no cycles or shared tables.
local seen = {}
local function serializable(value)
    if type(value) ~= "table" then
        assert(type(value) == "string" or type(value) == "number" or type(value) == "boolean")
        return
    end
    assert(not seen[value], "saved tables must not alias or form cycles")
    seen[value] = true
    for key, item in pairs(value) do serializable(key) serializable(item) end
end
serializable(GL.db)
GrudgeLedgerDB = nil
GL.InitDB()
assert(next(GL.db.players) == nil and not GL.db.battlegroundArchive, "new accounts stay empty")
print("PASS battleground cleanup: exact locations, six counters, archival, mixed histories, personal choices/notes, ambiguity, idempotence, statistics, aliases, outdoor return and UI")
