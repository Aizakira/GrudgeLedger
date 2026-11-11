-- Grudge Ledger: combat inference and group memories.
-- Heuristic evidence is always recorded as probable, never as a confirmed kill.
local GL = GrudgeLedger
local T = {}
GL.Tracker = T

local frame = CreateFrame("Frame")
local plates, recentCredits = {}, {}
local fight, lastFight
local pendingDeath, lastDeathAt, lastRecapStamp
local duel, deathHandled, registered = false, false, false
local duelPendingUntil
local serial, honorBaseline, session = 0, nil, nil
local damageEvents = {
    SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
    SPELL_BUILDING_DAMAGE = true, DAMAGE_SHIELD = true, DAMAGE_SPLIT = true, ENVIRONMENTAL_DAMAGE = true,
}

local function bool(fn, ...)
    return GL.Clean(GL.Safe(fn, ...), "boolean")
end

local function hostileFlags(value)
    local flags = GL.Clean(value, "number")
    local bit = COMBATLOG_OBJECT_REACTION_HOSTILE or 64
    return flags and flags >= 0 and flags <= 4294967295 and flags % 1 == 0
        and flags % (bit * 2) >= bit
end

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
    return GL.db and GL.Settings().pvpTracking and not duel
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
    if not guid or not guid:match("^Player%-") or guid == playerGUID() then return nil end
    for _, unit in ipairs(units()) do
        local identity = GL.Identity(unit)
        if identity and identity.guid == guid then return identity end
    end
    local known = GL.Get("guid:" .. guid)
    if known then return known end
    local f = encounter or combatSession()
    for _, enemy in pairs(f and f.enemies or {}) do
        if enemy.identity.guid == guid then return enemy.identity end
    end
    -- Recap names can be Given-Realm, not Forever's Given Family.
    if name and not name:find(" ", 1, true) then name = name:match("^[^%-]+") end
    return GL.IdentityFromName(name, nil, guid)
end

local function creditKill(identity, confidence, evidence)
    if not enabled() or not identity then return end
    local key = identity.guid or identity.key
    local previous = recentCredits["kill:" .. key]
    if previous and GL.Now() - previous < 4 then return end
    recentCredits["kill:" .. key] = GL.Now()
    return GL.RecordPvP(identity, "kill", confidence, evidence, nextID("kill"))
end

local function recordAggression(f, identity, confidence, evidence)
    if not f or not identity or not enabled() then return end
    f.aggressions = f.aggressions or {}
    local key = identity.guid or identity.key
    if f.aggressions[key] or (identity.alias and f.aggressions[identity.alias]) then return end
    f.aggressions[key] = true
    GL.RecordAggression(identity, confidence, evidence, f.id .. ":attack:" .. key)
end

local function recentAttackers(f, age)
    local candidates, now = {}, GL.Now()
    for key, enemy in pairs(f.enemies) do
        if enemy.dead == false and enemy.aliveAt and now - enemy.aliveAt <= age
            and enemy.targetingMeAt and now - enemy.targetingMeAt <= age then
            candidates[key] = enemy.identity
        end
    end
    return candidates
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
        and now - f.healthAt <= 2 and health < f.health and not f.pve and not f.damageLogged then
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
    if age <= 3 and not f.pve and not f.damageLogged then
        local candidates = recentAttackers(f, 2)
        for key, identity in pairs(pending.candidates) do
            if candidates[key] then
                recordAggression(f, identity, "probable", "Baisse de santé pendant que cet adversaire PvP en combat vous ciblait ; participation déduite, source de dégâts non confirmée.")
            end
        end
    end
end

