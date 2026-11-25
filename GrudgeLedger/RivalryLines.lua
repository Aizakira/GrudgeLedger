-- What a rivalry says to the player (owner, 25/11): "why this sheet matters", in a line that
-- bites. The journal keeps, for each fight, who struck first, your health when it began, whether
-- you were fighting monsters, both levels, how many attacked you, a pet's blow, a group's help, the
-- hour. From those facts a situation is found (the sharpest first), told by a fact that names it,
-- then a line that pushes you: to take revenge when you trail, to savour when you lead, to settle
-- it when even. Several facts and many pushes a situation make hundreds of sentences; the choice
-- is fixed for a sheet until its next fight, so a sentence does not change at every look.
-- French and English here; the other languages read the English lines.
local GL = GrudgeLedger
local M = {}
GL.RivalryLines = M
local MINUTE, DAY = 60, 86400

-- {name} the rival, {zone} where, {gap} levels, {health} per cent, {n} a count, {minutes},
-- {days}, {hour}, {friend} who helped, {debt} points owed.
local LINES = {
    frFR = {
        headline = {
            pve = "Vous a pris en traître à {zone}",
            camping = "Vous a tué {n} fois en {minutes}",
            lowHealth = "Vous a achevé à {health} % de vie",
            gank = "Vous a tué avec {gap} niveaux de plus",
            pack = "Ils étaient {n} sur vous",
            pet = "Achevé par son familier",
            firstStrike = "Vous a attaqué le premier",
            quickRevenge = "Vengé en {minutes}",
            underdog = "Battu avec {gap} niveaux de moins",
            bully = "Battu avec {gap} niveaux d’avance",
            group = "Abattu avec {friend}",
            returned = "De retour après {days} jours",
            night = "Croisé à {hour} h du matin",
            domination = "{n} victoires, il vous craint",
            nemesis = "{n} morts, votre bête noire",
        },
        fact = {
            pve = { "{name} a attendu que vous soyez occupé avec des monstres pour frapper.",
                "Vous vous battiez contre des monstres à {zone} quand {name} s’est invité.",
                "Pendant que vous nettoyiez {zone}, {name} vous a planté une lame dans le dos." },
            camping = { "{n} morts en {minutes} : {name} vous attendait à la sortie.",
                "{name} vous a tué {n} fois en {minutes} à {zone}. Ce n’était plus un combat, c’était une garde.",
                "Chaque fois que vous reveniez, {name} était là : {n} fois en {minutes}." },
            lowHealth = { "Il vous restait {health} % de vie quand {name} a frappé. Facile.",
                "{name} a choisi le moment où vous étiez à {health} % de vie.",
                "À {health} % de vie, vous n’aviez aucune chance, et {name} le savait." },
            gank = { "{name} avait {gap} niveaux de plus que vous. Pas vraiment un duel.",
                "Avec {gap} niveaux d’avance, {name} n’a pas pris beaucoup de risques.",
                "{gap} niveaux d’écart : {name} aime les combats gagnés d’avance." },
            pack = { "Ils étaient {n} sur vous, et {name} en faisait partie.",
                "{name} n’est pas venu seul : vous aviez {n} adversaires sur le dos.",
                "{n} contre un à {zone}, avec {name} dans le lot." },
            pet = { "Ce n’est même pas {name} qui vous a achevé, c’est son familier.",
                "Le coup fatal est venu du familier de {name}.",
                "{name} a laissé son familier finir le travail." },
            firstStrike = { "{name} a frappé le premier, sans attendre.",
                "C’est {name} qui a ouvert les hostilités à {zone}.",
                "Vous n’aviez rien demandé : {name} a attaqué le premier." },
            quickRevenge = { "Tué par {name}, vous l’avez vengé {minutes} plus tard.",
                "{minutes} : le temps qu’il vous a fallu pour rendre la pareille à {name}.",
                "{name} a eu {minutes} pour savourer. Pas une de plus." },
            underdog = { "Vous avez battu {name} avec {gap} niveaux de moins.",
                "{gap} niveaux de retard, et c’est quand même {name} qui est tombé.",
                "{name} avait {gap} niveaux d’avance. Ça ne lui a pas suffi." },
            bully = { "Vous aviez {gap} niveaux d’avance sur {name}.",
                "{name} avait {gap} niveaux de moins que vous. Victoire facile.",
                "Avec {gap} niveaux d’écart, {name} n’avait pas grand-chose à opposer." },
            group = { "{name} est tombé sous vos coups et ceux de {friend}.",
                "Avec {friend} à vos côtés, {name} n’a pas tenu.",
                "{friend} et vous : {name} n’avait aucune chance." },
            returned = { "{days} jours sans nouvelles, puis {name} a refait surface.",
                "{name} avait disparu {days} jours. Le revoilà.",
                "Après {days} jours de silence, {name} est revenu croiser votre route." },
            night = { "{hour} h du matin à {zone}, et {name} était encore là.",
                "Même à {hour} h du matin, {name} rôde à {zone}.",
                "{name} ne dort pas : {hour} h du matin, et vous voilà face à face." },
            domination = { "{n} victoires sur {name}. Il doit changer de chemin en vous voyant.",
                "Vous avez battu {name} {n} fois. Il connaît le goût de la poussière.",
                "{n} fois, {name} est tombé devant vous." },
            nemesis = { "{name} vous a tué {n} fois. C’est devenu une habitude.",
                "{n} morts face à {name}. Il commence à vous connaître par cœur.",
                "{name} compte {n} victoires contre vous. Il les compte, vous pouvez en être sûr." },
        },
        push = {
            behind = { "Il est temps de lui rendre la monnaie de sa pièce.", "Votre honneur attend toujours réparation.",
                "{name} dort tranquille. Pas pour longtemps.", "Une prime ferait des merveilles.",
                "Le compte n’est pas soldé : {debt} points.", "Retournez à {zone}, il y traîne sûrement encore.",
                "On ne laisse pas une dette pareille vieillir.", "La prochaine fois, c’est vous qui frappez le premier.",
                "Faites-lui regretter ce jour-là.", "Il compte sur votre oubli. Ne lui faites pas ce plaisir.",
                "Chaque jour qui passe, il en rit un peu plus.", "Certains comptes se règlent à la lame." },
            lead = { "Il vous évite peut-être déjà.", "Savourez : il ne l’oubliera pas de sitôt.", "Votre nom doit le hanter.",
                "Il apprend à ses dépens qu’on ne vous provoque pas.", "Gardez la main, il reviendra.",
                "Un adversaire de plus qui connaît votre nom.", "Belle série. Il faudra la défendre.",
                "Il sait désormais qui commande à {zone}.", "Ne baissez pas la garde : il prépare sa revanche." },
            even = { "Rien n’est joué : le prochain combat tranchera.", "Le prochain qui tombe perd la main.",
                "Deux lames, un seul vainqueur à venir.", "Il connaît vos coups, vous connaissez les siens.",
                "La revanche de la revanche se prépare.", "À égalité, c’est le plus patient qui gagne." },
        },
    },
    enUS = {
        headline = {
            pve = "Stabbed you in the back in {zone}", camping = "Killed you {n} times in {minutes}",
            lowHealth = "Finished you at {health}% health", gank = "Killed you with {gap} levels on you",
            pack = "There were {n} of them", pet = "Finished by their pet", firstStrike = "Struck first",
            quickRevenge = "Avenged in {minutes}", underdog = "Beaten {gap} levels below",
            bully = "Beaten {gap} levels above", group = "Brought down with {friend}", returned = "Back after {days} days",
            night = "Met at {hour} in the morning", domination = "{n} victories, they fear you", nemesis = "{n} deaths, your nemesis",
        },
        fact = {
            pve = { "{name} waited until you were busy with monsters to strike.", "You were fighting monsters in {zone} when {name} joined in.",
                "While you were clearing {zone}, {name} put a blade in your back." },
            camping = { "{n} deaths in {minutes}: {name} was waiting for you.",
                "{name} killed you {n} times in {minutes} in {zone}. Not a fight anymore, a watch.",
                "Every time you came back, {name} was there: {n} times in {minutes}." },
            lowHealth = { "You had {health}% health left when {name} struck. Easy.", "{name} picked the moment you were at {health}% health.",
                "At {health}% health you had no chance, and {name} knew it." },
            gank = { "{name} was {gap} levels above you. Hardly a duel.", "With {gap} levels on you, {name} took few risks.",
                "{gap} levels apart: {name} likes fights won in advance." },
            pack = { "There were {n} of them on you, {name} among them.", "{name} did not come alone: {n} enemies on your back.",
                "{n} against one in {zone}, {name} in the pack." },
            pet = { "It was not even {name} who finished you, it was their pet.", "The killing blow came from {name}'s pet.",
                "{name} let their pet finish the job." },
            firstStrike = { "{name} struck first, without waiting.", "{name} started it in {zone}.", "You asked for nothing: {name} attacked first." },
            quickRevenge = { "Killed by {name}, you avenged it {minutes} later.", "{minutes}: all it took to pay {name} back.",
                "{name} had {minutes} to enjoy it. Not one more." },
            underdog = { "You beat {name} {gap} levels below them.", "{gap} levels behind, and still {name} fell.",
                "{name} was {gap} levels ahead. It was not enough." },
            bully = { "You were {gap} levels above {name}.", "{name} was {gap} levels below you. An easy win.",
                "{gap} levels apart, {name} had little to answer with." },
            group = { "{name} fell to you and {friend}.", "With {friend} at your side, {name} did not last.",
                "{friend} and you: {name} never stood a chance." },
            returned = { "{days} days without a word, then {name} came back.", "{name} had vanished for {days} days. Here they are again.",
                "After {days} days of silence, {name} crossed your path again." },
            night = { "{hour} in the morning in {zone}, and {name} was still there.", "Even at {hour} in the morning, {name} prowls {zone}.",
                "{name} never sleeps: {hour} in the morning, and there you are." },
            domination = { "{n} victories over {name}. They must change paths when they see you.", "You beat {name} {n} times. They know the taste of dust.",
                "{n} times, {name} fell before you." },
            nemesis = { "{name} killed you {n} times. It became a habit.", "{n} deaths to {name}. They know you by heart.",
                "{name} has {n} victories over you. Be sure they count them." },
        },
        push = {
            behind = { "Time to pay them back in kind.", "Your honour still awaits amends.", "{name} sleeps soundly. Not for long.",
                "A bounty would work wonders.", "The account is not settled: {debt} points.", "Go back to {zone}, they surely still roam there.",
                "A debt like that should not grow old.", "Next time, you strike first.", "Make them regret that day.",
                "They count on you forgetting. Do not give them that pleasure.", "Every day that passes, they laugh a little more.",
                "Some accounts are settled with a blade." },
            lead = { "They may already be avoiding you.", "Savour it: they will not forget soon.", "Your name must haunt them.",
                "They are learning the hard way not to provoke you.", "Keep the upper hand, they will be back.",
                "One more enemy who knows your name.", "A fine streak. You will have to defend it.", "They now know who rules {zone}.",
                "Do not lower your guard: they are planning revenge." },
            even = { "Nothing is settled: the next fight will decide.", "Whoever falls next loses the upper hand.",
                "Two blades, one winner to come.", "They know your moves, you know theirs.", "The revenge of the revenge is coming.",
                "When even, the most patient one wins." },
        },
    },
}
local function lines()
    local locale = GetLocale and GetLocale() or "frFR"
    return LINES[locale] or LINES.enUS
