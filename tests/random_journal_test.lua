-- Randomised journals (25/11): fights drawn at random go through the addon's own entry points
-- (deaths to one or several attackers, victories, coups de main, annulments, repeats of the same
-- event), in several zones, with and without a position. After each run, rules that must always
-- hold are checked: counters equal the history, one death counts once on the map and in the lands,
-- the map never draws more than it counts, debts stay whole and positive, every page opens.
-- Synthetic players only. Deterministic: the same seeds every time.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local R = GL.RelationsPages
local now = 1800000000
GetServerTime = function() return now end
local seed = 1
-- The high bits of the generator: its low bits repeat in short cycles.
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return math.floor(seed / 65536) % n + 1 end
local ZONES = { { 1446, "Tanaris" }, { 1448, "Gangrebois" }, { 1444, "Feralas" }, { 1422, "Maleterres de l’Ouest" } }
local zones = {}
for i, z in ipairs(ZONES) do
    zones[i] = { mapID = z[1], name = z[2], rect = { left = 0.2 * i - 0.2, right = 0.2 * i, top = 0.1, bottom = 0.3 } }
end
local where = ZONES[1]
local placed = true
GetRealZoneText = function() return where[2] end
C_Map = C_Map or {}
C_Map.GetBestMapForUnit = function() return where[1] end
C_Map.GetPlayerMapPosition = function()
    if placed then return { GetXY = function() return rnd(999) / 1000, rnd(999) / 1000 end } end
end

local function count(list, test)
    local n = 0
    for _, v in ipairs(list) do if test(v) then n = n + 1 end end
    return n
