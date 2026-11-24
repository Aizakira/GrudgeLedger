-- What the sheet knows about a player's habits, as dated facts. There is no threat score:
-- every sentence is computed from your journal and lists the events that justify it.
local GL = GrudgeLedger
local L = GL.L
local I = {}
GL.CharacterInsights = I

-- ponytail: 20 recent visits, 40 zones and 400 days per character, inside the character history entry.
local MAX_VISITS, MAX_ZONES, MAX_DAYS = 20, 40, 400
-- Two sightings closer than this are the same visit.
local VISIT_GAP = 600
local DAY = 86400
local fightKinds = {kill = true, death = true, aggression = true}

-- Weekday (1 = Monday) and hour, in the player's local time when the client provides it.
local function clock(at)
    local t = GL.Safe(date, "*t", at)
    if type(t) == "table" and t.wday and t.hour then
        return (t.wday + 5) % 7 + 1, t.hour
    end
    return (math.floor(at / DAY) + 3) % 7 + 1, math.floor(at / 3600) % 24
end
local function cell(at)
    local day, hour = clock(at)
    return (day - 1) * 24 + hour
end
-- A calendar day in the player's local time: year * 1000 + day of the year.
function I.DayKey(at)
    local t = GL.Safe(date, "*t", at)
    if type(t) == "table" and t.year and t.yday then
        return t.year * 1000 + t.yday
    end
    return math.floor(at / DAY)
end
local function countDay(days, at)
    local key = I.DayKey(at)
    days[key] = (days[key] or 0) + 1
    local count, oldest = 0, nil
    for k in pairs(days) do
        count = count + 1
        if not oldest or k < oldest then
            oldest = k
        end
    end
    if count > MAX_DAYS then
        days[oldest] = nil
    end
end

local function presenceFor(guid, create)
    local entry = GL.CharacterHistory.Entry(guid, create)
    if entry and create and not entry.presence then
        entry.presence = {hours = {}, zones = {}, visits = {}, total = 0, since = GL.Now()}
    end
    return entry and entry.presence
end
local function countZone(zones, zone)
    if not zones[zone] then
        local count, smallest = 0, nil
        for name, n in pairs(zones) do
            count = count + 1
            if not smallest or n < zones[smallest] then
                smallest = name
            end
        end
        if count >= MAX_ZONES then
            zones[smallest] = nil
        end
    end
    zones[zone] = (zones[zone] or 0) + 1
end

-- One visit: its hour and weekday, its zone, and the twenty most recent visits.
function I.RecordVisit(guid, at, zone)
    if type(guid) ~= "string" or type(at) ~= "number" then
        return
    end
    local p = presenceFor(guid, true)
    local last = p.visits[#p.visits]
    if last and math.abs(at - last.at) < VISIT_GAP then
        return
    end
    local key = cell(at)
    p.hours[key] = (p.hours[key] or 0) + 1
    p.days = p.days or {}
    countDay(p.days, at)
    if type(zone) == "string" and zone ~= "" and zone ~= "?" then
        countZone(p.zones, zone)
    else
        zone = nil
    end
    p.visits[#p.visits + 1] = {at = at, zone = zone}
    if #p.visits > MAX_VISITS then
        table.remove(p.visits, 1)
    end
    p.total = p.total + 1
    local entry = GL.CharacterHistory.Entry(guid, true)
    entry.seen = math.max(entry.seen or 0, at)
end
GL.On("CONTACT_SEEN", function(record)
    if record and record.guid then
        I.RecordVisit(record.guid, GL.Now(), record.lastZone)
    end
end)

local function usable(e)
    return type(e) == "table" and not e.voided and e.voidReason ~= "battleground" and type(e.time) == "number"
end
local function fightsOf(record)
    local list = {}
    for _, e in ipairs(record and record.history or {}) do
        if usable(e) and fightKinds[e.kind] then
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b) return a.time < b.time end)
    return list
