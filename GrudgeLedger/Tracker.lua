-- Grudge Ledger: combat inference and group memories.
-- Heuristic evidence is always recorded as probable, never as a confirmed kill.
local GL = GrudgeLedger
local L = GL.L
local T = {}
GL.Tracker = T

local frame = CreateFrame("Frame")
local plates, recentCredits = {}, {}
local petOwners, petSlots, nextPetSlot = {}, {}, 1
local fight, lastFight
local pendingDeath, lastDeathAt, lastRecapStamp
local duel, deathHandled, registered = false, false, false
local duelPendingUntil
local serial, honorBaseline, session = 0, nil, nil
local worldActive = true
local idleOpponents, idleAt, openingFeed
local damageEvents = {
    SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
    SPELL_BUILDING_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true, ENVIRONMENTAL_DAMAGE = true,
}
local priorActions = {
    SPELL_AURA_APPLIED = true, SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REFRESH = true,
    SPELL_CAST_START = true, SPELL_CAST_SUCCESS = true, SPELL_INTERRUPT = true, SPELL_DISPEL = true,
    SPELL_STOLEN = true, SWING_MISSED = true, RANGE_MISSED = true, SPELL_MISSED = true,
    SPELL_PERIODIC_MISSED = true, SPELL_DRAIN = true, SPELL_LEECH = true, SPELL_ABSORBED = true,
}

-- Evidence stays in its original form so older records and later language changes agree.
function GL.LocalizeEvidence(event)
    local text = event.evidence
    if type(text) ~= "string" then return nil end
    if event.kind == "trade" then
        return GL.LocalizeTradeReceipt and GL.LocalizeTradeReceipt(text) or text
    elseif event.kind == "kill" or event.kind == "aggression" or event.kind == "death" then
        local kind = text:match("^Journal de combat : dégâts reçus de ce joueur hostile %(([A-Z_]+)%)%.$")
        if kind and damageEvents[kind] then
            return L("Journal de combat : dégâts reçus de ce joueur hostile (%s)."):format(kind)
        end
        return L(text)
    elseif event.kind == "reputation" then
        if event.source == "emote" then
            local positive = text:match("^Geste amical envoyé : /([a-z]+)$")
            local negative = text:match("^Geste négatif envoyé : /([a-z]+)$")
            if positive then return L("Geste amical envoyé : /%s"):format(positive) end
            if negative then return L("Geste négatif envoyé : /%s"):format(negative) end
        elseif text == "Avis personnel" then return L("Avis personnel") end
    end
    return text
end

local function bool(fn, ...)
    return GL.Clean(GL.Safe(fn, ...), "boolean")
end

local function hasFlag(value, bit)
    local flags = GL.Clean(value, "number")
    return flags and flags >= 0 and flags <= 4294967295 and flags % 1 == 0
        and flags % (bit * 2) >= bit
end

local function hostileFlags(value) return hasFlag(value, COMBATLOG_OBJECT_REACTION_HOSTILE or 64) end

local function playerGUID()
    return GL.Clean(GL.Safe(UnitGUID, "player"), "string")
end

local function enabled()
    -- No documented duel-state getter exists. Preserve suppression throughout a
    -- long fight, but an ignored request must expire once ordinary combat ends.
    -- ponytail: an unconfirmed duel idle beyond this deadline is indistinguishable
    -- from an ignored request; confirmed boundary events remain latched until finish.
    if duel and duelPendingUntil and GL.Now() > duelPendingUntil
        and bool(UnitAffectingCombat, "player") == false then duel, duelPendingUntil = false, nil end
    return GL.db and GL.Settings().pvpTracking and not duel and not GL.IsPvPInstance()
end

local function combatSession()
    if fight then return fight end
    if lastFight and GL.Now() - lastFight.endedAt <= 3 then return lastFight end
end