end
local function check(run)
    local label = "run " .. run .. ": "
    assert(#GL.errors == 0, label .. tostring(GL.errors[1] and GL.errors[1].text))
    -- 1. Each sheet's counters are its history.
    local deathIds, kills = {}, 0
    for _, record in pairs(GL.db.players) do
        local k = count(record.history, function(e) return e.kind == "kill" and not e.voided end)
        local d = count(record.history, function(e) return e.kind == "death" and not e.voided end)
        assert(record.pvp.kills == k, label .. "kills counter " .. record.pvp.kills .. " for " .. k .. " in history")
        assert(record.pvp.deaths == d, label .. "deaths counter " .. record.pvp.deaths .. " for " .. d .. " in history")
        local debt = GL.Debt(record)
        assert(type(debt) == "number" and debt >= 0 and debt == math.floor(debt) and debt < math.huge, label .. "debt " .. tostring(debt))
        for _, e in ipairs(record.history) do
            if e.kind == "death" and not e.voided then deathIds[e.eventId] = true end
            if e.kind == "kill" and not e.voided then kills = kills + 1 end
        end
    end
    local deaths = 0
    for _ in pairs(deathIds) do deaths = deaths + 1 end
    -- 2. The lands count each death once, each victory once.
    local landDeaths, landKills = 0, 0
    for _, entry in ipairs(R.Lands()) do
        landDeaths, landKills = landDeaths + entry.deaths, landKills + entry.kills
        local named = 0
        for _, times in pairs(entry.killers) do named = named + times end
        assert(named >= entry.deaths, label .. "every death of a zone has its attacker")
    end
    assert(landDeaths == deaths and landKills == kills, label .. ("lands %d/%d, journal %d/%d"):format(landDeaths, landKills, deaths, kills))
    -- 3. The map counts the same, by zone, and draws no more than it counts, forty a zone at most.
    local tallies, tallyOf, own = R.MapTally(947, zones)
    local mapDeaths, mapKills = 0, 0
    for _, tally in ipairs(tallies) do
        mapDeaths, mapKills = mapDeaths + tally.deaths, mapKills + tally.kills
        local marks = count(own, function(m) return m.key == tally.zone.mapID end)
        assert(marks <= tally.deaths + tally.kills and marks <= 40, label .. "marks " .. marks .. " in " .. tally.zone.name)
        assert(marks + tally.unplaced >= math.min(40, tally.deaths + tally.kills) or marks == 40, label .. "a placed fight left undrawn in " .. tally.zone.name)
        local balance = R.ZoneBalance(tally.kills, tally.deaths)
        assert(balance >= -1 and balance <= 1 and math.abs(balance + R.ZoneBalance(tally.deaths, tally.kills)) < 1e-12, label .. "balance")
    end
    assert(mapDeaths == deaths and mapKills == kills, label .. ("map %d/%d, journal %d/%d"):format(mapDeaths, mapKills, deaths, kills))
    for _, mark in ipairs(own) do assert(mark.event.kind == "death" or mark.event.kind == "kill", label .. "mark of " .. mark.event.kind) end
    -- 4. The statistics of the period "all" agree with the journal.
    local stats = GL.PersonalStatistics({ period = "all", scope = "all" })
    assert(stats.kills == kills and stats.deaths == deaths, label .. ("statistics %d/%d, journal %d/%d"):format(stats.deaths, stats.kills, deaths, kills))
    -- 5. The week and the month count the fights of their last 7 and 30 days, each death once.
    for period, span in pairs({ week = 7 * 86400, month = 30 * 86400 }) do
        local ids, wins = {}, 0
        for _, record in pairs(GL.db.players) do
            for _, e in ipairs(record.history) do
                if not e.voided and e.time >= now - span and e.time <= now then
                    if e.kind == "death" then ids[e.eventId] = true elseif e.kind == "kill" then wins = wins + 1 end
                end
            end
        end
        local dead = 0
        for _ in pairs(ids) do dead = dead + 1 end
        local within = GL.PersonalStatistics({ period = period, scope = "all" })
        assert(within.kills == wins and within.deaths == dead,
            label .. ("%s: statistics %d/%d, journal %d/%d"):format(period, within.deaths, within.kills, dead, wins))
    end
end

local people = {}
for i = 1, 12 do people[i] = GL.IdentityFromName("Rand" .. string.char(64 + i), "Test", ("Player-9-%08d"):format(i)) end
local serial = 0
for run = 1, 25 do
    seed = run * 7919
    for _ = 1, 40 do
        now = now + rnd(3600)
        where, placed = ZONES[rnd(#ZONES)], rnd(5) > 1
        local what = rnd(10)
        serial = serial + 1
        if what <= 4 then
            -- A death, to one attacker or several, the killing blow to one of them.
            local id = "rand:death:" .. serial
            local first = rnd(#people)
            for j = 0, rnd(3) - 1 do
                GL.RecordPvP(people[(first + j - 1) % #people + 1], "death", "confirmed", "fixture", id, nil, nil, j == 0)
            end
            -- A repeat of the same event changes nothing.
            if rnd(4) == 1 then GL.RecordPvP(people[first], "death", "confirmed", "fixture", id) end
        elseif what <= 8 then
            local id = "rand:kill:" .. serial
            local target = people[rnd(#people)]
            GL.RecordPvP(target, "kill", "confirmed", "fixture", id)
            if rnd(5) == 1 then GL.RecordPvP(target, "kill", "confirmed", "fixture", id) end
        elseif what == 9 then
            GL.RecordAssist(people[rnd(#people)])
        else
            -- An annulment, of any fight already in a sheet.
            local who = people[rnd(#people)]
            local record = GL.Get(who)
            local history = record and record.history or {}
            local e = history[rnd(math.max(1, #history))]
            if e and (e.kind == "death" or e.kind == "kill") then
                GL.VoidPvP(who, e, true)
                -- Twice: the second changes nothing.
                GL.VoidPvP(who, e, true)
            end
        end
    end
    check(run)
end
-- 5. Every page of both books opens on what was drawn, in turn, with nothing raised.
GL.ShowRelations()
for _, page in ipairs({ "recap", "honor", "debts", "rivals", "lands", "rankings", "guildlog", "enemies", "guilds", "members" }) do
    R.Open(page)
    R.Refresh()
end
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS random journals: 25 runs of 40 fights, counters, lands, map, statistics and debts agree; every page opens")
