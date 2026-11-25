-- Rivalries told from the journal (owner's brief of 25/11, rules proposed with the kit in
-- art/reference-journal/2026-11-25-rivalites-parchemins, adapted here). It reads, never writes.
-- SPDX-License-Identifier: GPL-3.0-or-later
-- FromRecord filters a COPY of the events, then calls the real GL.Fights and GL.FightTitle.
-- Analyze takes their valid fights, latest first; it never groups events itself. The counts are
-- those of the current book; the debt is GL.Debt's. Every motif rests on recorded facts only,
-- never on a one-to-one duel assumed. A motif carries an id and its numbers: Relations.lua writes
-- the sentence in the player's language. A sheet whose data breaks a rule (an assert) is told as
-- a plain score by Relations.lua, never by stopping the page.
local GL = GrudgeLedger
local M = {}
GL.RivalryRules = M
local DAY = 86400
-- ponytail: 7 jours reprend la fenetre des faits existants; seuil editorial a valider avec le proprietaire.
M.RECENT_DAYS = 7
-- ponytail: 5 parchemins par page est une limite d'affichage, jamais de retention ni de selection.
M.PAGE_SIZE = 5
M.categories = {
    fait_marquant_recent = 1,
    duel_dispute = 2,
    rencontres_recurrentes = 3,
    revanche = 4,
    historique_simple = 5,
}
local kinds = { kill = true, death = true, aggression = true, assist = true }

local function integer(value, label)
    assert(type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value), label)
    return value
end

local function validDate(value, now)
    return type(value) == "number" and value > 0 and value <= now
end

local function recent(at, now)
    return at ~= nil and at >= now - M.RECENT_DAYS * DAY and at <= now
end

local function knownZone(value)
    if type(value) == "string" and value:match("%S") and value ~= "?" then return value end
end

-- Memes preuves STRUCTUREES/historiques que UI.lua:eventTitle, sans relire un titre traduit.
local function deathCause(event)
    if event.evidence == "Le familier de ce joueur vous a porté le coup fatal." then return "pet_killing_blow" end
    if event.killingBlow or event.evidence == "Dégâts létaux explicitement attribués à ce joueur." then return "killing_blow" end
    if event.killingBlow == false or event.evidence == "Participation à l’attaque ayant causé votre mort." then return "contributed" end
    return "unknown"
end