end
local function facts(events)
    local out = {}
    for i = #events, 1, -1 do
        out[#out + 1] = {at = events[i].time, event = events[i]}
    end
    return out
end
local function ranked(counts, limit)
    local keys = {}
    for key in pairs(counts) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return a < b
    end)
    local parts = {}
    for i = 1, math.min(limit, #keys) do
        parts[i] = keys[i] .. " (" .. counts[keys[i]] .. ")"
    end
    return table.concat(parts, ", "), #keys
end

local function openings(record, out)
    local list, first = {}, 0
    for _, e in ipairs(record.history or {}) do
        if usable(e) and e.kind == "opening" then
            list[#list + 1] = e
            first = first + (e.opener == "opponent" and 1 or 0)
        end
    end
    if #list > 0 then
        table.sort(list, function(a, b) return a.time < b.time end)
        out[#out + 1] = {key = "opening", text = L("Il ouvre le combat %d fois sur %d"):format(first, #list), facts = facts(list),
            value = ("%d / %d"):format(first, #list), caption = L("ouvre le combat lui-même")}
    end
end
local function levels(fights, out)
    local list, gap = {}, 0
    for _, e in ipairs(fights) do
        local c = type(e.combat) == "table" and e.combat
        local his, mine = c and GL.ValidLevel(c.opponentLevel), c and GL.ValidLevel(c.playerLevel)
        if his and mine then
            list[#list + 1] = e
            gap = gap + his - mine
        end
    end
    if #list > 0 then
        local mean = gap / #list
        mean = mean >= 0 and math.floor(mean + .5) or -math.floor(-mean + .5)
        local text = #list == 1 and L("Écart de niveau avec vous : %s (un combat)") or L("Écart de niveau moyen avec vous : %s (%d combats)")
        out[#out + 1] = {key = "levels", text = text:format(("%+d"):format(mean), #list), facts = facts(list),
            value = ("%+d"):format(mean), caption = mean >= 0 and L("niveaux de plus que vous, en moyenne") or L("niveaux de moins que vous, en moyenne")}
    end
end
-- His spells against you, and the players who hit you during his fights.
local function reports(guid, fights, out)
    local spells, spellFights, helpers, helperFights, reported = {}, {}, {}, {}, 0
    for _, e in ipairs(fights) do
        local report = type(e.report) == "table" and e.report
        local rows = report and (report.live or report.recap)
        if type(rows) == "table" and #rows > 0 then
            reported = reported + 1
            local cast, seen = false, {}
            for _, hit in ipairs(rows) do
                if hit.dst == e.actorGUID and hit.src == guid and type(hit.spell) == "string" then
                    spells[hit.spell] = (spells[hit.spell] or 0) + 1
                    cast = true
                elseif hit.dst == e.actorGUID and type(hit.src) == "string" and hit.src ~= guid
                    and hit.src:match("^Player%-") and not hit.srcPet and type(hit.from) == "string" and not seen[hit.from] then
                    seen[hit.from] = true
                    helpers[hit.from] = (helpers[hit.from] or 0) + 1
                end
            end
            if cast then
                spellFights[#spellFights + 1] = e
            end
            if next(seen) then
                helperFights[#helperFights + 1] = e
            end
        end
    end
    if #spellFights > 0 then
        local top = ranked(spells, 1):gsub(" %(%d+%)$", "")
        out[#out + 1] = {key = "spells", text = L("Ses sorts contre vous : %s"):format((ranked(spells, 3))), facts = facts(spellFights),
            value = top, caption = L("son sort principal contre vous")}
    end
    if #helperFights > 0 then
        local names = ranked(helpers, 2)
        local text = L("Combats avec complices : %d sur %d · %s"):format(#helperFights, reported, names)
        out[#out + 1] = {key = "helpers", text = text, facts = facts(helperFights),
            value = ("%d / %d"):format(#helperFights, reported), caption = L("combats avec des complices")}
    end
end
local function streak(fights, out)
    local run, kind = {}, nil
    for i = #fights, 1, -1 do
        local e = fights[i]
        if e.kind ~= "aggression" then
            if kind and e.kind ~= kind then
                break
            end
            kind = e.kind
            table.insert(run, 1, e)
        end
    end
    if #run >= 2 then
        local text = kind == "kill" and L("Vous l’avez vaincu %d fois de suite") or L("Il vous a tué %d fois de suite")
        out[#out + 1] = {key = "streak", text = text:format(#run), facts = facts(run), value = tostring(#run),
            caption = kind == "kill" and L("victoires de suite contre lui") or L("morts de suite contre lui")}
    end
end
-- Whole fights, not their blows: an aggression and the death it caused are one fight.
local function recent(record, out)
    local list = {}
    for _, fight in ipairs(GL.Fights(record)) do
        if fight.at >= GL.Now() - 7 * DAY then
            table.insert(list, 1, fight.main)
        end
    end
    if #list >= 2 then
        out[#out + 1] = {key = "recent", text = L("%d combats ces 7 derniers jours"):format(#list), facts = facts(list),
            value = tostring(#list), caption = L("combats ces 7 derniers jours")}
    end
end

-- Sightings: the recorded visits, plus the dated journal events from before visits were recorded.
function I.Presence(record, guid)
    local p = guid and presenceFor(guid, false)
    local grid, zones, sightings, total, days = {}, {}, {}, 0, {}
    for key, n in pairs(p and p.hours or {}) do
        grid[key], total = n, total + n
    end
    for key, n in pairs(p and p.days or {}) do
        days[key] = n
    end
    -- Visits recorded before days were counted (0.17 to 0.20) still give their day.
    if p and not p.days then
        for _, v in ipairs(p.visits or {}) do
            days[I.DayKey(v.at)] = (days[I.DayKey(v.at)] or 0) + 1
        end
    end
    for zone, n in pairs(p and p.zones or {}) do
        zones[zone] = n
    end
    for _, v in ipairs(p and p.visits or {}) do
        sightings[#sightings + 1] = {at = v.at, zone = v.zone}
    end
    local since, last = p and p.since or math.huge, nil
    local events = {}
    for _, e in ipairs(record and record.history or {}) do
        if usable(e) and e.time < since and e.kind ~= "note" then
            events[#events + 1] = e
        end
    end
    table.sort(events, function(a, b) return a.time < b.time end)
    for _, e in ipairs(events) do
        if not last or e.time - last >= VISIT_GAP then
            local key = cell(e.time)
            grid[key], total = (grid[key] or 0) + 1, total + 1
            days[I.DayKey(e.time)] = (days[I.DayKey(e.time)] or 0) + 1
            if type(e.zone) == "string" and e.zone ~= "?" then
                zones[e.zone] = (zones[e.zone] or 0) + 1
            end
            sightings[#sightings + 1] = {at = e.time, event = e}
        end
        last = e.time
    end
    table.sort(sightings, function(a, b) return a.at > b.at end)
    local max = 0
    for _, n in pairs(grid) do
        max = math.max(max, n)
    end
    return {grid = grid, max = max, total = total, zones = zones, sightings = sightings, days = days}
end
-- The three-hour window with the most sightings, and the days seen over the last two weeks.
local function habits(presence, out)
    if presence.total < 3 then
        return
    end
    local byHour = {}
    for key, n in pairs(presence.grid) do
        byHour[key % 24] = (byHour[key % 24] or 0) + n
    end
    local best, most = 0, -1
    for h = 0, 23 do
        local n = (byHour[h] or 0) + (byHour[(h + 1) % 24] or 0) + (byHour[(h + 2) % 24] or 0)
        if n > most then
            best, most = h, n
        end
    end
    local window = {}
    local days, cutoff = {}, GL.Now() - 14 * DAY
    for _, s in ipairs(presence.sightings) do
        local _, hour = clock(s.at)
        if (hour - best) % 24 < 3 then
            window[#window + 1] = s
        end
        if s.at >= cutoff then
            -- The player's local day, like the hour grid (audit 24/11).
            days[I.DayKey(s.at) or math.floor(s.at / DAY)] = true
        end
    end
    local text = L("Surtout vu entre %d h et %d h (%d sur %d apparitions)"):format(best, (best + 3) % 24, most, presence.total)
    out[#out + 1] = {key = "hours", text = text, facts = window, value = L("%d h – %d h"):format(best, (best + 3) % 24),
        caption = L("l'heure où il est le plus souvent vu")}
    local count = 0
    for _ in pairs(days) do
        count = count + 1
    end
    if count > 0 then
        local text = count == 1 and L("Vu un jour sur les 14 derniers") or L("Vu %d jours sur les 14 derniers"):format(count)
        out[#out + 1] = {key = "days", text = text, facts = presence.sightings, value = ("%d / 14"):format(count),
            caption = L("jours où il a été vu, sur deux semaines")}
    end
end

-- "Your story with them": a few dated sentences from your own journal, friends and enemies alike.
function I.Story(record)
    local out = {}
    if type(record) ~= "table" then return out end
    local function day(at) return GL.Safe(date, "%d/%m/%Y", at) or "?" end
    local first, zone
    for _, e in ipairs(record.history or {}) do
        if type(e) == "table" and type(e.time) == "number" and (not first or e.time < first) then
            first, zone = e.time, type(e.zone) == "string" and e.zone ~= "?" and e.zone or nil
        end
    end
    local seen = tonumber(record.firstSeen)
    if seen and (not first or seen < first) then
        first, zone = seen, nil
    end
    first = first or math.huge
    if first < math.huge then
        out[#out + 1] = zone and L("Croisé pour la première fois le %s, %s."):format(day(first), zone)
            or L("Croisé pour la première fois le %s."):format(day(first))
    end
    local groups = tonumber(record.groupCount) or 0
    if groups > 0 then
        local seconds = 0
        for _, e in ipairs(record.history or {}) do
            if type(e) == "table" and e.kind == "grouped" and GL.GroupDuration then seconds = seconds + GL.GroupDuration(e) end
        end
        local line = groups == 1 and L("Un groupe ensemble") or L("%d groupes ensemble"):format(groups)
        if seconds >= 60 then
            line = line .. " · " .. L("%d h %02d au total"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
        end
        out[#out + 1] = line .. "."
    end
    local duels = type(record.duels) == "table" and record.duels or {}
    if (duels.wins or 0) + (duels.losses or 0) > 0 then
        out[#out + 1] = L("Duels : %d gagnés, %d perdus."):format(duels.wins or 0, duels.losses or 0)
    end
    local pvp = record.pvp or {}
    if (pvp.deaths or 0) + (pvp.kills or 0) > 0 then
        out[#out + 1] = L("Il vous a tué %d fois ; vous l’avez vaincu %d fois."):format(pvp.deaths or 0, pvp.kills or 0)
    end
    local fights = GL.Fights(record)
    if fights[1] and GL.FightTitle then
        out[#out + 1] = L("Dernier combat le %s : %s."):format(day(fights[1].at), GL.FightTitle(fights[1]))
    end
    local debt = GL.Debt(record)
    if debt > 0 then
        out[#out + 1] = L("Il vous doit encore %d."):format(debt)
    elseif (pvp.deaths or 0) > 0 then
        out[#out + 1] = L("Compte réglé.")
    end
    return out
end

-- The facts shown under "À savoir", most telling first.
-- A nickname drawn from the facts, the strongest first; none while the facts are too thin, because
-- a name without a nickname is better than a false one. Each kind has a pool of names
-- (Epithets.lua), drawn with the player's identifier: the same player keeps the same nickname.
-- Enemies:
--   three deaths within ten minutes                                    -> camper
--   five deaths at least, never beaten                                 -> nemesis
--   two deaths at least, mostly while 3+ levels above you              -> bully
--   two deaths at least, mostly between midnight and 5 am              -> nightstalker
--   two deaths in the same zone                                        -> zone ("Le Fléau de <zone>")
--   opens the fight three times out of four (three openings at least)  -> backstab
--   half of your deaths with accomplices (two at least)                -> pack
--   beaten twice at least while 2+ levels above you, never the reverse  -> giant
--   beaten three times, never the reverse, mostly 3+ levels below you  -> smallfry
--   beaten three times, never the reverse                              -> prey
--   three victories and three deaths at least, neither twice the other -> rival
-- Allies (never an enemy or a watched player):
--   five groups or three hours together                                -> companion
--   three duels at least                                               -> duelpartner
--   three groups at least                                              -> dungeonbuddy
--   marked as a friend                                                 -> friend
--   known for three months and seen in the last two weeks              -> veteran
--   crossed fifteen times                                              -> regular
-- Anyone crossed eight times and never fought                          -> passerby
function I.NicknameKind(record)
    if type(record) ~= "table" then return nil end
    local zones, deaths, packs, openings, first, seconds, times = {}, 0, 0, 0, 0, 0, {}
    local leveledDeaths, bigger, nightDeaths, leveledKills, smaller, higher = 0, 0, 0, 0, 0, 0
    for _, e in ipairs(record.history or {}) do
        if usable(e) then
            local combat = type(e.combat) == "table" and e.combat or {}
            local mine, theirs = tonumber(combat.playerLevel), tonumber(combat.opponentLevel)
            if e.kind == "death" then
                deaths = deaths + 1
                if type(e.time) == "number" then
                    times[#times + 1] = e.time
                    local hour = type(date) == "function" and tonumber(date("%H", e.time))
                    if hour and hour < 5 then nightDeaths = nightDeaths + 1 end
                end
                if mine and theirs then
                    leveledDeaths = leveledDeaths + 1
                    if theirs >= mine + 3 then bigger = bigger + 1 end
                end
                if type(e.zone) == "string" and e.zone ~= "" and e.zone ~= "?" then zones[e.zone] = (zones[e.zone] or 0) + 1 end
                local rows = type(e.report) == "table" and (e.report.live or e.report.recap) or {}
                for _, hit in ipairs(rows) do
                    if type(hit) == "table" and hit.dst == e.actorGUID and type(hit.src) == "string"
                        and hit.src:match("^Player%-") and hit.src ~= record.guid then
                        packs = packs + 1
                        break
                    end
                end
            elseif e.kind == "kill" then
                if mine and theirs then
                    leveledKills = leveledKills + 1
                    if mine >= theirs + 3 then smaller = smaller + 1 end
                    if theirs >= mine + 2 then higher = higher + 1 end
                end
            elseif e.kind == "opening" then
                openings = openings + 1
                first = first + (e.opener == "opponent" and 1 or 0)
            elseif e.kind == "grouped" and GL.GroupDuration then
                seconds = seconds + GL.GroupDuration(e)
            end
        end
    end
    local pvp = record.pvp or {}
    local kills, killed = tonumber(pvp.kills) or 0, tonumber(pvp.deaths) or 0
    table.sort(times)
    for i = 3, #times do
        if times[i] - times[i - 2] <= 600 then return "camper" end
    end
    if killed >= 5 and kills == 0 then return "nemesis" end
    if deaths >= 2 and leveledDeaths >= 2 and bigger * 2 >= leveledDeaths then return "bully" end
    if deaths >= 2 and nightDeaths * 2 >= deaths then return "nightstalker" end
    local worst, most = nil, 1
    for zone, n in pairs(zones) do
        if n > most or (n == most and worst and zone < worst) then worst, most = zone, n end
    end
    if worst then return "zone", worst end
    if openings >= 3 and first * 4 >= openings * 3 then return "backstab" end
    if packs >= 2 and packs * 2 >= deaths then return "pack" end
    if killed == 0 and kills >= 2 and higher >= 2 and higher * 2 >= leveledKills then return "giant" end
    if killed == 0 and kills >= 3 and leveledKills >= 2 and smaller * 2 >= leveledKills then return "smallfry" end
    if kills >= 3 and killed == 0 then return "prey" end
    if kills >= 3 and killed >= 3 and kills < 2 * killed and killed < 2 * kills then return "rival" end
    local relation = GL.Relation(record)
    local fought = kills + killed + (tonumber(pvp.aggressions) or 0)
    if relation ~= "enemy" and relation ~= "warning" then
        local groups = tonumber(record.groupCount) or 0
        local duels = type(record.duels) == "table" and record.duels or {}
        local seen = type(record.encounters) == "table" and tonumber(record.encounters.count) or 0
        local now, firstSeen, last = GL.Now(), tonumber(record.firstSeen), tonumber(record.lastEncounterAt)
        if groups >= 5 or seconds >= 3 * 3600 then return "companion" end
        if (tonumber(duels.wins) or 0) + (tonumber(duels.losses) or 0) >= 3 then return "duelpartner" end
        if groups >= 3 then return "dungeonbuddy" end
        if relation == "friend" then return "friend" end
        if firstSeen and last and now - firstSeen >= 90 * 86400 and now - last <= 14 * 86400 then return "veteran" end
        if seen >= 15 then return "regular" end
    end
    if fought == 0 and (type(record.encounters) == "table" and tonumber(record.encounters.count) or 0) >= 8 then return "passerby" end
    return nil
end
function I.Nickname(record)
    local kind, zone = I.NicknameKind(record)
    if not kind or not GL.Epithets then return nil end
    return GL.Epithets.Nickname(kind, record.guid or record.key or record.fullName, zone and GL.UITheme.plain(zone))
end

function I.Facts(record, guid)
    local out = {}
    if not record then
        return out
    end
    local fights = fightsOf(record)
    openings(record, out)
    levels(fights, out)
    reports(guid or record.guid, fights, out)
    streak(fights, out)
    recent(record, out)
    habits(I.Presence(record, guid or record.guid), out)
    return out
end
-- Zones sorted by sightings: {name, count}.
function I.ZoneList(presence)
    local list = {}
    for zone, n in pairs(presence.zones) do
        list[#list + 1] = {name = zone, count = n}
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return list
end
function I.Zones(presence, limit)
    return (ranked(presence.zones, limit or 3))
end
