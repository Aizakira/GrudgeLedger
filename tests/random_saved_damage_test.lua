-- Damaged saved files (25/11): a saved file can come back damaged (an old version, another addon,
-- a hand edit, a crash while writing). A realistic journal is built, then copies of it are damaged
-- at random, one to four fields replaced by a wrong type or an absurd value anywhere in the tree,
-- and the addon is loaded on each. Loading, opening every page, the statistics, the debts, the map
-- and a new fight must raise no error. Synthetic players only. Deterministic.
local now = 1800000000
local function load(saved)
    local env = setmetatable({ _G = false, GrudgeLedgerDB = saved }, { __index = _G })
    env._G = env
    env.loadfile = function(p) return setfenv(assert(loadfile(p)), env) end
    local mock = env.loadfile(TEST_WORK .. "/tests/addon_mock.lua")()
    env.GetServerTime = function() return now end
    return env.GrudgeLedger, env, mock
end
local seed = 99
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return math.floor(seed / 65536) % n + 1 end

-- A realistic journal: fights, groups, notes, a guild met, settings changed.
local GL, env = load(nil)
env.GetRealZoneText = function() return "Tanaris" end
env.C_Map = env.C_Map or {}
env.C_Map.GetBestMapForUnit = function() return 1446 end
env.C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end
local people = {}
for i = 1, 8 do
    people[i] = GL.IdentityFromName("Save" .. string.char(64 + i), "Test", ("Player-9-%08d"):format(100 + i))
    people[i].guild, people[i].guildSeenAt = i % 2 == 0 and "Les Ombres" or nil, now
end
for i = 1, 60 do
    now = now + 600
    local who = people[(i % #people) + 1]
    local kind = i % 3 == 0 and "kill" or "death"
    GL.RecordPvP(who, kind, "confirmed", "fixture", "save:" .. i, nil, nil, true)
    if i % 7 == 0 then GL.RecordAggression(who, "confirmed", "fixture", "save-a:" .. i) end
    if i % 11 == 0 then GL.RecordAssist(who) end
end
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    return out
end
local pristine = copy(GL.db)

-- Every place of the tree, to damage one at random.
local function places(root)
    local list, seen = {}, {}
    local function walk(t, depth)
        if seen[t] or depth > 8 then return end
        seen[t] = true
        for k, v in pairs(t) do
            list[#list + 1] = { t, k }
            if type(v) == "table" then walk(v, depth + 1) end
        end
    end
    walk(root, 0)
    table.sort(list, function(a, b) return tostring(a[2]) < tostring(b[2]) end)
    return list
end
local BAD = { "nil", "", "x", 0, -1, 1e309, -1e309, 2 ^ 53, 3.5, true, false, {}, { 1, 2, 3 }, { x = "y" }, string.rep("z", 500) }
local function bad()
    local v = BAD[rnd(#BAD)]
    if v == "nil" then return nil end
    return type(v) == "table" and copy(v) or v
end

local failures = {}
local function try(label, run, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then failures[#failures + 1] = ("run %d, %s: %s"):format(run, label, tostring(err)) end
    return ok
end
local RUNS = 320
for run = 1, RUNS do
    local saved = copy(pristine)
    local where = places(saved)
    local changed = {}
    for _ = 1, rnd(4) do
        local spot = where[rnd(#where)]
        spot[1][spot[2]] = bad()
        changed[#changed + 1] = tostring(spot[2])
    end
    local label = "damaged " .. table.concat(changed, ",")
    local G, E, mock
    if try(label .. " / load", run, function() G, E, mock = load(saved) end) then
        E.GetRealZoneText = function() return "Feralas" end
        local R = G.RelationsPages
        try(label .. " / statistics", run, function()
            G.PersonalStatistics({ period = "all", scope = "all" })
            G.PersonalStatistics({ period = "week", scope = "character" })
            G.GuildStatistics()
        end)
        try(label .. " / debts", run, function()
            for _, record in pairs(type(G.db.players) == "table" and G.db.players or {}) do
                if type(record) == "table" then G.Debt(record) G.Relation(record) end
            end
        end)
        try(label .. " / lands and map", run, function()
            R.Lands()
            R.MapTally(947, { { mapID = 1446, name = "Tanaris", rect = { left = 0, right = 0.5, top = 0, bottom = 0.5 } } })
        end)
        try(label .. " / pages", run, function()
            G.ShowRelations()
            for _, page in ipairs({ "recap", "honor", "debts", "rivals", "lands", "rankings", "guildlog", "enemies", "guilds", "members" }) do
                R.Open(page)
                R.Refresh()
            end
        end)
        try(label .. " / new fight", run, function()
            G.RecordPvP(G.IdentityFromName("Nouveau", "Venu", "Player-9-77777777"), "death", "confirmed", "fixture", "after:" .. run)
            G.RecordPvP(people[1], "kill", "confirmed", "fixture", "after-k:" .. run)
        end)
        -- What the addon caught itself counts too: an error it swallowed is still a bug.
        -- Except the notice of a sheet set aside in "quarantine": that is the addon doing its job.
        for _, e in ipairs(G.errors or {}) do
            if not tostring(e.text):find("quarantine", 1, true) then failures[#failures + 1] = ("run %d, %s / caught: %s"):format(run, label, tostring(e.text)) end
        end
    end
end
table.sort(failures)
assert(#failures == 0, #failures .. " failures on damaged saved files:\n" .. table.concat(failures, "\n", 1, math.min(#failures, 20)))
print(("PASS damaged saved files: %d damaged copies load, open every page, count and record without error"):format(RUNS))
