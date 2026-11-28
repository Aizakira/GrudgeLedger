-- The map of fights counts what it draws (owner report 25/11): Felwood showed many marks under
-- "4 morts", Tanaris said 13 deaths for 4 marks, and unticking then ticking "Vision de guilde" lost
-- the guild's fights. Synthetic journal and guild only.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local R = GL.RelationsPages
local now = 1800000000
GetServerTime = function() return now end
local function person(first, last, id) return GL.IdentityFromName(first, last, "Player-9-" .. id) end
local zoneName, mapID, x, y = "Tanaris", 1446, 0.5, 0.5
GetRealZoneText = function() return zoneName end
C_Map = C_Map or {}
C_Map.GetBestMapForUnit = function() return mapID end
C_Map.GetPlayerMapPosition = function() if x then return { GetXY = function() return x, y end } end end

-- The world as the map sees it: zones named by the map, which the zone text need not match.
local zones = {
    { mapID = 1446, name = "Tanaris", rect = { left = 0.4, right = 0.6, top = 0.6, bottom = 0.8 } },
    { mapID = 1448, name = "Gangrebois", rect = { left = 0.1, right = 0.3, top = 0.1, bottom = 0.3 } },
    { mapID = 1444, name = "Feralas", rect = { left = 0.1, right = 0.3, top = 0.5, bottom = 0.7 } },
}
local function tally(guild)
    local tallies, tallyOf, own, others = R.MapTally(947, zones, guild)
    return tallies, tallyOf, own, others
end
local function marks(list, map, kind)
    local n = 0
    for _, mark in ipairs(list) do
        if mark.key == map and (not kind or mark.event.kind == kind) then n = n + 1 end
    end
    return n
end

-- Tanaris: four deaths, each to three attackers at once. One death each, one mark each.
local a, b, c = person("Aa", "Un", "0001"), person("Bb", "Deux", "0002"), person("Cc", "Trois", "0003")
for i = 1, 4 do
    now = now + 600
    x, y = 0.1 * i, 0.2
    for _, attacker in ipairs({ a, b, c }) do GL.RecordPvP(attacker, "death", "confirmed", "fixture", "death-" .. i) end
end
now = now + 600
GL.RecordPvP(a, "kill", "confirmed", "fixture", "kill-1")
local tallies, tallyOf, own = tally()
assert(#tallies == 1 and tallyOf[1446].deaths == 4 and tallyOf[1446].kills == 1, tallyOf[1446] and tallyOf[1446].deaths)
assert(marks(own, 1446, "death") == 4 and marks(own, 1446, "kill") == 1, #own)
-- The list of dangerous lands says the same, and still names every attacker.
local lands = R.Lands()
assert(#lands == 1 and lands[1].deaths == 4 and lands[1].kills == 1, lands[1].deaths)
local attackers = 0
for _, times in pairs(lands[1].killers) do
    attackers = attackers + 1
    assert(times == 4)
end
assert(attackers == 3)

-- Felwood: the game's zone text said "Felwood", the map says "Gangrebois". The map's own zone wins.
zoneName, mapID = "Felwood", 1448
for i = 1, 3 do
    now = now + 600
    x, y = 0.3, 0.1 * i
    GL.RecordPvP(person("Fel", "Bois", "01" .. i), "death", "confirmed", "fixture", "fel-death-" .. i)
    now = now + 600
    GL.RecordPvP(person("Fel", "Bois", "01" .. i), "kill", "confirmed", "fixture", "fel-kill-" .. i)
end
-- A death whose place the game hid: counted by the zone's name when the name matches a zone, never drawn.
zoneName, x = "Gangrebois", nil
now = now + 600
GL.RecordPvP(person("Sans", "Place", "0200"), "death", "confirmed", "fixture", "hidden-1")
-- A "coup de main" is neither a death nor a victory: neither counted nor drawn.
x, y = 0.4, 0.4
local helped = GL.Remember(person("Coup", "Main", "0300"))
GL.RecordAssist(helped)
tallies, tallyOf, own = tally()
assert(tallyOf[1448].deaths == 4 and tallyOf[1448].kills == 3 and tallyOf[1448].unplaced == 1, tallyOf[1448].deaths)
assert(marks(own, 1448, "death") == 3 and marks(own, 1448, "kill") == 3 and marks(own, 1448, "assist") == 0, marks(own, 1448))
for _, mark in ipairs(own) do assert(mark.event.kind ~= "assist") end
-- Every mark is counted: a zone never draws more than it counts.
for map, entry in pairs(tallyOf) do
    assert(marks(own, map) <= entry.deaths + entry.kills, map)
end

-- Many fights in one zone: each zone draws its latest forty, another zone is never crowded out.
zoneName, mapID = "Tanaris", 1446
for i = 1, 90 do
    now = now + 60
    x, y = 0.5, 0.005 * i
    GL.RecordPvP(person("Foule", "Nombreuse", ("%04d"):format(1000 + i)), "kill", "confirmed", "fixture", "crowd-" .. i)
end
tallies, tallyOf, own = tally()
assert(tallyOf[1446].kills == 91 and marks(own, 1446) == 40 and marks(own, 1448) == 6, marks(own, 1446))
local latest = 0
for _, mark in ipairs(own) do if mark.key == 1446 then latest = math.max(latest, mark.event.time) end end
assert(latest == now, "the latest fights are the ones drawn")

-- The guild's fights: counted where their map is, drawn there; an unknown map is left out.
local guild = {
    { actor = "Player-1-mate0001", time = now - 10, mapID = 1444, x = 0.5, y = 0.5, kind = "death" },
    { actor = "Player-1-mate0001", time = now - 20, mapID = 1444, x = 0.2, y = 0.4, kind = "kill" },
    { actor = "Player-1-mate0002", time = now - 30, mapID = 1448, x = 0.2, y = 0.4, kind = "death" },
    { actor = "Player-1-mate0002", time = now - 40, mapID = 99999, x = 0.2, y = 0.4, kind = "death" },
}
local _, guildOf, _, others = tally(guild)
assert(guildOf[1444].deaths == 1 and guildOf[1444].kills == 1 and guildOf[1448].deaths == 5 and #others == 3, #others)
assert(math.abs(others[1].x - (0.1 + 0.5 * 0.2)) < 0.001 and others[1].guild == "Player-1-mate0001")
-- The colour of a zone (owner's rule, 25/11): none when even, full at four to one either way.
local B = R.ZoneBalance
assert(B(20, 20) == 0 and B(1, 1) == 0, "even: the map's own colour")
assert(B(4, 1) == 1 and B(40, 10) == 1 and B(9, 1) == 1, "four victories a death: full green")
assert(B(1, 4) == -1 and B(10, 40) == -1 and B(0, 3) == -1, "four deaths a victory: deep red")
assert(math.abs(B(2, 1) - 0.5) < 1e-9 and math.abs(B(10, 20) + 0.5) < 1e-9, "two to one: half way")
assert(B(20, 11) > 0.4 and B(20, 11) < 0.5, "Felwood, 20 victories for 11 deaths: a fair green")
assert(B(3, 0) == 1 and B(1, 0) == 0.5 and B(0, 1) == -0.5, "a side with nothing counts one more")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS map tally: one death once whatever the attackers, zones by map, no coups de main, forty marks a zone, guild counted as drawn")