function T.Observe(unit)
    local f = combatSession()
    if not enabled() or not f or not unit or deathHandled then return end
    local hostile = bool(UnitCanAttack, "player", unit) == true
    local engaged = bool(UnitAffectingCombat, unit) == true
    local targetingMe = bool(UnitIsUnit, unit .. "target", "player") == true
    local identity = GL.Identity(unit)
    if not identity then
        -- A visible attacking NPC makes a fallback death attribution unsafe.
        if hostile and targetingMe and engaged and bool(UnitIsPlayer, unit) == false then f.pve = true end
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
    local dead = bool(UnitIsDeadOrGhost, unit)
    if dead == false then
        if engaged then
            if targetingMe then enemy.targetingMeAt = now end
            if bool(UnitIsUnit, unit, "target") == true then enemy.targetedAt = now end
        else enemy.targetingMeAt, enemy.targetedAt = nil, nil end
        if enemy.dead then
            enemy.signalAt = nil enemy.deadAt = nil enemy.credited = nil
            recentCredits["kill:" .. (identity.guid or identity.key)] = nil
        end
        enemy.aliveAt, enemy.dead = now, false
    elseif dead == true and enemy.dead == false then
        enemy.dead, enemy.deadAt = true, now
    end
end

local function tryKills()
    local f = combatSession()
    if not enabled() or not f or f.otherCombatant or f.pve then return end
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
    if count ~= 1 or not candidate or candidate.credited then return end
    local e = candidate
    if not e.deadAt or not e.signalAt or not e.targetingMeAt or not e.targetedAt then return end
    if now - e.deadAt < 1 or now - e.deadAt > 3 then return end
    if math.abs(e.signalAt - e.deadAt) > 2 or e.deadAt - e.aliveAt > 3 then return end
    if e.deadAt - e.targetingMeAt > 4 or e.deadAt - e.targetedAt > 4 then return end
    e.credited = true
    creditKill(e.identity, "probable", "Adversaire vu vivant puis mort, combat mutuel isolé et gain d'honneur concordant.")
end

function T.OnHonorMessage(message)
    message = GL.Clean(message, "string")
    local f = combatSession()
    if not enabled() or not f or not message then return end
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
            local amount = GL.Clean(event.amount, "number")
            if stamp and stamp >= death.at - 10 and stamp <= death.at + 1
                and (not death.previousAt or stamp > death.previousAt)
                and (kind == "SPELL_INSTAKILL" or (damageEvents[kind] and amount and amount > 0 and amount < math.huge)) then
                newest = math.max(newest or stamp, stamp)
                rows[#rows + 1] = {
                    guid = GL.Clean(event.sourceGUID, "string"), name = GL.Clean(event.sourceName, "string"),
                    flags = GL.Clean(event.sourceFlags, "number"), overkill = GL.Clean(event.overkill, "number"),
                    kind = kind,
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
    pendingDeath = nil
    local participants, lethal = death.candidates, death.confirmed
    if rows then
        lastRecapStamp = stamp
        participants = {} -- explicit sources replace, rather than extend, guesses
        local otherLethal
        for _, row in ipairs(rows) do
            local identity = hostileFlags(row.flags) and identityForGUID(row.guid, row.name, death.fight)
            local fatal = row.kind == "SPELL_INSTAKILL" or (row.overkill and row.overkill >= 0 and row.overkill < math.huge)
            if identity then
                participants[identity.guid or identity.key] = identity
                recordAggression(death.fight, identity, "confirmed", "Récapitulatif de mort : dégâts reçus de ce joueur hostile.")
                if fatal then lethal = lethal or identity end
            elseif fatal then otherLethal = true end
        end
        if otherLethal and not lethal then participants = {} end
    end
    if lethal then participants[lethal.guid or lethal.key] = lethal end
    -- ponytail: reuse per-person death counters for participation in one fatal attack.
    -- Only an explicit lethal hit is confirmed; other participants remain probable.
    for _, identity in pairs(participants) do
        local confirmed = lethal and (identity.guid or identity.key) == (lethal.guid or lethal.key)
        local evidence = confirmed and "Dégâts létaux explicitement attribués à ce joueur."
            or "Participation probable à l'attaque ayant causé votre mort ; le coup fatal n'est pas attribué à ce joueur."
        GL.RecordPvP(identity, "death", confirmed and "confirmed" or "probable", evidence, death.id)
    end
end

function T.OnDeath(confirmed)
    if pendingDeath and confirmed then pendingDeath.confirmed = confirmed return end
    if deathHandled then return end
    -- Freeze the encounter before waiting for a delayed recap. Later sightings cannot join it.
    deathHandled = true
    local f, now = combatSession(), GL.Now()
    if enabled() then
        local candidates = {}
        if f and not f.pve then
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
            confirmed = confirmed, fight = f or { id = nextID("fight"), enemies = {} } }
        resolveDeath()
    end
    lastDeathAt = now
