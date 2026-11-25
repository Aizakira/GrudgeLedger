-- What a rivalry says to the player (owner, 25/11): why this sheet matters, in a line that seems
-- written for this fight. Everything comes from what the journal recorded:
--   the fight: who struck first, your health when it began, monsters around you, both levels, how
--     many attacked you, your group, your mount, how long after your last revival, how long it
--     lasted, the opponent's health at the end, the pet's blow, a groupmate's help, the hour;
--   its last blows (the report kept with a death or a victory): the killing spell, how many hits;
--   the rivalry: how many times in this zone, how many fights in all, the streak, how long since.
-- A line is built: when and where, a main verb, up to two details (the sharpest first, each with its
-- degree), a reminder of the rivalry, then a push chosen by the balance (crushed, trailing, even,
-- leading, dominating). The choice is fixed for a sheet until its next fight.
-- French and English here; the other languages read the English lines.
local GL = GrudgeLedger
local M = {}
GL.RivalryLines = M
local MINUTE, HOUR, DAY = 60, 3600, 86400

-- {name} the rival, {zone}, {gap} levels, {health} and {left} per cent, {n} a count, {minutes},
-- {seconds}, {since}, {days}, {hour}, {friend}, {spell}, {hits}, {debt}, {nth}, {guild}.
local LINES = {
    frFR = {
        headline = {
            pve = "Vous a pris en traître à {zone}", resCamp = "Vous a tué à peine ressuscité", camping = "Vous a tué {n} fois en {minutes}",
            lowHealth = "Vous a achevé à {health} % de vie", gank = "Vous a tué avec {gap} niveaux de plus", pack = "Ils étaient {n} sur vous",
            close = "Il ne lui restait que {left} %", pet = "Achevé par son familier", mounted = "Vous a jeté de votre monture",
            firstStrike = "Vous a attaqué le premier", quickRevenge = "Vengé en {minutes}", outnumbered = "Seul contre {n}, et vainqueur",
            underdog = "Battu avec {gap} niveaux de moins", bully = "Battu avec {gap} niveaux d’avance", group = "Abattu avec {friend}",
            quick = "Plié en {seconds} secondes", long = "Un combat de {minutes}", returned = "De retour après {days} jours",
            night = "Croisé à {hour} h du matin", domination = "{n} victoires, il vous craint", nemesis = "{n} morts, votre bête noire",
        },
        -- The main verb of a fight, by its outcome.
        verb = {
            death = { "{name} vous a abattu", "{name} a eu votre peau", "{name} vous a fait mordre la poussière", "{name} vous a envoyé au cimetière",
                "{name} vous a tué" },
            kill = { "Vous avez abattu {name}", "Vous avez eu la peau de {name}", "{name} a mordu la poussière", "Vous avez envoyé {name} au cimetière",
                "{name} est tombé sous vos coups" },
        },
        -- One detail of the fight, a clause that follows the verb; some have degrees.
        detail = {
            pve = { "pendant que vous vous battiez contre des monstres", "alors que des monstres vous occupaient déjà" },
            camping = { "{n} fois en {minutes}", "{n} fois en {minutes}, comme on garde une porte" },
            resCamp = { "{since} après votre résurrection", "à peine relevé, {since} après être revenu à la vie" },
            lowHealth = { [15] = { "alors que vous étiez à l’agonie, à {health} % de vie" },
                [35] = { "alors qu’il vous restait {health} % de vie", "en profitant de vos {health} % de vie" } },
            gank = { [5] = { "avec {gap} niveaux de plus que vous" }, [9] = { "avec {gap} niveaux d’avance, rien de moins" },
                [99] = { "avec pas moins de {gap} niveaux de plus" } },
            pack = { "à {n} contre vous", "avec {n} complices sur votre dos" },
            alone = { "alors que vous étiez seul" },
            close = { "alors qu’il ne lui restait que {left} % de vie", "lui-même à {left} % de vie, à un souffle de la défaite" },
            pet = { "en laissant son familier vous achever", "son familier portant le dernier coup" },
            mounted = { "en vous jetant à bas de votre monture", "avant même que vous ne soyez descendu de monture" },
            firstStrike = { "en frappant le premier", "sans même vous laisser le premier coup" },
            spell = { "{spell} en coup de grâce", "avec {spell} pour finir" },
            quick = { "en {seconds} secondes à peine", "le temps de {hits} coups" },
            long = { "au bout de {minutes} de combat", "après {minutes} d’un combat acharné" },
            quickRevenge = { "{minutes} après qu’il vous a tué", "moins d’un quart d’heure après votre mort" },
            outnumbered = { "seul contre {n}", "alors qu’ils étaient {n} contre vous" },
            underdog = { "avec {gap} niveaux de moins", "malgré {gap} niveaux de retard" },
            bully = { "avec {gap} niveaux d’avance", "du haut de vos {gap} niveaux de plus" },
            group = { "avec l’aide de {friend}", "{friend} à vos côtés" },
        },
        -- When and where, at the head of the line.
        when = { today = { night = "Cette nuit", morning = "Ce matin", afternoon = "Cet après-midi", evening = "Ce soir" },
            yesterday = { night = "La nuit dernière", morning = "Hier matin", afternoon = "Hier après-midi", evening = "Hier soir" },
            days = "Il y a {days} jours", long = "Le {day}", at = "{when} à {zone}, " , plain = "{when}, " },
        -- The rivalry behind the fight.
        memory = {
            sameZone = { "C’est la {nth} fois qu’il vous tue à {zone}.", "{zone} lui réussit : {nth} fois déjà." },
            sameTrick = { "Ce n’est pas la première fois qu’il vous fait le coup.", "Il recommence : c’est sa méthode." },
            count = { "Votre {nth} combat contre lui.", "{nth} affrontement entre vous." },
            streak = { "{n} de suite pour lui.", "Sa {nth} victoire d’affilée." },
            yourStreak = { "{n} de suite pour vous.", "Votre {nth} victoire d’affilée." },
            first = { "Votre premier combat contre lui, et déjà une histoire.", "Première rencontre. Elle ne sera pas la dernière." },
            guild = { "Encore un des {guild}.", "Les {guild} vous ont dans le collimateur." },
        },
        nth = { "première", "deuxième", "troisième", "quatrième", "cinquième", "sixième", "septième", "huitième", "neuvième", "dixième" },
        nthMasc = { "premier", "deuxième", "troisième", "quatrième", "cinquième", "sixième", "septième", "huitième", "neuvième", "dixième" },
        nthMore = "{n}e",
        units = { seconds = "{n} secondes", minute = "1 minute", minutes = "{n} minutes" },
        lower = { ["Vous "] = "vous " },
        push = {
            crushed = { "Ça ne peut plus durer.", "{name} vous a pris pour cible. À vous de renverser la vapeur.",
                "Une prime, peut-être : seul, ça ne passe pas.", "Il est temps d’appeler la guilde.", "Changez de route, ou changez la donne.",
                "{debt} points de dette. Il serait temps de les réclamer.", "Il vous connaît par cœur. Surprenez-le." },
            behind = { "Il est temps de lui rendre la monnaie de sa pièce.", "Votre honneur attend toujours réparation.",
                "{name} dort tranquille. Pas pour longtemps.", "Une prime ferait des merveilles.",
                "Le compte n’est pas soldé : {debt} points.", "Retournez à {zone}, il y traîne sûrement encore.",
                "On ne laisse pas une dette pareille vieillir.", "La prochaine fois, c’est vous qui frappez le premier.",
                "Faites-lui regretter ce jour-là.", "Il compte sur votre oubli. Ne lui faites pas ce plaisir.",
                "Chaque jour qui passe, il en rit un peu plus.", "Certains comptes se règlent à la lame." },
            even = { "Rien n’est joué : le prochain combat tranchera.", "Le prochain qui tombe perd la main.",
                "Deux lames, un seul vainqueur à venir.", "Il connaît vos coups, vous connaissez les siens.",
                "La revanche de la revanche se prépare.", "À égalité, c’est le plus patient qui gagne." },
            lead = { "Il vous évite peut-être déjà.", "Savourez : il ne l’oubliera pas de sitôt.", "Votre nom doit le hanter.",
                "Il apprend à ses dépens qu’on ne vous provoque pas.", "Gardez la main, il reviendra.",
                "Un adversaire de plus qui connaît votre nom.", "Belle série. Il faudra la défendre.",
                "Il sait désormais qui commande à {zone}.", "Ne baissez pas la garde : il prépare sa revanche." },
            dominating = { "À ce stade, ce n’est plus une rivalité, c’est une habitude.", "Il devrait songer à changer de serveur.",
                "Votre nom est sûrement sa hantise.", "Il tremble en vous voyant arriver, croyez-le.", "Un trophée de plus sur votre mur." },
        },
    },
    enUS = {
        headline = {
            pve = "Stabbed you in the back in {zone}", resCamp = "Killed you right after you revived", camping = "Killed you {n} times in {minutes}",
            lowHealth = "Finished you at {health}% health", gank = "Killed you with {gap} levels on you", pack = "There were {n} of them",
            close = "Had only {left}% left", pet = "Finished by their pet", mounted = "Knocked you off your mount", firstStrike = "Struck first",
            quickRevenge = "Avenged in {minutes}", outnumbered = "Alone against {n}, and won", underdog = "Beaten {gap} levels below",
            bully = "Beaten {gap} levels above", group = "Brought down with {friend}", quick = "Over in {seconds} seconds",
            long = "A {minutes} fight", returned = "Back after {days} days", night = "Met at {hour} in the morning",
            domination = "{n} victories, they fear you", nemesis = "{n} deaths, your nemesis",
        },
        verb = {
            death = { "{name} brought you down", "{name} got your hide", "{name} made you bite the dust", "{name} sent you to the graveyard",
                "{name} killed you" },
            kill = { "You brought {name} down", "You got {name}'s hide", "{name} bit the dust", "You sent {name} to the graveyard",
                "{name} fell to your blows" },
        },
        detail = {
            pve = { "while you were fighting monsters", "while monsters already kept you busy" },
            camping = { "{n} times in {minutes}", "{n} times in {minutes}, like guarding a door" },
            resCamp = { "{since} after your revival", "barely up again, {since} after coming back to life" },
            lowHealth = { [15] = { "while you were dying at {health}% health" },
                [35] = { "while you had {health}% health left", "taking advantage of your {health}% health" } },
            gank = { [5] = { "with {gap} levels on you" }, [9] = { "with a {gap}-level lead, no less" },
                [99] = { "with no fewer than {gap} levels on you" } },
            pack = { "{n} against you", "with {n} accomplices on your back" },
            alone = { "while you were alone" },
            close = { "with only {left}% health left themselves", "at {left}% health themselves, a breath away from defeat" },
            pet = { "letting their pet finish you", "their pet landing the last blow" },
            mounted = { "knocking you off your mount", "before you could even get off your mount" },
            firstStrike = { "striking first", "without even leaving you the first blow" },
            spell = { "{spell} as the final blow", "with {spell} to finish" },
            quick = { "in barely {seconds} seconds", "in the time of {hits} blows" },
            long = { "after {minutes} of fighting", "after {minutes} of a fierce fight" },
            quickRevenge = { "{minutes} after they killed you", "less than a quarter of an hour after your death" },
            outnumbered = { "alone against {n}", "while there were {n} of them against you" },
            underdog = { "{gap} levels below them", "despite {gap} levels behind" },
            bully = { "{gap} levels above them", "from the height of your {gap} extra levels" },
            group = { "with {friend}'s help", "with {friend} at your side" },
        },
        when = { today = { night = "Last night", morning = "This morning", afternoon = "This afternoon", evening = "This evening" },
            yesterday = { night = "The night before", morning = "Yesterday morning", afternoon = "Yesterday afternoon", evening = "Last evening" },
            days = "{days} days ago", long = "On {day}", at = "{when} in {zone}, ", plain = "{when}, " },
        memory = {
            sameZone = { "The {nth} time they killed you in {zone}.", "{zone} suits them: {nth} time already." },
            sameTrick = { "Not the first time they pull that on you.", "They do it again: that is their way." },
            count = { "Your {nth} fight against them.", "Your {nth} clash." },
            streak = { "{n} in a row for them.", "Their {nth} victory in a row." },
            yourStreak = { "{n} in a row for you.", "Your {nth} victory in a row." },
            first = { "Your first fight against them, and already a story.", "First meeting. It will not be the last." },
            guild = { "Another one from {guild}.", "{guild} have you in their sights." },
        },
        nth = { "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth" },
        nthMore = "{n}th",
        units = { seconds = "{n} seconds", minute = "1 minute", minutes = "{n} minutes" },
        lower = { ["You "] = "you " },
        push = {
            crushed = { "This cannot go on.", "{name} made you a target. Turn the tables.", "A bounty, maybe: alone, it does not work.",
                "Time to call the guild.", "Change your road, or change the game.", "{debt} points owed. Time to collect.",
                "They know you by heart. Surprise them." },
            behind = { "Time to pay them back in kind.", "Your honour still awaits amends.", "{name} sleeps soundly. Not for long.",
                "A bounty would work wonders.", "The account is not settled: {debt} points.", "Go back to {zone}, they surely still roam there.",
                "A debt like that should not grow old.", "Next time, you strike first.", "Make them regret that day.",
                "They count on you forgetting. Do not give them that pleasure.", "Every day that passes, they laugh a little more.",
                "Some accounts are settled with a blade." },
            even = { "Nothing is settled: the next fight will decide.", "Whoever falls next loses the upper hand.",
                "Two blades, one winner to come.", "They know your moves, you know theirs.", "The revenge of the revenge is coming.",
                "When even, the most patient one wins." },
            lead = { "They may already be avoiding you.", "Savour it: they will not forget soon.", "Your name must haunt them.",
                "They are learning the hard way not to provoke you.", "Keep the upper hand, they will be back.",
                "One more enemy who knows your name.", "A fine streak. You will have to defend it.", "They now know who rules {zone}.",
                "Do not lower your guard: they are planning revenge." },
            dominating = { "At this point it is not a rivalry, it is a habit.", "They should think about changing realms.",
                "Your name is surely their nightmare.", "They tremble when they see you coming, believe it.", "One more trophy on your wall." },
        },
    },
}
-- The languages of the addon: French, English, Spanish (Spain and Mexico), German, Portuguese
-- (Brazil). Any other client reads English, as the rest of the addon does.
local ALIASES = { enGB = "enUS", esMX = "esES", ptPT = "ptBR" }
local function bank()
    local locale = GetLocale and GetLocale() or "frFR"
    return LINES[ALIASES[locale] or locale] or LINES.enUS