local function units()
    local out = { "target", "focus", "mouseover" }
    for unit in pairs(plates) do out[#out + 1] = unit end
    return out
end

local function nextID(kind)
    serial = serial + 1
    return session .. ":" .. kind .. ":" .. serial
end

local function identityForGUID(guid, name, encounter)
    if not guid or #guid > 128 or not guid:match("^Player%-%w") or guid == playerGUID() then return nil end
    local token = GL.Clean(GL.Safe(UnitTokenFromGUID, guid), "string")
    local visible = token and GL.Identity(token)
    if visible and visible.guid == guid then return visible end
    for _, unit in ipairs(units()) do
        local identity = GL.Identity(unit)
        if identity and identity.guid == guid then return identity end
    end
    local f = encounter or combatSession()
    for _, enemy in pairs(f and f.enemies or {}) do
        if enemy.identity.guid == guid then return enemy.identity end
    end
    -- Recap names can be Given-Realm, not Forever's Given Family.
    name = name or GL.Clean(GL.Safe(UnitNameFromGUID, guid), "string")
    if name and not name:find(" ", 1, true) then name = name:match("^[^%-]+") end
    local identity = GL.IdentityFromName(name, nil, guid)
    if identity and identity.guild then return identity end
    return GL.Get("guid:" .. guid) or identity
end

-- Pet GUIDs carry no owner ID. Use an explicit summon or the native UnitOwner
-- tooltip line. Matching by a pet name would confuse two hunters with the same pet.
local function rememberPet(guid, owner, mine)
    if not petOwners[guid] then
        local oldest = petSlots[nextPetSlot]
        if oldest then petOwners[oldest] = nil end
        petSlots[nextPetSlot] = guid
        nextPetSlot = nextPetSlot % 64 + 1
    end
    petOwners[guid] = { owner = owner, mine = mine, at = GL.Now() }
end

local function petOwner(guid, unit, encounter)
    if not guid or not (guid:match("^Pet%-") or guid:match("^Creature%-")) then return end
    local cached = petOwners[guid]
    local age = cached and GL.Now() - cached.at
    -- ponytail: bound ownership lookups to 64 recent units; failed reads are
    -- retried after one second as nameplates and tooltip data arrive asynchronously.
    if age and age >= 0 and age < ((cached.owner or cached.mine) and 120 or 1) then return cached.owner end
    local info = C_TooltipInfo
    unit = unit or GL.Clean(GL.Safe(UnitTokenFromGUID, guid), "string")
    local tip = info and (unit and GL.Safe(info.GetUnit, unit) or GL.Safe(info.GetHyperlink, "unit:" .. guid))
    local lines = type(tip) == "table" and GL.Clean(tip.guid, "string") == guid and GL.Clean(tip.lines, "table")
    local ownerType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.UnitOwner
    local owner
    for _, line in ipairs(lines or {}) do
        line = GL.Clean(line, "table")
        if line and ownerType and GL.Clean(line.type, "number") == ownerType then
            owner = identityForGUID(GL.Clean(line.guid, "string"), nil, encounter)
            if owner then break end
        end
    end
    rememberPet(guid, owner)
    return owner
end

local function petSource(guid, flags)
    return guid and (guid:match("^Pet%-") or petOwners[guid]
        or (guid:match("^Creature%-") and hasFlag(flags, COMBATLOG_OBJECT_CONTROL_PLAYER or 256)))
end

local function attacker(guid, name, flags, encounter)
    local direct = identityForGUID(guid, name, encounter)
    if direct then return direct end
    if petSource(guid, flags) then return petOwner(guid, nil, encounter), true end
end

-- Only count identified players engaged with us. A pet uses its owner's GUID.
-- A recap after death cannot supply the player's health when combat began.
local function observeOpponent(f, guid, level, live)
    if not f or not guid or not guid:match("^Player%-%w") then return end
    if not f.combatants then
        f.combatants, f.opponentCount = {}, 0
        if live then
            local hp = GL.Clean(GL.Safe(UnitHealth, "player"), "number")
            local max = GL.Clean(GL.Safe(UnitHealthMax, "player"), "number")
            if hp and max and hp > 0 and hp <= max and max < math.huge then
                f.firstHealth = math.floor(100 * (hp / max) + 0.5)
            end
            f.observerLevel = GL.Clean(GL.Safe(UnitLevel, "player"), "number")
        end
    end
    if not f.combatants[guid] then
        f.opponentCount = f.opponentCount + 1
        f.combatants[guid] = true
    end
    if level and level > 0 and level < math.huge then f.combatants[guid] = level end
end

local function combatSnapshot(f, identity, viaPet, credit)
    if not f or not f.combatants then return end
    local level = identity.guid and f.combatants[identity.guid]
    local snapshot = { healthPct = f.firstHealth, playerLevel = f.observerLevel, opponentLevel = level,
        opponents = f.opponentCount, pve = f.npcPressure, pet = viaPet }
    local opening = f.opening
    if opening and opening.guid == identity.guid and not opening.defeated and not (credit and f.endedAt) then
        snapshot.opener, snapshot.hadGrudge, snapshot.encounterId = opening.opener, opening.hadGrudge, f.id
        snapshot.priorDeath = opening.priorDeath
    end
    return snapshot
end

local function creditKill(identity, confidence, evidence, native)
    if not enabled() or not identity then return end
    local key = identity.guid or identity.key
    local now, previous = GL.Now(), recentCredits[key] or (identity.alias and recentCredits[identity.alias])
    local f = combatSession()
    if previous and f and f.opening and f.opening.guid == identity.guid and previous.fightId ~= f.id then
        previous = nil -- a freshly witnessed opening proves this is a different encounter
    end
    -- The native event identifies each kill, even without a visible resurrection.
    -- Coalesce its other evidence for ten seconds and same-tick native repeats.
    if previous and now >= previous.at and now - previous.at <= 10
        and not (native and previous.nativeAt and now > previous.nativeAt) then
        if identity.guid and previous == recentCredits[identity.alias] then
            GL.Remember(identity)
            recentCredits[identity.alias], recentCredits[key] = nil, previous
        end
        if confidence == "confirmed" and previous.event.confidence == "probable" and not previous.event.voided then
            GL.ConfirmKill(identity, previous.event, evidence)
        end
        if native then previous.nativeAt = now end
        return
    end
    observeOpponent(f, identity.guid)
    -- A late PARTY_KILL alone cannot put a new defeat in a completed fight.
    local record, event = GL.RecordPvP(identity, "kill", confidence, evidence, nextID("kill"), combatSnapshot(f, identity, nil, true))
    if event then
        recentCredits[key] = { at = now, nativeAt = native and now, event = event, fightId = f and f.id }
        if f and f.opening and f.opening.guid == identity.guid then f.opening.defeated = true end
    end
    return record
end

-- Forever exposes this native event independently of restricted combat-log access.
-- https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua
local function killingBlow(src, dst, name, evidence, native)
    src, dst = GL.Clean(src, "string"), GL.Clean(dst, "string")
    if not src or not dst or not dst:match("^Player%-%w") or not enabled() then return end
    local me = playerGUID()
    if not me or dst == me then return end
    if src ~= me then
        if src:match("^Player%-%w") then
            local f, previous = combatSession(), recentCredits[dst]
            local enemy = f and f.enemies["guid:" .. dst]
            if enemy then enemy.otherKiller = true end
            local age = previous and GL.Now() - previous.at
            -- A later fight against the same GUID need not concern the death we
            -- inferred. Retract only while the corpse/credit was just observed.
            if age and age >= 0 and age <= 2 and previous.event.confidence == "probable" and not previous.event.voided
                and not (f and f.opening and f.opening.guid == dst and previous.fightId ~= f.id) then
                GL.VoidPvP("guid:" .. dst, previous.event, false, "other-killer")
            end
            return
        end
        if src ~= GL.Clean(GL.Safe(UnitGUID, "pet"), "string") then return end
        evidence = "Votre familier a porté le coup fatal à ce joueur."
    end
    creditKill(identityForGUID(dst, name), "confirmed", evidence, native)
end

local function recordAggression(f, identity, confidence, evidence, viaPet)
    if not f or not identity or not enabled() then return end
    f.aggressions = f.aggressions or {}
    local key = identity.guid or identity.key
    if f.aggressions[key] or (identity.alias and f.aggressions[identity.alias]) then return end
    f.aggressions[key] = true
    GL.RecordAggression(identity, confidence, evidence, f.id .. ":attack:" .. key, combatSnapshot(f, identity, viaPet))
end

local function recentAttackers(f, age)
    local candidates, now = {}, GL.Now()
    for key, enemy in pairs(f.enemies) do
        if enemy.dead == false and enemy.aliveAt and now - enemy.aliveAt <= age
            and enemy.targetingMeAt and now - enemy.targetingMeAt <= age then
            candidates[key] = enemy.identity
        end
    end
    for key, attack in pairs(f.petAttackers or {}) do
        if now - attack.at <= age then candidates[key] = attack.owner end
    end
    return candidates
end

local function unresolvedAttack(f)
    return f.pve or (f.unknownPets and next(f.unknownPets))
end

local function observeHealth()
    local f = fight
    if not enabled() or not f then return end
    if deathHandled or bool(UnitIsDeadOrGhost, "player") ~= false then
        f.pendingAggression = nil
        return
    end
    local health = GL.Clean(GL.Safe(UnitHealth, "player"), "number")
    local maximum = GL.Clean(GL.Safe(UnitHealthMax, "player"), "number")
    local now = GL.Now()
    if health and maximum and f.health and f.maxHealth == maximum and f.healthAt
        and now - f.healthAt <= 2 and health < f.health and not unresolvedAttack(f) and not f.damageLogged then
        if not f.opening then f.idleOpponents = nil end
        local candidates = recentAttackers(f, 2)
        if next(candidates) and not f.pendingAggression then
            f.pendingAggression = { candidates = candidates, at = now }
        end
    end
    f.health, f.maxHealth, f.healthAt = health, maximum, now
end

local function tryAggression()
    local f = combatSession()
    local pending = f and f.pendingAggression
    if not pending then return end
    if deathHandled or bool(UnitIsDeadOrGhost, "player") ~= false then
        f.pendingAggression = nil
        return
    end
    local age = GL.Now() - pending.at
    if age < 1 then return end -- give explicit combat-log evidence priority
    f.pendingAggression = nil
    if age <= 3 and not unresolvedAttack(f) and not f.damageLogged then
        local candidates = recentAttackers(f, 2)
        for key, identity in pairs(pending.candidates) do
            if candidates[key] then
                local pet = f.petAttackers and f.petAttackers[key]
                local evidence = pet and GL.Now() - pet.at <= 2 and "Votre santé a baissé pendant que le familier de ce joueur vous ciblait en combat."
                    or "Baisse de santé pendant que cet adversaire PvP en combat vous ciblait ; participation déduite, source de dégâts non confirmée."
                recordAggression(f, identity, "probable", evidence, pet and GL.Now() - pet.at <= 2)
            end
        end
    end
end

function T.Observe(unit, reuseObservation)
    if GL.IsPvPInstance() then return end
    local f = combatSession()
    if not unit then return end
    local identity = GL.Identity(unit, reuseObservation)
    local dead
    if idleOpponents and identity and identity.guid then
        local idle = bool(UnitAffectingCombat, unit) == false and bool(UnitIsDeadOrGhost, unit) == false
        idleOpponents[identity.guid] = idle and idleAt or nil
    end
    if identity then
        local key = identity.guid or identity.key
        local receipt = recentCredits[key]
        if receipt then
            dead = bool(UnitIsDeadOrGhost, unit)
            local now = GL.Now()
            if now < receipt.at or now - receipt.at > 10 then recentCredits[key] = nil
            elseif dead then receipt.observedDead, receipt.at = true, now
            elseif dead == false and receipt.observedDead then recentCredits[key] = nil end
        end
        local record = GL.Get(identity)
        local previousGuild = record and record.guild
        record = GL.RecordSeen(identity)
        if record and record.guild ~= previousGuild then GL.Emit("CHANGED", record) end
    end
    if not enabled() or not f or deathHandled then return end
    local hostile = bool(UnitCanAttack, "player", unit) == true
    local engaged = bool(UnitAffectingCombat, unit) == true
    local targetingMe = bool(UnitIsUnit, unit .. "target", "player") == true
    if not identity then
        if hostile and targetingMe and engaged and bool(UnitIsPlayer, unit) == false then
            local guid = GL.Clean(GL.Safe(UnitGUID, unit), "string")
            local controlled = bool(UnitPlayerControlled, unit)
            local owner = controlled and petOwner(guid, unit, f)
            if owner and bool(UnitIsPVP, "player") == true then
                observeOpponent(f, owner.guid, nil, true)
                if f.unknownPets then f.unknownPets[guid] = nil end
                f.petAttackers = f.petAttackers or {}
                f.petAttackers[owner.key] = { owner = owner, at = GL.Now() }
            elseif controlled and guid then
                f.unknownPets = f.unknownPets or {}
                f.unknownPets[guid] = true
            else
                f.pve = true
                if controlled == false and guid and guid:match("^Creature%-") then f.npcPressure = true end
            end
        end
        return
    end
    if not hostile then
        if engaged and not bool(UnitIsUnit, unit, "player") then f.otherCombatant = true end
        return
    end
    -- A duel can look hostile. Normal same-faction and unflagged encounters are
    -- never inferred; exact combat-log evidence still works for real FFA combat.
    local faction = GL.Clean(GL.Safe(UnitFactionGroup, "player"), "string")
    if not faction or not identity.faction or faction == identity.faction then return end
    if bool(UnitIsPVP, "player") ~= true or bool(UnitIsPVP, unit) ~= true then return end
    local enemy = f.enemies[identity.key]
    if not enemy and identity.guid and identity.alias then
        enemy = f.enemies[identity.alias]
        if enemy then f.enemies[identity.alias], f.enemies[identity.key] = nil, enemy end
    end
    if not enemy then
        if not fight or not engaged then return end
        if not targetingMe and bool(UnitIsUnit, unit, "target") ~= true then return end
        enemy = { identity = identity }
        f.enemies[identity.key] = enemy
    end
    enemy.identity = identity
    local now = GL.Now()
    if dead == nil then dead = bool(UnitIsDeadOrGhost, unit) end
    if dead == false then
        if engaged then
            if targetingMe then
                enemy.targetingMeAt = now
                observeOpponent(f, identity.guid, identity.level, true)
            end
            if bool(UnitIsUnit, unit, "target") == true then enemy.targetedAt = now end
        else enemy.targetingMeAt, enemy.targetedAt = nil, nil end
        if enemy.dead then
            enemy.signalAt, enemy.deadAt, enemy.credited, enemy.otherKiller = nil, nil, nil, nil
            if f.opening and f.opening.guid == identity.guid then f.opening.defeated = true end
            recentCredits[identity.guid or identity.key] = nil
            if identity.alias then recentCredits[identity.alias] = nil end
        end
        enemy.aliveAt, enemy.dead = now, false
    elseif dead == true and enemy.dead == false then
        enemy.dead, enemy.deadAt = true, now
    end
end

local function tryKills()
    local f = combatSession()
    if not enabled() or not f or f.otherCombatant or unresolvedAttack(f) then return end
    -- Honor is shared. Even a named honor line is not personal killing-blow proof.
    -- ponytail: only infer isolated solo encounters; crowded/group fights need CLE proof.
    local grouped = GL.Clean(GL.Safe(GetNumGroupMembers), "number")
    if grouped ~= 0 then return end
    local now, candidate, count = GL.Now(), nil, 0
    for _, enemy in pairs(f.enemies) do
        if enemy.aliveAt and now - enemy.aliveAt <= 6 then
            count = count + 1
            candidate = enemy
        end
    end
    if count ~= 1 or not candidate or candidate.credited or candidate.otherKiller then return end
    local e = candidate
    for _, attack in pairs(f.petAttackers or {}) do
        if attack.owner.guid ~= e.identity.guid and now - attack.at <= 6 then return end
    end
    if not e.deadAt or not e.signalAt or not e.targetingMeAt or not e.targetedAt then return end
    if now - e.deadAt < 1 or now - e.deadAt > 3 then return end
    if math.abs(e.signalAt - e.deadAt) > 2 or e.deadAt - e.aliveAt > 3 then return end
    if e.deadAt - e.targetingMeAt > 4 or e.deadAt - e.targetedAt > 4 then return end
    e.credited = true
    creditKill(e.identity, "probable", "Adversaire vu vivant puis mort, combat mutuel isolé et gain d'honneur concordant.")
end

-- Forever GlobalStrings, build 1.60.1.70938. Only the four named victories
-- report the points from this defeat. COMBATLOG_HONORAWARD also covers quests.
local honorFormats, honorRanks = {}, {}
local honorLines, honorSlots, nextHonorSlot = {}, {}, 1
local hasHonorTemplates = COMBATLOG_HONORGAIN or COMBATLOG_HONORGAIN_NO_RANK
    or COMBATLOG_HONORGAIN_EXHAUSTION1 or COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1
local function addHonorFormat(fmt, pointsArg)
    if type(fmt) ~= "string" then return end
    -- Expand the client's Russian plurals and Korean particles once at load.
    local first, last, choices = fmt:find("|4([^;]+);")
    if not first then first, last, choices = fmt:find("|1([^;]+;[^;]+);") end
    if first then
        for word in choices:gmatch("[^:;]+") do
            addHonorFormat(fmt:sub(1, first - 1) .. word .. fmt:sub(last + 1), pointsArg)
        end
        return
    end
    local pattern, capture, cursor, count = "^", {}, 1, 0
    while cursor <= #fmt do
        local at = fmt:find("%", cursor, true) or #fmt + 1
        pattern = pattern .. fmt:sub(cursor, at - 1):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
        if at > #fmt then break end
        local token, position, kind = fmt:sub(at):match("^(%%(%d*%$?)([sd]))")
        if token then
            count = count + 1
            local arg = position == "" and count or tonumber(position:match("^(%d+)%$$"))
            if not arg or capture[arg] or (kind == "d") ~= (arg == pointsArg) then return end
            capture[arg] = count
            pattern = pattern .. (kind == "d" and "([0-9]+)" or "(.-)")
            cursor = at + #token
        elseif fmt:sub(at, at + 1) == "%%" then
            pattern, cursor = pattern .. "%%", at + 2
        else return end
    end
    if capture[1] and capture[pointsArg] and (pointsArg == 2 or capture[2]) then
        honorFormats[#honorFormats + 1] = { pattern = pattern .. "$", name = capture[1],
            points = capture[pointsArg], rank = pointsArg == 3 and capture[2] }
    end
end
addHonorFormat(COMBATLOG_HONORGAIN, 3)
addHonorFormat(COMBATLOG_HONORGAIN_NO_RANK, 2)
addHonorFormat(COMBATLOG_HONORGAIN_EXHAUSTION1, 3)
addHonorFormat(COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1, 2)
-- Faction leaders can also award honor. A known player rank identifies the
-- source without requiring a visible unit. Rank 19 is the special NPC rank.
for rank = 0, 19 do
    for faction = 0, 1 do
        local key = ("PVP_RANK_%d_%d"):format(rank, faction)
        for _, label in pairs({ _G[key], _G[key .. "_FEMALE"] }) do
            if label ~= "" then honorRanks[label] = rank == 19 and "leader" or "player" end
        end
    end
end
if PVP_RANK_LEADER then honorRanks[PVP_RANK_LEADER] = "leader" end

local function recordHonorReceipt(message, lineID, f)
    local inside, kind = GL.Safe(IsInInstance)
    if not worldActive or inside ~= false or kind ~= "none" or #message > 2048 then return end
    lineID = GL.Clean(lineID, "number")
    if not (lineID and lineID > 0 and lineID < math.huge and lineID == math.floor(lineID)) then lineID = nil end
    if lineID and honorLines[lineID] then return end
    for _, format in ipairs(honorFormats) do
        local fields = { message:match(format.pattern) }
        local victim = fields[format.name]
        if victim then
            local points = tonumber(fields[format.points])
            local rank = honorRanks[format.rank and fields[format.rank]]
            if not points or points > 2147483647 or rank == "leader" then return end
            victim = victim:match("^|c%x%x%x%x%x%x%x%x(.-)|r$") or victim:match("^|cn[%w_]+:(.-)|r$") or victim
            local linkName = victim:match("^|Hplayer:([^:|]+)[^|]*|h%[[^|]+%]|h$")
            -- Some hyperlinks qualify a complete regional name with -Realm.
            -- A single Given-Realm is still an incomplete regional identity.
            if linkName then linkName = linkName:match("^([^ %-]+ [^ %-]+)%-[^ %-]+$") or linkName end
            victim = linkName or victim
            if #victim > 160 or not victim:match("^[A-Za-z\128-\255][A-Za-z\128-\255'%-]* ?[A-Za-z\128-\255'%-]*$")
                or victim:sub(-1) == " "
                or GL.ContainsControlOrMarkup(victim) then return end
            local name = GL.IdentityFromName(victim)
            local candidate = name and GL.Get(name)
            local verified, ambiguous = linkName or rank == "player", name and GL.db.aliases[name.alias] == false
            local function observe(identity)
                if not identity or identity.fullName ~= victim then return end
                verified = true
                if candidate and candidate.guid and identity.guid and candidate.guid ~= identity.guid then ambiguous = true end
                if not candidate or identity.guid then candidate = identity end
            end
            for _, enemy in pairs(f and f.enemies or {}) do observe(enemy.identity) end
            for _, unit in ipairs(units()) do
                local first, last = GL.Safe(UnitName, unit)
                if type(first) == "string" and (first == victim or
                    (type(last) == "string" and first .. " " .. last == victim)) then
                    -- An NPC or our own character with the printed name makes the source unsafe.
                    if bool(UnitIsPlayer, unit) ~= true or bool(UnitIsUnit, unit, "player") == true then return end
                    observe(GL.Identity(unit))
                end
            end
            if not verified then return end
            local first, last = GL.Safe(UnitName, "player")
            if name and type(first) == "string" and (first == victim or (type(last) == "string" and first .. " " .. last == victim)) then return end
            -- A bare given name is never a unique key on Forever. A client with
            -- no usable lineID delivers one frame event per award; identical text
            -- and timestamps can legitimately describe two separate defeats.
            local identity = name and not ambiguous and (candidate or name) or nil
            if not GL.RecordHonor(identity, points) then return end
            if lineID then
                -- ponytail: remember the last 256 awards; extend this window
                -- if a client begins replaying older native chat lines.
                local old = honorSlots[nextHonorSlot]
                if old then honorLines[old] = nil end
                honorSlots[nextHonorSlot], honorLines[lineID] = lineID, true
                nextHonorSlot = nextHonorSlot % 256 + 1
            end
            return identity
        end
    end
end

function T.OnHonorMessage(message, lineID)
    message = GL.Clean(message, "string")
    if not enabled() or not message then return end
    local f = combatSession()
    if hasHonorTemplates then
        local identity = recordHonorReceipt(message, lineID, f)
        local enemy = identity and f and (f.enemies[identity.key] or f.enemies[identity.alias])
        if enemy then enemy.signalAt = GL.Now() tryKills() end
        return
    end
    -- Compatibility with clients missing all named formats: this old signal
    -- can support an isolated probable kill but cannot establish any points.
    if not f then return end
    for _, enemy in pairs(f.enemies) do
        local name = enemy.identity.fullName
        -- Match the whole known identity; never use only a shared first name.
        if name and enemy.identity.surname and enemy.identity.surname ~= "" then
            local a, b = message:find(name, 1, true)
            if a and (a == 1 or not message:sub(a - 1, a - 1):match("[%w_]"))
                and (b == #message or not message:sub(b + 1, b + 1):match("[%w_]")) then
                enemy.signalAt = GL.Now()
            end
        end
    end
    tryKills()
end

function T.OnHonorCount()
    local count = GL.Clean(GL.Safe(GetPVPSessionStats), "number")
    local increased = count and honorBaseline and count > honorBaseline
    honorBaseline = count or honorBaseline
    if not enabled() or not increased then return end
    local f = combatSession()
    if not f then return end
    for _, enemy in pairs(f.enemies) do enemy.signalAt = GL.Now() end
    tryKills()
end

-- Public Forever API; no combat-log access or protected-data workaround required.
-- https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/DeathRecapDocumentation.lua
local function readRecap(death)
    local events = C_DeathRecap and GL.Safe(C_DeathRecap.GetRecapEvents)
    if type(events) ~= "table" then return end
    local rows, newest = {}, nil
    for _, event in ipairs(events) do
        event = GL.Clean(event, "table")
        if event then
            local kind = GL.Clean(event.event, "string")
            local stamp = GL.Clean(event.timestamp, "number")
            -- Clients can expose timestamps in session time rather than server time.
            if stamp and death.uptime and math.abs(stamp - death.uptime) < math.abs(stamp - death.at) then
                stamp = death.at + (stamp - death.uptime)
            end
            local amount = GL.Clean(event.amount, "number")
            if stamp and stamp >= death.at - 10 and stamp <= death.at + 1
                and (not death.previousAt or stamp > death.previousAt)
                and (kind == "SPELL_INSTAKILL" or (damageEvents[kind] and amount and amount > 0 and amount < math.huge)) then
                newest = math.max(newest or stamp, stamp)
                rows[#rows + 1] = {
                    guid = GL.Clean(event.sourceGUID, "string"), name = GL.Clean(event.sourceName, "string"),
                    flags = GL.Clean(event.sourceFlags, "number"), overkill = GL.Clean(event.overkill, "number"),
                    kind = kind, at = stamp, health = GL.Clean(event.currentHP, "number"),
                }
            end
        end
    end
    if newest and newest >= death.at - 2 and (not lastRecapStamp or newest > lastRecapStamp) then
        return rows, newest
    end
end

local function resolveDeath()
    local death = pendingDeath
    if not death then return end
    if not enabled() then pendingDeath = nil return end
    local rows, stamp = readRecap(death)
    if not rows and C_DeathRecap and type(C_DeathRecap.GetRecapEvents) == "function"
        and GL.Now() - death.at < 2 then return end
    local participants, lethal, lethalPet = death.candidates, death.confirmed, death.pet
    local petSources
    if rows then
        participants = {} -- explicit sources replace, rather than extend, guesses
        local otherLethal, waitingForOwner
        petSources = {}
        for _, row in ipairs(rows) do
            local identity, viaPet
            if hostileFlags(row.flags) then identity, viaPet = attacker(row.guid, row.name, row.flags, death.fight) end
            local fatal = row.kind == "SPELL_INSTAKILL" or (row.overkill and row.overkill >= 0 and row.overkill < math.huge)
                or (row.health == 0 and row.at == stamp)
            if identity then
                local key = identity.guid or identity.key
                participants[key] = identity
                if viaPet then petSources[key] = true end
                observeOpponent(death.fight, identity.guid)
                if fatal and not lethal then lethal, lethalPet = identity, viaPet end
            else
                if viaPet then waitingForOwner = true end
                if fatal then otherLethal = true end
            end
        end
        for key, identity in pairs(participants) do
            local viaPet = petSources[key]
            recordAggression(death.fight, identity, "confirmed", viaPet and "Le récapitulatif attribue les dégâts au familier de ce joueur."
                or "Récapitulatif de mort : dégâts reçus de ce joueur hostile.", viaPet)
        end
        if waitingForOwner and C_TooltipInfo and GL.Now() - death.at < 2 then return end
        lastRecapStamp = stamp
        if otherLethal and not lethal then participants = {} end
    end
    pendingDeath = nil
    if lethal then participants[lethal.guid or lethal.key] = lethal end
    -- ponytail: reuse per-person death counters for participation in one fatal attack.
    -- Only an explicit lethal hit is confirmed; other participants remain probable.
    for _, identity in pairs(participants) do
        local confirmed = lethal and (identity.guid or identity.key) == (lethal.guid or lethal.key)
        local pet = death.fight.petAttackers and death.fight.petAttackers[identity.key]
        local evidence = confirmed and (lethalPet and "Le familier de ce joueur vous a porté le coup fatal."
            or "Dégâts létaux explicitement attribués à ce joueur.")
            or (not rows and pet and death.at - pet.at <= 5 and "Le familier de ce joueur vous ciblait en combat juste avant votre mort. Le coup fatal reste incertain.")
            or "Participation probable à l'attaque ayant causé votre mort ; le coup fatal n'est pas attribué à ce joueur."
        local viaPet = confirmed and lethalPet or (petSources and petSources[identity.guid or identity.key])
            or (not rows and pet and death.at - pet.at <= 5)
        GL.RecordPvP(identity, "death", confirmed and "confirmed" or "probable", evidence, death.id, combatSnapshot(death.fight, identity, viaPet))
    end
end

function T.OnDeath(confirmed, viaPet)
    if pendingDeath and confirmed then pendingDeath.confirmed, pendingDeath.pet = confirmed, viaPet return end
    if deathHandled then return end
    -- Freeze the encounter before waiting for a delayed recap. Later sightings cannot join it.
    deathHandled = true
    local f, now = combatSession(), GL.Now()
    if enabled() then
        local candidates = {}
        if f and not unresolvedAttack(f) then
            if f.damageLogged then
                for _, enemy in pairs(f.enemies) do
                    if enemy.damageAt and now - enemy.damageAt <= 5 then
                        candidates[enemy.identity.guid or enemy.identity.key] = enemy.identity
                    end
                end
            else
                for _, identity in pairs(recentAttackers(f, 5)) do candidates[identity.guid or identity.key] = identity end
            end
        end
        pendingDeath = { at = now, previousAt = lastDeathAt, id = nextID("death"), candidates = candidates,
            uptime = GL.Clean(GL.Safe(GetTime), "number"), confirmed = confirmed, pet = viaPet,
            fight = f or { id = nextID("fight"), enemies = {} } }
        resolveDeath()
    end
    lastDeathAt = now
end

-- ponytail: require both players on visible unit tokens, idle within two
-- seconds. A bidirectional client encounter feed could cover unseen ambushes.
local function observeOpening(sub, args, me, src, dst, srcName, dstName, srcFlags, dstFlags)
    local idle = fight and fight.idleOpponents or idleOpponents
    if not idle or not next(idle) or not worldActive or deathHandled then return end
    local pet = GL.Clean(GL.Safe(UnitGUID, "pet"), "string")
    local aura = sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_APPLIED_DOSE" or sub == "SPELL_AURA_REFRESH"
    if aura and GL.Clean(args[15], "string") == "BUFF" then return end
    if priorActions[sub] and src and src == dst then return end
    local function ourUnit(guid)
        if not guid then return false end
        if guid == me or guid == pet then return true end
        local summoned = petOwners[guid]
        local age = summoned and GL.Now() - summoned.at
        return age and age >= 0 and age < 120 and summoned.mine
    end
    local ours, theirs = ourUnit(src), ourUnit(dst)
    if not ours and not theirs then
        if not src or not dst then
            if fight then fight.idleOpponents = nil end
            idleOpponents = nil
            return
        end
        idle[src], idle[dst] = nil, nil
        local fromPet, toPet = petOwners[src], petOwners[dst]
        if fromPet and fromPet.owner then idle[fromPet.owner.guid] = nil end
        if toPet and toPet.owner then idle[toPet.owner.guid] = nil end
        return
    end
    local amountAt = sub == "SWING_DAMAGE" and 12 or 15
    local amount = GL.Clean(args[amountAt], "number")
    if amount == 0 and (sub == "SWING_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "SPELL_DAMAGE") then return end
    if not fight then
        fight, lastFight = { enemies = {}, id = nextID("fight") }, nil
    end
    local f = fight
    -- Only the earliest personal health damage is eligible. Unknown/indirect
    -- first hits close the window instead of letting later retaliation claim it.
    f.idleOpponents, idleOpponents = nil, nil
    local opponentGUID, opponentName, flags = src, srcName, srcFlags
    if ours then opponentGUID, opponentName, flags = dst, dstName, dstFlags end
    if (sub ~= "SWING_DAMAGE" and sub ~= "RANGE_DAMAGE" and sub ~= "SPELL_DAMAGE")
        or not amount or not (amount > 0 and amount < math.huge) or ours and theirs
        or not hostileFlags(flags) or unresolvedAttack(f) or f.otherCombatant or f.pendingAggression
        or GL.Clean(GL.Safe(GetNumGroupMembers), "number") ~= 0 then return end
    local inside, kind = GL.Safe(IsInInstance)
    if inside ~= false or kind ~= "none" then return end
    local identity = attacker(opponentGUID, opponentName, flags, f)
    local at = identity and idle[identity.guid]
    local now = GL.Now()
    if not at or now < at or now - at > 2 then return end
    for guid in pairs(f.combatants or {}) do if guid ~= identity.guid then return end end
    local relation = GL.Relation(GL.Remember(identity))
    local opener, hadGrudge = ours and "player" or "opponent", relation == "warning" or relation == "enemy"
    local event = GL.RecordOpening(identity, opener, hadGrudge, f.id)
    if event then
        f.opening = {guid = identity.guid, opener = opener, hadGrudge = hadGrudge, priorDeath = event.priorDeath}
        observeOpponent(f, identity.guid, identity.level, true)
    end
end

function T.OnCombatLog(...)
    if not enabled() then return end
    local args
    if select("#", ...) > 0 then args = { ... }
    else
        local getter = (C_CombatLog and C_CombatLog.GetCurrentEventInfo) or CombatLogGetCurrentEventInfo
        -- select preserves nil payload slots, including concealed player names.
        args = type(getter) == "function" and { select(2, pcall(getter)) } or {}
    end
    local sub = GL.Clean(args[2], "string")
    local src = GL.Clean(args[4], "string")
    local dst = GL.Clean(args[8], "string")
    local me = playerGUID()
    if not sub or not me then
        idleOpponents = nil
        if fight then fight.idleOpponents = nil end
        return
    end
    local srcName, dstName = GL.Clean(args[5], "string"), GL.Clean(args[9], "string")
    local srcFlags, dstFlags = args[6], args[10]
    if (fight and fight.idleOpponents or idleOpponents) and (damageEvents[sub] or sub == "SPELL_INSTAKILL"
        or priorActions[sub] and (hostileFlags(srcFlags) or hostileFlags(dstFlags))) then
        -- A witnessed hostile cast, control effect, or miss may precede damage.
        observeOpening(sub, args, me, src, dst, srcName, dstName, srcFlags, dstFlags)
    end
    if sub == "SPELL_SUMMON" and src and src:match("^Player%-") and (src == me or hostileFlags(srcFlags))
        and dst and (dst:match("^Pet%-") or dst:match("^Creature%-")) then
        if src == me then rememberPet(dst, nil, true)
        else
            local owner = identityForGUID(src, srcName)
            if owner then rememberPet(dst, owner) end
        end
    elseif sub == "PARTY_KILL" then
        killingBlow(src, dst, dstName, "Journal de combat : coup fatal personnel (PARTY_KILL).")
    elseif dst ~= me and hostileFlags(dstFlags) and (damageEvents[sub] or sub == "SPELL_INSTAKILL") then
        if src == me and fight and not deathHandled then
            observeOpponent(fight, dst, nil, true)
            if dst and dst:match("^Creature%-") and hasFlag(dstFlags, COMBATLOG_OBJECT_CONTROL_NPC or 512)
                and not petOwners[dst] then fight.npcPressure = true end
        end
        -- Zero overkill is ambiguous across clients. Require a strictly positive
        -- surplus here; PARTY_KILL can still confirm an exact-zero killing blow.
        local amountAt = sub == "SWING_DAMAGE" and 12 or 15
        local amount, excess = GL.Clean(args[amountAt], "number"), GL.Clean(args[amountAt + 1], "number")
        if sub == "SPELL_INSTAKILL" or (sub ~= "ENVIRONMENTAL_DAMAGE" and amount and excess
            and excess > 0 and excess <= amount and amount < math.huge) then
            killingBlow(src, dst, dstName, "Le journal de combat vous attribue les dégâts mortels.")
        end
    -- Only health-damage payloads contain overkill. LEECH/DRAIN use powerType in
    -- that position, and durability damage is not damage to the player either.
    elseif dst == me and (damageEvents[sub] or sub == "SPELL_INSTAKILL") then
        local identity, viaPet = attacker(src, srcName, srcFlags)
        local f = combatSession()
        if not identity and f then
            f.pve = true
            if src and src:match("^Creature%-") and hasFlag(srcFlags, COMBATLOG_OBJECT_CONTROL_NPC or 512)
                and hostileFlags(srcFlags) and not viaPet then f.npcPressure = true end
        end
        local hostile = hostileFlags(srcFlags)
        if identity and hostile and not deathHandled then
            -- Initial damage can arrive before PLAYER_REGEN_DISABLED.
            if not fight then fight = { enemies = {}, id = nextID("fight") } end
            f = fight
            observeOpponent(f, identity.guid, nil, true)
            recordAggression(f, identity, "confirmed", viaPet and "Le journal de combat attribue les dégâts au familier de ce joueur."
                or "Journal de combat : dégâts reçus de ce joueur hostile (" .. sub .. ").", viaPet)
            local enemy = f.enemies[identity.key] or { identity = identity }
            enemy.damageAt = GL.Now()
            f.enemies[identity.key] = enemy
        end
        -- ponytail: once incoming damage is logged, use its explicit source for this
        -- encounter. Guessing from health could blame the selected player instead.
        if f then f.damageLogged, f.pendingAggression = true, nil end
        local overkill = GL.Clean(args[sub == "SWING_DAMAGE" and 13 or 16], "number")
        if identity and hostile and (sub == "SPELL_INSTAKILL" or (overkill and overkill >= 0)) then
            T.OnDeath(identity, viaPet)
        end
    end
end

local groupTimers = {}
local function groupTime(timer, now)
    return math.max(0, math.floor((now or GL.Now()) - timer.started))
end
local function stopGroupTime(now, online)
    for id, timer in pairs(groupTimers) do
        if not online or not online[id] then
            timer.event.seconds = GL.GroupDuration(timer.event, now)
            groupTimers[id] = nil
        end
    end
end
function GL.GroupDuration(event, now)
    local seconds = GL.Clean(event.seconds, "number") or 0
    local timer = event.sessionId and groupTimers[event.sessionId]
    return (seconds >= 0 and seconds < math.huge and seconds or 0) + (timer and timer.event == event and groupTime(timer, now) or 0)
end

function T.ScanGroup()
    local now = GL.Now()
    if not worldActive or not GL.db or not GL.Settings().groupTracking or GL.IsPvPInstance() then stopGroupTime(now) return end
    local size = GL.Clean(GL.Safe(GetNumGroupMembers), "number")
    local me = playerGUID()
    if size == nil or not me then stopGroupTime(now) return end
    if type(GL.db.tracker) ~= "table" then GL.db.tracker = {} end
    local state = GL.db.tracker
    if type(state.groups) ~= "table" then state.groups = {} end
    if type(state.serial) ~= "number" or state.serial ~= state.serial or state.serial < 0 or state.serial == math.huge then state.serial = 0 end
    local previous, current = type(state.groups[me]) == "table" and state.groups[me] or {}, {}
    local identified, online = 0, {}
    local raid = bool(IsInRaid) == true
    if size > 0 then
        local selfOnline = GL.Safe(UnitIsConnected, "player") == true
        for i = 1, raid and math.min(size, 40) or 4 do
            local unit = (raid and "raid" or "party") .. i
            local identity = GL.Identity(unit)
            if identity then
                identified = identified + 1
                local record = GL.Get(identity)
                local id = previous[identity.key] or (record and previous[record.key])
                record = GL.RecordSeen(identity)
                if record then
                    if not id then
                        state.serial = state.serial + 1
                        id = me .. ":group:" .. state.serial
                        GL.RecordGroup(identity, id, GL.Where())
                    end
                    current[record.key] = id
                    if selfOnline and GL.Safe(UnitIsConnected, unit) == true then
                        online[id] = true
                        if not groupTimers[id] then
                            -- A session may predate this login. Accumulate only intervals observed online.
                            for n = #record.history, 1, -1 do
                                local entry = record.history[n]
                                if type(entry) == "table" and entry.kind == "grouped" and entry.sessionId == id then
                                    groupTimers[id] = { event = entry, started = now }
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if identified < math.max(0, size - 1) then
        -- Roster tokens can be incomplete during login or a raid transition.
        for key, id in pairs(previous) do if not current[key] then current[key] = id end end
    end
    state.groups[me] = current
    stopGroupTime(now, online)
end

function T.Poll()
    if not GL.db then return end
    local inside, kind = GL.Safe(IsInInstance)
    if kind == "pvp" or kind == "arena" then
        -- Discard pending inference too, so a late recap cannot cross the boundary.
        fight, lastFight, pendingDeath, idleOpponents = nil, nil, nil, nil
        return
    end
    resolveDeath()
    if openingFeed and not fight then
        if worldActive and GL.Settings().pvpTracking and not duel and not deathHandled and inside == false and kind == "none"
            and bool(UnitAffectingCombat, "player") == false and bool(UnitIsDeadOrGhost, "player") == false then
            idleOpponents, idleAt = {}, GL.Now()
        else idleOpponents = nil end
    end
    for _, unit in ipairs(units()) do T.Observe(unit, true) end
    observeHealth()
    tryAggression()
    tryKills()
    local now = GL.Now()
    for key, credit in pairs(recentCredits) do if now < credit.at or now - credit.at > 10 then recentCredits[key] = nil end end
end

function T.HandleEvent(event, ...)
    if not GL.db then return end
    local arg, second = ...
    if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
        worldActive = false
        idleOpponents = nil
        if fight then fight.idleOpponents, fight.opening = nil, nil end
        stopGroupTime(GL.Now())
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if event == "PLAYER_ENTERING_WORLD" then worldActive = true end
        recentCredits, idleOpponents = {}, nil
        petOwners, petSlots, nextPetSlot = {}, {}, 1
        fight, lastFight, plates, duel, duelPendingUntil, pendingDeath = nil, nil, {}, false, nil, nil
        honorBaseline = GL.Clean(GL.Safe(GetPVPSessionStats), "number")
        deathHandled = bool(UnitIsDeadOrGhost, "player") == true
        local visible = C_NamePlate and GL.Safe(C_NamePlate.GetNamePlates)
        for _, plate in ipairs(type(visible) == "table" and visible or {}) do
            local unit = GL.Clean(plate.namePlateUnitToken, "string")
                or (plate.UnitFrame and GL.Clean(plate.UnitFrame.unit, "string"))
            if unit then plates[unit] = true end
        end
        if not deathHandled and enabled() and bool(UnitAffectingCombat, "player") == true then
            fight = { enemies = {}, id = nextID("fight") }
            T.Poll()
        end
        T.ScanGroup()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_CONNECTION"
        or event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then T.ScanGroup()
    elseif event == "DUEL_REQUESTED" or event == "DUEL_TO_THE_DEATH_REQUESTED" or event == "DUEL_INBOUNDS" or event == "DUEL_OUTOFBOUNDS" then
        duel = true
        -- Failed/ignored outgoing requests must not disable tracking forever.
        duelPendingUntil = (event == "DUEL_REQUESTED" or event == "DUEL_TO_THE_DEATH_REQUESTED") and (GL.Now() + 120) or nil
        fight, lastFight, pendingDeath, idleOpponents = nil, nil, nil, nil
    elseif event == "DUEL_FINISHED" then
        duel, duelPendingUntil = false, nil
        fight, lastFight, pendingDeath, idleOpponents = nil, nil, nil, nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        if enabled() then
            if not fight then fight = { enemies = {}, id = nextID("fight"), idleOpponents = idleOpponents } end
            idleOpponents = nil
            lastFight = nil
            honorBaseline = GL.Clean(GL.Safe(GetPVPSessionStats), "number")
            T.Poll()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        idleOpponents = nil
        if fight then fight.endedAt = GL.Now() lastFight = fight fight = nil end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if bool(UnitIsDeadOrGhost, "player") == false then
            deathHandled = false
            fight, lastFight, pendingDeath, idleOpponents = nil, nil, nil, nil
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        arg = GL.Clean(arg, "string")
        if arg then plates[arg] = true T.Observe(arg) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        arg = GL.Clean(arg, "string")
        if arg then plates[arg] = nil end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then T.Poll()
    elseif event == "UNIT_TARGET" or event == "UNIT_FLAGS" or event == "UNIT_HEALTH" or event == "UNIT_NAME_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        arg = GL.Clean(arg, "string")
        if event == "UNIT_HEALTH" and arg == "player" then T.Poll() else T.Observe(arg) end
    elseif event == "PLAYER_DEAD" then T.OnDeath()
    elseif event == "PARTY_KILL" then killingBlow(arg, second, nil, "Le jeu vous attribue le coup fatal (PARTY_KILL).", true)
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then T.OnHonorCount()
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then T.OnHonorMessage(arg, (select(11, ...))) -- field 12 is the sender, never the victim
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then T.OnCombatLog() end
end

GL.On("READY", function()
    if registered then return end
    registered = true
    session = tostring(GL.Now()) .. ":" .. tostring(GL.Safe(GetTimePreciseSec) or GL.Safe(GetTime) or 0)
    local events = {
        "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
        "UNIT_CONNECTION", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_TARGET", "UNIT_FLAGS", "UNIT_HEALTH", "UNIT_NAME_UPDATE", "PLAYER_GUILD_UPDATE",
        "PLAYER_PVP_KILLS_CHANGED", "CHAT_MSG_COMBAT_HONOR_GAIN", "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED", "DUEL_INBOUNDS", "DUEL_OUTOFBOUNDS", "DUEL_FINISHED",
    }
    T.nativeKillEvent = pcall(frame.RegisterEvent, frame, "PARTY_KILL")
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
    -- Forever may reject registration even when the getter exists.
    if (C_CombatLog and C_CombatLog.GetCurrentEventInfo) or CombatLogGetCurrentEventInfo then
        openingFeed = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
    end
    -- Blizzard's player menu and /duel call StartDuel. A secure post-hook observes
    -- outgoing requests; DUEL_REQUESTED is only delivered to the recipient.
    if type(hooksecurefunc) == "function" and type(StartDuel) == "function" then
        pcall(hooksecurefunc, "StartDuel", function() T.HandleEvent("DUEL_REQUESTED") end)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        local ok, err = pcall(T.HandleEvent, event, ...)
        if not ok then GL.Debug(L("Suivi JcJ : %s"):format(tostring(err))) end
    end)
    local elapsedTotal = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < 0.25 then return end
        elapsedTotal = 0
        local ok, err = pcall(T.Poll)
        if not ok then GL.Debug(L("Suivi JcJ : %s"):format(tostring(err))) end
    end)
    honorBaseline = GL.Clean(GL.Safe(GetPVPSessionStats), "number")
    deathHandled = bool(UnitIsDeadOrGhost, "player") == true
    -- Roster data can still be empty at ADDON_LOADED; PLAYER_ENTERING_WORLD scans it.
end)

GL.On("SETTINGS", function()
    if not GL.Settings().pvpTracking then fight, lastFight, pendingDeath, idleOpponents = nil, nil, nil, nil end
    T.ScanGroup()
end)
