-- Audit 0.12.0, problem 6: numbered migrations, and migration 1 (probable merged into confirmed)
-- keeps what it replaces. A synthetic 0.10 journal is loaded twice on the real TOC.
local now=1800000000
local function load(saved)
    local env=setmetatable({_G=false,GrudgeLedgerDB=saved},{__index=_G})
    env._G=env
    env.loadfile=function(p) return setfenv(assert(loadfile(p)),env) end
    env.loadfile(TEST_WORK.."/tests/addon_mock.lua")()
    env.GetServerTime=function() return now end
    return env.GrudgeLedger,env
end
local key="guid:Player-1-0010"
local old={players={[key]={name="Old",surname="Enemy",guid="Player-1-0010",
    pvp={deaths=1,probableDeaths=2,kills=3,probableKills=1},
    history={
        {kind="death",confidence="probable",evidence="Participation probable à votre mort.",time=now-86400,eventId="a"},
        {kind="death",confidence="confirmed",evidence="Dégâts létaux explicitement attribués à ce joueur.",time=now-3600,eventId="b"},
        {kind="kill",confidence="probable",evidence="Probable victory",time=now-1800,eventId="c"},
    }}}}
local GL=load(old)
local record=GL.db.players[key]
-- The counters are merged as before, and the merged probable counters stay readable.
assert(record.pvp.deaths==3 and record.pvp.kills==4 and not record.pvp.probableDeaths)
assert(record.migrated1.probableDeaths==2 and record.migrated1.probableKills==1 and not record.migrated1.probableAggressions)
-- Each event keeps its former nature and evidence.
local probable=record.history[1]
assert(probable.confidence=="confirmed" and probable.migrated1.confidence=="probable")
assert(probable.migrated1.evidence=="Participation probable à votre mort.")
assert(probable.evidence=="Participation à l’attaque ayant causé votre mort.")
assert(not record.history[2].migrated1,"a confirmed event is untouched")
assert(record.history[3].migrated1.evidence=="Probable victory")
-- Numbered migrations, each with its date.
local ran=GL.db.migrations[1]
assert(ran and ran>0 and GL.db.migrations[2]==ran and GL.db.migrations[3]==ran,"each migration keeps the date it ran")
-- Running again changes nothing.
local saved=GL.db
GL=load(saved)
record=GL.db.players[key]
assert(record.pvp.deaths==3 and record.migrated1.probableDeaths==2 and record.history[1].migrated1.confidence=="probable")
assert(GL.db.migrations[1]==ran,"the date of a migration never changes")
-- A journal migrated before the numbered list: its markers count as done, dated 0.
GL=load({schema=2,battlegroundCleanupVersion=1,grimoireFontDefaultApplied=true,players={}})
assert(GL.db.migrations[1]==0 and GL.db.migrations[2]==0 and GL.db.migrations[3]==0)
assert(#GL.errors==0,(GL.errors[1] or {}).text)
print("PASS migrations: numbered list, migration 1 keeps merged probable counters and each event's former nature, idempotent reload, older markers")
