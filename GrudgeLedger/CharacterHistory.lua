-- Dated history of each character, and the build of both players at every fight.
-- An observation adds a dated change; it never rewrites an older one. Values come from the
-- resolved profile (GL.ArmoryProfile, with its provenance) and from the session inspection.
local GL = GrudgeLedger
local L = GL.L
local H = {}
GL.CharacterHistory = H

-- ponytail: 120 changes per character and 600 characters, the least recently seen dropped first.
-- Raise only if a real journal reaches these ceilings; every change is a few numbers.
local MAX_CHANGES, MAX_CHARACTERS = 120, 600
-- A character is read again at most every five seconds; journal changes arrive in bursts.
local THROTTLE = 5
local STAT_KEYS = {"HEALTH", "MANA", "RAGE", "ENERGY", "ARMOR", "STRENGTH", "AGILITY", "STAMINA", "INTELLECT"}
local SLOTS = {"head", "neck", "shoulder", "shirt", "chest", "waist", "leg", "foot", "wrist", "hand",
    "leftfinger", "rightfinger", "lefttrinket", "righttrinket", "back", "weapon", "offhand", "ranged", "tabard"}
local lastRead = {}

local function seconds(at)
    at = tonumber(at)
    if at and at >= 1e11 then
        at = at / 1000
    end
    if at and at > 0 then
        return math.floor(at)
    end
end

local function store()
    GL.db.characterHistory = GL.db.characterHistory or {}
    return GL.db.characterHistory
end

local function entryFor(guid)
    local all = store()
    local entry = all[guid]
    if entry then
        return entry
    end
    local count, oldest = 0, nil
    for key, value in pairs(all) do
        count = count + 1
        if not oldest or value.seen < all[oldest].seen then
            oldest = key
        end
    end
    if count >= MAX_CHARACTERS then
        all[oldest] = nil
    end
    entry = {seen = 0, state = {}, stateAt = {}, changes = {}}
    all[guid] = entry
    return entry
end

-- The saved entry of a character; create makes one when it is missing.
function H.Entry(guid, create)
    if not GL.db or type(guid) ~= "string" then
        return
    end
    if create then
        return entryFor(guid)
    end
    return store()[guid]
end