end
-- A fixed choice for a sheet and a fight: the same sentence until something new happens.
local function pick(list, key)
    if type(list) ~= "table" or #list == 0 then return nil end
    local h = 5381
    for i = 1, #key do h = (h * 33 + key:byte(i)) % 2147483647 end
    return list[h % #list + 1]
end
-- A detail with degrees ({ [15] = ..., [35] = ... }): the first degree the value fits.
local function graded(entry, value)
    if type(entry) ~= "table" or entry[1] ~= nil then return entry end
    local steps = {}
    for limit in pairs(entry) do steps[#steps + 1] = limit end
    table.sort(steps)
    for _, limit in ipairs(steps) do if (value or 0) <= limit then return entry[limit] end end
    return entry[steps[#steps]]
end
local function fill(text, params)
    return (text:gsub("{(%w+)}", function(k)
        local v = params[k]
        return v ~= nil and tostring(v) or ""
    end))
end
local function wanted(text, params)
    for k in text:gmatch("{(%w+)}") do
        if params[k] == nil or params[k] == "" then return false end
    end
    return true
end
-- "1 minute", "12 minutes", "40 secondes": the unit goes with the number.
local function duration(seconds, b)
    local units = b.units
    if seconds < MINUTE then return fill(units.seconds, { n = seconds }) end
    local m = math.floor(seconds / MINUTE + 0.5)
    return m == 1 and units.minute or fill(units.minutes, { n = m })
end
local function ordinal(b, n, masculine)
    local list = masculine and b.nthMasc or b.nth
    return list and list[n] or fill(b.nthMore, { n = n })
end
local function usable(e)
    return type(e) == "table" and not e.voided and e.voidReason ~= "battleground" and e.confidence == "confirmed"
        and type(e.time) == "number" and (e.kind == "death" or e.kind == "kill")
end
local function zoneOf(e)
    return type(e.zone) == "string" and e.zone ~= "" and e.zone ~= "?" and e.zone or nil
end
-- What the last blows say: the killing spell, how many hits from the rival, the span of the log.
local function blows(e, rival)
    local live = type(e.report) == "table" and type(e.report.live) == "table" and e.report.live or {}
    local hits, spell, first, last = 0, nil, nil, nil
    for _, line in ipairs(live) do
        if type(line) == "table" and type(line.at) == "number" then
            local theirs = rival and line.src == rival
            if (e.kind == "death" and theirs) or (e.kind == "kill" and line.dst == rival) then
                hits = hits + 1
                first, last = first or line.at, line.at
                if line.fatal and type(line.spell) == "string" and line.spell ~= "" and #line.spell <= 40 then spell = line.spell end
            end
        end
    end
    return hits, spell, first and last and last - first or nil
end
-- The situations of the latest decisive fight and of the rivalry, the sharpest first. Each one:
-- { id, at, params }. Every number comes from the journal.
local ORDER = { "pve", "resCamp", "camping", "lowHealth", "gank", "pack", "close", "pet", "mounted", "firstStrike", "quickRevenge",
    "outnumbered", "underdog", "bully", "group", "quick", "long", "returned", "night", "domination", "nemesis" }
-- The details a sentence may carry, by outcome, the sharpest first ("spell" and "alone" are only details).
local DETAILS = {
    death = { "camping", "pve", "resCamp", "lowHealth", "gank", "pack", "close", "pet", "mounted", "firstStrike", "alone", "spell", "quick", "long" },
    kill = { "quickRevenge", "outnumbered", "underdog", "bully", "group", "spell", "quick", "long" },
}
local function read(record, now)
    local facts = {}
    for _, e in ipairs(type(record.history) == "table" and record.history or {}) do
        if usable(e) and e.time <= now then facts[#facts + 1] = e end
    end
    table.sort(facts, function(a, b) return a.time > b.time end)
    return facts
end
function M.Situations(record, now)
    now = now or GL.Now()
    local facts = read(record, now)
    local found, latest = {}, facts[1]
    if not latest then return {}, {} end
    local b = bank()
    local c = type(latest.combat) == "table" and latest.combat or {}
    local mine, theirs = tonumber(c.playerLevel), tonumber(c.opponentLevel)
    local where = zoneOf(latest)
    local hits, spell, span = blows(latest, record.guid)
    local seconds = tonumber(c.duration) or span
    local function add(id, params)
        params = params or {}
        params.zone = params.zone or where or ""
        found[id] = { id = id, at = latest.time, params = params }
    end
    if spell then add("spell", { spell = spell }) end
    local many = tonumber(c.opponents)
    if latest.kind == "death" then
        if c.pve then add("pve") end
        local since = tonumber(c.sinceRevive)
        if since and since <= 120 then add("resCamp", { since = duration(math.max(1, math.floor(since)), b) }) end
        local health = tonumber(c.healthPct)
        if health and health <= 35 then add("lowHealth", { health = math.floor(health + 0.5) }) end
        if mine and theirs and theirs - mine >= 3 then add("gank", { gap = theirs - mine }) end
        if many and many >= 3 then add("pack", { n = many }) end
        if many and many >= 2 and tonumber(c.groupSize) == 1 then add("alone") end
        local left = tonumber(c.opponentHealthPct)
        if left and left <= 20 then add("close", { left = left }) end
        if c.pet or latest.evidence == "Le familier de ce joueur vous a porté le coup fatal." then add("pet") end
        if c.mounted then add("mounted") end
        if c.opener == "opponent" then add("firstStrike") end
    else
        if mine and theirs and theirs - mine >= 3 then add("underdog", { gap = theirs - mine }) end
        if mine and theirs and mine - theirs >= 5 then add("bully", { gap = mine - theirs }) end
        if type(c.assist) == "string" and c.assist ~= "" then add("group", { friend = c.assist }) end
        if many and many >= 2 and (tonumber(c.groupSize) or 1) == 1 then add("outnumbered", { n = many }) end
        -- The death this victory answered, a quarter of an hour at most before it.
        for i = 2, #facts do
            local before = facts[i]
            if latest.time - before.time > 15 * MINUTE then break end
            if before.kind == "death" then
                add("quickRevenge", { minutes = duration(math.max(MINUTE, latest.time - before.time), b) })
                break
            end
        end
    end
    if seconds and seconds >= 1 and seconds <= 8 then add("quick", { seconds = math.floor(seconds), hits = hits > 0 and hits or nil }) end
    if seconds and seconds >= 90 then add("long", { minutes = duration(seconds, b) }) end
    -- Three deaths or more in half an hour, the latest among them.
    local deaths, first = 0, nil
    for _, e in ipairs(facts) do
        if latest.time - e.time > 30 * MINUTE then break end
        if e.kind == "death" then deaths, first = deaths + 1, e.time end
    end
    if latest.kind == "death" and deaths >= 3 then
        add("camping", { n = deaths, minutes = duration(math.max(MINUTE, latest.time - first), b) })
    end
    if facts[2] and latest.time - facts[2].time >= 14 * DAY then add("returned", { days = math.floor((latest.time - facts[2].time) / DAY) }) end
    local hour = tonumber(GL.Safe(date, "%H", latest.time))
    if hour and hour < 5 then add("night", { hour = hour }) end
    local kills, losses = tonumber(record.pvp and record.pvp.kills) or 0, tonumber(record.pvp and record.pvp.deaths) or 0
    if kills >= 4 and kills >= 3 * math.max(1, losses) then add("domination", { n = kills }) end
    if losses >= 4 and losses >= 3 * math.max(1, kills) then add("nemesis", { n = losses }) end
    local list = {}
    for _, id in ipairs(ORDER) do if found[id] then list[#list + 1] = found[id] end end
    return list, found, facts
end
-- "Hier soir à Azshara, ": when the fight was, from the player's clock, and where.
local function whenWhere(b, at, now, zone)
    local function part(t)
        local hour = tonumber(GL.Safe(date, "%H", t)) or 12
        return hour < 5 and "night" or hour < 12 and "morning" or hour < 18 and "afternoon" or "evening"
    end
    local today, that = GL.Safe(date, "%Y-%m-%d", now), GL.Safe(date, "%Y-%m-%d", at)
    local yesterday = GL.Safe(date, "%Y-%m-%d", now - DAY)
    local when
    if that and that == today then when = b.when.today[part(at)]
    elseif that and that == yesterday then when = b.when.yesterday[part(at)]
    elseif now - at < 30 * DAY then when = fill(b.when.days, { days = math.max(2, math.floor((now - at) / DAY)) })
    else when = fill(b.when.long, { day = GL.Safe(date, "%d/%m", at) or "" }) end
    if not when then return "" end
    return zone and fill(b.when.at, { when = when, zone = zone }) or fill(b.when.plain, { when = when })
end
-- The rivalry behind the latest fight: the same zone, the same trick, the streak, the count.
local function memory(b, record, facts, found, key, name)
    local latest = facts[1]
    if not latest then return nil end
    local zone = zoneOf(latest)
    if latest.kind == "death" and zone and not found.camping then
        local n = 0
        for _, e in ipairs(facts) do if e.kind == "death" and zoneOf(e) == zone then n = n + 1 end end
        if n >= 2 then return fill(pick(b.memory.sameZone, key .. ":zone"), { nth = ordinal(b, n), n = n, zone = zone }) end
    end
    if latest.kind == "death" and (found.pve or found.firstStrike) then
        local trick = found.pve and "pve" or "opener"
        local n = 0
        for _, e in ipairs(facts) do
            local c = type(e.combat) == "table" and e.combat or {}
            if e.kind == "death" and (trick == "pve" and c.pve or trick == "opener" and c.opener == "opponent") then n = n + 1 end
        end
        if n >= 2 then return pick(b.memory.sameTrick, key .. ":trick") end
    end
    local run = 0
    for _, e in ipairs(facts) do
        if e.kind ~= latest.kind then break end
        run = run + 1
    end
    if run >= 2 then
        local list = latest.kind == "death" and b.memory.streak or b.memory.yourStreak
        local line = pick(list, key .. ":run")
        return fill(line, { n = run, nth = ordinal(b, run) })
    end
    if type(record.guild) == "string" and record.guild ~= "" then
        local sameGuild = 0
        for _, other in pairs(GL.db and GL.db.players or {}) do
            if type(other) == "table" and other ~= record and other.guild == record.guild and (tonumber(other.pvp and other.pvp.deaths) or 0) > 0 then
                sameGuild = sameGuild + 1
            end
        end
        if sameGuild >= 2 and latest.kind == "death" then return fill(pick(b.memory.guild, key .. ":guild"), { guild = record.guild }) end
    end
    local total = #facts
    if total >= 3 then return fill(pick(b.memory.count, key .. ":count"), { nth = ordinal(b, math.min(total, 99), true), n = total }) end
end
-- The line of a sheet: { headline, fact, push, mood, situation }.
function M.Tell(record, analysis, now)
    now = now or GL.Now()
    local b = bank()
    local name = record.name or record.fullName or "?"
    local list, found, facts = M.Situations(record, now)
    local situation = list[1]
    local kills, deaths = analysis and analysis.kills or 0, analysis and analysis.deaths or 0
    local mood = deaths >= 3 * math.max(1, kills) and deaths >= 3 and "crushed" or deaths > kills and "behind"
        or kills >= 3 * math.max(1, deaths) and kills >= 3 and "dominating" or kills > deaths and "lead" or "even"
    local latest = facts and facts[1]
    local key = tostring(record.key) .. ":" .. tostring(latest and latest.time or analysis and analysis.lastOutcomeAt or 0)
    local base = { name = name, debt = analysis and analysis.debt or GL.Debt(record),
        zone = latest and zoneOf(latest) or analysis and analysis.lastOutcomeZone or "" }
    -- A push that needs a zone or a debt the sheet does not have is passed over.
    local pushes = {}
    for _, line in ipairs(b.push[mood] or {}) do
        local needsDebt = line:find("{debt}", 1, true)
        if wanted(line, base) and not (needsDebt and (base.debt or 0) <= 0) then pushes[#pushes + 1] = line end
    end
    local result = { push = fill(pick(pushes, key .. ":push") or "", base), mood = mood, situation = situation }
    if not latest then return result end
    if situation then
        local params = {}
        for k, v in pairs(base) do params[k] = v end
        for k, v in pairs(situation.params) do if v ~= "" then params[k] = v end end
        local headline = b.headline[situation.id] or ""
        -- Without a zone, its word goes with it ("à", "in", "en", "em").
        if params.zone == "" then headline = headline:gsub(" [^ ]+ {zone}", "") end
        if wanted(headline, params) then result.headline = fill(headline, params) end
    end
    -- The sentence: when and where, the verb, two details at most, the sharpest first.
    local verb = fill(pick(b.verb[latest.kind], key .. ":verb") or "", base)
    local clauses = {}
    for _, id in ipairs(DETAILS[latest.kind] or {}) do
        local s = found[id]
        if s and #clauses < 2 then
            local params = {}
            for k, v in pairs(base) do params[k] = v end
            for k, v in pairs(s.params) do params[k] = v end
            local options = graded(b.detail[id], params.health or params.gap)
            local usableOptions = {}
            for _, line in ipairs(options or {}) do if wanted(line, params) then usableOptions[#usableOptions + 1] = line end end
            local line = pick(usableOptions, key .. ":" .. id)
            if line then clauses[#clauses + 1] = fill(line, params) end
        end
    end
    -- After "Hier soir à Azshara, " the pronoun loses its capital; a name keeps it.
    local head = whenWhere(b, latest.time, now, zoneOf(latest))
    local lowered = verb
    for from, to in pairs(b.lower or {}) do
        if lowered:sub(1, #from) == from then lowered = to .. lowered:sub(#from + 1) end
    end
    local sentence = head ~= "" and (head .. lowered) or verb
    if #clauses > 0 then sentence = sentence .. ", " .. table.concat(clauses, ", ") end
    sentence = sentence .. "."
    local remembered = memory(b, record, facts, found, key, name)
    if remembered then sentence = sentence .. " " .. (remembered:gsub("^%l", string.upper)) end
    result.fact = sentence
    return result
end
M.LINES, M.ORDER, M.DETAILS = LINES, ORDER, DETAILS