-- context = { fightTitle = GL.FightTitle, dayKey = function(timestamp),
--             unknownDates = 0, futureDates = 0, unconfirmed = 0, excluded = 0 }.
-- dayKey est injecte: utiliser date("%Y-%j", at) du CLIENT; aucun fuseau UTC impose.
-- Les dates inconnues/futures/non confirmees doivent etre signalees meme apres filtrage.
function M.Analyze(record, fights, now, debt, context)
    assert(type(record) == "table" and type(record.key) == "string" and record.key ~= "", "record.key requis")
    assert(type(fights) == "table" and type(context) == "table", "combats et contexte requis")
    assert(type(context.fightTitle) == "function" and type(context.dayKey) == "function", "helpers titre/jour requis")
    assert(validDate(now, math.huge) and now < math.huge, "maintenant invalide")
    local pvp = type(record.pvp) == "table" and record.pvp or {}
    -- Meme fallback que Relations.count: les anciens champs absents/non numeriques valent zero.
    local kills = integer(tonumber(pvp.kills) or 0, "kills invalide")
    local deaths = integer(tonumber(pvp.deaths) or 0, "deaths invalide")
    integer(debt, "dette invalide")
    local state = {
        unknownDates = integer(context.unknownDates or 0, "unknownDates invalide"),
        futureDates = integer(context.futureDates or 0, "futureDates invalide"),
        unconfirmed = integer(context.unconfirmed or 0, "unconfirmed invalide"),
        excluded = integer(context.excluded or 0, "excluded invalide"),
        datedKills = 0,
        datedDeaths = 0,
        datedAggressions = 0,
        datedAssists = 0,
    }
    local result = {
        key = record.key,
        kills = kills,
        deaths = deaths,
        volume = kills + deaths,
        debt = debt,
        eligible = kills + deaths >= 2,
        timeline = {},
        chronology = state,
        motifs = {},
    }
    local days, dayCount, previousStart = {}, 0, math.huge
    for i, fight in ipairs(fights) do
        assert(type(fight) == "table" and type(fight.events) == "table" and #fight.events > 0, "combat sans evenements")
        local entry = { at = fight.at, last = fight.last, kills = 0, deaths = 0, assists = 0, aggressions = 0 }
        entry.zone = knownZone(type(fight.main) == "table" and fight.main.zone)
        assert(validDate(entry.at, now) and validDate(entry.last, now), "date combat non validee")
        assert(entry.at <= entry.last and entry.at <= previousStart, "GL.Fights attendu: recents d'abord")
        previousStart = entry.at
        local previousAt = 0
        for _, event in ipairs(fight.events) do
            assert(type(event) == "table" and kinds[event.kind] and not event.voided and event.voidReason ~= "battleground",
                "evenement non valide: appeler FromRecord")
            assert(validDate(event.time, now) and event.time >= previousAt, "date evenement non validee")
            assert(event.kind == "assist" or event.confidence == "confirmed", "issue/agression non confirmee")
            previousAt = event.time
            if event.kind == "kill" or event.kind == "death" then
                local field = event.kind == "kill" and "kills" or "deaths"
                entry[field] = entry[field] + 1
                if event.kind == "death" then entry.deathCause = entry.deathCause or deathCause(event) end
                entry.lastOutcomeAt = math.max(entry.lastOutcomeAt or 0, event.time)
                local zone = knownZone(event.zone)
                if not result.lastOutcomeAt or event.time > result.lastOutcomeAt then
                    result.lastOutcomeAt, result.lastOutcomeZone = event.time, zone
                    result.lastOutcomeZoneAmbiguous = nil
                elseif event.time == result.lastOutcomeAt and zone ~= result.lastOutcomeZone then
                    result.lastOutcomeZone, result.lastOutcomeZoneAmbiguous = nil, true
                end
                if recent(event.time, now) then
                    local day = context.dayKey(event.time)
                    assert(type(day) == "string" or type(day) == "number", "jour calendaire invalide")
                    if not days[day] then
                        days[day] = true
                        dayCount = dayCount + 1
                    end
                end
            elseif event.kind == "assist" then
                entry.assists = entry.assists + 1
            else
                entry.aggressions = entry.aggressions + 1
            end
        end
        assert(entry.at == fight.events[1].time and entry.last == previousAt, "bornes combat incoherentes")
        assert(entry.kills == fight.kills and entry.deaths == fight.deaths, "compteurs combat incoherents")
        assert(entry.assists == fight.assists and entry.aggressions == fight.aggressions, "composantes combat incoherentes")
        state.datedKills = state.datedKills + entry.kills
        state.datedDeaths = state.datedDeaths + entry.deaths
        state.datedAssists = state.datedAssists + entry.assists
        state.datedAggressions = state.datedAggressions + entry.aggressions
        if entry.deaths > 0 and (entry.kills > 0 or entry.assists > 0) then
            entry.outcome = "mixte"
            entry.mixedKind = entry.kills > 0 and "mort_victoire" or "mort_assistance"
        elseif entry.deaths > 0 then
            entry.outcome = "mort"
        elseif entry.kills > 0 then
            entry.outcome = "victoire"
        elseif entry.assists > 0 then
            entry.outcome = "assistance"
        else
            entry.outcome = "agression"
        end
        -- Conserver exactement le vocabulaire du jeu: groupe, coup fatal, participation, coup de main.
        entry.title = context.fightTitle(fight)
        assert(type(entry.title) == "string", "titre de combat invalide")
        result.timeline[i] = entry
    end
    state.missingKills = math.max(0, kills - state.datedKills)
    state.missingDeaths = math.max(0, deaths - state.datedDeaths)
    state.counterConflict = state.datedKills > kills or state.datedDeaths > deaths
    state.counterMismatch = kills ~= state.datedKills or deaths ~= state.datedDeaths
    if pvp.aggressions ~= nil then
        state.counterMismatch = state.counterMismatch or integer(tonumber(pvp.aggressions) or 0, "aggressions invalide") ~= state.datedAggressions
    end
    if record.assists ~= nil then
        state.counterMismatch = state.counterMismatch or integer(record.assists, "assists invalide") ~= state.datedAssists
    end
    -- Une couverture partielle ne prouve pas OU sont les trous: ne jamais raccorder une serie a travers eux.
    state.complete = not state.counterMismatch and state.unknownDates == 0 and state.futureDates == 0 and state.unconfirmed == 0
    state.status = state.complete and "couverture_des_compteurs" or "chronologie_incomplete"
    result.recent = recent(result.lastOutcomeAt, now)
    result.recentOutcomeDays = dayCount
    local timeline = result.timeline
    local latest = timeline[1]
    local function motif(id, category, params)
        result.motifs[#result.motifs + 1] = { id = id, category = category, params = params or {} }
    end
    -- Toute preuve d'une serie doit etre recente, contigue, d'issue pure et strictement ordonnee en temps.
    -- Une agression seule, assistance, issue mixte ou date egale coupe la sequence, sans filtrage intermediaire.
    local function runFrom(start, outcome)
        local count, newerAt = 0, start > 1 and timeline[start - 1].at or math.huge
        for i = start, #timeline do
            local item = timeline[i]
            if item.outcome ~= outcome or not recent(item.at, now) or item.last >= newerAt then break end
            count = count + 1
            newerAt = item.at
        end
        return count
    end
    if result.recent and latest and recent(latest.at, now) then
        if latest.outcome == "mixte" then
            motif("issue_mixte", "fait_marquant_recent", { at = latest.lastOutcomeAt, kind = latest.mixedKind, fight = 1 })
        elseif state.complete and (latest.outcome == "victoire" or latest.outcome == "mort") then
            local opposite = latest.outcome == "mort" and "victoire" or "mort"
            local preceding = runFrom(2, opposite)
            local run = runFrom(1, latest.outcome)
            if preceding >= 2 then
                local lost = latest.outcome == "mort"
                -- The series had brought the score back to even, and the last fight broke it.
                local equalBefore = lost and latest.deaths == 1 and kills == deaths - 1
                motif(lost and "serie_victoires_interrompue" or "serie_morts_interrompue", "fait_marquant_recent",
                    { count = preceding, at = latest.lastOutcomeAt, firstFight = 1, lastFight = preceding + 1,
                        egaliteAvantDernier = equalBefore or nil })
            elseif run >= 2 then
                local won = latest.outcome == "victoire"
                motif(won and "serie_victoires" or "serie_morts", "fait_marquant_recent",
                    { count = run, at = latest.lastOutcomeAt, firstFight = 1, lastFight = run })
            end
        end
    end
    if result.recent and not state.counterConflict and kills >= 3 and deaths >= 3 and kills < 2 * deaths and deaths < 2 * kills then
        motif("duel_dispute", "duel_dispute", { kills = kills, deaths = deaths, at = result.lastOutcomeAt })
    end
    -- ponytail: trois jours distincts est un seuil editorial, pas une preuve de poursuite ou d'intention.
    if result.recent and dayCount >= 3 then
        motif("rencontres_jours_distincts", "rencontres_recurrentes", { days = dayCount, windowDays = M.RECENT_DAYS, at = result.lastOutcomeAt })
    end
    if result.recent and state.complete and latest and latest.outcome == "victoire" and recent(latest.at, now)
        and runFrom(2, "mort") >= 1 then
        motif("victoire_apres_mort", "revanche", { at = latest.lastOutcomeAt, firstFight = 1, lastFight = 2 })
    end
    if result.recent and not state.counterConflict and kills == 0 and deaths >= 2 then
        motif("premiere_victoire_a_prendre", "revanche", { kills = kills, deaths = deaths, at = result.lastOutcomeAt })
    end
    if not result.lastOutcomeAt then
        motif("aucune_issue_datee", "historique_simple")
    elseif not state.complete then
        motif("historique_incomplet", "historique_simple", { at = result.lastOutcomeAt })
    else
        motif("historique_simple", "historique_simple", { kills = kills, deaths = deaths, at = result.lastOutcomeAt })
    end
    result.narrative = result.motifs[1]
    result.category = result.narrative.category
    result.categoryRank = M.categories[result.category]
    return result
end

function M.FromRecord(record, GL, now)
    assert(type(record) == "table" and type(GL) == "table", "fiche et API GL requises")
    now = now or GL.Now()
    assert(validDate(now, math.huge) and now < math.huge, "maintenant invalide")
    local snapshot = { history = {} }
    local context = { unknownDates = 0, futureDates = 0, unconfirmed = 0, excluded = 0, fightTitle = GL.FightTitle }
    context.dayKey = function(at)
        -- date est l'API du client WoW (injection synthetique dans le check hors jeu).
        assert(type(date) == "function", "API date du client requise")
        return date("%Y-%j", at)
    end
    for _, event in ipairs(record.history or {}) do
        if type(event) == "table" and kinds[event.kind] then
            if event.voided or event.voidReason == "battleground" then
                context.excluded = context.excluded + 1
            elseif not validDate(event.time, now) then
                if type(event.time) == "number" and event.time < math.huge and event.time > now then
                    context.futureDates = context.futureDates + 1
                else
                    context.unknownDates = context.unknownDates + 1
                end
            elseif event.kind ~= "assist" and event.confidence ~= "confirmed" then
                -- Core.pvpFields/RecordPvP exigent confirmed; GL.Fights seul ne verifie pas ce champ.
                -- Choix explicite de la proposition: limiter les preuves narratives aux faits confirmes,
                -- conserver les compteurs et signaler la lacune; ne pas requalifier un ancien fait.
                context.unconfirmed = context.unconfirmed + 1
                snapshot.history[#snapshot.history + 1] = event
            else
                snapshot.history[#snapshot.history + 1] = event
            end
        end
    end
    -- Un fait non confirme peut SEPARER deux combats dans GL.Fights. Le retirer avant groupement
    -- fusionnerait parfois une mort et une victoire. Conserver d'abord les limites natives, puis
    -- retirer les preuves non confirmees a l'interieur de chaque groupe, sans raccord entre groupes.
    local fights = {}
    for _, nativeFight in ipairs(GL.Fights(snapshot)) do
        local confirmed = { history = {} }
        for _, event in ipairs(nativeFight.events) do
            if event.kind == "assist" or event.confidence == "confirmed" then
                confirmed.history[#confirmed.history + 1] = event
            end
        end
        for _, fight in ipairs(GL.Fights(confirmed)) do fights[#fights + 1] = fight end
    end
    return M.Analyze(record, fights, now, GL.Debt(record), context)
end

function M.Rank(candidates)
    assert(type(candidates) == "table", "candidats requis")
    local sorted, keys = {}, {}
    for _, candidate in ipairs(candidates) do
        assert(type(candidate) == "table" and type(candidate.key) == "string", "candidat invalide")
        assert(not keys[candidate.key], "cle de rival dupliquee")
        keys[candidate.key] = true
        if candidate.eligible then sorted[#sorted + 1] = candidate end
    end
    table.sort(sorted, function(a, b)
        if a.categoryRank ~= b.categoryRank then return a.categoryRank < b.categoryRank end
        local at, bt = a.lastOutcomeAt or 0, b.lastOutcomeAt or 0
        if at ~= bt then return at > bt end
        if a.volume ~= b.volume then return a.volume > b.volume end
        return a.key < b.key
    end)
    return sorted
end

function M.Page(sorted, page)
    assert(type(sorted) == "table", "liste triee requise")
    page = page or 1
    integer(page, "page invalide")
    local pages = math.ceil(#sorted / M.PAGE_SIZE)
    page = pages == 0 and 0 or math.max(1, math.min(page, pages))
    local result = { items = {}, page = page, pages = pages, total = #sorted }
    if pages == 0 then return result end
    for i = (page - 1) * M.PAGE_SIZE + 1, math.min(page * M.PAGE_SIZE, #sorted) do
        result.items[#result.items + 1] = sorted[i]
    end
    return result
end

return M