-- Records value for key at its own observation date. The same value only confirms it;
-- a value dated before what is already known is ignored rather than inserted out of order.
local function observe(guid, key, value, at, source, by)
    at = seconds(at)
    if value == nil or not at then
        return
    end
    local entry = entryFor(guid)
    entry.seen = math.max(entry.seen, at)
    if entry.state[key] == value then
        entry.stateAt[key] = math.max(entry.stateAt[key] or 0, at)
        return
    end
    if (entry.stateAt[key] or 0) > at then
        return
    end
    entry.state[key] = value
    entry.stateAt[key] = at
    local changes = entry.changes
    changes[#changes + 1] = {at = at, key = key, value = value, source = source, by = by}
    if #changes > MAX_CHANGES then
        table.remove(changes, 1)
    end
end

-- "31/0/20" and the name of the tree with the most points.
local function specOf(trees)
    if type(trees) ~= "table" or #trees == 0 then
        return
    end
    local points, best = {}, nil
    for i, tree in ipairs(trees) do
        points[i] = tonumber(tree.points) or 0
        if points[i] > 0 and (not best or points[i] > (tonumber(trees[best].points) or 0)) then
            best = i
        end
    end
    if not best then
        return
    end
    return table.concat(points, "/"), type(trees[best].name) == "string" and trees[best].name or nil
end

local function itemID(value)
    if type(value) == "table" then
        return tonumber(value.id)
    end
    if type(value) == "string" then
        return tonumber(value:match("item:(%d+)"))
    end
end

local function statsOf(stats)
    if type(stats) ~= "table" then
        return
    end
    local out, any = {}, false
    for _, key in ipairs(STAT_KEYS) do
        local value = tonumber(stats[key])
        if value then
            out[key] = value
            any = true
        end
    end
    return any and out or nil
end

-- Reads everything known about a character now and records what changed.
local function collect(guid)
    if type(guid) ~= "string" or not guid:match("^Player%-") then
        return
    end
    local now = GL.Now()
    if lastRead[guid] and now - lastRead[guid] < THROTTLE then
        return
    end
    lastRead[guid] = now
    local record = GL.Get("guid:" .. guid)
    local probe = record or {guid = guid}
    local profile = GL.ArmoryProfile(probe) or {}
    local provenance = type(profile.provenance) == "table" and profile.provenance or {}
    local dates = type(profile.dates) == "table" and profile.dates or {}
    local updated = profile.updated
    local function origin(key)
        local p = provenance[key]
        return p and p.source or "armory", p and p.by
    end
    local source, by = origin("level")
    observe(guid, "level", tonumber(profile.level), profile.levelAt or updated, source, by)
    local identity = type(profile.identity) == "table" and profile.identity or {}
    local identityDates = type(dates.identity) == "table" and dates.identity or {}
    source, by = origin("identity")
    observe(guid, "guild", identity.guild, identityDates.guild or profile.identityAt or updated, source, by)
    source, by = origin("averageItemLevel")
    observe(guid, "ilvl", tonumber(profile.averageItemLevel), profile.averageItemLevelAt or updated, source, by)
    source, by = origin("trees")
    observe(guid, "spec", (specOf(profile.trees)), profile.treesAt or updated, source, by)
    source, by = origin("gear")
    local gearDates = type(dates.gear) == "table" and dates.gear or {}
    for slot, value in pairs(type(profile.gear) == "table" and profile.gear or {}) do
        local id = itemID(value) or itemID(GL.ArmoryItem(probe, slot))
        observe(guid, "gear:" .. tostring(slot), id, gearDates[slot] or profile.gearAt or updated, source, by)
    end
    local me = GL.Safe(UnitGUID, "player")
    if record then
        observe(guid, "level", GL.ValidLevel(record.level), record.lastSeen, "sighting", me)
        observe(guid, "guild", record.guild, record.guildSeenAt or record.lastSeen, "sighting", me)
    end
    local inspected = GL.DossierInspection and GL.DossierInspection(probe)
    if type(inspected) == "table" then
        observe(guid, "spec", (specOf(inspected.trees)), inspected.talentsAt, "inspection", me)
        observe(guid, "ilvl", tonumber(inspected.averageItemLevel), inspected.gearAt, "inspection", me)
        for index, link in pairs(type(inspected.gear) == "table" and inspected.gear or {}) do
            if SLOTS[index] then
                observe(guid, "gear:" .. SLOTS[index], itemID(link), inspected.gearAt, "inspection", me)
            end
        end
    end
end
H.Collect = collect

-- Build of the opponent as best known at the moment of the fight, with the date it was observed.
local function opponentBuild(record)
    local profile = GL.ArmoryProfile(record) or {}
    local inspected = GL.DossierInspection and GL.DossierInspection(record)
    inspected = type(inspected) == "table" and inspected or {}
    local profileAt = seconds(profile.gearAt or profile.updated) or 0
    local live = inspected.gear and (seconds(inspected.gearAt) or 0) >= profileAt
    local build = {level = GL.ValidLevel(record.level) or tonumber(profile.level), gear = {}}
    if live then
        for index, link in pairs(inspected.gear) do
            if SLOTS[index] then
                build.gear[SLOTS[index]] = itemID(link)
            end
        end
        build.at, build.source = seconds(inspected.gearAt), "inspection"
        build.ilvl = tonumber(inspected.averageItemLevel)
    else
        for slot, value in pairs(type(profile.gear) == "table" and profile.gear or {}) do
            build.gear[slot] = itemID(value) or itemID(GL.ArmoryItem(record, slot))
        end
        local p = type(profile.provenance) == "table" and profile.provenance.gear
        build.at = seconds(p and p.at or profileAt)
        build.source, build.by = p and p.source or "armory", p and p.by
        build.ilvl = tonumber(profile.averageItemLevel)
    end
    local trees = inspected.trees or profile.trees
    build.spec, build.specName = specOf(trees)
    build.stats = statsOf(inspected.stats) or statsOf(profile.stats)
    if not next(build.gear) then
        build.gear = nil
    end
    return build
end

-- Our talent trees, read from either GetTalentTabInfo signature (name first, or id first).
local function ownTrees()
    local trees = {}
    for tab = 1, tonumber(GL.Safe(GetNumTalentTabs)) or 0 do
        local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab)
        if ok then
            local name, points = a, c
            if type(a) == "number" then
                name, points = b, e
            end
            if type(name) == "string" and type(points) == "number" then
                trees[#trees + 1] = {name = name, points = points}
            end
        end
    end
    return #trees > 0 and trees or nil
end

-- Our own build at the moment of the fight.
local function selfBuild()
    local build = {level = GL.ValidLevel(GL.Safe(UnitLevel, "player")), gear = {}, stats = {}}
    local _, equipped = GL.Safe(GetAverageItemLevel)
    build.ilvl = tonumber(equipped)
    for index, slot in ipairs(SLOTS) do
        build.gear[slot] = tonumber(GL.Safe(GetInventoryItemID, "player", index))
    end
    build.stats.HEALTH = tonumber(GL.Safe(UnitHealthMax, "player"))
    local power, token = GL.Safe(UnitPowerType, "player")
    if type(token) == "string" and power then
        build.stats[token] = tonumber(GL.Safe(UnitPowerMax, "player", power))
    end
    local _, armor = GL.Safe(UnitArmor, "player")
    build.stats.ARMOR = tonumber(armor)
    for i, key in ipairs({"STRENGTH", "AGILITY", "STAMINA", "INTELLECT"}) do
        local _, effective = GL.Safe(UnitStat, "player", i)
        build.stats[key] = tonumber(effective)
    end
    build.stats = statsOf(build.stats)
    build.spec, build.specName = specOf(ownTrees())
    return build
end

GL.On("FIGHT_RECORDED", function(record, event)
    if type(record) ~= "table" or type(event) ~= "table" or not record.guid then
        return
    end
    event.build = {opponent = opponentBuild(record), me = selfBuild()}
    local combat = type(event.combat) == "table" and event.combat or {}
    observe(record.guid, "level", GL.ValidLevel(combat.opponentLevel), event.time, "combat", GL.Safe(UnitGUID, "player"))
end)
GL.On("DOSSIER_UPDATED", collect)
GL.On("CHANGED", function(record)
    if type(record) == "table" then
        collect(record.guid)
    end
end)

local function day(at)
    return date("%d/%m", at)
end

local function describe(build)
    if type(build) ~= "table" then
        return
    end
    local parts = {}
    if build.level then
        parts[#parts + 1] = L("niv. %s"):format(build.level)
    end
    if build.spec then
        parts[#parts + 1] = (build.specName and (build.specName .. " ") or "") .. build.spec
    end
    if build.ilvl then
        parts[#parts + 1] = L("objet %s"):format(math.floor(build.ilvl + .5))
    end
    if build.stats and build.stats.HEALTH then
        parts[#parts + 1] = L("vie %s"):format(build.stats.HEALTH)
    end
    if build.at then
        parts[#parts + 1] = L("relevé du %s"):format(date("%d/%m/%Y %H:%M", build.at))
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

-- Two lines for the fight detail: the opponent's build then ours, as recorded at the fight.
function GL.FightBuildText(event)
    local build = type(event) == "table" and event.build
    if type(build) ~= "table" then
        return
    end
    local lines = {L("Build au moment du combat")}
    local opponent, mine = describe(build.opponent), describe(build.me)
    if opponent then
        lines[#lines + 1] = L("Adversaire : %s"):format(opponent)
    end
    if mine then
        lines[#lines + 1] = L("Vous : %s"):format(mine)
    end
    return #lines > 1 and table.concat(lines, "\n") or nil
end

-- Short lines for the dossier: only what changed at least once.
function GL.CharacterEvolution(guid)
    local entry = guid and store()[guid]
    if not entry then
        return {}
    end
    local first, last, count, gearChanges, gearSince = {}, {}, {}, 0, nil
    for _, change in ipairs(entry.changes) do
        local key = change.key
        if key:sub(1, 5) == "gear:" then
            if first[key] then
                gearChanges = gearChanges + 1
                gearSince = gearSince or change.at
            end
            first[key] = first[key] or change
        else
            first[key] = first[key] or change
            last[key] = change
            count[key] = (count[key] or 0) + 1
        end
    end
    local lines = {}
    local labels = {level = L("Niveau"), ilvl = L("Niveau d’objet"), spec = L("Spécialisation"), guild = L("Guilde")}
    for _, key in ipairs({"level", "ilvl", "spec", "guild"}) do
        if (count[key] or 0) >= 2 then
            local from, to = tostring(first[key].value), tostring(last[key].value)
            -- The game font has no arrow glyph: "from 36 to 41" reads in every language.
            lines[#lines + 1] = L("%s : de %s à %s (depuis le %s)"):format(labels[key], from, to, day(first[key].at))
        end
    end
    if gearChanges > 0 then
        lines[#lines + 1] = L("Équipement : %d pièces changées depuis le %s"):format(gearChanges, day(gearSince))
    end
    return lines
end