end
-- A fixed choice for a sheet and a fight: the same sentence until something new happens.
local function pick(list, key)
    if type(list) ~= "table" or #list == 0 then return "" end
    local h = 5381
    for i = 1, #key do h = (h * 33 + key:byte(i)) % 2147483647 end
    return list[h % #list + 1]
end
-- "1 minute", "12 minutes": the unit goes with the number, in the player's language.
local function minutes(n)
    local french = not GetLocale or GetLocale() == "frFR"
    return n == 1 and (french and "1 minute" or "1 minute") or tostring(n) .. " minutes"
end
local function fill(text, params)
    return (text:gsub("{(%w+)}", function(k)
        local v = params[k]
        return v ~= nil and tostring(v) or ""
    end))
end
local function usable(e)
    return type(e) == "table" and not e.voided and e.voidReason ~= "battleground" and e.confidence == "confirmed"
        and type(e.time) == "number" and (e.kind == "death" or e.kind == "kill")
end
local function zone(e)
    return type(e.zone) == "string" and e.zone ~= "" and e.zone ~= "?" and e.zone or nil
end
-- The situations of the latest decisive fight and of the week, the sharpest first. Each one:
-- { id, at, params }. The levels, health and the rest come only from what the journal recorded.
local ORDER = { "pve", "camping", "lowHealth", "gank", "pack", "pet", "firstStrike", "quickRevenge", "underdog", "bully",
    "group", "returned", "night", "domination", "nemesis" }
function M.Situations(record, now)
    now = now or GL.Now()
    local facts = {}
    for _, e in ipairs(type(record.history) == "table" and record.history or {}) do
        if usable(e) and e.time <= now then facts[#facts + 1] = e end
    end
    table.sort(facts, function(a, b) return a.time > b.time end)
    local found = {}
    local latest = facts[1]
    if not latest then return found end
    local c = type(latest.combat) == "table" and latest.combat or {}
    local mine, theirs = tonumber(c.playerLevel), tonumber(c.opponentLevel)
    local where = zone(latest)
    local function add(id, params)
        params = params or {}
        params.zone = params.zone or where or ""
        found[id] = { id = id, at = latest.time, params = params }
    end
    if latest.kind == "death" then
        if c.pve then add("pve") end
        local health = tonumber(c.healthPct)
        if health and health <= 35 then add("lowHealth", { health = math.floor(health + 0.5) }) end
        if mine and theirs and theirs - mine >= 5 then add("gank", { gap = theirs - mine }) end
        local many = tonumber(c.opponents)
        if many and many >= 3 then add("pack", { n = many }) end
        if latest.evidence == "Le familier de ce joueur vous a porté le coup fatal." then add("pet") end
        if c.opener == "opponent" then add("firstStrike") end
    else
        if mine and theirs and theirs - mine >= 3 then add("underdog", { gap = theirs - mine }) end
        if mine and theirs and mine - theirs >= 5 then add("bully", { gap = mine - theirs }) end
        if type(c.assist) == "string" and c.assist ~= "" then add("group", { friend = c.assist }) end
        -- The death this victory answered, a quarter of an hour at most before it.
        for i = 2, #facts do
            local before = facts[i]
            if latest.time - before.time > 15 * MINUTE then break end
            if before.kind == "death" then
                add("quickRevenge", { minutes = math.max(1, math.floor((latest.time - before.time) / MINUTE + 0.5)) })
                break
            end
        end
    end
    -- Three deaths or more in half an hour, the latest among them.
    local deaths, first = 0, nil
    for _, e in ipairs(facts) do
        if latest.time - e.time > 30 * MINUTE then break end
        if e.kind == "death" then deaths, first = deaths + 1, e.time end
    end
    if latest.kind == "death" and deaths >= 3 then
        add("camping", { n = deaths, minutes = math.max(1, math.floor((latest.time - first) / MINUTE + 0.5)) })
    end
    if facts[2] and latest.time - facts[2].time >= 14 * DAY then add("returned", { days = math.floor((latest.time - facts[2].time) / DAY) }) end
    local hour = tonumber(GL.Safe(date, "%H", latest.time))
    if hour and hour < 5 then add("night", { hour = hour }) end
    local kills, losses = tonumber(record.pvp and record.pvp.kills) or 0, tonumber(record.pvp and record.pvp.deaths) or 0
    if kills >= 4 and kills >= 3 * math.max(1, losses) then add("domination", { n = kills }) end
    if losses >= 4 and losses >= 3 * math.max(1, kills) then add("nemesis", { n = losses }) end
    local list = {}
    for _, id in ipairs(ORDER) do if found[id] then list[#list + 1] = found[id] end end
    return list
end
-- The line of a sheet: { headline, fact, push, situation }, or a push alone when nothing stands out.
function M.Tell(record, analysis, now)
    local bank = lines()
    local name = record.name or record.fullName or "?"
    local situation = M.Situations(record, now)[1]
    local kills, deaths = analysis and analysis.kills or 0, analysis and analysis.deaths or 0
    local mood = deaths > kills and "behind" or kills > deaths and "lead" or "even"
    local params = situation and situation.params or {}
    params.name, params.debt = name, analysis and analysis.debt or GL.Debt(record)
    if type(params.minutes) == "number" then params.minutes = minutes(params.minutes) end
    params.zone = params.zone ~= "" and params.zone or (analysis and analysis.lastOutcomeZone) or ""
    local key = tostring(record.key) .. ":" .. tostring(situation and situation.at or analysis and analysis.lastOutcomeAt or 0)
    -- A push that needs a zone or a debt the sheet does not have is passed over.
    local pushes = {}
    for _, line in ipairs(bank.push[mood] or {}) do
        local needsZone, needsDebt = line:find("{zone}", 1, true), line:find("{debt}", 1, true)
        if not (needsZone and params.zone == "") and not (needsDebt and (params.debt or 0) <= 0) then pushes[#pushes + 1] = line end
    end
    local result = { push = fill(pick(pushes, key .. ":push"), params), mood = mood, situation = situation }
    if situation then
        -- Without a known zone, the words that name it leave the line.
        local headline = bank.headline[situation.id] or ""
        local facts = {}
        for _, line in ipairs(bank.fact[situation.id] or {}) do
            if params.zone ~= "" or not line:find("{zone}", 1, true) then facts[#facts + 1] = line end
        end
        if params.zone == "" then headline = headline:gsub(" à {zone}", ""):gsub(" in {zone}", "") end
        result.headline = fill(headline, params)
        result.fact = fill(pick(facts, key .. ":" .. situation.id), params)
    end
    return result
end
M.LINES, M.ORDER = LINES, ORDER
