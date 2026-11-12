-- Grudge Ledger: shared identities, relationships and persistent history.
-- Identity/saved-variable approach informed by Worth Remembering (Kyle, GPL-3.0).
local ADDON = ...
GrudgeLedger = { version = "0.6.1", errors = {}, icon = "Interface\\AddOns\\GrudgeLedger\\Media\\LedgerIcon",
    minimapIcon = "Interface\\AddOns\\GrudgeLedger\\Media\\LedgerBook" }
local GL = GrudgeLedger
local listeners = {}
local guildSightings = {}
local traceLast = {}
local observations, observationCount = {}, 0
local guildStatistics
local journalIndex, journalSorted, personalStatistics
local socialTotals = setmetatable({}, { __mode = "k" })
local defaults = {
    markers = true, nameColor = false, friendAlerts = true, enemyAlerts = true,
    sounds = true, alertCooldown = 180, iconSize = 20, pvpTracking = true,
    groupTracking = true, socialTracking = true, minimapAngle = 225, readableFont = false,
    quickGestures = true, detectionLog = true, partyWarnings = false,
    listSort = "recent", listDetail = "identity",
}
local listSorts = { recent = true, name = true, reputation = true, kills = true, deaths = true, encounters = true }
local listDetails = { identity = true, guild = true, pvp = true, notes = true }
local function invalidateJournal() journalIndex, journalSorted, personalStatistics = nil, nil, nil end

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
}
function GL.Trace(code, identity, unit)
    if not GL.db or not GL.Settings().detectionLog or not traceReasons[code] then return end
    local record = identity and GL.Get(identity)
    local key = record and record.key
    local source = type(unit) == "string" and (unit:match("^nameplate%d+$") and "nameplate"
        or ({ target = "target", mouseover = "mouseover", focus = "focus" })[unit]) or "autre"
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
    local lines, aliases, count = { "\nDétections : 200 dernières décisions, répétitions espacées de 30 s." }, {}, 0
    for _, event in ipairs(GL.db.detectionLog or {}) do
        if traceReasons[event.code] then
            local who = "identité inconnue"
            if event.key then
                if not aliases[event.key] then count = count + 1 aliases[event.key] = "joueur #" .. count end
                local record = private and GL.Get(event.key)
                who = record and (record.fullName or record.name):gsub("|", "||") or aliases[event.key]
            end
            lines[#lines + 1] = date("%d/%m %H:%M:%S", event.time) .. " · " .. who .. " · " .. event.source .. " · " .. traceReasons[event.code]
        end
    end
    local probe = GL.db.minimapProbe
    lines[#lines + 1] = "\nRadar minimap : expérimental, non activé."
    if probe then lines[#lines + 1] = "Dernier test : " .. probe.result .. " (build " .. probe.build .. ")"
    else lines[#lines + 1] = "Aucun résultat de test sauvegardé." end
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

local function cleanName(value)
    value = GL.Clean(value, "string")
    if not value or #value > 160 or value:find("[|%c]") then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

function GL.IdentityFromName(name, surname, guid)
    name, surname, guid = cleanName(name), cleanName(surname), GL.Clean(guid, "string")
    if guid and (not guid:match("^Player%-%w") or #guid > 128) then guid = nil end
    if not name then return nil end
    if not surname then
        local first, last = name:match("^(%S+)%s+(.+)$")
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
    local raceName, race = GL.Safe(UnitRace, unit)
    identity.race, identity.raceName = cleanName(race), cleanName(raceName)
    local sex = GL.Safe(UnitSex, unit)
    identity.sex = (sex == 2 or sex == 3) and sex or nil
    identity.faction = GL.Clean(GL.Safe(UnitFactionGroup, unit), "string")
    identity.level = GL.Clean(GL.Safe(UnitLevel, unit), "number")
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
local function refreshReputation(record)
    if record.reaction and record.reactionSource ~= "emote" and record.reactionSource ~= "automatic" then return end
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
    local balance = (pvp.kills or 0) + (pvp.probableKills or 0)
        - 10 * ((pvp.deaths or 0) + (pvp.probableDeaths or 0))
        - (pvp.aggressions or 0) - (pvp.probableAggressions or 0)
    -- Friendly gestures cannot conceal an unsettled attack; victories repay one
    -- point at a time but cannot by themselves make an opponent a friend.
    local score = balance < 0 and math.min(0, social) + balance
        or social < 0 and math.min(0, social + balance) or social
    record.reputation = math.max(-100, math.min(100, score))
    if record.reactionSource == "emote" or record.reactionSource == "automatic" then record.reaction = scoreRelation(record.reputation) end
end
local function normalize(record)
    socialTotals[record] = nil
    record.notes = type(record.notes) == "table" and record.notes or {}
    record.history = type(record.history) == "table" and record.history or {}
    if record.encounters ~= nil then
        local e = type(record.encounters) == "table" and record.encounters or {}
        local function nonnegative(value, fallback)
            return type(value) == "number" and value >= 0 and value < math.huge and math.floor(value) or fallback
        end
        e.count, e.since = nonnegative(e.count, 0), nonnegative(e.since, GL.Now())
        e.seen = type(e.seen) == "table" and e.seen or {}
        for character, at in pairs(e.seen) do
            if type(character) ~= "string" or not nonnegative(at) then e.seen[character] = nil end
        end
        record.encounters = e
    end
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
    for _, field in ipairs({ "kills", "deaths", "probableKills", "probableDeaths", "aggressions", "probableAggressions" }) do
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
    invalidateJournal()
    guildStatistics, socialTotals[record] = nil, nil
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
    for _, event in ipairs(provisional.history or {}) do table.insert(record.history, event) end
    for _, field in ipairs({ "kills", "deaths", "probableKills", "probableDeaths", "aggressions", "probableAggressions" }) do
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
    for _, field in ipairs({ "class", "race" }) do
        local value = cleanName(identity[field])
        local name = cleanName(identity[field .. "Name"])
        if value and value ~= record[field] then record[field], record[field .. "Name"] = value, nil end
        if name and (not record[field] or value == record[field]) then record[field .. "Name"] = name end
    end
    record.faction = cleanName(identity.faction) or record.faction
    local sex = GL.Clean(identity.sex, "number")
    if sex == 2 or sex == 3 then record.sex = sex end
    record.level = GL.Clean(identity.level, "number") or record.level
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
    if record or (rule and rule.reaction ~= "neutral") then record = GL.Remember(identity) end
    local me = visible and GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if record and me then
        -- ponytail: one encounter after >10 minutes without a public observation,
        -- not an exact distance/time-spent measurement. No invented historical visits.
        record.encounters = record.encounters or { count = 0, seen = {}, since = GL.Now() }
        local visits, now = record.encounters, GL.Now()
        local previous = visits.seen[me]
        if not previous or now - previous > 600 then visits.count = visits.count + 1 end
        visits.seen[me] = now
    end
    return record
end
local function effectiveRelation(record)
    if not record then return "neutral", "neutral" end
    local opinion = record.reaction == "friend" or record.reaction == "enemy" or record.reaction == "neutral" or record.reaction == "warning"
    if opinion and record.reactionSource ~= "emote" and record.reactionSource ~= "automatic" then return record.reaction, "manual" end
    local pvp = record.pvp or {}
    if (pvp.deaths or 0) + (pvp.probableDeaths or 0) > 0 and (record.reputation or 0) < 0 then
        return record.reputation <= -10 and "enemy" or "warning", "pvp"
    end
    local rule = GL.GetGuildRule(record)
    if rule and rule.reaction == "enemy" then return "enemy", "guild" end
    if (pvp.aggressions or 0) + (pvp.probableAggressions or 0) > 0 and (record.reputation or 0) < 0 then return "warning", "pvp" end
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
    local confirmed = (record.pvp.deaths or 0) + (record.pvp.probableDeaths or 0) > 0
        and record.pvp.deaths or record.pvp.aggressions
    return (confirmed or 0) > 0 and "confirmed" or "probable"
end
local function currentActor()
    local name, surname = GL.Safe(UnitName, "player")
    local actor = GL.IdentityFromName(name, surname, GL.Safe(UnitGUID, "player"))
    return actor and actor.guid, actor and actor.fullName
end
local function history(record, kind, extra)
    local entry = extra or {}
    local now, zone = GL.Now(), GL.Where()
    entry.time, entry.kind, entry.zone = entry.time or now, kind, entry.zone or zone
    entry.actorGUID, entry.actorName = currentActor()
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
    end
    table.insert(record.history, entry)
    guildStatistics = nil
    invalidateJournal()
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
                friends = 0, deaths = 0, probableDeaths = 0, kills = 0, aggressions = 0 }
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
                local field = event.kind == "death" and (event.confidence == "confirmed" and "deaths"
                    or event.confidence == "probable" and "probableDeaths")
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
        elseif metric == "friendsRecent" or metric == "enemiesRecent" then
            local match = metric == "friendsRecent" and relation == "friend"
                or metric == "enemiesRecent" and (relation == "warning" or relation == "enemy")
            if match then
                -- lastSeen also changes on manual edits and group updates; these are real observations.
                for _, at in pairs(record.encounters and record.encounters.seen or {}) do
                    if type(at) == "number" and at > value and at < math.huge then value = at end
                end
            end
        elseif metric == "friendsGrouped" then value = relation == "friend" and record.groupCount or 0
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
    if not text or not text:find("%S") then return nil, "La note est vide." end
    if #text > 2000 then return nil, "La note est trop longue (2000 octets maximum)." end
    return text
end
function GL.AddNote(identity, text)
    local err
    text, err = noteText(text)
    if not text then return false, err end
    local record = GL.Remember(identity)
    if not record then return false, "Identité du joueur indisponible." end
    local actorGUID, actorName = currentActor()
    table.insert(record.notes, { time = GL.Now(), text = text, actorGUID = actorGUID, actorName = actorName })
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
    if not record then return false, "Cette note n'appartient plus à cette fiche." end
    local value, err = noteText(text)
    if not value then return false, err end
    if note.text ~= value then
        note.text, note.updatedAt = value, GL.Now()
        GL.Emit("CHANGED", record)
    end
    return true
end
function GL.DeleteNote(identity, note)
    local record, index = findNote(identity, note)
    if not record then return false, "Cette note n'appartient plus à cette fiche." end
    table.remove(record.notes, index)
    guildStatistics = nil
    GL.Emit("CHANGED", record)
    return true
end
local pvpFields = {
    kill = { confirmed = "kills", probable = "probableKills" },
    death = { confirmed = "deaths", probable = "probableDeaths" },
    aggression = { confirmed = "aggressions", probable = "probableAggressions" },
}
function GL.RecordPvP(identity, kind, confidence, evidence, eventId)
    if GL.IsPvPInstance() then return nil end
    if kind ~= "kill" and kind ~= "death" then return nil end
    if confidence ~= "confirmed" and confidence ~= "probable" then return nil end
    local record = GL.Remember(identity)
    if not record then return nil end
    if eventId then
        for _, event in ipairs(record.history) do if event.eventId == eventId then return nil end end
    end
    local field = pvpFields[kind][confidence]
    record.pvp[field] = record.pvp[field] + 1
    refreshReputation(record)
    history(record, kind, { confidence = confidence, evidence = evidence, eventId = eventId })
    GL.Emit("CHANGED", record)
    return record
end
function GL.RecordAggression(identity, confidence, evidence, eventId)
    if GL.IsPvPInstance() then return nil end
    if confidence ~= "confirmed" and confidence ~= "probable" then return nil end
    local record = GL.Remember(identity)
    if not record then return nil end
    if eventId then
        for _, event in ipairs(record.history) do if event.eventId == eventId then return nil end end
    end
    local field = pvpFields.aggression[confidence]
    record.pvp[field] = record.pvp[field] + 1
    refreshReputation(record)
    history(record, "aggression", { confidence = confidence, evidence = evidence, eventId = eventId })
    GL.Emit("CHANGED", record)
    return record
end
function GL.VoidPvP(identity, event, silent)
    local record = GL.Get(identity)
    if not record or type(event) ~= "table" or event.voided then return false, "Événement indisponible ou déjà annulé." end
    local fields = pvpFields[event.kind]
    local field = fields and fields[event.confidence]
    if not field then return false, "Seul un événement PvP peut être corrigé ici." end
    local found = false
    for _, entry in ipairs(record.history) do if entry == event then found = true break end end
    if not found then return false, "Cet événement n'appartient pas à cette fiche." end
    -- Keep the original evidence and eventId: repeated observations must not resurrect it.
    event.voided, event.voidedAt = true, GL.Now()
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
        GL.Debug("Archive de champs de bataille invalide : nettoyage reporté.")
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
        GL.Print("Champs de bataille : " .. events .. " événement(s) écarté(s), " .. count
            .. " fiche(s) archivée(s). Notes et avis personnels conservés.")
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

local function queryWords(query)
    local words = {}
    query = GL.Clean(query, "string") or ""
    for word in query:sub(1, 512):lower():gmatch("%S+") do words[#words + 1] = word end
    return words
end
local function matchesWords(text, words)
    text = text:lower()
    for _, word in ipairs(words) do if not text:find(word, 1, true) then return false end end
    return true
end
local function recordText(record, notes)
    local parts = {}
    for _, field in ipairs({ "fullName", "name", "surname", "guild", "class", "className", "race", "raceName", "lastZone", "faction" }) do
        if type(record[field]) == "string" then parts[#parts + 1] = record[field] end
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
            and (#words == 0 or matchesWords(recordText(record, true), words)) then result[#result + 1] = record end
    end
    local sort = listSorts[options.sort] and options.sort or "recent"
    local function value(record)
        if sort == "name" then return (record.fullName or record.name or record.key):lower() end
        if sort == "reputation" then return record.reputation or 0 end
        if sort == "kills" or sort == "deaths" then return record.pvp[sort] or 0 end
        if sort == "encounters" then return record.encounters and record.encounters.count or 0 end
        return record.lastSeen or 0
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
    local guid = GL.Clean(event.actorGUID, "string")
    return guid and guid:match("^Player%-%w") and #guid <= 128 and guid or nil
end
local function indexedJournal()
    if journalIndex then return journalIndex end
    local rows = {}
    for _, record in pairs(GL.db and GL.db.players or {}) do
        for index, event in ipairs(record.history or {}) do
            if type(event) == "table" then
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
            if a.record.key ~= b.record.key then return a.record.key < b.record.key end
            return a.sequence > b.sequence
        end)
        journalSorted = true
    end
    for _, row in ipairs(rows) do
        local event, record = row.event, row.record
        local category = pvpFields[event.kind] and "pvp" or event.kind == "note" and "notes" or "social"
        if not GL.IsGroupOnly(record) and within(event, row.at) and inScope(row.actor, scope, actor)
            and (kind == "all" or kind == category or kind == event.kind) then
            local match = true
            if #words > 0 then
                texts[record] = texts[record] or recordText(record)
                local parts = { texts[record] }
                for _, field in ipairs({ "text", "zone", "subzone", "guild", "questTitle", "evidence" }) do
                    if type(event[field]) == "string" then parts[#parts + 1] = event[field] end
                end
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
local function statisticsCopy(stats)
    local result = {}
    for key, value in pairs(stats) do
        if key == "mostKilled" or key == "mostDeaths" then result[key] = { record = value.record, value = value.value }
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
    local stats = { kills = 0, deaths = 0, probableKills = 0, probableDeaths = 0,
        aggressions = 0, probableAggressions = 0, events = 0, unknownActorEvents = 0,
        unlinkedEvents = 0, currentActor = actor, actorName = actorName, scope = scope }
    local counted, unknown, ranked, rankings = {}, {}, {}, { kill = {}, death = {} }
    for _, row in ipairs(indexedJournal()) do
        local event, record = row.event, row.record
        local fields = pvpFields[event.kind]
        local at = row.at
        if fields and not event.voided and at > now and (not nextAt or at < nextAt) then nextAt = at end
        if fields and not event.voided and fields[event.confidence] and within(event, at) then
            local id = pvpEventKey(row)
            if not row.actor and not unknown[id] then
                unknown[id], stats.unknownActorEvents = true, stats.unknownActorEvents + 1
            end
            if inScope(row.actor, scope, actor) then
                local previous = counted[id]
                if not previous or event.confidence == "confirmed" then counted[id] = event end
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
    for id, event in pairs(counted) do
        local field = pvpFields[event.kind][event.confidence]
        stats[field], stats.events = stats[field] + 1, stats.events + 1
        if type(id) == "table" then stats.unlinkedEvents = stats.unlinkedEvents + 1 end
    end
    for kind, records in pairs(rankings) do
        local field = kind == "kill" and "mostKilled" or "mostDeaths"
        for _, row in pairs(records) do
            local best = stats[field]
            if not best or row.value > best.value or row.value == best.value and row.record.key < best.record.key then stats[field] = row end
        end
    end
    -- One bounded result cache; changing a filter replaces it. Rolling windows
    -- expire each server second, so events at the boundary never linger in totals.
    personalStatistics = { key = key, value = stats, at = now, nextAt = nextAt }
    return statisticsCopy(stats)
end
function GL.Settings() return GL.db and GL.db.settings or defaults end
function GL.SetSetting(key, value)
    if not GL.db or defaults[key] == nil or type(value) ~= type(defaults[key]) then return false end
    if key == "listSort" and not listSorts[value] or key == "listDetail" and not listDetails[value] then return false end
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return false end
        if key == "alertCooldown" then value = math.max(15, math.min(3600, value))
        elseif key == "iconSize" then value = math.max(12, math.min(40, value))
        elseif key == "minimapAngle" then value = value % 360 end
    end
    GL.db.settings[key] = value
    GL.Emit("SETTINGS")
    return true
end
function GL.InitDB()
    invalidateJournal()
    observations, observationCount, guildStatistics = {}, 0, nil
    socialTotals = setmetatable({}, { __mode = "k" })
    guildSightings = {}
    traceLast = {}
    if type(GrudgeLedgerDB) ~= "table" then GrudgeLedgerDB = {} end
    GL.db = GrudgeLedgerDB
    GL.db.schema = 1
    GL.db.players = type(GL.db.players) == "table" and GL.db.players or {}
    GL.db.aliases = type(GL.db.aliases) == "table" and GL.db.aliases or {}
    GL.db.guilds = type(GL.db.guilds) == "table" and GL.db.guilds or {}
    GL.db.settings = type(GL.db.settings) == "table" and GL.db.settings or {}
    for key, value in pairs(defaults) do
        if type(GL.db.settings[key]) ~= type(value) then GL.db.settings[key] = value end
    end
    if not listSorts[GL.db.settings.listSort] then GL.db.settings.listSort = defaults.listSort end
    if not listDetails[GL.db.settings.listDetail] then GL.db.settings.listDetail = defaults.listDetail end
    for key, record in pairs(GL.db.players) do
        if type(key) == "string" and type(record) == "table" then
            record.key = key
            normalize(record)
        else
            GL.db.quarantine = GL.db.quarantine or {}
            GL.db.quarantine[key] = record
            GL.db.players[key] = nil
            GL.Debug("Entrée sauvegardée invalide conservée dans quarantine : " .. tostring(key))
        end
    end
    cleanBattlegroundHistory()
    GL.Emit("READY")
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
    if name == ADDON then GL.InitDB() boot:UnregisterEvent("ADDON_LOADED") end
end)
