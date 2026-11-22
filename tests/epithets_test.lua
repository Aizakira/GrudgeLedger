-- Epithets (0.59.0): large pools for the archetypes and titles of the Bilan and for nicknames, a
-- stable draw for one seed, and the French articles before a place or a name.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local E = GL.Epithets
local I = GL.CharacterInsights
local now = GL.Now()
GetServerTime = function() return now end

-- Articles: "d’" before a vowel, "du", "des", "de la", "de l’", "de" otherwise.
assert(E.Of("Orgrimmar") == "d’Orgrimmar", E.Of("Orgrimmar"))
assert(E.Of("Éclairs") == "d’Éclairs" and E.Of("Tanaris") == "de Tanaris")
assert(E.Of("Les Paluns") == "des Paluns" and E.Of("Le Bois de la Pénombre") == "du Bois de la Pénombre")
assert(E.Of("La Vallée") == "de la Vallée" and E.Of("L’Aile") == "de l’Aile")
-- Zone names come without their article.
assert(E.Of("Vallée de Strangleronce") == "de la Vallée de Strangleronce" and E.Of("Bois de la Pénombre") == "du Bois de la Pénombre")
assert(E.Of("Terres foudroyées") == "des Terres foudroyées" and E.Of("Île de Quel’Danas") == "de l’Île de Quel’Danas")

-- The same seed always gives the same name; different players rarely share one.
local seen = {}
for i = 1, 40 do
    local name = E.Archetype("target", "Player-1-" .. i .. ":target:month:1", {})
    assert(E.Known("target", name), name)
    assert(E.Archetype("target", "Player-1-" .. i .. ":target:month:1", {}) == name, "stable")
    seen[name] = true
end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
assert(distinct >= 10, "only " .. distinct .. " different names for forty players")
-- With a nemesis, a personal name is likely and well formed.
local personal = 0
for i = 1, 40 do
    local name = E.Archetype("target", "seed" .. i, { nemesis = "Arthas" })
    if name:find("d’Arthas", 1, true) then personal = personal + 1 end
end
assert(personal >= 10, personal)
-- Every pool answers, sentences keep their values.
for _, kind in ipairs({ "traveler", "avenger", "predator", "rampart", "target", "duelist" }) do
    assert(E.Archetype(kind, "x", {}) and E.Sentence(kind, "x"), kind)
end
assert(E.Sentence("predatorUnknown", "x"):find("%s pour %s", 1, true))
assert(E.Title("x", "Feralas"):sub(-11) == " de Feralas")

-- 0.59.1: the owner's case. Killed four times by players four levels above: in the Bilan, a victim of
-- bigger players; the killer is a bully.
UnitLevel = function(unit) return unit == "player" and 30 or nil end
local big = GL.IdentityFromName("Grand", "Costaud", "Player-9-0100")
big.level = 34
for i = 1, 4 do
    now = now + 3600
    GL.RecordPvP(big, "death", "confirmed", "fixture", "big" .. i)
end
local facts = GL.Recap.Facts("all", "character")
assert(facts.kind == "victimhigher" and E.Known("victimhigher", facts.archetype), tostring(facts.kind) .. " " .. tostring(facts.archetype))
assert(I.NicknameKind(GL.Get(big)) == "bully" and E.Known("bully", I.Nickname(GL.Get(big))), tostring(I.NicknameKind(GL.Get(big))))
-- An ally met in three groups is a dungeon buddy.
local buddy = GL.Remember(GL.IdentityFromName("Ami", "Donjon", "Player-9-0200"))
buddy.groupCount = 3
assert(I.NicknameKind(buddy) == "dungeonbuddy" and E.Known("dungeonbuddy", I.Nickname(buddy)), tostring(I.NicknameKind(buddy)))

-- Nicknames: three deaths within ten minutes make a camper; five deaths and never beaten, a nemesis;
-- even fights, a rival.
local function person(first, id)
    return GL.IdentityFromName(first, "Test", "Player-9-" .. id)
end
GetRealZoneText = function() return "" end
local camper = person("Camp", "0001")
for i = 1, 3 do
    now = now + 120
    GL.RecordPvP(camper, "death", "confirmed", "fixture", "c" .. i)
end
assert(I.NicknameKind(GL.Get(camper)) == "camper" and E.Known("camper", I.Nickname(GL.Get(camper))))
local nemesis = person("Nem", "0002")
for i = 1, 5 do
    now = now + 3600
    GL.RecordPvP(nemesis, "death", "confirmed", "fixture", "n" .. i)
end
assert(I.NicknameKind(GL.Get(nemesis)) == "nemesis", tostring(I.NicknameKind(GL.Get(nemesis))))
local rival = person("Riv", "0003")
for i = 1, 3 do
    now = now + 3600
    GL.RecordPvP(rival, "death", "confirmed", "fixture", "rd" .. i)
    now = now + 3600
    GL.RecordPvP(rival, "kill", "confirmed", "fixture", "rk" .. i)
end
assert(I.NicknameKind(GL.Get(rival)) == "rival", tostring(I.NicknameKind(GL.Get(rival))))
assert(I.Nickname(GL.Get(rival)) == I.Nickname(GL.Get(rival)), "a player keeps the same nickname")
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS epithets: French articles, stable and varied draws, personal names, camper, nemesis and rival nicknames")
