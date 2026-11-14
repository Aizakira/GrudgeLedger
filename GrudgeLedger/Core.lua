-- Grudge Ledger: shared identities, relationships and persistent history.
-- Identity/saved-variable approach informed by Worth Remembering (Kyle, GPL-3.0).
local ADDON, private = ...
GrudgeLedger = { version = "0.10.5", errors = {}, icon = "Interface\\AddOns\\GrudgeLedger\\Media\\JournalMedallion",
    minimapIcon = "Interface\\AddOns\\GrudgeLedger\\Media\\LedgerBook" }
local GL = GrudgeLedger
local translations = private and private.translations
local function L(source)
    return translations and translations[source] or source
end
GL.L = L
local listeners = {}
local guildSightings = {}
local deletedGuildSightings = {}
local traceLast = {}
local observations, observationCount = {}, 0
local guildStatistics
local journalIndex, journalSorted, personalStatistics
local breakdownStatistics = {}
local socialTotals = setmetatable({}, { __mode = "k" })
local lastInteraction = setmetatable({}, { __mode = "k" })
local openingProofs = setmetatable({}, { __mode = "k" })
local defaults = {
    markers = true, nameColor = false, friendAlerts = true, enemyAlerts = true, indirectAlerts = false,
    sounds = true, alertCooldown = 180, iconSize = 20, pvpTracking = true, zoneTime = false,
    groupTracking = true, socialTracking = true, tradeTracking = false, minimapAngle = 225, readableFont = false,
    quickGestures = true, detectionLog = true, partyWarnings = false, chatBadges = false, compactTooltips = false,
    listSort = "recent", listDetail = "identity", readingScale = 1, compactMode = false, guideSeen = false,
}
local listSorts = { recent = true, name = true, reputation = true, kills = true, deaths = true, encounters = true }
local listDetails = { identity = true, guild = true, pvp = true, notes = true }
local function invalidateJournal()
    journalIndex, journalSorted, personalStatistics, breakdownStatistics = nil, nil, nil, {}
end

function GL.Clean(value, kind)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return nil end
    end
    if value == nil or (kind and type(value) ~= kind) then return nil end
    return value
end

function GL.Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return GL.Clean(a), GL.Clean(b), GL.Clean(c), GL.Clean(d) end
end

function GL.IsPvPInstance()
    local _, kind = GL.Safe(IsInInstance)
    return kind == "pvp" or kind == "arena"
end

function GL.Now() return GL.Safe(GetServerTime) or GL.Safe(time) or 0 end
function GL.Where() return GL.Clean(GL.Safe(GetRealZoneText), "string") or GL.Clean(GL.Safe(GetZoneText), "string") or "?" end
function GL.Print(message)
    local chat = DEFAULT_CHAT_FRAME or ChatFrame1
    if chat then chat:AddMessage("|cffe4bc67[Grudge Ledger]|r " .. tostring(message)) end
