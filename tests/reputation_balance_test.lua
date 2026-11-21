dofile(TEST_WORK .. "/tests/wow_mock.lua")
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
-- These assertions were written with the weights of before 0.42.0; they are pinned here.
GL.SetSetting("grudgeAggression", 5) GL.SetSetting("grudgeDeath", 5) GL.SetSetting("grudgeVictory", 1)
local id = GL.IdentityFromName("Balance", "Example", "Player-1-balance")
local r = GL.RecordPvP(id, "kill", "confirmed", "Observed", "k1")
assert(r.reputation == 0 and GL.Relation(r) == "neutral", "a victory never creates friendship")
GL.RecordPvP(id, "death", "confirmed", "Observed", "d1")
GL.AdjustReputation(id, -1, "SPIT", "emote")
GL.RecordPvP(id, "kill", "confirmed", "Observed", "k2")
-- 0.26.0 weights: a death -5, an aggression -5, a victory +1.
assert(r.reputation == -4 and GL.Relation(r) == "warning" and GL.RelationSource(r) == "pvp")
assert(GL.RelationConfidence(r) == "confirmed", "a remaining debt from an inferred death stays uncertain")
assert(not GL.RecordPvP(id, "kill", "confirmed", "Duplicate", "k2") and r.reputation == -4)
GL.InitDB()
assert(r.reputation == -4, "reload must not apply victories twice")
assert(GL.VoidPvP(id, r.history[#r.history]) and r.reputation == -5 and GL.Relation(r) == "enemy")
assert(not GL.VoidPvP(id, r.history[#r.history]) and r.reputation == -5)
GL.RecordPvP(id, "kill", "confirmed", "Direct", "k3")
assert(r.reputation == -4 and GL.RelationConfidence(r) == "confirmed", "a confirmed victory does not prove the death")
for i = 4, 6 do GL.RecordPvP(id, "kill", "confirmed", "Direct", "k" .. i) end
assert(r.reputation == -1 and GL.Relation(r) == "warning")
GL.RecordPvP(id, "kill", "confirmed", "Direct", "k7")
assert(r.reputation == 0 and GL.Relation(r) == "neutral", "only the fully repaid debt becomes neutral")
GL.RecordPvP(id, "kill", "confirmed", "Direct", "k8")
assert(r.reputation == 0 and GL.Relation(r) == "neutral")
GL.RecordPvP(id, "death", "confirmed", "Direct", "d2")
assert(r.reputation == -4 and GL.Relation(r) == "warning" and GL.RelationConfidence(r) == "confirmed")
-- An aggression goes in the grudge book: -5 at once, and the aggressor stays an enemy even
-- after you kill him. His reply to an attack you opened counts -1 and does not make him one.
local hit = GL.IdentityFromName("Aggressive", "Example", "Player-1-hit")
local aggressor = GL.RecordAggression(hit, "confirmed", "Observed", "a1")
assert(aggressor.reputation == -5 and GL.Relation(aggressor) == "enemy")
for i = 1, 6 do GL.RecordPvP(hit, "kill", "confirmed", "Direct", "hk" .. i) end
assert(aggressor.reputation == 0 and GL.Relation(aggressor) == "enemy", "killing an aggressor does not clear him")
GL.RecordPvP(hit, "death", "confirmed", "Direct", "hd1")
assert(aggressor.reputation == -4 and GL.Relation(aggressor) == "enemy")
local reply = GL.IdentityFromName("Defending", "Example", "Player-1-reply")
local defender = GL.RecordAggression(reply, "confirmed", "Observed", "r1", {opener = "player", encounterId = "fight-r1"})
assert(defender.reputation == -1 and GL.Relation(defender) == "neutral" and GL.ProvokedAggressions(defender) == 1,
    "a reply to your own attack is not an aggression")

-- 0.32.0: each player chooses the weights; every automatic balance follows at once.
local tuned = GL.IdentityFromName("Tuned", "Weights", "Player-1-tuned")
local t = GL.RecordAggression(tuned, "confirmed", "Observed", "tuned-a")
GL.RecordPvP(tuned, "death", "confirmed", "Direct", "tuned-d")
assert(t.reputation == -10 and GL.BalanceFormula(t) == "1 agression × −5  ·  1 mort × −5")
assert(GL.SetSetting("grudgeDeath", 2) and GL.SetSetting("grudgeAggression", 1))
assert(t.reputation == -3 and GL.BalanceFormula(t) == "1 agression × −1  ·  1 mort × −2", GL.BalanceFormula(t))
assert(GL.Relation(t) == "enemy", "an aggressor stays an enemy whatever the weights")
assert(GL.SetSetting("grudgeDeath", 99) and GL.Settings().grudgeDeath == 10, "weights are bounded to 0..10")
assert(GL.SetSetting("grudgeAggression", -3) and GL.Settings().grudgeAggression == 0)
assert(t.reputation == -10 and not GL.SetSetting("grudgeDeath", "5"))
assert(GL.SetSetting("grudgeDeath", 5) and GL.SetSetting("grudgeAggression", 5) and t.reputation == -10)

-- Rebuild a pre-0.4.2 cached score, preserving counters, evidence and notes.
local legacy = GL.Remember(GL.IdentityFromName("Legacy", "Balance", "Player-1-old-balance"))
legacy.reaction, legacy.reactionSource, legacy.reputation = "enemy", "emote", -11
legacy.pvp.probableDeaths, legacy.pvp.probableKills = 1, 2
legacy.history = { {kind="kill", confidence="probable"}, {kind="death", confidence="probable"},
    {kind="reputation", source="emote", delta=-1, reputation=-11}, {kind="kill", confidence="probable"} }
legacy.notes = { {text="Keep this note"} }
GL.InitDB()
assert(legacy.reputation == -4 and GL.Relation(legacy) == "warning" and #legacy.history == 4)
assert(legacy.notes[1].text == "Keep this note" and legacy.history[3].reputation == -11, "historical evidence is immutable")
GL.InitDB()
assert(legacy.reputation == -4 and legacy.pvp.deaths == 1 and legacy.pvp.kills == 2)
assert(legacy.pvp.probableDeaths == nil and legacy.history[2].confidence == "confirmed")

-- Issue #22: one previously attributed death stays one through two reloads.
local migrated = GL.Remember(GL.IdentityFromName("Migration", "Example", "Player-1-migration"))
migrated.pvp.probableDeaths, migrated.pvp.probableAggressions = 1, 1
migrated.history = {
    {kind="death", confidence="probable", eventId="old-death"},
    {kind="aggression", confidence="probable", eventId="old-attack"},
}
for _ = 1, 2 do
    GL.InitDB()
    assert(migrated.pvp.deaths == 1 and migrated.pvp.aggressions == 1 and migrated.reputation == -10)
end
assert(not GL.RecordPvP(migrated, "death", "confirmed", "Repeated signal", "old-death"))
GL.RecordPvP(migrated, "death", "confirmed", "New encounter", "new-death")
assert(migrated.pvp.deaths == 2 and migrated.reputation == -15)

-- A later Neutral click used to pin this same outstanding debt at zero.
legacy.reaction, legacy.reactionSource, legacy.reputation = "neutral", "manual", 0
table.insert(legacy.history, {kind="reaction", reaction="neutral"})
GL.InitDB()
assert(legacy.reputation == -4 and GL.Relation(legacy) == "warning" and legacy.reactionSource == "automatic")
assert(GL.RelationConfidence(legacy) == "confirmed" and #legacy.history == 5)
assert(legacy.history[5].reaction == "neutral" and legacy.history[3].reputation == -11 and legacy.notes[1].text == "Keep this note")
GL.InitDB()
GL.SetReaction(legacy, "neutral")
assert(legacy.reputation == -4 and #legacy.history == 5, "reload and repeated automatic action cannot reset debt or duplicate history")
GL.RecordPvP(legacy, "kill", "confirmed", "Direct", "migrated-kill")
assert(legacy.reputation == -3 and GL.Relation(legacy) == "warning")
assert(GL.VoidPvP(legacy, legacy.history[#legacy.history]) and legacy.reputation == -4)
GL.SetReaction(legacy, "friend")
GL.SetReaction(legacy, "neutral")
assert(legacy.reputation == -4 and GL.Relation(legacy) == "warning")
assert(legacy.history[#legacy.history].source == "automatic", "returning to automatic is recorded honestly")
GL.AdjustReputation(legacy, -1, "SPIT", "emote")
assert(legacy.reputation == -5 and GL.Relation(legacy) == "enemy", "gestures keep working after automatic migration")

-- A genuine zero reached with a manual opinion remains an explicit choice.
local zero = GL.SetReaction(GL.IdentityFromName("Manual", "Zero", "Player-1-manual-zero"), "warning")
GL.AdjustReputation(zero, 1, "Opinion", "manual")
GL.RecordPvP(zero, "death", "confirmed", "Direct", "manual-zero-death")
GL.InitDB()
assert(zero.reputation == 0 and GL.Relation(zero) == "neutral" and zero.reactionSource == "manual")
local auto, pvp = GL.AutomaticBalance(zero)
assert(auto == -5 and pvp == -5 and zero.reputation == 0 and GL.Relation(zero) == "neutral",
    "viewing the automatic balance must not change a personal classification")

-- Positive gestures do not hide outstanding PvP danger; corrections restore them.
local friendly = GL.IdentityFromName("Gestures", "Balance", "Player-1-gestures-balance")
local f = GL.AdjustReputation(friendly, 1, "KISS", "emote")
GL.RecordPvP(friendly, "death", "confirmed", "Direct", "friendly-death")
local death = f.history[#f.history]
GL.AdjustReputation(friendly, 1, "WINK", "emote")
assert(f.reputation == -5 and GL.Relation(f) == "enemy")
assert(GL.VoidPvP(friendly, death) and f.reputation == 2 and GL.Relation(f) == "friend")
GL.SetReaction(id, "enemy")
GL.RecordPvP(id, "kill", "confirmed", "Direct", "pinned-kill")
assert(r.reputation == -10 and GL.Relation(r) == "enemy", "explicit classifications remain authoritative")

local capped = GL.IdentityFromName("Capped", "Balance", "Player-1-capped-balance")
for i=1,21 do GL.RecordPvP(capped, "death", "confirmed", "Direct", "cap-d" .. i) end
local c = GL.RecordPvP(capped, "kill", "confirmed", "Direct", "cap-k1")
assert(c.reputation == -100, "the displayed floor must not erase debt below -100")
for i=2,6 do GL.RecordPvP(capped, "kill", "confirmed", "Direct", "cap-k" .. i) end
assert(c.reputation == -99)

local alias = GL.IdentityFromName("Merged", "Balance")
GL.AdjustReputation(alias, -1, "SPIT", "emote")
local live = GL.IdentityFromName("Merged", "Balance", "Player-1-merged-balance")
GL.RecordPvP(GL.IdentityFromName("Merged", nil, live.guid), "death", "confirmed", "Direct", "merge-d")
local merged = GL.Remember(live)
GL.RecordPvP(live, "kill", "confirmed", "Direct", "merge-k")
assert(merged.reputation == -5 and GL.Relation(merged) == "enemy", "identity merging retains both social and PvP debts")
print("PASS reputation balance: gradual repayment, migration, reload, corrections, dedup, confidence, manual precedence, saturation and identity merge")
