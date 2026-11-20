-- One fight = one entry. Owner report (0.26.0 test): an aggression and the death it caused showed as
-- two fights, and "4 combats ces 7 derniers jours" counted blows instead of fights.
dofile(TEST_WORK .. "/tests/wow_mock.lua")
local now = 1800000000
GetServerTime = function() return now end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
local id = GL.IdentityFromName("Fighter", "Example", "Player-1-fighter")
-- Fight 1: he attacks, hits again 40 s later, then kills you.
GL.RecordAggression(id, "confirmed", "Observed", "f1-a")
now = now + 40
assert(GL.RecordAggression(id, "confirmed", "Observed", "f1-b") == nil, "one aggression per fight")
now = now + 30
GL.RecordPvP(id, "death", "confirmed", "Direct", "f1-d")
local r = GL.Get(id)
assert(r.pvp.aggressions == 1 and r.reputation == -10)
-- Fight 2, after your release: he attacks again, then you kill him.
now = now + 90
assert(GL.RecordAggression(id, "confirmed", "Observed", "f2-a"), "a death ends the fight")
now = now + 20
GL.RecordPvP(id, "kill", "confirmed", "Direct", "f2-k")
-- Fight 3, an hour later: a skirmish, he flees.
now = now + 3600
GL.RecordAggression(id, "confirmed", "Observed", "f3-a")
local fights = GL.Fights(r)
assert(#fights == 3, #fights)
assert(fights[1].aggressions == 1 and fights[1].main.kind == "aggression" and not fights[1].ended)
assert(fights[2].kills == 1 and fights[2].aggressions == 1 and fights[2].main.kind == "kill")
assert(fights[3].deaths == 1 and fights[3].aggressions == 1 and fights[3].main.kind == "death" and #fights[3].events == 2)
assert(fights[3].at < fights[3].last and fights[2].at > fights[3].last)
-- Voided events leave the fight.
assert(GL.VoidPvP(id, fights[2].main))
assert(GL.Fights(r)[2].kills == 0 and GL.Fights(r)[2].main.kind == "aggression")
assert(GL.FoughtRecently(id), "the skirmish is less than two minutes old")
now = now + 200
assert(not GL.FoughtRecently(id))

-- Titles: one line per fight.
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
local titles = {}
for i, fight in ipairs(GL.Fights(r)) do titles[i] = GL.FightTitle(fight) end
assert(titles[1] == "Escarmouche sans mort · il vous a agressé", titles[1])
assert(titles[3]:find("^Agression → Vous a tué"), titles[3])
local avenged = { aggressions = 0, events = { { kind = "death", killingBlow = true }, { kind = "kill", combat = { assist = "Mate" } } } }
avenged.main = avenged.events[1]
assert(GL.FightTitle(avenged) == "Vous a tué · coup fatal → Vaincu avec votre groupe", GL.FightTitle(avenged))

-- The weekly count reads fights, not blows.
assert(loadfile(TEST_ROOT .. "/CharacterHistory.lua"))()
assert(loadfile(TEST_ROOT .. "/CharacterInsights.lua"))()
local recent
for _, fact in ipairs(GL.CharacterInsights.Facts(r, r.guid)) do
    if fact.key == "recent" then recent = fact end
end
assert(recent and recent.value == "3", recent and recent.value)
print("PASS fight grouping: one aggression per fight, a death or victory ends it, voided events leave it, "
    .. "one title per fight, weekly count of whole fights")

-- Zones on the Habits tab: most crossings first, never the order of the visits.
local zones = GL.CharacterInsights.ZoneList({ zones = { ["Tanaris"] = 2, ["Feralas"] = 7, ["Desolace"] = 2, ["Azshara"] = 1 } })
assert(zones[1].name == "Feralas" and zones[2].name == "Desolace" and zones[3].name == "Tanaris" and zones[4].name == "Azshara")
print("PASS zones sorted by number of crossings")
