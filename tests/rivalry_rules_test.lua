-- The stories of the Rivalités page (owner's brief, 25/11): what the rules may say from a journal,
-- and what they must not. Synthetic sheets only, written as the journal writes them.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local R, Rules = GL.RelationsPages, GL.RivalryRules
local now = 1800000000
GetServerTime = function() return now end
-- The calendar days of the client: the harness gives one fixed date for every moment.
date = function(format, at) return os.date(format, at) end
local DAY = 86400
local KB, WITH = "Dégâts létaux explicitement attribués à ce joueur.", "Participation à l’attaque ayant causé votre mort."
-- A sheet from a list of facts, oldest first: { kind, seconds ago, evidence or zone }.
local serial = 0
local function sheet(id, facts, zone)
    local record = { key = "guid:Player-9-" .. id, guid = "Player-9-" .. id, name = id, fullName = id .. " Test", history = {},
        pvp = { kills = 0, deaths = 0, aggressions = 0 } }
    for _, f in ipairs(facts) do
        serial = serial + 1
        local e = { kind = f[1], time = now - f[2], confidence = "confirmed", eventId = "r" .. serial, zone = f[4] or zone or "Azshara",
            combat = f[5] }
        if f[1] == "death" then
            e.evidence = f[3] or KB
            e.killingBlow = e.evidence == KB
        end
        record.history[#record.history + 1] = e
        local field = ({ kill = "kills", death = "deaths", aggression = "aggressions" })[f[1]]
        if field then record.pvp[field] = record.pvp[field] + 1 end
    end
    GL.db.players[record.key] = record
    return record
end
local function story(record) return Rules.FromRecord(record, GL, now) end

-- 1. Nhaya, Azshara, 22/11: a death with others, a death to her blow, two victories, a death to her
-- blow. Two victories had brought it back to even; the last fight gave her the lead again.
local nhaya = sheet("Nhaya", {
    { "aggression", 9000 }, { "death", 8990, WITH }, { "aggression", 7000 }, { "death", 6990 },
    { "kill", 5000 }, { "kill", 3000 }, { "aggression", 1000 }, { "death", 990 } })
local a = story(nhaya)
assert(a.kills == 2 and a.deaths == 3 and #a.timeline == 5 and a.chronology.complete, "Nhaya's five fights")
assert(a.narrative.id == "serie_victoires_interrompue" and a.narrative.params.egaliteAvantDernier, a.narrative.id)
assert(R.RivalSentence(a) == "2 victoires vous avaient ramenés à égalité. Au dernier combat, votre rival a repris l’avantage.")
assert(a.timeline[5].deathCause == "contributed" and a.timeline[1].deathCause == "killing_blow" and a.timeline[1].aggressions == 1)
assert(a.lastOutcomeZone == "Azshara" and a.debt == GL.Debt(nhaya))

-- 2. The same final score with a journal that lost fights: no story is made up, only the score.
local partial = sheet("Partiel", { { "kill", 5000 }, { "death", 990 } })
partial.pvp.kills, partial.pvp.deaths = 2, 3
a = story(partial)
assert(not a.chronology.complete and a.narrative.id == "historique_incomplet", a.narrative.id)
assert(R.RivalSentence(a) == "Le journal ne garde pas le détail de tous vos combats contre ce rival.")

-- 3. A death and a victory in the same fight: one mixed step.
local mixed = sheet("Mixte", { { "kill", 3000 }, { "death", 2950 }, { "kill", 2900 } })
a = story(mixed)
assert(a.narrative.id == "issue_mixte" and a.timeline[1].outcome == "mixte", a.narrative.id)
assert(R.RivalSentence(a) == "Une mort et une victoire dans le même combat.")

-- 4. A close duel this week: 3 victories and 3 deaths, alternating, no series.
local duel = sheet("Duel", { { "kill", 6 * 3600 }, { "death", 5 * 3600 }, { "kill", 4 * 3600 }, { "death", 3 * 3600 },
    { "kill", 2 * 3600 }, { "death", 3600 } })
a = story(duel)
assert(a.narrative.id == "duel_dispute" and R.RivalSentence(a) == "Le bilan reste partagé : 3 victoires et 3 morts.", a.narrative.id)

-- 5. Met on three different days: three deaths the same evening count as one day.
local days = sheet("Jours", { { "kill", 3 * DAY }, { "death", 2 * DAY }, { "kill", DAY } })
a = story(days)
assert(a.recentOutcomeDays == 3, a.recentOutcomeDays)
local evening = sheet("Soir", { { "death", 7200 }, { "death", 3600 }, { "death", 600 } })
assert(story(evening).recentOutcomeDays == 1 and story(evening).narrative.id == "serie_morts")

-- 6. Old fights only: the score, no recent motif.
local old = sheet("Ancien", { { "kill", 40 * DAY }, { "death", 39 * DAY } })
a = story(old)
assert(a.narrative.id == "historique_simple" and not a.recent, a.narrative.id)
assert(R.RivalSentence(a) == "Votre journal garde 1 victoire et 1 mort face à ce rival.", R.RivalSentence(a))

-- 7. A sheet the rules cannot read (a damaged counter) is told as a plain score: the page goes on.
local broken = sheet("Casse", { { "kill", 900 }, { "death", 800 } })
broken.pvp.kills = -3
local list = R.RivalStories()
local found
for _, item in ipairs(list) do if item.record == broken then found = item end end
assert(found == nil or found.narrative.id == "aucune_issue_datee", "a damaged sheet stays on the page as a score")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)

-- 8. The ranking: what stands out first, then the latest fight, then the volume, each rival once.
broken.pvp.kills = 1
list = R.RivalStories()
local seen = {}
for i, item in ipairs(list) do
    assert(not seen[item.record.key], "each rival once")
    seen[item.record.key] = true
    if i > 1 then
        local p = list[i - 1]
        assert(p.categoryRank < item.categoryRank or p.categoryRank == item.categoryRank and (p.lastOutcomeAt or 0) >= (item.lastOutcomeAt or 0),
            "ranked by motif, then by the latest fight")
    end
end
assert(list[#list].record == old, "the old score comes last")
-- The search reads names and guilds, any case and accents; the order is kept.
old.guild = "Les Épées"
local hits = R.RivalStories("epees")
assert(#hits == 1 and hits[1].record == old, "found by its guild without accents")
assert(#R.RivalStories("NHAYA") == 1 and #R.RivalStories("zzz") == 0)

-- 9. Random journals: every story reads, every sentence is a sentence, nothing raised.
local seed = 515
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return math.floor(seed / 65536) % n + 1 end
local kinds = { "kill", "death", "aggression", "assist" }
for run = 1, 400 do
    local facts, at = {}, 20 * DAY
    for _ = 1, rnd(14) do
        at = math.max(1, at - rnd(2 * DAY))
        local kind = kinds[rnd(#kinds)]
        facts[#facts + 1] = { kind, at, rnd(2) == 1 and WITH or KB, rnd(3) == 1 and "?" or nil }
    end
    local record = sheet("Rand" .. run, facts)
    if rnd(5) == 1 then record.pvp.kills = record.pvp.kills + rnd(3) end
    if rnd(9) == 1 then record.history[rnd(#record.history)].time = now + 999 end
    local ok, result = pcall(story, record)
    if ok then
        local sentence = R.RivalSentence(result)
        assert(type(sentence) == "string" and #sentence > 10 and not sentence:find("%%"), "run " .. run .. ": " .. tostring(sentence))
        assert(#result.timeline <= #record.history and result.kills == record.pvp.kills, "run " .. run)
    end
end
-- Every sheet with two finished fights is on the page, once; the others are not.
local expected = 0
for _, record in pairs(GL.db.players) do
    if (tonumber(record.pvp.kills) or 0) + (tonumber(record.pvp.deaths) or 0) >= 2 then expected = expected + 1 end
end
list = R.RivalStories()
assert(#list == expected and expected > 200, #list .. " on the page for " .. expected)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
-- 10. The lines (RivalryLines.lua): each situation found from what the journal recorded, the
-- sharpest first, told without a placeholder left, the same sentence until the next fight.
local Lines = GL.RivalryLines
local function first(record) return (Lines.Situations(record, now)[1] or {}).id end
local cases = {
    { "pve", { { "kill", 9000 }, { "death", 60, nil, nil, { pve = true, healthPct = 20, opener = "opponent" } } } },
    { "camping", { { "death", 1500 }, { "death", 900 }, { "death", 60 } } },
    { "lowHealth", { { "kill", 9000 }, { "death", 60, nil, nil, { healthPct = 30 } } } },
    { "gank", { { "kill", 9000 }, { "death", 60, nil, nil, { playerLevel = 50, opponentLevel = 58 } } } },
    { "pack", { { "kill", 9000 }, { "death", 60, WITH, nil, { opponents = 4 } } } },
    { "pet", { { "kill", 9000 }, { "death", 60, "Le familier de ce joueur vous a porté le coup fatal." } } },
    { "firstStrike", { { "kill", 9000 }, { "death", 60, nil, nil, { opener = "opponent" } } } },
    { "quickRevenge", { { "death", 600 }, { "kill", 60 } } },
    { "underdog", { { "death", 9000 }, { "kill", 60, nil, nil, { playerLevel = 50, opponentLevel = 54 } } } },
    { "bully", { { "death", 9000 }, { "kill", 60, nil, nil, { playerLevel = 58, opponentLevel = 50 } } } },
    { "group", { { "death", 9000 }, { "kill", 60, nil, nil, { assist = "Célestine" } } } },
    { "returned", { { "death", 30 * DAY }, { "kill", 60 } } },
    { "resCamp", { { "kill", 9000 }, { "death", 60, nil, nil, { sinceRevive = 35 } } } },
    { "close", { { "kill", 9000 }, { "death", 60, nil, nil, { opponentHealthPct = 7 } } } },
    { "mounted", { { "kill", 9000 }, { "death", 60, nil, nil, { mounted = true } } } },
    { "outnumbered", { { "death", 9000 }, { "kill", 60, nil, nil, { opponents = 3, groupSize = 1 } } } },
    { "quick", { { "death", 9000 }, { "kill", 60, nil, nil, { duration = 4 } } } },
    { "long", { { "death", 9000 }, { "kill", 60, nil, nil, { duration = 240 } } } },
    { "domination", { { "kill", 5000 }, { "kill", 4000 }, { "kill", 3000 }, { "kill", 2000 }, { "death", 1000 }, { "kill", 60 } } },
    { "nemesis", { { "death", 5000 }, { "death", 4000 }, { "death", 3000 }, { "kill", 2000 }, { "death", 1000 } } },
}
for i, case in ipairs(cases) do
    local record = sheet("Ligne" .. i, case[2])
    assert(first(record) == case[1], case[1] .. " found as " .. tostring(first(record)))
    local tell = Lines.Tell(record, story(record), now)
    for _, part in ipairs({ tell.headline, tell.fact, tell.push }) do
        assert(type(part) == "string" and #part > 3 and not part:find("[{}]"), case[1] .. ": " .. tostring(part))
    end
    assert(tell.fact:find("Ligne" .. i, 1, true), case[1] .. " names the rival: " .. tell.fact)
    -- The same sentence on every look, until something new happens.
    local again = Lines.Tell(record, story(record), now)
    assert(again.fact == tell.fact and again.push == tell.push, case[1] .. " is stable")
end
-- The last blows: the killing spell from the report kept with the death, in the sentence.
local spelled = sheet("Sort", { { "kill", 9000 }, { "death", 60 } })
spelled.history[2].report = { live = { { at = now - 70, src = spelled.guid, dst = "me" },
    { at = now - 61, src = spelled.guid, dst = "me", fatal = true, spell = "Éviscération" } } }
assert(Lines.Tell(spelled, story(spelled), now).fact:find("Éviscération", 1, true), "the killing spell is told")
-- The rivalry behind the fight: the third death in the same zone, a streak, the count.
local zoned = sheet("Zone", { { "death", 9 * DAY, nil, "Tanaris" }, { "kill", 5 * DAY, nil, "Tanaris" }, { "death", 2 * DAY, nil, "Tanaris" },
    { "kill", DAY, nil, "Tanaris" }, { "death", 60, nil, "Tanaris" } })
local zonedTell = Lines.Tell(zoned, story(zoned), now)
assert(zonedTell.fact:find("troisième", 1, true) and zonedTell.fact:find("Tanaris", 1, true), zonedTell.fact)
local streak = sheet("Serie", { { "death", 9000 }, { "kill", 5000 }, { "kill", 3000 }, { "kill", 60 } })
assert(Lines.Tell(streak, story(streak), now).fact:find("3 de suite", 1, true) or Lines.Tell(streak, story(streak), now).fact:find("troisième", 1, true))
-- When: today, yesterday, days ago, from the player's clock.
assert(Lines.Tell(zoned, story(zoned), now).fact:find("^Ce ") or Lines.Tell(zoned, story(zoned), now).fact:find("^Cet") or zonedTell.fact:find("^Cette"))
-- The sharpest wins: treachery before a low health, a low health before a first strike.
assert(first(sheet("Ordre", { { "kill", 9000 }, { "death", 60, nil, nil, { pve = true, healthPct = 20, opener = "opponent" } } })) == "pve")
-- Without a zone, no "à {zone}" left in the line.
local nowhere = sheet("Nulle", { { "kill", 9000, nil, "?" }, { "death", 60, nil, "?", { pve = true } } })
local tell = Lines.Tell(nowhere, story(nowhere), now)
assert(tell.headline == "Vous a pris en traître" and not tell.fact:find("{", 1, true), tell.headline)
-- The two banks have the same parts and the English never asks for a word the French lacks.
local function strings(t, out)
    out = out or {}
    if type(t) == "string" then out[#out + 1] = t elseif type(t) == "table" then for _, v in pairs(t) do strings(v, out) end end
    return out
end
for _, part in ipairs({ "headline", "verb", "detail", "memory", "push", "when" }) do
    for id, fr in pairs(Lines.LINES.frFR[part]) do
        local en = Lines.LINES.enUS[part][id]
        assert(en, part .. " " .. tostring(id) .. " in English")
        local marks = {}
        for _, line in ipairs(strings(fr)) do for m in line:gmatch("{%w+}") do marks[m] = true end end
        for _, line in ipairs(strings(en)) do
            for m in line:gmatch("{%w+}") do assert(marks[m], part .. " " .. tostring(id) .. ": " .. m .. " only in English") end
        end
    end
end
-- In English on an English client.
local nativeLocale = GetLocale
GetLocale = function() return "enUS" end
local english = Lines.Tell(nowhere, story(nowhere), now)
assert(english.headline == "Stabbed you in the back", english.headline)
GetLocale = nativeLocale
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS rivalry rules: Nhaya's turn, no story from a partial journal, mixed fight, close duel, days, ranking, search, 400 random sheets")
