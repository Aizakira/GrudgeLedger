-- Audit 24/11: one death against three attackers is written on three sheets with one eventId. The
-- export for an AI counts it once, with the player who landed the killing blow.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local ids = {}
for i, name in ipairs({ "Un", "Deux", "Trois" }) do
    ids[i] = GL.IdentityFromName(name, "Assaillant", "Player-1-gank" .. i)
    GL.RecordPvP(ids[i], "death", "confirmed", "test", "death-shared", nil, nil, i == 2)
end
local deaths = GL.DeathReport.Deaths()
assert(#deaths == 1, "one death, not " .. #deaths)
assert(deaths[1].record.guid == ids[2].guid and deaths[1].event.killingBlow, "the killing blow names the killer")
local text, count = GL.DeathReport.Export()
assert(text:find("Morts : 1", 1, true), text)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS death export count: one death per fight, told with its killing blow")
