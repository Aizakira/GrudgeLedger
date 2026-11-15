dofile(TEST_WORK .. "/tests/wow_mock.lua")
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
local id = GL.IdentityFromName("Balance", "Example", "Player-1-balance")
local r = GL.RecordPvP(id, "kill", "confirmed", "Observed", "k1")
assert(r.reputation == 0 and GL.Relation(r) == "neutral", "a victory never creates friendship")
GL.RecordPvP(id, "death", "confirmed", "Observed", "d1")
GL.AdjustReputation(id, -1, "SPIT", "emote")
GL.RecordPvP(id, "kill", "confirmed", "Observed", "k2")
assert(r.reputation == -9 and GL.Relation(r) == "warning" and GL.RelationSource(r) == "pvp")
assert(GL.RelationConfidence(r) == "confirmed", "a remaining debt from an inferred death stays uncertain")
assert(not GL.RecordPvP(id, "kill", "confirmed", "Duplicate", "k2") and r.reputation == -9)
GL.InitDB()
assert(r.reputation == -9, "reload must not apply victories twice")
assert(GL.VoidPvP(id, r.history[#r.history]) and r.reputation == -10 and GL.Relation(r) == "enemy")
assert(not GL.VoidPvP(id, r.history[#r.history]) and r.reputation == -10)
GL.RecordPvP(id, "kill", "confirmed", "Direct", "k3")
assert(r.reputation == -9 and GL.RelationConfidence(r) == "confirmed", "a confirmed victory does not prove the death")
for i = 4, 11 do GL.RecordPvP(id, "kill", "confirmed", "Direct", "k" .. i) end
assert(r.reputation == -1 and GL.Relation(r) == "warning")
GL.RecordPvP(id, "kill", "confirmed", "Direct", "k12")
assert(r.reputation == 0 and GL.Relation(r) == "neutral", "only the fully repaid debt becomes neutral")
GL.RecordPvP(id, "kill", "confirmed", "Direct", "k13")
assert(r.reputation == 0 and GL.Relation(r) == "neutral")
GL.RecordPvP(id, "death", "confirmed", "Direct", "d2")
assert(r.reputation == -9 and GL.Relation(r) == "warning" and GL.RelationConfidence(r) == "confirmed")

-- Rebuild a pre-0.4.2 cached score, preserving counters, evidence and notes.
local legacy = GL.Remember(GL.IdentityFromName("Legacy", "Balance", "Player-1-old-balance"))
legacy.reaction, legacy.reactionSource, legacy.reputation = "enemy", "emote", -11
legacy.pvp.probableDeaths, legacy.pvp.probableKills = 1, 2
legacy.history = { {kind="kill", confidence="probable"}, {kind="death", confidence="probable"},
    {kind="reputation", source="emote", delta=-1, reputation=-11}, {kind="kill", confidence="probable"} }
legacy.notes = { {text="Keep this note"} }
GL.InitDB()
assert(legacy.reputation == -9 and GL.Relation(legacy) == "warning" and #legacy.history == 4)
assert(legacy.notes[1].text == "Keep this note" and legacy.history[3].reputation == -11, "historical evidence is immutable")
GL.InitDB()
assert(legacy.reputation == -9 and legacy.pvp.deaths == 1 and legacy.pvp.kills == 2)
assert(legacy.pvp.probableDeaths == nil and legacy.history[2].confidence == "confirmed")

-- A later Neutral click used to pin this same outstanding debt at zero.
legacy.reaction, legacy.reactionSource, legacy.reputation = "neutral", "manual", 0
table.insert(legacy.history, {kind="reaction", reaction="neutral"})
GL.InitDB()
assert(legacy.reputation == -9 and GL.Relation(legacy) == "warning" and legacy.reactionSource == "automatic")
assert(GL.RelationConfidence(legacy) == "confirmed" and #legacy.history == 5)
assert(legacy.history[5].reaction == "neutral" and legacy.history[3].reputation == -11 and legacy.notes[1].text == "Keep this note")
GL.InitDB()
GL.SetReaction(legacy, "neutral")
assert(legacy.reputation == -9 and #legacy.history == 5, "reload and repeated automatic action cannot reset debt or duplicate history")
GL.RecordPvP(legacy, "kill", "confirmed", "Direct", "migrated-kill")
assert(legacy.reputation == -8 and GL.Relation(legacy) == "warning")
assert(GL.VoidPvP(legacy, legacy.history[#legacy.history]) and legacy.reputation == -9)
GL.SetReaction(legacy, "friend")
GL.SetReaction(legacy, "neutral")
assert(legacy.reputation == -9 and GL.Relation(legacy) == "warning")
assert(legacy.history[#legacy.history].source == "automatic", "returning to automatic is recorded honestly")
GL.AdjustReputation(legacy, -1, "SPIT", "emote")
assert(legacy.reputation == -10 and GL.Relation(legacy) == "enemy", "gestures keep working after automatic migration")

-- A genuine zero reached with a manual opinion remains an explicit choice.
local zero = GL.SetReaction(GL.IdentityFromName("Manual", "Zero", "Player-1-manual-zero"), "warning")
GL.AdjustReputation(zero, 1, "Opinion", "manual")
GL.RecordPvP(zero, "death", "confirmed", "Direct", "manual-zero-death")
GL.InitDB()
assert(zero.reputation == 0 and GL.Relation(zero) == "neutral" and zero.reactionSource == "manual")
local auto, pvp = GL.AutomaticBalance(zero)
assert(auto == -10 and pvp == -10 and zero.reputation == 0 and GL.Relation(zero) == "neutral",
    "viewing the automatic balance must not change a personal classification")

-- Positive gestures do not hide outstanding PvP danger; corrections restore them.
local friendly = GL.IdentityFromName("Gestures", "Balance", "Player-1-gestures-balance")
local f = GL.AdjustReputation(friendly, 1, "KISS", "emote")
GL.RecordPvP(friendly, "death", "confirmed", "Direct", "friendly-death")
local death = f.history[#f.history]
GL.AdjustReputation(friendly, 1, "WINK", "emote")
assert(f.reputation == -10 and GL.Relation(f) == "enemy")
assert(GL.VoidPvP(friendly, death) and f.reputation == 2 and GL.Relation(f) == "friend")
GL.SetReaction(id, "enemy")
GL.RecordPvP(id, "kill", "confirmed", "Direct", "pinned-kill")
assert(r.reputation == -10 and GL.Relation(r) == "enemy", "explicit classifications remain authoritative")

local capped = GL.IdentityFromName("Capped", "Balance", "Player-1-capped-balance")
for i=1,11 do GL.RecordPvP(capped, "death", "confirmed", "Direct", "cap-d" .. i) end
local c = GL.RecordPvP(capped, "kill", "confirmed", "Direct", "cap-k1")
assert(c.reputation == -100, "the displayed floor must not erase debt below -100")
for i=2,11 do GL.RecordPvP(capped, "kill", "confirmed", "Direct", "cap-k" .. i) end
assert(c.reputation == -99)

local alias = GL.IdentityFromName("Merged", "Balance")
GL.AdjustReputation(alias, -1, "SPIT", "emote")
local live = GL.IdentityFromName("Merged", "Balance", "Player-1-merged-balance")
GL.RecordPvP(GL.IdentityFromName("Merged", nil, live.guid), "death", "confirmed", "Direct", "merge-d")
local merged = GL.Remember(live)
GL.RecordPvP(live, "kill", "confirmed", "Direct", "merge-k")
assert(merged.reputation == -10 and GL.Relation(merged) == "enemy", "identity merging retains both social and PvP debts")
print("PASS reputation balance: gradual repayment, migration, reload, corrections, dedup, confidence, manual precedence, saturation and identity merge")
