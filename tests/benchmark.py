"""Offline audit only: real addon + existing mock, never the running game or WTF.

Run: python tests/benchmark.py > benchmark.json (same dependencies as run_tests.py).
Times exclude WoW/native rendering; no timing threshold is a correctness test.
"""
import json
import sys
from pathlib import Path
from statistics import median
from time import perf_counter

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "test-runtime"))
from lupa.lua51 import LuaRuntime



def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().TEST_ROOT = (ROOT / "GrudgeLedger").as_posix()
    lua.globals().TEST_WORK = ROOT.as_posix()
    lua.execute('assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()')
    lua.execute("""
        GL = GrudgeLedger
        simulatedTime = 0
        GetTime = function() return simulatedTime end
        assert(#GL.errors == 0)
        GL.db.settings.sounds = false
        GL.db.settings.friendAlerts = false
        GL.db.settings.enemyAlerts = false
        GL.db.settings.markers = true
        function CheckErrors() assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text) end
        function Populate(n, events)
            GL.db.players, GL.db.aliases = {}, {}
            for i = 1, n do
                local id = GL.IdentityFromName('Person' .. i, 'Example', 'Player-1-audit' .. i)
                id.guild, id.realm = 'Guild' .. (i % 20), 'Forever'
                local r = GL.Remember(id)
                r.reaction, r.reactionSource = 'enemy', 'manual'
                for j = 1, events do
                    r.history[j] = {kind='death', confidence='confirmed', guild=r.guild,
                        guildRealm=r.realm, eventId='event' .. i .. ':' .. j, time=j, zone='Example'}
                end
                r.pvp.deaths = events
            end
        end
        function Updates(seconds)
            for i = 1, seconds * 60 do
                simulatedTime = simulatedTime + 1/60
                for _, f in ipairs(GL_TEST_MOCK.frames) do
                    if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 1/60) end
                end
            end
            CheckErrors()
        end
    """)
    return lua


def timed(lua, source, repetitions=7):
    fn = lua.eval("function() " + source + " end")
    fn()
    values = []
    for _ in range(repetitions):
        lua.execute("collectgarbage('collect')")
        start = perf_counter()
        fn()
        values.append((perf_counter() - start) * 1000)
    lua.globals().CheckErrors()
    return round(median(values), 3)


result = {"scope": "Lua 5.1 mocked WoW; NOT live CPU/FPS/GPU or total addon memory", "scaling": [], "visible": []}
for people in (100, 1000, 10000):
    lua = runtime()
    lua.execute("collectgarbage('collect')")
    before = lua.eval("collectgarbage('count')")
    lua.globals().Populate(people, 10)
    lua.execute("collectgarbage('collect')")
    memory = lua.eval("collectgarbage('count')") - before
    row = {"people": people, "events": people * 10, "synthetic_db_kib": round(memory)}
    row["guild_stats_rebuild_ms"] = timed(lua, "GL.SetGuildReaction('Guild0', 'warning', nil, 'Forever'); GL.GuildStatistics()")
    row["hidden_change_ms"] = timed(lua, "GL.Emit('CHANGED')")
    lua.execute("GL.ShowLedger()")
    row["open_ledger_change_ms"] = timed(lua, "GL.Emit('CHANGED')")
    lua.execute("GL.ShowStatistics('guilds')")
    row["open_guild_stats_change_ms"] = timed(lua, "GL.Emit('CHANGED')")
    result["scaling"].append(row)

for visible in (1, 20, 80):
    lua = runtime()
    lua.globals().VISIBLE = visible
    lua.execute("""
        local mock = GL_TEST_MOCK
        mock.Fire('NAME_PLATE_UNIT_REMOVED', 'nameplate1')
        mock.units.target = nil
        local plates, list = {}, {}
        C_NamePlate.GetNamePlates = function() return list end
        C_NamePlate.GetNamePlateForUnit = function(unit) return plates[unit] end
        for i = 1, VISIBLE do
            local unit = 'nameplate' .. i
            local p = CreateFrame('Frame', nil, UIParent)
            p.namePlateUnitToken = unit
            p.TPFrame = CreateFrame('Frame', nil, p)
            p.TPFrame.visual = {NameText = p.TPFrame:CreateFontString()}
            plates[unit], list[i] = p, p
            mock.units[unit] = {name='Person' .. i, surname='Example', guid='Player-1-audit' .. i, guild='Guild'}
            local r = GL.Remember(GL.Identity(unit))
            r.reaction, r.reactionSource = 'enemy', 'manual'
            mock.Fire('NAME_PLATE_UNIT_ADDED', unit)
        end
        Updates(1)
        identityCalls, anchorCalls, textureCalls = 0, 0, 0
        metadataCalls = 0
        local name = UnitName
        UnitName = function(...) metadataCalls = metadataCalls + 1 return name(...) end
        local old = GL.Identity
        GL.Identity = function(...) identityCalls = identityCalls + 1 return old(...) end
        local methods = getmetatable(UIParent).__index
        local point, texture = methods.SetPoint, methods.SetTexture
        methods.SetPoint = function(...) anchorCalls=anchorCalls+1 return point(...) end
        methods.SetTexture = function(...) textureCalls=textureCalls+1 return texture(...) end
        Updates(10)
    """)
    result["visible"].append({"known_plates": visible,
        "identity_calls_in_10_simulated_seconds": lua.globals().identityCalls,
        "name_reads_in_10_simulated_seconds": lua.globals().metadataCalls,
        "anchor_calls_in_10_simulated_seconds": lua.globals().anchorCalls,
        "texture_calls_in_10_simulated_seconds": lua.globals().textureCalls,
        "mock_ms_per_10_simulated_seconds": timed(lua, "Updates(10)", 3)})

print(json.dumps(result, indent=2))