end
function GL.Debug(message)
    GL.errors[#GL.errors + 1] = { time = GL.Now(), text = tostring(message) }
    if #GL.errors > 30 then table.remove(GL.errors, 1) end
end
local traceReasons = {
    observed = "Identité reçue", unreadable = "Identité absente ou non lisible", unknown = "Aucun avis connu",
    neutral = "Neutre : pas d'alerte", grouped = "Ami dans le groupe", present = "Ami déjà présent ou visibilité non confirmée",
    disabled = "Alerte désactivée", cooldown = "Délai entre alertes", priority = "Alerte plus prioritaire affichée",
    burst = "Regroupé avec l'alerte de guilde", shown = "Fenêtre affichée", protected = "Marqueur : cadre protégé",
    indirect = "Signal indirect affiché",
}
function GL.Trace(code, identity, unit)
    if not GL.db or not GL.Settings().detectionLog or not traceReasons[code] then return end
    local record = identity and GL.Get(identity)
    local key = record and record.key
    local source = type(unit) == "string" and (unit:match("^nameplate%d+$") and "nameplate"
        or ({ target = "target", mouseover = "mouseover", focus = "focus", say = "parole", yell = "cri", partyTarget = "cible du groupe" })[unit]) or "autre"
    local token = code .. ":" .. (key or "inconnu") .. ":" .. source
    local now = GL.Now()
    if traceLast[token] and now >= traceLast[token] and now - traceLast[token] < 30 then return end
    for k, at in pairs(traceLast) do if now - at >= 30 or now < at then traceLast[k] = nil end end
    traceLast[token] = now
    -- ponytail: bounded local evidence, never a complete world scan or exported personal data.
    GL.db.detectionLog = type(GL.db.detectionLog) == "table" and GL.db.detectionLog or {}
    local log = GL.db.detectionLog
    log[#log + 1] = { time = now, code = code, key = key, source = source }
    while #log > 200 do table.remove(log, 1) end
end
function GL.DetectionReport(private)
    local lines, aliases, count = { L("\nDétections : 200 dernières décisions, répétitions espacées de 30 s.") }, {}, 0
    for _, event in ipairs(GL.db.detectionLog or {}) do
        if traceReasons[event.code] then
            local who = L("identité inconnue")
            if event.key then
                if not aliases[event.key] then count = count + 1 aliases[event.key] = L("joueur #") .. count end
                local record = private and GL.Get(event.key)
                who = record and (record.fullName or record.name):gsub("|", "||") or aliases[event.key]
            end
            lines[#lines + 1] = date("%d/%m %H:%M:%S", event.time) .. " · " .. who .. " · " .. L(event.source) .. " · " .. L(traceReasons[event.code])
        end
    end
    local probe = GL.db.minimapProbe
    lines[#lines + 1] = L("\nRadar minimap : expérimental, non activé.")
    if probe then lines[#lines + 1] = L("Dernier test : ") .. (GL.ProbeResultText and GL.ProbeResultText(probe.result) or L(probe.result)) .. " (build " .. L(probe.build) .. ")"
    else lines[#lines + 1] = L("Aucun résultat de test sauvegardé.") end
    if GL.DruidRadarReport then lines[#lines + 1] = GL.DruidRadarReport() end
    return table.concat(lines, "\n")
end
function GL.ClearDetectionLog() GL.db.detectionLog, traceLast = {}, {} end
function GL.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end
function GL.Emit(event, ...)
    if event == "CHANGED" then invalidateJournal() end
    for _, fn in ipairs(listeners[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then GL.Debug(event .. ": " .. tostring(err)) end
    end
end

-- Lua's %c and %s use the Windows byte locale and can match half an accented letter.
function GL.ContainsControlOrMarkup(value)
    return value:find("[|%z\1-\31\127]") ~= nil or value:find("\194[\128-\159]") ~= nil
end
function GL.ValidLevel(value)
    local n = GL.Clean(value, "number")
    return n and n >= 1 and n <= 1000 and n == math.floor(n) and n or nil
end
local function cleanName(value)
    value = GL.Clean(value, "string")
    if not value or #value > 160 or GL.ContainsControlOrMarkup(value) then return nil end
    value = value:match("^ *(.-) *$")
    return value ~= "" and value or nil
end

local function playerGUID(value)
    local guid = GL.Clean(value, "string")
    return guid and guid:match("^Player%-%w") and #guid <= 128 and guid or nil
end
function GL.IdentityFromName(name, surname, guid)
    name, surname, guid = cleanName(name), cleanName(surname), playerGUID(guid)
    if not name then return nil end
    if not surname then
        local first, last = name:match("^([^ ]+) +(.+)$")
        if last then name, surname = first, last end
    end
    -- ponytail: an unknown surname without a GUID is ambiguous on Forever; wait for a live identity.
    if not guid and not surname then return nil end
    local fullName = name .. (surname and " " .. surname or "")
    local alias = surname and ("name:" .. fullName:lower()) or nil
    local identity = { key = guid and ("guid:" .. guid) or alias, guid = guid, name = name,
        surname = surname, fullName = fullName, alias = alias }
    local seen = guid and guildSightings[guid]
    if seen and GL.Now() - seen.time <= 60 then
        identity.guild, identity.realm, identity.guildSeenAt = seen.guild, seen.realm, seen.time
    end
    return identity
end

function GL.Identity(unit, reuseObservation)
    unit = GL.Clean(unit, "string")
    if not unit or not GL.Safe(UnitExists, unit) or not GL.Safe(UnitIsPlayer, unit) then return nil end
    if GL.Safe(UnitIsUnit, unit, "player") then return nil end
    local guid = GL.Clean(GL.Safe(UnitGUID, unit), "string")
    local mine = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if guid and mine and guid == mine then return nil end
    local now = GL.Clean(GL.Safe(GetTime), "number")
    if now and not (now >= 0 and now < math.huge) then now = nil end
    local cached = guid and observations[guid]
    -- ponytail: polling shares metadata for at most 0.5 s, keyed by live GUID
    -- (unit tokens are recycled). Events/actions read fresh; combat state is never cached.
    if reuseObservation and cached and now and now >= cached.time and now - cached.time < 0.5 then
        return cached.identity
    end
    local name, surname = GL.Safe(UnitName, unit)
    local identity = GL.IdentityFromName(name, surname, guid)
    if not identity then
        if cached then observations[guid], observationCount = nil, observationCount - 1 end
        return nil
    end
    local className, class = GL.Safe(UnitClass, unit)
    identity.class, identity.className = cleanName(class), cleanName(className)
    local raceName, race, raceID = GL.Safe(UnitRace, unit)
    identity.race, identity.raceName = cleanName(race), cleanName(raceName)
    identity.raceID = raceID
    local sex = GL.Safe(UnitSex, unit)
    identity.sex = (sex == 2 or sex == 3) and sex or nil
    identity.faction = GL.Clean(GL.Safe(UnitFactionGroup, unit), "string")
    identity.level = GL.ValidLevel(GL.Safe(UnitLevel, unit))
    if type(GetGuildInfo) == "function" then
        local ok, guild, rank, rankIndex, guildRealm = pcall(GetGuildInfo, unit)
        guild = ok and cleanName(guild) or nil
        if guild then
            identity.guildKnown = true
            identity.guild, identity.guildSeenAt = guild, GL.Now()
            identity.realm = cleanName(guildRealm) or cleanName(GL.Safe(GetRealmName))
            if guid then
                -- ponytail: retain only 256 recent guild observations, for 60 seconds.
                -- This recovers recap-only attackers without adding bystanders to the journal.
                if not guildSightings[guid] then
                    local count, oldest, oldestTime = 0, nil, math.huge
                    for key, seen in pairs(guildSightings) do
                        if identity.guildSeenAt - seen.time > 60 then guildSightings[key] = nil
                        else
                            count = count + 1
                            if seen.time < oldestTime then oldest, oldestTime = key, seen.time end
                        end
                    end
                    if count >= 256 then guildSightings[oldest] = nil end
                end
                guildSightings[guid] = { guild = guild, realm = identity.realm, time = identity.guildSeenAt }
            end
        end
        -- An empty/secret reply is not proof that a known player left their guild.
    end
    if now and identity.guid then
        -- Bounded session cache: a crowded zone cannot retain every passer-by.
        if not observations[guid] then
            if observationCount >= 256 then observations, observationCount = {}, 0 end
            observationCount = observationCount + 1
        end
        observations[guid] = { time = now, identity = identity }
    end
    return identity
end

local function scoreRelation(score)
    return score > 0 and "friend" or score <= -10 and "enemy" or score < 0 and "warning" or "neutral"
end
function GL.AutomaticBalance(record)
    -- Histories remain authoritative and untouched. Replay only new entries;
    -- normalization/merges discard this session-only subtotal before replaying.
    local events = record.history or {}
    local cached = socialTotals[record]
    if not cached or cached.history ~= events or cached.count > #events then
        cached = { history = events, count = 0, total = 0 }
        socialTotals[record] = cached
    end
    local social = cached.total
    for i = cached.count + 1, #events do
        local event = events[i]
        if type(event) == "table" and event.kind == "reputation" and event.source == "emote" then
            local delta = GL.Clean(event.delta, "number")
            if delta and delta == delta and math.abs(delta) < math.huge then social = social + delta end
        end
    end
    cached.total, cached.count = social, #events
    local pvp = record.pvp
    local balance = (pvp.kills or 0)
        - 10 * (pvp.deaths or 0)
        - (pvp.aggressions or 0)
    -- Friendly gestures cannot conceal an unsettled attack; victories repay one
    -- point at a time but cannot by themselves make an opponent a friend.
    local score = balance < 0 and math.min(0, social) + balance
        or social < 0 and math.min(0, social + balance) or social
    return math.max(-100, math.min(100, score)), balance, social
end
local function refreshReputation(record)
    if record.reaction and record.reactionSource ~= "emote" and record.reactionSource ~= "automatic" then return end
    record.reputation = GL.AutomaticBalance(record)
    if record.reactionSource == "emote" or record.reactionSource == "automatic" then record.reaction = scoreRelation(record.reputation) end
end
local interactionKinds = {kill=true, death=true, aggression=true, grouped=true, group=true,
    reaction=true, reputation=true, trade=true, note=true, honor=true, opening=true}
local function interactionTime(value, now)
    return type(value) == "number" and value > 0 and value <= now and value or 0
end
local function rebuildInteraction(record)
    local now = GL.Now()
    local at = interactionTime(record.lastDirectEncounterAt, now)
    for _, e in ipairs(record.history) do
        if type(e) == "table" and interactionKinds[e.kind] and not e.voided and e.voidReason ~= "battleground" then
            at = math.max(at, interactionTime(e.time, now))
        end
    end
    for _, note in ipairs(record.notes) do
        if type(note) == "table" then at = math.max(at, interactionTime(note.time, now), interactionTime(note.updatedAt, now)) end
    end
    lastInteraction[record] = at
end
local function normalize(record)
    openingProofs[record] = nil
    socialTotals[record] = nil
    record.notes = type(record.notes) == "table" and record.notes or {}
    record.history = type(record.history) == "table" and record.history or {}
    local seen = GL.Clean(record.lastEncounterAt, "number")
    record.lastEncounterAt = seen and seen >= 0 and seen < math.huge and seen or nil
    record.lastEncounterZone = record.lastEncounterAt and cleanName(record.lastEncounterZone) or nil
    record.lastEncounterSubzone = record.lastEncounterAt and cleanName(record.lastEncounterSubzone) or nil
    if record.encounters ~= nil then
        local e = type(record.encounters) == "table" and record.encounters or {}
        local function nonnegative(value, fallback)
            return type(value) == "number" and value >= 0 and value < math.huge and math.floor(value) or fallback
        end
        e.count, e.since = nonnegative(e.count, 0), nonnegative(e.since, GL.Now())
        e.seen = type(e.seen) == "table" and e.seen or {}
        for character, at in pairs(e.seen) do
            if type(character) ~= "string" or not nonnegative(at) then
                e.seen[character] = nil
            elseif at > (record.lastEncounterAt or 0) then
                -- Older versions saved the sighting time per character, without a location.
                record.lastEncounterAt, record.lastEncounterZone, record.lastEncounterSubzone = at, nil, nil
            end
        end
        record.encounters = e
    end
    -- Older journals kept the last real sighting, without a separate visit start.
    local visit = interactionTime(record.lastDirectEncounterAt or record.lastEncounterAt, GL.Now())
    record.lastDirectEncounterAt = visit > 0 and visit or nil
    rebuildInteraction(record)
    if record.reaction and not record.reactionSource then
        record.reactionSource = "manual"
        for i = #record.history, 1, -1 do
            local event = record.history[i]
            if type(event) == "table" and event.kind == "reaction" then
                record.reaction, record.reactionSource = event.reaction, event.source == "automatic" and "automatic" or "manual"
                break
            elseif type(event) == "table" and event.kind == "reputation" then
                if event.source == "emote" then record.reactionSource = "emote"
                else
                    local score = GL.Clean(event.reputation, "number")
                    if score then record.reaction = score > 0 and "friend" or score <= -10 and "enemy" or score < 0 and "warning" or "neutral" end
                    record.reactionSource = "manual"
                    break
                end
            end
        end
    end
    if record.reaction == "neutral" and record.reactionSource == "manual" then
        -- Old Neutral buttons erased the displayed score and pinned it at zero.
        -- Restore automatic calculation, but keep a genuine zero reached by +/-.
        local manualScore = false
        for i = #record.history, 1, -1 do
            local event = record.history[i]
            if type(event) == "table" then
                if event.kind == "reaction" then break end
                if event.kind == "reputation" and event.source ~= "emote" then manualScore = true break end
            end
        end
        if not manualScore then record.reactionSource = "automatic" end
    end
    record.pvp = type(record.pvp) == "table" and record.pvp or {}
    for _, field in ipairs({ "kills", "deaths", "aggressions" }) do
        record.pvp[field] = tonumber(record.pvp[field]) or 0
    end
    record.groupCount = tonumber(record.groupCount) or 0
    refreshReputation(record)
    return record
end

function GL.Get(identity)
    if not GL.db then return nil end
    local key = type(identity) == "table" and identity.key or identity
    if type(key) ~= "string" then return nil end
    local record = GL.db.players[key]
    local alias = type(identity) == "table" and identity.alias or key
    if not record and alias and GL.db.aliases[alias] then record = GL.db.players[GL.db.aliases[alias]] end
    if record and type(identity) == "table" and identity.guid and record.guid and identity.guid ~= record.guid then return nil end
    return record
end

local function merge(provisional, record)
    openingProofs[record] = nil
    invalidateJournal()
    guildStatistics, socialTotals[record] = nil, nil
    if (provisional.lastEncounterAt or 0) > (record.lastEncounterAt or 0) then
        record.lastEncounterAt, record.lastEncounterZone, record.lastEncounterSubzone =
            provisional.lastEncounterAt, provisional.lastEncounterZone, provisional.lastEncounterSubzone
    end
    if (provisional.lastDirectEncounterAt or 0) > (record.lastDirectEncounterAt or 0) then record.lastDirectEncounterAt = provisional.lastDirectEncounterAt end
    lastInteraction[record] = math.max(lastInteraction[record] or 0, lastInteraction[provisional] or 0)
    if provisional.encounters then
        record.encounters = record.encounters or { count = 0, seen = {}, since = GL.Now() }
        local a, b = record.encounters, provisional.encounters
        -- ponytail: merge totals and the latest shared encounter; older visits have
        -- no individual IDs. Exact historical overlap would require a visit ledger.
        a.count = a.count + b.count
        a.since = math.min(a.since, b.since)
        for character, seen in pairs(b.seen) do
            if a.seen[character] and math.abs(a.seen[character] - seen) <= 600 then a.count = math.max(1, a.count - 1) end
            a.seen[character] = math.max(a.seen[character] or 0, seen)
        end
    end
    record.level = GL.ValidLevel(record.level) or GL.ValidLevel(provisional.level)
    if provisional.guild and (not record.guild or (provisional.guildSeenAt or 0) > (record.guildSeenAt or 0)) then
        record.guild, record.realm, record.guildSeenAt = provisional.guild, provisional.realm, provisional.guildSeenAt
    end
    for _, field in ipairs({ "class", "race" }) do
        if record[field] == nil and provisional[field] ~= nil then
            record[field], record[field .. "Name"] = provisional[field], provisional[field .. "Name"]
        elseif record[field] == provisional[field] and record[field .. "Name"] == nil then
            record[field .. "Name"] = provisional[field .. "Name"]
        end
    end
    if record.race and record.race == provisional.race then record.raceID = record.raceID or provisional.raceID end
    for _, field in ipairs({ "faction", "sex" }) do
        if record[field] == nil then record[field] = provisional[field] end
    end
    if type(provisional.friendPresence) == "table" then
        record.friendPresence = type(record.friendPresence) == "table" and record.friendPresence or {}
        for character, seen in pairs(provisional.friendPresence) do
            if type(character) == "string" and type(seen) == "number" and seen >= 0 and seen < math.huge then
                local previous = record.friendPresence[character]
                if type(previous) ~= "number" or not (previous >= seen and previous < math.huge) then
                    record.friendPresence[character] = seen
                end
            end
        end
    end
    if type(provisional.partyPresence) == "table" then
        record.partyPresence = type(record.partyPresence) == "table" and record.partyPresence or {}
        for character, visit in pairs(provisional.partyPresence) do
            if type(character) == "string" and type(visit) == "table" then
                local current = type(record.partyPresence[character]) == "table" and record.partyPresence[character] or {}
                for _, field in ipairs({ "seenAt", "attemptAt" }) do
                    local at = GL.Clean(visit[field], "number")
                    if at and at >= 0 and at < math.huge then
                        local previous = GL.Clean(current[field], "number")
                        current[field] = previous and previous >= at and previous < math.huge and previous or at
                    end
                end
                record.partyPresence[character] = current
            end
        end
    end
    for _, note in ipairs(provisional.notes or {}) do table.insert(record.notes, note) end
    local seen = {}
    local fields = {death="deaths", kill="kills", aggression="aggressions"}
    for _, event in ipairs(record.history) do
        if fields[event.kind] and event.eventId then seen[event.eventId] = event end
    end
    for _, event in ipairs(provisional.history or {}) do
        local field = fields[event.kind]
        local existing = field and seen[event.eventId]
        if existing and existing.kind == event.kind then
            if not event.voided then provisional.pvp[field] = math.max(0, provisional.pvp[field] - 1) end
            if event.voided and not existing.voided then
                for key, value in pairs(event) do existing[key] = value end
                record.pvp[field] = math.max(0, record.pvp[field] - 1)
            end
        else
            table.insert(record.history, event)
            if field and event.eventId then seen[event.eventId] = event end
        end
    end
    for _, field in ipairs({ "kills", "deaths", "aggressions" }) do
        record.pvp[field] = record.pvp[field] + (provisional.pvp[field] or 0)
    end
    if not record.reaction or ((record.reactionSource == "emote" or record.reactionSource == "automatic")
        and provisional.reaction and provisional.reactionSource == "manual") then
        record.reaction, record.reactionSource, record.reputation = provisional.reaction, provisional.reactionSource, provisional.reputation
    end
    record.reputation = record.reputation or provisional.reputation
    record.groupCount = record.groupCount + (provisional.groupCount or 0)
    record.firstSeen = math.min(record.firstSeen or GL.Now(), provisional.firstSeen or GL.Now())
    table.sort(record.notes, function(a, b) return (a.time or 0) < (b.time or 0) end)
    table.sort(record.history, function(a, b) return (a.time or 0) < (b.time or 0) end)
    refreshReputation(record)
end

function GL.Remember(identity)
    if not GL.db or type(identity) ~= "table" then return nil end
    local clean = GL.IdentityFromName(identity.name, identity.surname, identity.guid)
    if not clean then return nil end
    if not clean.guid and clean.alias and GL.db.aliases[clean.alias] == false then return nil end
    local record = GL.Get(clean)
    if record and clean.guid and record.key ~= clean.key and not record.guid then
        GL.db.players[record.key] = nil
        record.key = clean.key
        GL.db.players[clean.key] = record
    end
    if not record then
        record = normalize({ key = clean.key, firstSeen = GL.Now() })
        GL.db.players[clean.key] = record
        guildStatistics = nil
    end
    if clean.guid and clean.alias then
        local provisional = GL.db.players[clean.alias]
        if provisional and provisional ~= record and not provisional.guid then
            merge(normalize(provisional), record)
            GL.db.players[clean.alias] = nil
        end
    end
    for _, field in ipairs({ "name", "surname", "guid" }) do
        if clean[field] then record[field] = clean[field] end
    end
    record.fullName = record.name .. (record.surname and " " .. record.surname or "")
    local previousRace = record.race
    for _, field in ipairs({ "class", "race" }) do
        local value = cleanName(identity[field])
        local name = cleanName(identity[field .. "Name"])
        if value and value ~= record[field] then record[field], record[field .. "Name"] = value, nil end
        if name and (not record[field] or value == record[field]) then record[field .. "Name"] = name end
    end
    if previousRace ~= record.race then record.raceID = nil end
    local raceID = GL.Clean(identity.raceID, "number")
    if record.race and record.race == identity.race and raceID and raceID > 0 and raceID < math.huge and raceID == math.floor(raceID) then
        record.raceID = raceID
    end
    record.faction = cleanName(identity.faction) or record.faction
    local sex = GL.Clean(identity.sex, "number")
    if sex == 2 or sex == 3 then record.sex = sex end
    record.level = GL.ValidLevel(identity.level) or GL.ValidLevel(record.level)
    local previousGuild, previousRealm = record.guild, record.realm
    record.realm = cleanName(identity.realm) or record.realm
    local guild = cleanName(identity.guild)
    if guild then
        record.guild, record.guildSeenAt = guild, GL.Clean(identity.guildSeenAt, "number")
            or (identity ~= record and GL.Now() or record.guildSeenAt)
    elseif identity.guildKnown then
        record.guild, record.guildSeenAt = nil, nil
        if record.guid then guildSightings[record.guid] = nil end
    end
    if record.guild ~= previousGuild or record.realm ~= previousRealm then guildStatistics = nil end
    record.lastSeen, record.lastZone = GL.Now(), GL.Where()
    if clean.alias then
        local previous = GL.db.aliases[clean.alias]
        if previous == nil or previous == record.key or previous == clean.alias then
            GL.db.aliases[clean.alias] = record.key
        elseif previous and previous ~= record.key then
            GL.db.aliases[clean.alias] = false -- two GUIDs, same display name: do not guess
        end
    end
    return record
end

function GL.RecordSeen(identity, visible)
    if GL.IsPvPInstance() then return nil end
    local record = GL.Get(identity)
    local rule = GL.GetGuildRule(identity)
    -- A guild rule can recreate a deleted contact while their nameplate is still visible.
    -- Use the journal's ten-minute absence window to treat the next visit as a new encounter.
    local last = identity and deletedGuildSightings[identity.key]
    if last then
        local now = GL.Now()
        if not record and now >= last and now - last <= 600 then
            deletedGuildSightings[identity.key] = now
            return nil
        end
        deletedGuildSightings[identity.key] = nil
    end
    if record or (rule and rule.reaction ~= "neutral") then record = GL.Remember(identity) end
    local me = visible and GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if record and me then
        -- ponytail: one encounter after >10 minutes without a public observation,
        -- not an exact distance/time-spent measurement. No invented historical visits.
        record.encounters = record.encounters or { count = 0, seen = {}, since = GL.Now() }
        local visits, now = record.encounters, GL.Now()
        local previous = visits.seen[me]
        local newVisit = not previous or now - previous > 600
        if newVisit then
            visits.count = visits.count + 1
            record.lastDirectEncounterAt = math.max(record.lastDirectEncounterAt or 0, now)
            lastInteraction[record] = math.max(lastInteraction[record] or 0, now)
        end
        visits.seen[me] = now
        -- Editing a note also calls Remember; only a public observation is a sighting.
        if record.lastEncounterAt ~= now or record.lastEncounterZone ~= record.lastZone then
            record.lastEncounterAt, record.lastEncounterZone = now, record.lastZone
            record.lastEncounterSubzone = cleanName(GL.Safe(GetSubZoneText))
        end
        if newVisit then GL.Emit("CONTACT_SEEN", record) end
    end
    return record
end
local function effectiveRelation(record)
    if not record then return "neutral", "neutral" end
    local opinion = record.reaction == "friend" or record.reaction == "enemy" or record.reaction == "neutral" or record.reaction == "warning"
    if opinion and record.reactionSource ~= "emote" and record.reactionSource ~= "automatic" then return record.reaction, "manual" end
    local pvp = record.pvp or {}
    if (pvp.deaths or 0) > 0 and (record.reputation or 0) < 0 then
        return (record.reputation <= -10 or (pvp.aggressions or 0) > 0) and "enemy" or "warning", "pvp"
    end
    local rule = GL.GetGuildRule(record)
    if rule and rule.reaction == "enemy" then return "enemy", "guild" end
    if (pvp.aggressions or 0) > 0 and (record.reputation or 0) < 0 then return "enemy", "pvp" end
    if opinion and record.reactionSource == "emote" then return record.reaction, "emote" end
    if rule then return rule.reaction, "guild" end
    if opinion then return record.reaction, "automatic" end
    return "neutral", "neutral"
end
function GL.Relation(record) local relation = effectiveRelation(record) return relation end
function GL.RelationSource(record) local _, source = effectiveRelation(record) return source end
function GL.IsGroupOnly(record)
    if not record or (record.groupCount or 0) == 0 or record.reaction or #(record.notes or {}) > 0
        or (record.reputation or 0) ~= 0 or GL.Relation(record) ~= "neutral" then return false end
    for _, count in pairs(record.pvp or {}) do if type(count) == "number" and count > 0 then return false end end
    for _, event in ipairs(record.history or {}) do
        if event.kind ~= "grouped" and event.kind ~= "group" then return false end
    end
    return true
end
function GL.RelationConfidence(record)
    local relation, source = effectiveRelation(record)
    if source ~= "pvp" then return nil end
    return "confirmed"
end
local function currentActor()
    local name, surname = GL.Safe(UnitName, "player")
    local actor = GL.IdentityFromName(name, surname, GL.Safe(UnitGUID, "player"))
    return actor and actor.guid, actor and actor.fullName
end
local function indexOpeningEvidence(proof, entry)
    if type(entry) ~= "table" or entry.voided or entry.voidReason == "battleground"
        or (entry.kind ~= "opening" and (entry.kind ~= "death" or entry.confidence ~= "confirmed"))
        or not playerGUID(entry.actorGUID) or type(entry.time) ~= "number" or not (entry.time > 0 and entry.time < math.huge) then return end
    local actor = proof[entry.actorGUID] or {openings = {}}
    proof[entry.actorGUID] = actor
    if entry.kind == "death" then actor.firstDeath = math.min(actor.firstDeath or entry.time, entry.time)
    elseif type(entry.encounterId) == "string" then actor.openings[entry.encounterId] = entry end
end
local function withLevels(combat, identity, record)
    local player = combat and combat.playerLevel or GL.ValidLevel(GL.Safe(UnitLevel, "player"))
    local opponent = combat and combat.opponentLevel or (identity ~= record and GL.ValidLevel(identity.level))
    if player or opponent then
        combat = combat or {}
        combat.playerLevel, combat.opponentLevel = player, opponent or nil
    end
    return combat
end
local function history(record, kind, extra)
    local entry = extra or {}
    local now, zone = GL.Now(), GL.Where()
    entry.time, entry.kind, entry.zone = entry.time or now, kind, entry.zone or zone
    if not entry.actorGUID then entry.actorGUID, entry.actorName = currentActor() end
    entry.opponentName = record and record.fullName
    -- Snapshot the explicitly tracked quest, never guess which quest the player is doing.
    -- ponytail: absent/protected quest APIs simply omit context; old events are not enriched.
    if entry.time == now and entry.zone == zone then
        entry.subzone = cleanName(GL.Safe(GetSubZoneText))
        if GL.Safe(C_SuperTrack and C_SuperTrack.IsSuperTrackingQuest) == true then
            local id = GL.Clean(GL.Safe(C_SuperTrack.GetSuperTrackedQuestID), "number")
            local index = id and id > 0 and id < math.huge and id == math.floor(id)
                and GL.Clean(GL.Safe(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, id), "number")
            if index and index > 0 then
                entry.questTitle = cleanName(GL.Safe(C_QuestLog and C_QuestLog.GetTitleForQuestID, id))
                if entry.questTitle then entry.questID = id end
            end
        end
    end
    if kind == "kill" or kind == "death" or kind == "aggression" then
        -- Snapshot once: later guild changes must never reassign old PvP events.
        entry.guild, entry.guildRealm, entry.guildObservedAt = record.guild, record.realm, record.guildSeenAt
        entry.guildSource = not record.guild and "unknown" or record.guildSeenAt == entry.time and "observed" or "last-known"
        entry.raceID = record.raceID
        entry.race, entry.raceName, entry.class, entry.className = record.race, record.raceName, record.class, record.className
    end
    if record then
        table.insert(record.history, entry)
        if openingProofs[record] then indexOpeningEvidence(openingProofs[record], entry) end
        lastInteraction[record] = math.max(lastInteraction[record] or 0, interactionTime(entry.time, now))
    else
        GL.db.unassignedHonor = GL.db.unassignedHonor or {}
        table.insert(GL.db.unassignedHonor, entry)
    end
    guildStatistics = nil
    invalidateJournal()
    return entry
end
local reactionScores = { friend = 1, enemy = -10, warning = -1, neutral = 0 }
local function guildIdentity(value, realm)
    local name = type(value) == "table" and value.guild or value
    realm = type(value) == "table" and value.realm or realm
    name, realm = cleanName(name), cleanName(realm) or cleanName(GL.Safe(GetRealmName)) or "Forever"
    if name then return realm:lower() .. ":" .. name:lower(), name, realm end
end
function GL.GetGuildRule(value, realm)
    if not GL.db then return nil end
    local key = guildIdentity(value, realm)
    return key and GL.db.guilds[key] or nil
end
function GL.SetGuildReaction(value, reaction, note, realm)
    if not GL.db or reactionScores[reaction] == nil then return nil end
    local key, name, server = guildIdentity(value, realm)
    if not key then return nil end
    if note ~= nil and (type(note) ~= "string" or #note > 2000) then return nil end
    local rule = GL.db.guilds[key] or { key = key, name = name, realm = server }
    rule.reaction, rule.updatedAt = reaction, GL.Now()
    if note ~= nil then rule.note = note end
    GL.db.guilds[key] = rule
    guildStatistics = nil
    GL.Emit("CHANGED")
    return rule
end

local function buildGuildStatistics()
    local guilds, deaths = {}, {}
    local function get(name, realm)
        local key, clean, server = guildIdentity(name, realm)
        if not key then return end
        if not guilds[key] then
            guilds[key] = { key = key, name = clean, realm = server, members = 0, grudges = 0,
                friends = 0, deaths = 0, kills = 0, aggressions = 0 }
        end
        return guilds[key]
    end
    for _, rule in pairs(GL.db.guilds) do get(rule.name, rule.realm) end
    for _, record in pairs(GL.db.players) do
        local guild = record.guild and not GL.IsGroupOnly(record) and get(record.guild, record.realm)
        if guild then
            guild.members = guild.members + 1
            local relation = GL.Relation(record)
            -- A guild rule must not manufacture personal grudges/friends in its own ranking.
            if GL.RelationSource(record) ~= "guild" then
                if relation == "friend" then guild.friends = guild.friends + 1
                elseif relation == "warning" or relation == "enemy" then guild.grudges = guild.grudges + 1 end
            end
        end
        for _, event in ipairs(record.history or {}) do
            if not event.voided and event.guild then
                local historical = get(event.guild, event.guildRealm)
                local field = event.kind == "death" and event.confidence == "confirmed" and "deaths"
                    or event.confidence == "confirmed" and ({ kill = "kills", aggression = "aggressions" })[event.kind]
                if historical and field then
                    if event.kind == "death" then
                        deaths[historical.key] = deaths[historical.key] or {}
                        local counted, id = deaths[historical.key], event.eventId or event
                        -- One death per guild; confirmed evidence wins over other participants.
                        -- Events without an ID stay separate: timestamps cannot prove a shared death.
                        if counted[id] ~= "deaths" then counted[id] = field end
                    else historical[field] = historical[field] + 1 end
                end
            end
        end
    end
    local result = {}
    for key, guild in pairs(guilds) do
        for _, field in pairs(deaths[key] or {}) do guild[field] = guild[field] + 1 end
        result[#result + 1] = guild
    end
    return result
end

function GL.GuildStatistics()
    -- Only Core mutations invalidate totals; a repaint or a sighting does not
    -- replay the ledger. Return copies so UI sorting/editing cannot alter the cache.
    if not guildStatistics then guildStatistics = buildGuildStatistics() end
    local result = {}
    for i, row in ipairs(guildStatistics) do
        local copy = {}
        for key, value in pairs(row) do copy[key] = value end
        result[i] = copy
    end
    return result
end

function GL.GuildMembers(name, realm)
    local key = guildIdentity(name, realm)
    local members = {}
    if key then
        for _, record in pairs(GL.db.players) do
            if record.guild and guildIdentity(record) == key and not GL.IsGroupOnly(record) then
                members[#members + 1] = record
            end
        end
        table.sort(members, function(a, b)
            if a.fullName ~= b.fullName then return a.fullName < b.fullName end
            return a.key < b.key
        end)
    end
    return members
end

function GL.PlayerStatistics(metric)
    local result = {}
    for _, record in pairs(GL.db.players) do
        local relation, value = GL.Relation(record), 0
        if metric == "reputation" then value = relation == "friend" and math.max(0, record.reputation or 0) or 0
        elseif metric == "grudge" then value = (relation == "enemy" or relation == "warning") and math.max(0, -(record.reputation or 0)) or 0
        elseif metric == "friendsSeen" or metric == "enemiesSeen" then
            local match = metric == "friendsSeen" and relation == "friend"
                or metric == "enemiesSeen" and (relation == "warning" or relation == "enemy")
            value = match and record.encounters and record.encounters.count or 0
            if type(value) == "number" and value < 2 then value = 0 end
        elseif metric == "friendsRecent" or metric == "enemiesRecent" then
            local match = metric == "friendsRecent" and relation == "friend"
                or metric == "enemiesRecent" and (relation == "warning" or relation == "enemy")
            value = match and record.lastEncounterAt or 0
        elseif metric == "friendsGrouped" then value = relation == "friend" and record.groupCount or 0
        elseif metric == "friendsOnline" then
            -- ponytail: total the recorded sessions only when this ranking is open.
            if relation == "friend" then
                for _, entry in ipairs(record.history) do
                    if type(entry) == "table" and entry.kind == "grouped" then value = value + GL.GroupDuration(entry) end
                end
            end
        else value = record.pvp[metric] or 0 end
        if type(value) == "number" and value > 0 and value < math.huge then result[#result + 1] = { record = record, value = value } end
    end
    table.sort(result, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.record.key < b.record.key
    end)
    return result
end
function GL.SetReaction(identity, reaction)
    if reactionScores[reaction] == nil then return nil end
    local record = GL.Remember(identity)
    if not record then return nil end
    local previous, score, source = record.reaction, record.reputation, record.reactionSource
    record.reaction = reaction
    record.reactionSource = reaction == "neutral" and "automatic" or "manual"
    record.reputation = reactionScores[reaction]
    refreshReputation(record)
    if record.reaction ~= previous or record.reputation ~= score or record.reactionSource ~= source then
        history(record, "reaction", { reaction = reaction, source = record.reactionSource })
        GL.Emit("CHANGED", record)
    end
    return record
end
function GL.AdjustReputation(identity, delta, reason, source)
    if source == "emote" and GL.IsPvPInstance() then return nil end
    delta = GL.Clean(delta, "number")
    if not delta or delta ~= delta or math.abs(delta) == math.huge or delta == 0 then return nil end
    delta = math.max(-100, math.min(100, math.floor(delta)))
    local record = GL.Remember(identity)
    if not record then return nil end
    local before = record.reputation or reactionScores[GL.Relation(record)] or 0
    if source == "emote" and (not record.reaction or record.reactionSource == "emote" or record.reactionSource == "automatic") then
        record.reactionSource = "emote"
        history(record, "reputation", { delta = delta, source = "emote", evidence = GL.Clean(reason, "string") })
        refreshReputation(record)
        record.history[#record.history].reputation = record.reputation
        GL.Emit("CHANGED", record)
        return record
    end
    record.reputation = math.max(-100, math.min(100, before + delta))
    local score = record.reputation
    if source ~= "emote" or not record.reaction or record.reactionSource ~= "manual" then
        record.reaction = score > 0 and "friend" or score <= -10 and "enemy" or score < 0 and "warning" or "neutral"
        record.reactionSource = source == "emote" and "emote" or "manual"
    end
    history(record, "reputation", { delta = score - before, reputation = score,
        evidence = GL.Clean(reason, "string"), source = GL.Clean(source, "string") or "manual" })
    GL.Emit("CHANGED", record)
    return record
end
local function noteText(text)
    text = GL.Clean(text, "string")
    if not text or not text:find("%S") then return nil, L("La note est vide.") end
    if #text > 2000 then return nil, L("La note est trop longue (2000 octets maximum).") end
    return text
end
function GL.AddNote(identity, text)
    local err
    text, err = noteText(text)
    if not text then return false, err end
    local record = GL.Remember(identity)
    if not record then return false, L("Identité du joueur indisponible.") end
    local actorGUID, actorName = currentActor()
    table.insert(record.notes, { time = GL.Now(), text = text, actorGUID = actorGUID, actorName = actorName })
    lastInteraction[record] = math.max(lastInteraction[record] or 0, record.notes[#record.notes].time)
    guildStatistics = nil -- a note makes a formerly group-only record personal
    GL.Emit("CHANGED", record)
    return true
end
local function findNote(identity, note)
    local record = GL.Get(identity)
    if record and type(note) == "table" then
        for index, entry in ipairs(record.notes) do if entry == note then return record, index end end
    end
end
function GL.UpdateNote(identity, note, text)
    local record = findNote(identity, note)
    if not record then return false, L("Cette note n'appartient plus à cette fiche.") end
    local value, err = noteText(text)
    if not value then return false, err end
    if note.text ~= value then
        note.text, note.updatedAt = value, GL.Now()
        lastInteraction[record] = math.max(lastInteraction[record] or 0, note.updatedAt)
        GL.Emit("CHANGED", record)
    end
    return true
end
function GL.DeleteNote(identity, note)
    local record, index = findNote(identity, note)
    if not record then return false, L("Cette note n'appartient plus à cette fiche.") end
    table.remove(record.notes, index)
    rebuildInteraction(record)
    guildStatistics = nil
    GL.Emit("CHANGED", record)
    return true
end
function GL.DeleteProfile(record)
    if not GL.db or type(record) ~= "table" or GL.db.players[record.key] ~= record then return false end
    local key = record.key
    GL.db.players[key] = nil
    local rule = GL.GetGuildRule(record)
    if rule and rule.reaction ~= "neutral" then deletedGuildSightings[key] = GL.Now() end
    for alias, owner in pairs(GL.db.aliases) do
        if owner == key then GL.db.aliases[alias] = nil end
    end
    local log = GL.db.detectionLog
    if type(log) == "table" then
        for i = #log, 1, -1 do
            if type(log[i]) == "table" and log[i].key == key then table.remove(log, i) end
        end
    end
    guildStatistics = nil
    GL.Emit("CHANGED", record, "deleted")
    return true
end
local pvpFields = {
    kill = { confirmed = "kills" },
    death = { confirmed = "deaths" },
    aggression = { confirmed = "aggressions" },
}
function GL.HonorPoints(event)
    local n = type(event) == "table" and event.kind == "honor" and GL.Clean(event.honor, "number")
    if n and n >= 0 and n <= 2147483647 and n == math.floor(n) then return n end
end
function GL.RecordHonor(identity, points)
    local inside, instance = GL.Safe(IsInInstance)
    if inside ~= false or instance ~= "none" or not GL.db or not GL.Settings().pvpTracking then return end
    local entry = {kind = "honor", honor = points}
    if not GL.HonorPoints(entry) then return end
    entry.actorGUID, entry.actorName = currentActor()
    if not entry.actorGUID or identity and (type(identity) ~= "table" or GL.Clean(identity.guid, "string") == entry.actorGUID) then return end
    local record = identity and GL.Remember(identity)
    history(record, "honor", entry)
    GL.Emit("CHANGED", record, "honor")
    return entry
end
local function sumHonor(stats, points)
    stats.honor = stats.honor + points
    stats.honorAwards = stats.honorAwards + 1
    stats.bestHonor = math.max(stats.bestHonor, points)
end
-- Read each contact's evidence once across summary rows. A corrected death
-- invalidates the index, including for victories in a later reporting period.
local function openingProof(record)
    if openingProofs[record] then return openingProofs[record] end
    local proof = {}
    for _, entry in ipairs(record.history or {}) do indexOpeningEvidence(proof, entry) end
    openingProofs[record] = proof
    return proof
end
function GL.RecordOpening(identity, opener, hadGrudge, encounterId)
    local inside, instance = GL.Safe(IsInInstance)
    if inside ~= false or instance ~= "none" or not GL.db or not GL.Settings().pvpTracking
        or (opener ~= "player" and opener ~= "opponent") or type(hadGrudge) ~= "boolean"
        or not cleanName(encounterId) or type(identity) ~= "table" then return end
    local actor, name = currentActor()
    if not actor or not playerGUID(identity.guid) or identity.guid == actor then return end
    local record = GL.Remember(identity)
    if not record then return end
    local previous = openingProof(record)[actor]
    if previous and previous.openings[encounterId] then return previous.openings[encounterId] end
    local at = GL.Now()
    local event = history(record, "opening", {actorGUID=actor, actorName=name, time=at, opener=opener, combat=withLevels(nil, identity, record),
        hadGrudge=hadGrudge, encounterId=encounterId, priorDeath=previous and previous.firstDeath and previous.firstDeath < at or false})
    GL.Emit("CHANGED", record, "opening")
    return event
end
function GL.KillOpeningCategory(record, event)
    if type(event) ~= "table" or event.kind ~= "kill" or event.confidence ~= "confirmed" or event.voided or event.voidReason == "battleground" then return end
    local context = event.combat
    local actor = record and type(context) == "table" and openingProof(record)[event.actorGUID]
    local opening = actor and actor.openings[context.encounterId]
    if not opening or context.opener ~= opening.opener or type(event.time) ~= "number"
        or not (event.time >= opening.time and event.time < math.huge) then return "unknownOpeningKills" end
    if opening.opener == "opponent" then return "responseKills" end
    if opening.opener ~= "player" then return "unknownOpeningKills" end
    if opening.priorDeath == true and actor.firstDeath and actor.firstDeath < opening.time then return "revengeKills" end
    if opening.hadGrudge == true then return "initiatedKillsGrudge" end
    if opening.hadGrudge == false then return "initiatedKillsNoGrudge" end
    return "unknownOpeningKills"
end
local function combatContext(value)
    if not GL.Clean(value, "table") then return end
    local function integer(field, low, high)
        local n = GL.Clean(value[field], "number")
        if n and n >= low and n <= high and n == math.floor(n) then return n end
    end
    local snapshot = {
        healthPct = integer("healthPct", 0, 100), playerLevel = integer("playerLevel", 1, 1000),
        opponentLevel = integer("opponentLevel", 1, 1000), opponents = integer("opponents", 1, 10000),
        pve = GL.Clean(value.pve, "boolean") or nil, pet = GL.Clean(value.pet, "boolean") or nil,
    }
    if (value.opener == "player" or value.opener == "opponent") and cleanName(value.encounterId) then
        snapshot.opener, snapshot.encounterId = value.opener, value.encounterId
        snapshot.priorDeath, snapshot.hadGrudge = GL.Clean(value.priorDeath, "boolean"), GL.Clean(value.hadGrudge, "boolean")
    end
    if next(snapshot) then return snapshot end
end
function GL.RecordPvP(identity, kind, confidence, evidence, eventId, combat)
    if GL.IsPvPInstance() then return nil end
    if kind ~= "kill" and kind ~= "death" then return nil end
    if confidence ~= "confirmed" then return nil end
    local record = GL.Remember(identity)
    if not record then return nil end
    if eventId then
        for _, event in ipairs(record.history) do if event.eventId == eventId then return nil end end
    end
    local field = pvpFields[kind][confidence]
    record.pvp[field] = record.pvp[field] + 1
    refreshReputation(record)
    local event = history(record, kind, { confidence = confidence, evidence = evidence, eventId = eventId, combat = withLevels(combatContext(combat), identity, record) })
    GL.Emit("CHANGED", record)
    return record, event
end
function GL.RecordAggression(identity, confidence, evidence, eventId, combat)
    if GL.IsPvPInstance() then return nil end
    if confidence ~= "confirmed" then return nil end
    local record = GL.Remember(identity)
    if not record then return nil end
    if eventId then
        for _, event in ipairs(record.history) do if event.eventId == eventId then return nil end end
    end
    local field = pvpFields.aggression[confidence]
    record.pvp[field] = record.pvp[field] + 1
    refreshReputation(record)
    history(record, "aggression", { confidence = confidence, evidence = evidence, eventId = eventId, combat = withLevels(combatContext(combat), identity, record) })
    GL.Emit("CHANGED", record)
    return record
end
local function hasEvent(record, event)
    for _, entry in ipairs(record.history) do if entry == event then return true end end
end


function GL.VoidPvP(identity, event, silent, reason)
    local record = GL.Get(identity)
    if not record or type(event) ~= "table" or event.voided then return false, L("Événement indisponible ou déjà annulé.") end
    local fields = pvpFields[event.kind]
    local field = fields and fields[event.confidence]
    if not field then return false, L("Seul un événement PvP peut être corrigé ici.") end
    if not hasEvent(record, event) then return false, L("Cet événement n'appartient pas à cette fiche.") end
    -- Keep the original evidence and eventId: repeated observations must not resurrect it.
    event.voided, event.voidedAt = true, GL.Now()
    if event.kind == "death" then openingProofs[record] = nil end
    if event.time == lastInteraction[record] then rebuildInteraction(record) end
    if reason then event.voidReason = reason
    else event.voidedByGUID, event.voidedByName = currentActor() end
    guildStatistics = nil
    invalidateJournal()
    record.pvp[field] = math.max(0, (record.pvp[field] or 0) - 1)
    refreshReputation(record)
    if not silent then GL.Emit("CHANGED", record) end
    return true
end
local function cleanBattlegroundHistory()
    if GL.db.battlegroundCleanupVersion == 1 then return end
    if GL.db.battlegroundArchive ~= nil and type(GL.db.battlegroundArchive) ~= "table" then
        GL.Debug(L("Archive de champs de bataille invalide : nettoyage reporté."))
        return
    end
    -- ponytail: old events have zone text, not instance IDs. Match only exact known
    -- FR/EN battleground names; unknown zones stay intact until evidence is available.
    local zones = { ["Bassin Arathi"] = true, ["Arathi Basin"] = true,
        ["Goulet des Chanteguerres"] = true, ["Warsong Gulch"] = true,
        ["Vallée d'Alterac"] = true, ["Alterac Valley"] = true }
    local archived, events, count = {}, 0, 0
    for key, record in pairs(GL.db.players) do
        local onlyBattlegrounds = #record.history > 0 and #record.notes == 0 and record.groupCount == 0
            and (not record.reaction or record.reactionSource == "automatic")
        for _, event in ipairs(record.history) do
            local fields = type(event) == "table" and pvpFields[event.kind]
            if fields and fields[event.confidence] and zones[event.zone] then
                -- READY refreshes consumers once; CHANGED here could observe players
                -- and mutate the database while it is still being migrated.
                if GL.VoidPvP(record, event, true) then
                    event.voidReason = "battleground"
                    events = events + 1
                end
            else onlyBattlegrounds = false end
        end
        -- Unexplained counters may describe older outdoor events: retain the record.
        for _, value in pairs(record.pvp) do if value ~= 0 then onlyBattlegrounds = false end end
        if onlyBattlegrounds and record.reputation == 0 then archived[key] = record end
    end
    for key, record in pairs(archived) do
        GL.db.battlegroundArchive = GL.db.battlegroundArchive or {}
        table.insert(GL.db.battlegroundArchive, record)
        GL.db.players[key] = nil
        count = count + 1
    end
    for alias, key in pairs(GL.db.aliases) do
        if archived[key] then GL.db.aliases[alias] = nil end
    end
    GL.db.battlegroundCleanupVersion = 1
    if events > 0 or count > 0 then
        GL.Print(L("Champs de bataille : ") .. events .. L(" événement(s) écarté(s), ") .. count
            .. L(" fiche(s) archivée(s). Notes et avis personnels conservés."))
    end
end
function GL.RecordGroup(identity, sessionId, zone)
    -- Group membership is history for an existing opinion, not an automatic introduction.
    local record = GL.RecordSeen(identity)
    if not record then return nil end
    for _, event in ipairs(record.history) do
        if event.kind == "grouped" and event.sessionId == sessionId then return nil end
    end
    record.groupCount = record.groupCount + 1
    history(record, "grouped", { sessionId = sessionId, zone = zone })
    GL.Emit("CHANGED", record)
    return record
end

function GL.RecordTrade(identity, summary)
    if not GL.Settings().tradeTracking or GL.IsPvPInstance() then return end
    local record = GL.Get(identity)
    if not record or GL.IsGroupOnly(record) then return end
    summary = GL.Clean(summary, "string")
    if not summary or #summary > 4096 then return end
    history(record, "trade", { evidence = summary })
    GL.Emit("CHANGED", record)
end

-- Normalize only search text. Display names, stored identity keys and notes keep their spelling.
local searchLetters = {}
for letter, variants in pairs({
    a="ÀÁÂÃÄÅàáâãäå", ae="Ææ", c="Çç", e="ÈÉÊËèéêë", i="ÌÍÎÏìíîï",
    n="Ññ", o="ÒÓÔÕÖòóôõö", oe="Œœ", u="ÙÚÛÜùúûü", y="ÝŸýÿ",
    [""]="̧̀́̂̃̈",
}) do
    for character in variants:gmatch("[\194-\244][\128-\191]+") do searchLetters[character] = letter end
end
local function searchText(text)
    return (text:gsub("[A-Z]+", string.lower):gsub("[\194-\244][\128-\191]+", searchLetters))
end
local function queryWords(query)
    local words = {}
    query = GL.Clean(query, "string") or ""
    for word in searchText(query:sub(1, 512)):gmatch("[^ \t\r\n\f\v]+") do words[#words + 1] = word end
    return words
end
local function matchesWords(text, words)
    text = searchText(text)
    for _, word in ipairs(words) do if not text:find(word, 1, true) then return false end end
    return true
end
local historySearchFields = { "opponentName", "zone", "subzone", "guild", "questTitle", "evidence" }
local searchRelations = {friend=L("Ami"), enemy=L("Ennemi"), warning=L("Méfiance"), neutral=L("Neutre")}
local searchKinds = {kill=L("Victoire"), death=L("Mort"), aggression=L("Agression"), honor=L("Honneur"), trade=L("Échange terminé"),
    opening=L("Initiative"), grouped=L("Vous avez partagé un groupe"), group=L("Vous avez partagé un groupe"), note=L("Note personnelle"),
    reputation=L("Avis personnel")}
local function addEventText(parts, event)
    for _, field in ipairs(historySearchFields) do
        if type(event[field]) == "string" then parts[#parts + 1] = event[field] end
    end
    parts[#parts + 1] = searchKinds[event.kind]
    if event.reaction then parts[#parts + 1] = searchRelations[event.reaction] end
    if event.evidence and GL.LocalizeEvidence then
        local display = GL.LocalizeEvidence(event)
        if display ~= event.evidence then parts[#parts + 1] = display end
    end
end
local function recordText(record, notes, past)
    local parts = {}
    for _, field in ipairs({ "fullName", "name", "surname", "guild", "class", "className", "race", "raceName", "lastZone", "lastEncounterZone", "lastEncounterSubzone", "faction" }) do
        if type(record[field]) == "string" then parts[#parts + 1] = record[field] end
    end
    parts[#parts + 1] = searchRelations[GL.Relation(record)]
    if GL.IdentityLabels then
        local faction, race, class = GL.IdentityLabels(record)
        parts[#parts + 1] = faction
        parts[#parts + 1] = race
        parts[#parts + 1] = class
    elseif record.faction then parts[#parts + 1] = L(record.faction) end
    if past then
        for _, event in ipairs(record.history or {}) do
            if type(event) == "table" then addEventText(parts, event) end
        end
    end
    if notes then
        for _, note in ipairs(record.notes or {}) do
            if type(note) == "table" and type(note.text) == "string" then parts[#parts + 1] = note.text end
        end
    end
    return table.concat(parts, "\n")
end
function GL.SearchPlayers(options)
    options = type(options) == "table" and options or {}
    local result, words = {}, queryWords(options.query)
    for _, record in pairs(GL.db and GL.db.players or {}) do
        local faction = record.faction or "unknown"
        if (not GL.IsGroupOnly(record) or record.key == options.selectedKey)
            and (not options.relation or options.relation == "all" or GL.Relation(record) == options.relation)
            and (not options.faction or options.faction == "all" or faction == options.faction)
            and (not options.notesOnly or #record.notes > 0)
            and (#words == 0 or matchesWords(recordText(record, true, true), words)) then result[#result + 1] = record end
    end
    local sort = listSorts[options.sort] and options.sort or "recent"
    local function value(record)
        if sort == "name" then return (record.fullName or record.name or record.key):lower() end
        if sort == "reputation" then return record.reputation or 0 end
        if sort == "kills" or sort == "deaths" then return record.pvp[sort] or 0 end
        if sort == "encounters" then return record.encounters and record.encounters.count or 0 end
        return lastInteraction[record] or 0
    end
    table.sort(result, function(a, b)
        local av, bv = value(a), value(b)
        if av ~= bv then if sort == "name" then return av < bv end return av > bv end
        return a.key < b.key
    end)
    return result
end

local function eventTime(event)
    local at = GL.Clean(event.time, "number")
    return at and at >= 0 and at < math.huge and at or 0
end
local function eventActor(event)
    return playerGUID(event.actorGUID)
end
local function indexedJournal()
    if journalIndex then return journalIndex end
    local rows = {}
    for _, record in pairs(GL.db and GL.db.players or {}) do
        for index, event in ipairs(record.history or {}) do
            if type(event) == "table" and (event.kind ~= "honor" or GL.HonorPoints(event)) then
                rows[#rows + 1] = { record = record, event = event, at = eventTime(event), actor = eventActor(event), sequence = index }
            end
        end
        for index, note in ipairs(record.notes or {}) do
            if type(note) == "table" and type(note.text) == "string" then
                rows[#rows + 1] = { record = record, at = eventTime(note), actor = eventActor(note), sequence = #record.history + index, event = {
                    kind = "note", time = note.time, text = note.text, updatedAt = note.updatedAt,
                    actorGUID = note.actorGUID, actorName = note.actorName, note = note,
                } }
            end
        end
    end
    for index, event in ipairs(GL.db and GL.db.unassignedHonor or {}) do
        if type(event) == "table" and GL.HonorPoints(event) then
            rows[#rows + 1] = {event = event, at = eventTime(event), actor = eventActor(event), sequence = index}
        end
    end
    -- ponytail: one session-only index, built on demand and invalidated on writes.
    -- The history stays authoritative; no timer or persisted duplicate event log.
    journalIndex = rows
    return rows
end
local function inScope(author, scope, actor)
    return scope == "all" or scope == "legacy" and not author or scope == "character" and actor and author == actor
end
local function periodFilter(options)
    local now = GL.Now()
    local period = options.period or "all"
    local year = tonumber(options.year)
    if not year or year % 1 ~= 0 or year < 1970 or year > 9999 then year = tonumber(GL.Safe(date, "%Y", now)) end
    local span = period == "week" and 7 * 86400 or period == "month" and 30 * 86400
    return function(event, at)
        at = at or eventTime(event)
        if at > now then return false end
        if span then return at >= now - span and at <= now end
        if period == "year" then return at > 0 and year and tonumber(GL.Safe(date, "%Y", at)) == year end
        return true
    end, tostring(period) .. ":" .. tostring(year) .. ":" .. (span and tostring(now) or "")
end
function GL.JournalYears()
    local years, present = {}, {}
    local current = tonumber(GL.Safe(date, "%Y", GL.Now()))
    if current then present[current] = true end
    local now = GL.Now()
    for _, row in ipairs(indexedJournal()) do
        if row.at > 0 and row.at <= now then
            local year = tonumber(GL.Safe(date, "%Y", row.at))
            if year then present[year] = true end
        end
    end
    for _, entry in pairs(type(GL.db.zoneExposure) == "table" and GL.db.zoneExposure or {}) do
        if type(entry) == "table" and type(entry.years) == "table" then
            for key in pairs(entry.years) do
                local year = tonumber(key)
                if year and current and year >= 1970 and year <= current then present[year] = true end
            end
        end
    end
    for year in pairs(present) do years[#years + 1] = year end
    table.sort(years, function(a, b) return a > b end)
    return years
end
function GL.JournalEvents(options)
    options = type(options) == "table" and options or {}
    local result, words, texts = {}, queryWords(options.query), {}
    local within = periodFilter(options)
    local actor, scope, kind = currentActor(), options.scope or "all", options.kind or "all"
    local rows = indexedJournal()
    if not journalSorted then
        table.sort(rows, function(a, b)
            if a.at ~= b.at then return a.at > b.at end
            local aKey, bKey = a.record and a.record.key or "", b.record and b.record.key or ""
            if aKey ~= bKey then return aKey < bKey end
            return a.sequence > b.sequence
        end)
        journalSorted = true
    end
    for _, row in ipairs(rows) do
        local event, record = row.event, row.record
        local category = (pvpFields[event.kind] or event.kind == "honor" or event.kind == "opening") and "pvp" or event.kind == "note" and "notes" or event.kind == "trade" and "trade" or "social"
        if not GL.IsGroupOnly(record) and within(event, row.at) and inScope(row.actor, scope, actor)
            and (kind == "all" or kind == category or kind == event.kind) then
            local match = true
            if #words > 0 then
                if record and not texts[record] then texts[record] = recordText(record) end
                local parts = { texts[record] }
                if type(event.text) == "string" then parts[#parts + 1] = event.text end
                addEventText(parts, event)
                match = matchesWords(table.concat(parts, "\n"), words)
            end
            if match then result[#result + 1] = { record = record, event = event } end
        end
    end
    return result
end

local function pvpEventKey(row, byOpponent)
    local event = row.event
    -- IDs link participants in one death. Without an ID we must count entries
    -- separately: matching timestamps do not prove that two reports are one death.
    if type(event.eventId) ~= "string" or event.eventId == "" then return event end
    return (row.actor or "legacy") .. "\031" .. event.kind .. "\031"
        .. ((byOpponent or event.kind ~= "death") and row.record.key or "") .. "\031" .. event.eventId
end
function GL.ContactMatchup(record, withHistory)
    local actor, now = currentActor(), GL.Now()
    local result = { kills = 0, deaths = 0, honor = 0, honorAwards = 0, bestHonor = 0,
        run = 0, recent = {}, indices = withHistory and {} or nil }
    if not actor or not record then return result end
    -- ponytail: only the open contact is read. Rebuild on demand so corrections and
    -- merged identities take effect without maintaining a second combat ledger.
    local entries, seen = {}, {}
    for i, event in ipairs(record.history or {}) do
        if type(event) == "table" and (GL.HonorPoints(event) or (event.kind == "kill" or event.kind == "death")
            and pvpFields[event.kind][event.confidence]) and not event.voided and event.voidReason ~= "battleground"
            and eventActor(event) == actor then
            local at = eventTime(event)
            local key = pvpEventKey({ record = record, actor = actor, event = event }, true)
            if at <= now then
                local row = seen[key]
                if not row then
                    row = { at = at, index = i, event = event }
                    seen[key], entries[#entries + 1] = row, row

                end
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.index < b.index
    end)
    local previous
    for i, row in ipairs(entries) do
        local kind, confidence = row.event.kind, row.event.confidence
        if kind == "honor" then
            sumHonor(result, row.event.honor)
        else
            local field = pvpFields[kind][confidence]
            result[field] = result[field] + 1
        end
        if withHistory then result.indices[#entries - i + 1] = row.index end
        if kind ~= "honor" and row.at > 0 and confidence == "confirmed" then
            result.run = result.lastKind == kind and result.run + 1 or 1
            result.lastKind = kind
            if previous and previous.event.kind == "death" and row.at > previous.at then
                if kind == "kill" then result.comeback = row.event
                elseif row.at - previous.at <= 180 then result.closeDeaths = row.event end
            end
            previous = row
        end
    end
    for i = #entries, 1, -1 do
        local row = entries[i]
        if row.event.kind ~= "honor" and row.at > 0 and row.event.confidence == "confirmed" then
            result.recent[#result.recent + 1] = row.event
            if #result.recent == 5 then break end
        end
    end
    return result
end
local function statisticsCopy(stats)
    local result = {}
    for key, value in pairs(stats) do
        if key == "topDeaths" then
            result[key] = {}
            for i, row in ipairs(value) do result[key][i] = { record = row.record, value = row.value } end
        elseif key == "mostKilled" or key == "mostDeaths" then result[key] = { record = value.record, value = value.value }
        else result[key] = value end
    end
    return result
end
function GL.PersonalStatistics(options)
    options = type(options) == "table" and options or {}
    local within, periodKey = periodFilter(options)
    local actor, actorName = currentActor()
    local scope = options.scope or "character"
    local key = periodKey .. ":" .. scope .. ":" .. (actor or "unknown")
    local now, nextAt = GL.Now()
    if personalStatistics and personalStatistics.key == key and now >= personalStatistics.at
        and (not personalStatistics.nextAt or now < personalStatistics.nextAt) then return statisticsCopy(personalStatistics.value) end
    local stats = { kills = 0, deaths = 0,
        honor = 0, honorAwards = 0, bestHonor = 0, unassignedHonor = 0,
        victims = 0, attackers = 0, initiated = 0, responded = 0, revengeKills = 0,
        initiatedKillsNoGrudge = 0, initiatedKillsGrudge = 0, responseKills = 0, unknownOpeningKills = 0,
        aggressions = 0, events = 0, unknownActorEvents = 0,
        unlinkedEvents = 0, currentActor = actor, actorName = actorName, scope = scope, topDeaths = {} }
    local counted, unknown, ranked, rankings = {}, {}, {}, { kill = {}, death = {} }
    local attackers, openings = {}, {}
    for _, row in ipairs(indexedJournal()) do
        local event, record = row.event, row.record
        local fields = pvpFields[event.kind]
        local at = row.at
        if (fields or event.kind == "honor" or event.kind == "opening") and not event.voided and at > now and (not nextAt or at < nextAt) then nextAt = at end
        if event.kind == "opening" and not event.voided and event.voidReason ~= "battleground" and within(event, at) and inScope(row.actor, scope, actor)
            and row.actor and type(event.encounterId) == "string" and (event.opener == "player" or event.opener == "opponent") then
            local key = row.actor .. "\031" .. record.key .. "\031" .. event.encounterId
            if not openings[key] then
                openings[key] = true
                local field = event.opener == "player" and "initiated" or "responded"
                stats[field] = stats[field] + 1
                if event.opener == "opponent" then attackers[record.key] = true end
            end
        elseif event.kind == "honor" and not event.voided and event.voidReason ~= "battleground" and within(event, at) and inScope(row.actor, scope, actor) then
            sumHonor(stats, event.honor)
            if not record then stats.unassignedHonor = stats.unassignedHonor + event.honor end
        elseif fields and not event.voided and event.voidReason ~= "battleground" and fields[event.confidence] and within(event, at) then
            local id = pvpEventKey(row)
            if not row.actor and not unknown[id] then
                unknown[id], stats.unknownActorEvents = true, stats.unknownActorEvents + 1
            end
            if inScope(row.actor, scope, actor) then
                if event.confidence == "confirmed" and (event.kind == "aggression" or event.kind == "death") then attackers[record.key] = true end
                counted[id] = counted[id] or row
                if not stats.firstAt or at < stats.firstAt then stats.firstAt = at end
                if not stats.lastAt or at > stats.lastAt then stats.lastAt = at end
                if event.confidence == "confirmed" and rankings[event.kind] then
                    local rankID = pvpEventKey(row, true)
                    if not ranked[rankID] then
                        ranked[rankID] = true
                        local rank = rankings[event.kind][record.key] or { record = record, value = 0 }
                        rank.value = rank.value + 1
                        rankings[event.kind][record.key] = rank
                    end
                end
            end
        end
    end
    for _ in pairs(attackers) do stats.attackers = stats.attackers + 1 end
    for _ in pairs(rankings.kill) do stats.victims = stats.victims + 1 end
    for id, row in pairs(counted) do
        local event = row.event
        local field = pvpFields[event.kind][event.confidence]
        stats[field], stats.events = stats[field] + 1, stats.events + 1
        if field == "kills" then
            local category = GL.KillOpeningCategory(row.record, event)
            stats[category] = stats[category] + 1
        end
        if type(id) == "table" then stats.unlinkedEvents = stats.unlinkedEvents + 1 end
    end
    for kind, records in pairs(rankings) do
        local field = kind == "kill" and "mostKilled" or "mostDeaths"
        for _, row in pairs(records) do
            local best = stats[field]
            if not best or row.value > best.value or row.value == best.value and row.record.key < best.record.key then stats[field] = row end
            if kind == "death" then
                -- Keep only the three displayed opponents, after deduplication and period filtering.
                for i = 1, 3 do
                    local other = stats.topDeaths[i]
                    if not other or row.value > other.value or row.value == other.value and row.record.key < other.record.key then
                        table.insert(stats.topDeaths, i, row)
                        stats.topDeaths[4] = nil
                        break
                    end
                end
            end
        end
    end
    -- One bounded result cache; changing a filter replaces it. Rolling windows
    -- expire each server second, so events at the boundary never linger in totals.
    personalStatistics = { key = key, value = stats, at = now, nextAt = nextAt }
    return statisticsCopy(stats)
end
function GL.PvPBreakdown(options, dimension)
    local subzones = dimension == "subzone"
    if dimension ~= "race" and dimension ~= "class" and dimension ~= "zone" and not subzones then return {} end
    options = type(options) == "table" and options or {}
    local parentZone = subzones and cleanName(options.zone)
    if subzones and not parentZone then return {} end
    local within, periodKey = periodFilter(options)
    local actor, scope, now = currentActor(), options.scope or "character", GL.Now()
    local key = periodKey .. ":" .. scope .. ":" .. (actor or "unknown")
    if subzones then key = key .. ":" .. parentZone end
    local cached = breakdownStatistics[dimension]
    if not cached or cached.key ~= key or now < cached.at or cached.nextAt and now >= cached.nextAt then
        local active, corrected, buckets, nextAt = {}, {}, {}
        for _, row in ipairs(indexedJournal()) do
            local event = row.event
            if (event.kind == "kill" or event.kind == "death") and pvpFields[event.kind][event.confidence]
                and event.voidReason ~= "battleground" and inScope(row.actor, scope, actor) then
                if row.at > now and (not nextAt or row.at < nextAt) then nextAt = row.at end
                if within(event, row.at) then
                    local token, name = cleanName(event[dimension]), cleanName(event[dimension .. "Name"])
                    local zone = subzones and cleanName(event.zone)
                    if subzones and (not zone or zone == "?") then zone = "unknown" end
                    if (dimension == "zone" or subzones) and (token == "?" or token == zone) then token = nil end
                    local category = token or name and "name:" .. name:lower() or "unknown"
                    local label = name or token or "Inconnue"
                    local counts = event.voided and corrected or active
                    local id = pvpEventKey(row)
                    local previous = counts[id]
                    if not previous then
                        counts[id] = { key = category, label = label, raceID = dimension == "race" and event.raceID or nil, kind = event.kind, confidence = event.confidence, zone = zone }
                    else
                        -- Group all participants before filtering by district.
                        if subzones and previous.zone ~= zone then
                            previous.zone = (zone == "unknown" or previous.zone == "unknown") and "unknown" or "mixed"
                        end
                        if previous.key ~= category then
                            previous.raceID = nil
                            previous.key = (previous.key == "unknown" or category == "unknown") and "unknown" or "mixed"
                            previous.label = previous.key == "unknown" and "Inconnue" or (dimension == "zone" or subzones) and "Plusieurs lieux" or "Groupe mixte"
                        elseif label < previous.label then previous.label = label end
                    end
                end
            end
        end
        for _, counts in ipairs({ active, corrected }) do
            for _, entry in pairs(counts) do
                if not subzones or entry.zone == parentZone then
                    local bucket = buckets[entry.key] or { key = entry.key, label = entry.label, kills = 0, deaths = 0,
                        correctedKills = 0, correctedDeaths = 0 }
                    local field = counts == corrected and (entry.kind == "kill" and "correctedKills" or "correctedDeaths")
                        or pvpFields[entry.kind][entry.confidence]
                    bucket.raceID = bucket.raceID or entry.raceID
                    bucket[field] = bucket[field] + 1
                    if entry.label < bucket.label then bucket.label = entry.label end
                    buckets[entry.key] = bucket
                end
            end
        end
        local rows = {}
        for _, bucket in pairs(buckets) do rows[#rows + 1] = bucket end
        table.sort(rows, function(a, b)
            local av, bv = a.kills + a.deaths, b.kills + b.deaths
            if av ~= bv then return av > bv end
            if a.label ~= b.label then return a.label < b.label end
            return a.key < b.key
        end)
        -- ponytail: one result per dimension, replaced when its filters change.
        -- Snapshots are never backfilled from a player's later identity or guild.
        cached = { key = key, at = now, nextAt = nextAt, rows = rows }
        breakdownStatistics[dimension] = cached
    end
    local result = {}
    for _, row in ipairs(cached.rows) do
        local copy = {}
        for field, value in pairs(row) do copy[field] = value end
        result[#result + 1] = copy
    end
    return result
end
function GL.Settings() return GL.db and GL.db.settings or defaults end
local function settingValue(key, value)
    if defaults[key] == nil or type(value) ~= type(defaults[key]) then return nil end
    if key == "listSort" and not listSorts[value] or key == "listDetail" and not listDetails[value] then return nil end
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        if key == "alertCooldown" then value = math.max(15, math.min(3600, value))
        elseif key == "iconSize" then value = math.max(12, math.min(40, value))
        elseif key == "readingScale" then value = math.max(0.85, math.min(1.25, value))
        elseif key == "minimapAngle" then value = value % 360 end
    end
    return value
end
function GL.SetSetting(key, value)
    if not GL.db then return false end
    value = settingValue(key, value)
    if value == nil then return false end
    GL.db.settings[key] = value
    GL.Emit("SETTINGS")
    return true
end
function GL.InitDB()
    invalidateJournal()
    observations, observationCount, guildStatistics = {}, 0, nil
    socialTotals = setmetatable({}, { __mode = "k" })
    guildSightings, deletedGuildSightings = {}, {}
    traceLast = {}
    if type(GrudgeLedgerDB) ~= "table" then GrudgeLedgerDB = {} end
    GL.db = GrudgeLedgerDB
    local migratePvP = GL.db.schema ~= 2
    GL.db.players = type(GL.db.players) == "table" and GL.db.players or {}
    if GL.db.unassignedHonor ~= nil and type(GL.db.unassignedHonor) ~= "table" then
        GL.db.quarantine = GL.db.quarantine or {}
        GL.db.quarantine.unassignedHonor, GL.db.unassignedHonor = GL.db.unassignedHonor, nil
    end
    GL.db.aliases = type(GL.db.aliases) == "table" and GL.db.aliases or {}
    GL.db.guilds = type(GL.db.guilds) == "table" and GL.db.guilds or {}
    GL.db.settings = type(GL.db.settings) == "table" and GL.db.settings or {}
    -- Start the new reading style once per account, including older journals.
    -- A later explicit choice of the native game font survives reloads.
    if not GL.db.grimoireFontDefaultApplied then
        GL.db.settings.readableFont = defaults.readableFont
        GL.db.grimoireFontDefaultApplied = true
    end
    for key, value in pairs(defaults) do
        local saved = settingValue(key, GL.db.settings[key])
        if saved == nil then saved = value end
        GL.db.settings[key] = saved
    end
    for key, record in pairs(GL.db.players) do
        if type(key) == "string" and type(record) == "table" then
            record.key = key
            if migratePvP or type(record.pvp) == "table" and (record.pvp.probableDeaths or record.pvp.probableKills or record.pvp.probableAggressions) then
                local pvp = record.pvp
                if type(pvp) == "table" then
                    for old, field in pairs({probableDeaths="deaths", probableKills="kills", probableAggressions="aggressions"}) do
                        pvp[field] = (tonumber(pvp[field]) or 0) + (tonumber(pvp[old]) or 0)
                        pvp[old] = nil
                    end
                end
                local seen = {}
                for _, event in ipairs(type(record.history) == "table" and record.history or {}) do
                    if type(event) == "table" and event.confidence == "probable" then
                        event.confidence = "confirmed"
                        if event.kind == "death" and type(event.evidence) == "string" and event.evidence:find("Participation probable", 1, true) then
                            event.evidence = "Participation à l’attaque ayant causé votre mort."
                        end
                    end
                    if type(event) == "table" and pvpFields[event.kind] and event.eventId and not event.voided then
                        local field = pvpFields[event.kind][event.confidence]
                        if field and seen[event.eventId] == field then
                            event.voided, event.voidReason = true, "duplicate"
                            if type(pvp) == "table" then pvp[field] = math.max(0, (pvp[field] or 0) - 1) end
                        elseif field then seen[event.eventId] = field end
                    end
                end
            end
            normalize(record)
        else
            GL.db.quarantine = GL.db.quarantine or {}
            GL.db.quarantine[key] = record
            GL.db.players[key] = nil
            GL.Debug(L("Entrée sauvegardée invalide conservée dans quarantine : ") .. tostring(key))
        end
    end
    GL.db.schema = 2
    cleanBattlegroundHistory()
    GL.Emit("READY")
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
    if name == ADDON then GL.InitDB() boot:UnregisterEvent("ADDON_LOADED") end
end)
