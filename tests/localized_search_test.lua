GetLocale = function() return "esMX" end
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local function person(guid, name, guild, faction)
    local id = GL.IdentityFromName(name, "Demo", guid)
    id.guild, id.faction = guild, faction
    return GL.SetReaction(id, "enemy")
end
local isa = person("Player-1-es", "Ísabel", "PEÑA", "Horde")
local ana = person("Player-1-es2", "Ana", "Heraldo", "Alliance")
assert(GL.IdentityFromName("Épée", "Àngel", "Player-1-valid"))
for _, name in ipairs({"a|b", "a\003b", "a\127b", "a\194\133b", "a\000b"}) do
    assert(not GL.IdentityFromName(name, "Test", "Player-1-invalid"))
end
isa.class, isa.className, isa.race, isa.raceName = "WARRIOR", "Guerrier", "Dwarf", "Nain"
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Guerrero" }
C_CreatureInfo = {GetRaceInfo = function() return {clientFileString="Dwarf", raceName="Enano"} end}
GL.AddNote(isa, "Última visita a Córdoba")
local proof = "Le familier de ce joueur vous a porté le coup fatal."
GL.RecordPvP(isa, "death", "confirmed", proof, "es-death")
local function found(query, expected)
    local hits = GL.SearchPlayers({query=query})
    assert(#hits == 1 and hits[1] == expected, query)
end
found("isabel peña ULTIMA", isa)
found("I\204\129SABEL PEÑA", isa) -- decomposed Í
found("horda enemigo", isa)
found("horda guerrero enano", isa)
found("alianza enemigo", ana)
found("muerte mascota", isa)
local rows = GL.JournalEvents({query="MUERTE horda mascota"})
assert(#rows == 1 and rows[1].event.evidence == proof)
assert(#GL.JournalEvents({query="nota CORDOBA"}) == 1 and #GL.JournalEvents({query="nota CORDOBA",kind="pvp"}) == 0)
assert(isa.fullName == "Ísabel Demo" and isa.guild == "PEÑA" and isa.faction == "Horde")
print("PASS search: accents, spelling variants, localized faction, relationship, event and evidence; original identity preserved")
