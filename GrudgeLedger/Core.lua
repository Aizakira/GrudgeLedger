-- Grudge Ledger: shared identities, relationships and persistent history.
-- Identity/saved-variable approach informed by Worth Remembering (Kyle, GPL-3.0).
local ADDON = ...
GrudgeLedger = { version = "0.4.0", errors = {}, icon = "Interface\\AddOns\\GrudgeLedger\\Media\\LedgerIcon",
    minimapIcon = "Interface\\AddOns\\GrudgeLedger\\Media\\LedgerBook" }
local GL = GrudgeLedger
local listeners = {}
local defaults = {
    markers = true, nameColor = false, friendAlerts = true, enemyAlerts = true,
    sounds = true, alertCooldown = 180, iconSize = 20, pvpTracking = true,
    groupTracking = true, socialTracking = true, minimapAngle = 225,
}

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
function GL.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end
function GL.Emit(event, ...)
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
    return { key = guid and ("guid:" .. guid) or alias, guid = guid, name = name,
        surname = surname, fullName = fullName, alias = alias }
end

function GL.Identity(unit)
    unit = GL.Clean(unit, "string")
    if not unit or not GL.Safe(UnitExists, unit) or not GL.Safe(UnitIsPlayer, unit) then return nil end
    if GL.Safe(UnitIsUnit, unit, "player") then return nil end
    local name, surname = GL.Safe(UnitName, unit)
    local guid = GL.Clean(GL.Safe(UnitGUID, unit), "string")
    local mine = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if guid and mine and guid == mine then return nil end
    local identity = GL.IdentityFromName(name, surname, guid)
    if not identity then return nil end
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
        if ok and (not issecretvalue or GL.Safe(issecretvalue, guild) == false) then
            identity.guildKnown = true
            identity.guild = cleanName(guild)
            identity.realm = cleanName(guildRealm) or cleanName(GL.Safe(GetRealmName))
        end
    end
    return identity
end

local function normalize(record)
    record.notes = type(record.notes) == "table" and record.notes or {}
    record.history = type(record.history) == "table" and record.history or {}
    if record.reaction and not record.reactionSource then
        record.reactionSource = "manual"
        for i = #record.history, 1, -1 do
            local event = record.history[i]
            if type(event) == "table" and event.kind == "reaction" then
                record.reaction, record.reactionSource = event.reaction, "manual"
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
    record.pvp = type(record.pvp) == "table" and record.pvp or {}
    for _, field in ipairs({ "kills", "deaths", "probableKills", "probableDeaths", "aggressions", "probableAggressions" }) do
        record.pvp[field] = tonumber(record.pvp[field]) or 0
    end
    record.groupCount = tonumber(record.groupCount) or 0
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
    for _, note in ipairs(provisional.notes or {}) do table.insert(record.notes, note) end
    for _, event in ipairs(provisional.history or {}) do table.insert(record.history, event) end
    for _, field in ipairs({ "kills", "deaths", "probableKills", "probableDeaths", "aggressions", "probableAggressions" }) do
        record.pvp[field] = record.pvp[field] + (provisional.pvp[field] or 0)
    end
    if not record.reaction or (record.reactionSource == "emote" and provisional.reaction and provisional.reactionSource == "manual") then
        record.reaction, record.reactionSource, record.reputation = provisional.reaction, provisional.reactionSource, provisional.reputation
    end
    record.reputation = record.reputation or provisional.reputation
    record.groupCount = record.groupCount + (provisional.groupCount or 0)
    record.firstSeen = math.min(record.firstSeen or GL.Now(), provisional.firstSeen or GL.Now())
    table.sort(record.notes, function(a, b) return (a.time or 0) < (b.time or 0) end)
    table.sort(record.history, function(a, b) return (a.time or 0) < (b.time or 0) end)
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
    record.realm = cleanName(identity.realm) or record.realm
    if identity.guildKnown then record.guild = cleanName(identity.guild)
    elseif identity.guild then record.guild = cleanName(identity.guild) end
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

function GL.RecordSeen(identity)
    local record = GL.Get(identity)
    local rule = GL.GetGuildRule(identity)
    if record or (rule and rule.reaction ~= "neutral") then record = GL.Remember(identity) end
    return record
