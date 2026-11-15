-- Replaying the same victory after a correction must reflect the remaining evidence.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
IsInInstance = function() return false, "none" end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
local now = GL.Now()
GetServerTime = function() return now end
local me = mock.units.player.guid
local opponent = GL.IdentityFromName("Asha", "Brightvale", "Player-1-bright")
local other = GL.IdentityFromName("Feri", "Valbrume", "Player-1-feri")
local function death(id, confidence)
    local _, event = GL.RecordPvP(id, "death", confidence)
    return assert(event)
end
local function victory(id, key)
    local opening = assert(GL.RecordOpening(id, "player", true, key))
    local record, kill = GL.RecordPvP(id, "kill", "confirmed", nil, key .. "-kill", opening)
    return GL.KillOpeningCategory(record, kill), record, kill
end
mock.units.player.guid = "Player-1-alt"
death(opponent, "confirmed")
mock.units.player.guid = me
death(other, "confirmed")
now = now + 1
assert(victory(opponent, "old-grudge") == "initiatedKillsGrudge")
local removed = death(opponent, "confirmed")
assert(victory(opponent, "same-second") == "initiatedKillsGrudge")
now = now + 1
local category, record, kill = victory(opponent, "documented")
assert(category == "revengeKills")
local stats = GL.PersonalStatistics({scope="character"})
assert(stats.kills == 3 and stats.revengeKills == 1)
assert(GL.VoidPvP(opponent, removed))
assert(GL.KillOpeningCategory(record, kill) == "initiatedKillsGrudge")
stats = GL.PersonalStatistics({scope="character"})
assert(stats.kills == 3 and stats.revengeKills == 0)
kill.combat.opener = "opponent"
assert(GL.KillOpeningCategory(record, kill) == "unknownOpeningKills")
kill.combat = 0
assert(GL.KillOpeningCategory(record, kill) == "unknownOpeningKills")
assert(not GL.RecordOpening({guid="Creature-1-guard",fullName="Guard"}, "player", false, "npc"))
print("PASS revenge requires the same character, opponent, earlier confirmed death and witnessed opening; corrections preserve victories")
