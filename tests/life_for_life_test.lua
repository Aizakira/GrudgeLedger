-- "A life for a life" (0.42.0, owner's decision): with -5 for an aggression, -5 for a death and +1
-- for a victory, a killer owed 10 and ten victories were needed, so no debt was ever struck out.
-- Defaults are now aggression -2, death -5, victory +5; all three are settings.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local now = 1000
GetServerTime = function() return now end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
assert(GL.Settings().grudgeAggression == 2 and GL.Settings().grudgeDeath == 5 and GL.Settings().grudgeVictory == 5)
assert(GL.db.migrations[4] and GL.db.replacedWeights == nil, "a new journal has nothing to replace")
local killer = GL.IdentityFromName("Life", "Taker", "Player-9-0001")
local record = GL.RecordAggression(killer, "confirmed", nil, "a1")
assert(record.reputation == -2)
now = now + 30
GL.RecordPvP(killer, "death", "confirmed", "Direct", "d1")
assert(record.reputation == -7 and GL.Debt(record) == 7 and GL.Relation(record) == "enemy")
-- One revenge settles the death and leaves the trace of the aggression; a second one clears it.
now = now + 600
GL.RecordPvP(killer, "kill", "confirmed", "Direct", "k1")
assert(record.reputation == -2 and GL.Debt(record) == 2, record.reputation)
assert(GL.BalanceFormula(record) == "1 agression × −2  ·  1 mort × −5  ·  1 victoire × +5", GL.BalanceFormula(record))
now = now + 600
GL.RecordPvP(killer, "kill", "confirmed", "Direct", "k2")
assert(GL.Debt(record) == 0 and record.reputation == 0, "victories never make a friend")
-- The victory weight is a setting, bounded like the others, and recomputes every balance at once.
assert(GL.SetSetting("grudgeVictory", 1) and record.reputation == -5 and GL.SetSetting("grudgeVictory", 99) and GL.Settings().grudgeVictory == 10)
assert(GL.SetSetting("grudgeVictory", 5))

-- Migration 4 on a journal of the previous version: weights left at the old defaults move to the
-- new ones, what they replaced is kept, and the stored balances are recomputed.
local function reload(settings)
    GrudgeLedgerDB = { settings = settings, migrations = { [1] = 0, [2] = 0, [3] = 0 }, schema = 2, players = {
        ["guid:Player-9-0002"] = { key = "guid:Player-9-0002", guid = "Player-9-0002", name = "Old", surname = "Debt", reputation = -10,
            pvp = { kills = 1, deaths = 1, aggressions = 1 }, history = {}, notes = {} } } }
    GrudgeLedger = nil
    assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
    GrudgeLedger.InitDB()
    return GrudgeLedger
end
local old = reload({ grudgeAggression = 5, grudgeDeath = 5 })
assert(old.Settings().grudgeAggression == 2 and old.Settings().grudgeDeath == 5 and old.Settings().grudgeVictory == 5)
assert(old.db.replacedWeights.aggression == 5 and old.db.replacedWeights.death == 5 and old.db.replacedWeights.victory == 1)
assert(old.Get("guid:Player-9-0002").reputation == -2, old.Get("guid:Player-9-0002").reputation)
-- Weights the player chose are kept; only the victory, which had no setting, takes its default.
local chosen = reload({ grudgeAggression = 3, grudgeDeath = 8 })
assert(chosen.Settings().grudgeAggression == 3 and chosen.Settings().grudgeDeath == 8 and chosen.Settings().grudgeVictory == 5)
assert(chosen.Get("guid:Player-9-0002").reputation == -6)
-- The migration runs once: weights set back to 5 afterwards stay where the player put them.
chosen.SetSetting("grudgeAggression", 5)
local saved = GrudgeLedgerDB
GrudgeLedger = nil
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
GrudgeLedgerDB = saved
GrudgeLedger.InitDB()
assert(GrudgeLedger.Settings().grudgeAggression == 5)
print("PASS a life for a life: new defaults, one revenge settles one death, adjustable victory, migration 4 keeps chosen weights")