end
local function effectiveRelation(record)
    if not record then return "neutral", "neutral" end
    local opinion = record.reaction == "friend" or record.reaction == "enemy" or record.reaction == "neutral" or record.reaction == "warning"
    if opinion and record.reactionSource ~= "emote" then return record.reaction, "manual" end
    local pvp = record.pvp or {}
    if (pvp.deaths or 0) + (pvp.probableDeaths or 0) > 0 then return "enemy", "pvp" end
    local rule = GL.GetGuildRule(record)
    if rule and rule.reaction == "enemy" then return "enemy", "guild" end
    if (pvp.aggressions or 0) + (pvp.probableAggressions or 0) > 0 then return "warning", "pvp" end
    if opinion then return record.reaction, "emote" end
    if rule then return rule.reaction, "guild" end
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
    local confirmed = relation == "enemy" and record.pvp.deaths or record.pvp.aggressions
    return (confirmed or 0) > 0 and "confirmed" or "probable"
end
local function history(record, kind, extra)
    local entry = extra or {}
    entry.time, entry.kind, entry.zone = entry.time or GL.Now(), kind, entry.zone or GL.Where()
    table.insert(record.history, entry)
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
    GL.Emit("CHANGED")
    return rule
end
function GL.SetReaction(identity, reaction)
    if reactionScores[reaction] == nil then return nil end
    local record = GL.Remember(identity)
    if not record then return nil end
    if record.reaction ~= reaction or record.reputation ~= reactionScores[reaction] or record.reactionSource ~= "manual" then
        record.reaction = reaction
        record.reactionSource = "manual"
        record.reputation = reactionScores[reaction]
        history(record, "reaction", { reaction = reaction })
        GL.Emit("CHANGED", record)
    end
    return record
end
function GL.AdjustReputation(identity, delta, reason, source)
    delta = GL.Clean(delta, "number")
    if not delta or delta ~= delta or math.abs(delta) == math.huge or delta == 0 then return nil end
    delta = math.max(-100, math.min(100, math.floor(delta)))
    local record = GL.Remember(identity)
    if not record then return nil end
    local before = record.reputation or reactionScores[GL.Relation(record)] or 0
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
function GL.AddNote(identity, text)
    text = GL.Clean(text, "string")
    if not text or not text:find("%S") then return false, "La note est vide." end
    if #text > 2000 then return false, "La note est trop longue (2000 octets maximum)." end
    local record = GL.Remember(identity)
    if not record then return false, "Identité du joueur indisponible." end
    table.insert(record.notes, { time = GL.Now(), text = text })
    GL.Emit("CHANGED", record)
    return true
end
local pvpFields = {
    kill = { confirmed = "kills", probable = "probableKills" },
    death = { confirmed = "deaths", probable = "probableDeaths" },
    aggression = { confirmed = "aggressions", probable = "probableAggressions" },
}
function GL.RecordPvP(identity, kind, confidence, evidence, eventId)
    if kind ~= "kill" and kind ~= "death" then return nil end
    if confidence ~= "confirmed" and confidence ~= "probable" then return nil end
    local record = GL.Remember(identity)
    if not record then return nil end
    if eventId then
        for _, event in ipairs(record.history) do if event.eventId == eventId then return nil end end
    end
    local field = pvpFields[kind][confidence]
    record.pvp[field] = record.pvp[field] + 1
    if kind == "death" and not record.reaction then record.reputation = math.max(-100, math.min(-10, (record.reputation or 0) - 10)) end
    history(record, kind, { confidence = confidence, evidence = evidence, eventId = eventId })
    GL.Emit("CHANGED", record)
    return record
end
function GL.RecordAggression(identity, confidence, evidence, eventId)
    if confidence ~= "confirmed" and confidence ~= "probable" then return nil end
    local record = GL.Remember(identity)
    if not record then return nil end
    if eventId then
        for _, event in ipairs(record.history) do if event.eventId == eventId then return nil end end
    end
    local field = pvpFields.aggression[confidence]
    record.pvp[field] = record.pvp[field] + 1
    if not record.reaction then record.reputation = math.max(-100, math.min(-1, (record.reputation or 0) - 1)) end
    history(record, "aggression", { confidence = confidence, evidence = evidence, eventId = eventId })
    GL.Emit("CHANGED", record)
    return record
end
function GL.VoidPvP(identity, event)
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
    record.pvp[field] = math.max(0, (record.pvp[field] or 0) - 1)
    if not record.reaction then
        local pvp = record.pvp
        record.reputation = math.max(-100, -10 * (pvp.deaths + pvp.probableDeaths)
            - pvp.aggressions - pvp.probableAggressions)
    end
    GL.Emit("CHANGED", record)
    return true
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
function GL.Settings() return GL.db and GL.db.settings or defaults end
function GL.SetSetting(key, value)
    if not GL.db or defaults[key] == nil or type(value) ~= type(defaults[key]) then return false end
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
    GL.Emit("READY")
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
    if name == ADDON then GL.InitDB() boot:UnregisterEvent("ADDON_LOADED") end
end)