end

function T.OnCombatLog(...)
    if not enabled() then return end
    local args
    if select("#", ...) > 0 then args = { ... }
    else
        local getter = (C_CombatLog and C_CombatLog.GetCurrentEventInfo) or CombatLogGetCurrentEventInfo
        if type(getter) ~= "function" then return end
        local result = { pcall(getter) }
        if result[1] ~= true then return end
        table.remove(result, 1)
        args = result
    end
    local sub = GL.Clean(args[2], "string")
    local src = GL.Clean(args[4], "string")
    local dst = GL.Clean(args[8], "string")
    local me = playerGUID()
    if not sub or not me then return end
    local srcName, dstName = GL.Clean(args[5], "string"), GL.Clean(args[9], "string")
    if sub == "PARTY_KILL" and src == me then
        creditKill(identityForGUID(dst, dstName), "confirmed", "Journal de combat : coup fatal personnel (PARTY_KILL).")
    -- Only health-damage payloads contain overkill. LEECH/DRAIN use powerType in
    -- that position, and durability damage is not damage to the player either.
    elseif dst == me and (damageEvents[sub] or sub == "SPELL_INSTAKILL") then
        local identity = identityForGUID(src, srcName)
        local f = combatSession()
        if not identity and f then f.pve = true end
        local hostile = hostileFlags(args[6])
        if identity and hostile and not deathHandled then
            -- Initial damage can arrive before PLAYER_REGEN_DISABLED.
            if not fight then fight = { enemies = {}, id = nextID("fight") } end
            f = fight
            recordAggression(f, identity, "confirmed", "Journal de combat : dégâts reçus de ce joueur hostile (" .. sub .. ").")
            local enemy = f.enemies[identity.key] or { identity = identity }
            enemy.damageAt = GL.Now()
            f.enemies[identity.key] = enemy
        end
        -- ponytail: once incoming damage is logged, use its explicit source for this
        -- encounter. Guessing from health could blame the selected player instead.
        if f then f.damageLogged, f.pendingAggression = true, nil end
        local overkill = GL.Clean(args[sub == "SWING_DAMAGE" and 13 or 16], "number")
        if identity and hostile and (sub == "SPELL_INSTAKILL" or (overkill and overkill >= 0)) then
            T.OnDeath(identity)
        end
    end
end

function T.ScanGroup()
    if not GL.db or not GL.Settings().groupTracking then return end
    local size = GL.Clean(GL.Safe(GetNumGroupMembers), "number")
    local me = playerGUID()
    if size == nil or not me then return end
    if type(GL.db.tracker) ~= "table" then GL.db.tracker = {} end
    local state = GL.db.tracker
    if type(state.groups) ~= "table" then state.groups = {} end
    if type(state.serial) ~= "number" or state.serial ~= state.serial or state.serial < 0 or state.serial == math.huge then state.serial = 0 end
    local previous, current = type(state.groups[me]) == "table" and state.groups[me] or {}, {}
    local identified = 0
    local raid = bool(IsInRaid) == true
    if size > 0 then
        for i = 1, raid and math.min(size, 40) or 4 do
            local identity = GL.Identity((raid and "raid" or "party") .. i)
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
                end
            end
        end
    end
    if identified < math.max(0, size - 1) then
        -- Roster tokens can be incomplete during login or a raid transition.
        for key, id in pairs(previous) do if not current[key] then current[key] = id end end
    end
    state.groups[me] = current
end

function T.Poll()
    if not GL.db then return end
    resolveDeath()
    for _, unit in ipairs(units()) do T.Observe(unit) end
    observeHealth()
    tryAggression()
    tryKills()
    local now = GL.Now()
    for key, when in pairs(recentCredits) do if now - when > 10 then recentCredits[key] = nil end end
end

function T.HandleEvent(event, arg)
    if not GL.db then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
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
    elseif event == "GROUP_ROSTER_UPDATE" then T.ScanGroup()
    elseif event == "DUEL_REQUESTED" or event == "DUEL_TO_THE_DEATH_REQUESTED" or event == "DUEL_INBOUNDS" or event == "DUEL_OUTOFBOUNDS" then
        duel = true
        -- Failed/ignored outgoing requests must not disable tracking forever.
        duelPendingUntil = (event == "DUEL_REQUESTED" or event == "DUEL_TO_THE_DEATH_REQUESTED") and (GL.Now() + 120) or nil
        fight, lastFight, pendingDeath = nil, nil, nil
    elseif event == "DUEL_FINISHED" then
        duel, duelPendingUntil = false, nil
        fight, lastFight, pendingDeath = nil, nil, nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        if enabled() then
            if not fight then fight = { enemies = {}, id = nextID("fight") } end
            lastFight = nil
            honorBaseline = GL.Clean(GL.Safe(GetPVPSessionStats), "number")
            T.Poll()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if fight then fight.endedAt = GL.Now() lastFight = fight fight = nil end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if bool(UnitIsDeadOrGhost, "player") == false then
            deathHandled = false
            fight, lastFight, pendingDeath = nil, nil, nil
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        arg = GL.Clean(arg, "string")
        if arg then plates[arg] = true T.Observe(arg) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        arg = GL.Clean(arg, "string")
        if arg then plates[arg] = nil end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then T.Poll()
    elseif event == "UNIT_TARGET" or event == "UNIT_FLAGS" or event == "UNIT_HEALTH" then
        arg = GL.Clean(arg, "string")
        if event == "UNIT_HEALTH" and arg == "player" then T.Poll() else T.Observe(arg) end
    elseif event == "PLAYER_DEAD" then T.OnDeath()
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then T.OnHonorCount()
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then T.OnHonorMessage(arg)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then T.OnCombatLog() end
end

GL.On("READY", function()
    if registered then return end
    registered = true
    session = tostring(GL.Now()) .. ":" .. tostring(GL.Safe(GetTimePreciseSec) or GL.Safe(GetTime) or 0)
    local events = {
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_TARGET", "UNIT_FLAGS", "UNIT_HEALTH",
        "PLAYER_PVP_KILLS_CHANGED", "CHAT_MSG_COMBAT_HONOR_GAIN", "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED", "DUEL_INBOUNDS", "DUEL_OUTOFBOUNDS", "DUEL_FINISHED",
    }
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
    -- Forever may reject registration even when the getter exists.
    if (C_CombatLog and C_CombatLog.GetCurrentEventInfo) or CombatLogGetCurrentEventInfo then
        pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
    end
    -- Blizzard's player menu and /duel call StartDuel. A secure post-hook observes
    -- outgoing requests; DUEL_REQUESTED is only delivered to the recipient.
    if type(hooksecurefunc) == "function" and type(StartDuel) == "function" then
        pcall(hooksecurefunc, "StartDuel", function() T.HandleEvent("DUEL_REQUESTED") end)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        local ok, err = pcall(T.HandleEvent, event, ...)
        if not ok then GL.Debug("Tracker: " .. tostring(err)) end
    end)
    local elapsedTotal = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < 0.25 then return end
        elapsedTotal = 0
        local ok, err = pcall(T.Poll)
        if not ok then GL.Debug("Tracker: " .. tostring(err)) end
    end)
    honorBaseline = GL.Clean(GL.Safe(GetPVPSessionStats), "number")
    deathHandled = bool(UnitIsDeadOrGhost, "player") == true
    -- Roster data can still be empty at ADDON_LOADED; PLAYER_ENTERING_WORLD scans it.
end)

GL.On("SETTINGS", function()
    if not GL.Settings().pvpTracking then fight, lastFight, pendingDeath = nil, nil, nil end
    T.ScanGroup()
end)
