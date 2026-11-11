-- Executes the actual Core and Tracker with deterministic WoW API fixtures.
local now, unitData, groupSize, honor, secret, GL, T
local passed = 0

local function fixture(saved)
    now, groupSize, honor, secret = 1000, 0, 0, {}
    C_DeathRecap, C_NamePlate, C_CombatLog = nil, nil, nil
    unitData = { player = { guid = "Player-1-self", name = "Testeur", surname = "Exemple", dead = false, isPlayer = true, health = 1000, maxHealth = 1000 } }
    local function unit(token)
        if unitData[token] then return unitData[token] end
        if type(token) == "string" and token:sub(-6) == "target" then
            local base = unit(token:sub(1, -7))
            return base and base.target and unitData[base.target]
        end
    end
    function issecretvalue(value) return value == secret end
    function GetServerTime() return now end
    function GetTimePreciseSec() return now + 0.125 end
    function GetRealZoneText() return "Bois de la Pénombre" end
    function GetNumGroupMembers() return groupSize end
    function GetPVPSessionStats() return honor, 0 end
    function IsInRaid() return false end
    function UnitExists(token) return unit(token) ~= nil end
    function UnitIsPlayer(token) local u = unit(token) return u and u.isPlayer or false end
    function UnitIsUnit(a, b) return unit(a) ~= nil and unit(a) == unit(b) end
    function UnitName(token) local u = unit(token) if u then return u.name, u.surname end end
    function UnitGUID(token) local u = unit(token) return u and u.guid end
    function UnitClass(token) if unit(token) then return "Guerrier", "WARRIOR" end end
    function UnitFactionGroup(token) local u = unit(token) return u and u.faction or (token == "player" and "Alliance" or "Horde") end
    function UnitIsPVP(token) local u = unit(token) return u and u.flagged ~= false end
    function UnitLevel(token) return unit(token) and 34 end
    function GetRealmName() return "Forever" end
    function GetGuildInfo(token) local u = unit(token) return u and u.guild, nil, nil, u and u.realm end
    function UnitCanAttack(_, token) local u = unit(token) return u and u.hostile or false end
    function UnitAffectingCombat(token) local u = unit(token) return u and u.combat or false end
    function UnitIsDeadOrGhost(token) local u = unit(token) if u then return u.dead end end
    function UnitHealth(token) local u = unit(token) return u and u.health end
    function UnitHealthMax(token) local u = unit(token) return u and u.maxHealth end
    function CombatLogGetCurrentEventInfo() return nil end
    function StartDuel() end
    function hooksecurefunc(name, after)
        local original = _G[name]
        _G[name] = function(...) original(...) after(...) end
    end
    function CreateFrame()
        return { scripts = {},
            RegisterEvent = function(_, event) if event == "COMBAT_LOG_EVENT_UNFILTERED" then error("Forbidden on Forever") end end,
            UnregisterEvent = function() end,
            SetScript = function(self, event, fn) self.scripts[event] = fn end }
    end
    GrudgeLedgerDB = saved
    assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
    assert(loadfile(TEST_ROOT .. "/Tracker.lua"))()
    GL = GrudgeLedger
    GL.InitDB()
    T = GL.Tracker
    assert(#GL.errors == 0, "READY raised an error despite optional unsupported CLE")
end

local function opponent(id, name, surname)
    return { guid = "Player-1-" .. id, name = name or "Alex", surname = surname or id,
        isPlayer = true, hostile = true, combat = true, target = "player", dead = false }
end
local function start(e)
    unitData.target = e or opponent("enemy")
    T.HandleEvent("PLAYER_REGEN_DISABLED")
    return unitData.target
end
local function total(field)
    local n = 0
    for _, record in pairs(GL.db.players) do n = n + (record.pvp[field] or 0) end
    return n
end
local function count()
    local n = 0 for _ in pairs(GL.db.players) do n = n + 1 end return n
end
local function killedTarget()
    now = now + 1
    unitData.target.dead = true
    T.Poll()
    honor = honor + 1
    T.HandleEvent("PLAYER_PVP_KILLS_CHANGED")
    now = now + 1
    T.Poll()
end
local function cle(kind, src, dst, overkill, sourceFlags)
    local args = { now, kind, false, src.guid, src.name .. " " .. src.surname, sourceFlags or 0, 0,
        dst.guid, dst.name .. " " .. dst.surname, 0, 0 }
    if kind == "SWING_DAMAGE" then args[12], args[13] = 300, overkill
    else args[12], args[13], args[14], args[15], args[16] = 1, "Sort", 1, 300, overkill end
    T.OnCombatLog(unpack(args, 1, kind == "SWING_DAMAGE" and 13 or 16))
end
local function recapRow(source, overkill, timestamp, kind)
    return { event = kind or "SPELL_DAMAGE", timestamp = timestamp or now, amount = 300,
        sourceGUID = source.guid, sourceName = source.name .. (source.surname and " " .. source.surname or ""),
        sourceFlags = 64, overkill = overkill == nil and -1 or overkill }
end
local function recapAPI(rows)
    C_DeathRecap = { GetRecapEvents = function(...)
        assert(select("#", ...) == 0, "Forever GetRecapEvents takes no arguments")
        return rows
    end }
    return rows
end
local function test(name, fn)
    fixture()
    local ok, err = pcall(fn)
    assert(ok, name .. ": " .. tostring(err))
    assert(#GL.errors == 0, name .. ": unexpected runtime debug error")
    passed = passed + 1
end

test("one recent hostile gives probable death once", function()
    start()
    T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 1 and total("deaths") == 0)
    assert(GL.Relation(GL.Get(GL.Identity("target"))) == "enemy")
end)

test("manual friend remains friend after inferred death", function()
    start()
    GL.SetReaction(GL.Identity("target"), "friend")
    T.HandleEvent("PLAYER_DEAD")
    assert(GL.Relation(GL.Get(GL.Identity("target"))) == "friend")
end)

test("multiple recent attackers share one probable fatal encounter", function()
    start()
    unitData.nameplate1 = opponent("second")
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 2 and total("deaths") == 0 and count() == 2)
    T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 2, "duplicate death events must not repeat the batch")
end)

test("NPC pressure prevents mixed PvE guess", function()
    start()
    unitData.mouseover = { guid = "Creature-1-wolf", hostile = true, combat = true, target = "player", isPlayer = false, dead = false }
    T.Poll()
    T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 0)
end)

test("stale or merely selected target does not qualify", function()
    start()
    now = now + 10
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0)
    T.HandleEvent("PLAYER_ALIVE")
    local e = opponent("idle") e.combat = false e.target = nil
    start(e)
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0)
end)

test("duels excluded even with explicit lethal event", function()
    local e = start()
    T.HandleEvent("DUEL_REQUESTED")
    cle("SWING_DAMAGE", e, unitData.player, 0, 64)
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0)
    T.HandleEvent("DUEL_FINISHED") T.HandleEvent("PLAYER_ALIVE")
    start(e) T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 1)
end)

test("outgoing duel is excluded without inbound duel events", function()
    local e = opponent("outgoing")
    unitData.target = e
    StartDuel("target", true)
    T.HandleEvent("PLAYER_REGEN_DISABLED")
    cle("SWING_DAMAGE", e, unitData.player, 0, 64)
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0)
    T.HandleEvent("DUEL_FINISHED") T.HandleEvent("PLAYER_ALIVE")
    start(e) T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 1)
end)

test("ignored duel request eventually stops suppressing tracking", function()
    StartDuel("target")
    now = now + 121
    start() T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 1)
end)

test("ordinary combat cannot make an ignored duel request permanent", function()
    StartDuel("target")
    unitData.player.combat = true start()
    now = now + 121 T.Poll()
    unitData.player.combat = false T.HandleEvent("PLAYER_REGEN_ENABLED") T.Poll()
    start() T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 1)
end)

test("long continuous and confirmed duels stay suppressed beyond request timeout", function()
    local e = opponent("duelist") unitData.target = e
    StartDuel("target") unitData.player.combat = true start(e)
    now = now + 600
    cle("SPELL_DAMAGE", e, unitData.player, 0, 64)
    T.HandleEvent("PLAYER_DEAD") assert(count() == 0)
    fixture() e = start()
    T.HandleEvent("DUEL_REQUESTED") T.HandleEvent("DUEL_INBOUNDS")
    now = now + 600
    cle("SWING_DAMAGE", e, unitData.player, 0, 64)
    T.HandleEvent("PLAYER_DEAD") assert(count() == 0)
    T.HandleEvent("DUEL_FINISHED") T.HandleEvent("PLAYER_ALIVE")
    start(e) T.HandleEvent("PLAYER_DEAD") assert(total("probableDeaths") == 1)
end)

test("unflagged or same-faction hostility cannot be inferred", function()
    local e = opponent("unflagged") e.flagged = false
    start(e) T.HandleEvent("PLAYER_DEAD") assert(count() == 0)
    T.HandleEvent("PLAYER_ALIVE")
    e = opponent("samefaction") e.faction = "Alliance"
    start(e) T.HandleEvent("PLAYER_DEAD") assert(count() == 0)
end)

test("secret hostility and secret combat-log identity skipped", function()
    local e = opponent("secret") e.hostile = secret
    start(e)
    T.HandleEvent("PLAYER_DEAD")
    T.OnCombatLog(now, "PARTY_KILL", false, secret, "Secret", 0, 0, e.guid, "Alex Secret", 0)
    assert(count() == 0)
end)

test("confirmed kill requires personal source and player victim", function()
    local e = opponent("known")
    cle("PARTY_KILL", opponent("other"), e)
    cle("PARTY_KILL", unitData.player, { guid = "Creature-1-wolf", name = "Loup", surname = "Gris" })
    assert(count() == 0)
    cle("PARTY_KILL", unitData.player, e)
    cle("PARTY_KILL", unitData.player, e)
    assert(total("kills") == 1 and total("probableKills") == 0)
end)

test("two identical first names never merged", function()
    cle("PARTY_KILL", unitData.player, opponent("one", "Alex", "Alpha"))
    cle("PARTY_KILL", unitData.player, opponent("two", "Alex", "Beta"))
    assert(count() == 2 and total("kills") == 2)
end)

test("solo observed death plus honor count gives probable kill", function()
    local e = start()
    killedTarget()
    assert(total("probableKills") == 1 and total("kills") == 0)
    T.HandleEvent("CHAT_MSG_COMBAT_HONOR_GAIN", e.name .. " " .. e.surname .. " dies.")
    cle("PARTY_KILL", unitData.player, e)
    T.Poll()
    assert(total("probableKills") + total("kills") == 1, "late confirmation double-counted")
end)

test("a corpse first seen after death never qualifies", function()
    local e = opponent("corpse") e.dead = true
    start(e)
    honor = 1 T.HandleEvent("PLAYER_PVP_KILLS_CHANGED")
    T.OnHonorMessage("Alex corpse dies.")
    now = now + 1 T.Poll()
    assert(count() == 0)
end)

test("selecting a corpse cannot create personal targeting evidence", function()
    T.HandleEvent("PLAYER_REGEN_DISABLED")
    unitData.nameplate1 = opponent("corpse")
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    now = now + 1 unitData.nameplate1.dead = true unitData.target = unitData.nameplate1
    T.Poll()
    honor = honor + 1 T.OnHonorCount()
    now = now + 1 T.Poll()
    assert(count() == 0)
end)

test("shared group honor cannot become personal probable kill", function()
    start()
    groupSize = 2
    killedTarget()
    T.OnHonorMessage("Alex enemy dies.")
    assert(total("probableKills") == 0)
    cle("PARTY_KILL", unitData.player, unitData.target)
    assert(total("kills") == 1)
end)

test("honor alone and partial name matches are ignored", function()
    T.OnHonorMessage("Alex unrelated dies.")
    honor = 1 T.OnHonorCount()
    assert(count() == 0)
    start()
    now = now + 1 unitData.target.dead = true T.Poll()
    T.OnHonorMessage("Alex enemyother dies.")
    now = now + 1 T.Poll()
    assert(count() == 0)
end)

test("observed third-party combat blocks solo kill inference", function()
    start()
    local other = opponent("helper") other.hostile = false
    unitData.nameplate1 = other
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    killedTarget()
    assert(total("probableKills") == 0)
end)

test("counter reset does not qualify", function()
    honor = 10 start()
    now = now + 1 unitData.target.dead = true T.Poll()
    honor = 0 T.OnHonorCount()
    now = now + 1 T.Poll()
    assert(count() == 0)
end)

test("only explicit lethal damage is confirmed death", function()
    local e = start()
    cle("SWING_DAMAGE", e, unitData.player, 0, 64)
    T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1 and total("probableDeaths") == 0)
    T.HandleEvent("PLAYER_ALIVE")
    start(e)
    cle("SPELL_DAMAGE", e, unitData.player, -1, 64)
    T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1 and total("probableDeaths") == 1)
end)

test("lethal NPC damage does not blame the nearby enemy", function()
    start()
    cle("SWING_DAMAGE", { guid = "Creature-1-wolf", name = "Loup", surname = "Gris" }, unitData.player, 0, 64)
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0)
end)

test("death immediately after combat end uses bounded grace", function()
    start() T.HandleEvent("PLAYER_REGEN_ENABLED")
    now = now + 1 T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 1)
    T.HandleEvent("PLAYER_ALIVE")
    start() T.HandleEvent("PLAYER_REGEN_ENABLED")
    now = now + 4 T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 1)
end)

test("world change clears stale battle candidates", function()
    start()
    T.HandleEvent("PLAYER_ENTERING_WORLD")
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0)
end)

test("group history dedupes roster events and survives reload", function()
    unitData.party1 = opponent("companion") groupSize = 2
    GL.SetReaction(GL.Identity("party1"), "friend")
    T.ScanGroup() T.ScanGroup()
    local record = GL.Get(GL.Identity("party1"))
    assert(record.groupCount == 1)
    local saved = GL.db
    fixture(saved)
    unitData.party1 = opponent("companion") groupSize = 2
    -- READY occurs before roster availability. Preserve saved membership until world entry.
    T.HandleEvent("PLAYER_ENTERING_WORLD")
    assert(record.groupCount == 1)
    groupSize = nil T.ScanGroup() groupSize = 2 T.ScanGroup()
    assert(record.groupCount == 1)
    groupSize = 0 unitData.party1 = nil T.ScanGroup()
    groupSize = 2 unitData.party1 = opponent("companion") T.ScanGroup()
    assert(record.groupCount == 2)
end)

test("partial roster resolution does not create a new session", function()
    unitData.party1 = opponent("companion") groupSize = 2
    GL.SetReaction(GL.Identity("party1"), "friend") T.ScanGroup()
    local record = GL.Get(GL.Identity("party1"))
    unitData.party1 = nil T.ScanGroup()
    unitData.party1 = opponent("companion") T.ScanGroup()
    assert(record.groupCount == 1)
end)

test("GUID availability changes do not duplicate group history", function()
    local p = opponent("companion") p.guid = nil
    unitData.party1 = p groupSize = 2
    GL.SetReaction(GL.Identity("party1"), "friend") T.ScanGroup()
    local record = GL.Get(GL.Identity("party1"))
    assert(record.groupCount == 1)
    p.guid = "Player-1-companion" T.ScanGroup()
    assert(record.groupCount == 1 and record.guid == p.guid)
    p.guid = secret T.ScanGroup()
    p.guid = "Player-1-companion" T.ScanGroup()
    assert(record.groupCount == 1)
end)

test("unrated group members do not enter the journal but can be marked during a group", function()
    unitData.party1 = opponent("companion") groupSize = 2
    local identity = GL.Identity("party1")
    assert(GL.RecordGroup(identity, "direct-call", "Test") == nil)
    T.ScanGroup() T.ScanGroup()
    assert(GL.Get(identity) == nil and next(GL.db.aliases) == nil)
    local record = GL.SetReaction(identity, "friend")
    T.ScanGroup() T.ScanGroup()
    assert(record.groupCount == 1, "marking the current companion starts one remembered session")
end)

test("untracked but identified roster members do not preserve departed friends", function()
    unitData.party1 = opponent("companion") groupSize = 2
    local record = GL.SetReaction(GL.Identity("party1"), "friend")
    T.ScanGroup()
    unitData.party1 = opponent("stranger") T.ScanGroup()
    assert(GL.Get(GL.Identity("party1")) == nil)
    unitData.party1 = opponent("companion") T.ScanGroup()
    assert(record.groupCount == 2, "a known friend's return is a new session after an observed departure")
end)

test("disabling tracking clears active inference", function()
    start() GL.SetSetting("pvpTracking", false)
    T.HandleEvent("PLAYER_DEAD")
    cle("PARTY_KILL", unitData.player, opponent("enemy"))
    assert(count() == 0)
end)

test("targeting without health loss does not imply aggression", function()
    start()
    now = now + 1 T.Poll()
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 0 and count() == 0)
end)

test("one recent attacker plus health loss records probable aggression once", function()
    start()
    now = now + 1 unitData.player.health = 900 T.HandleEvent("UNIT_HEALTH", "player")
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 1 and total("aggressions") == 0)
    assert(GL.Relation(GL.Get(GL.Identity("target"))) == "warning")
    unitData.player.health = 800 T.Poll() now = now + 1 T.Poll()
    assert(total("probableAggressions") == 1)
end)

test("health loss under multiple targeting attackers records probable participation", function()
    start()
    unitData.nameplate1 = opponent("second") T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    now = now + 1 unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 2 and total("aggressions") == 0)
end)

test("a dead opponent cannot explain a fresh health drop", function()
    local e = start()
    now = now + 1 e.dead = true unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 0)
end)

test("post-death health updates and pending guesses cannot create aggression", function()
    start()
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    now = now + 1 unitData.player.health = 0 T.Poll()
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 0)
    fixture() start()
    now = now + 1 unitData.player.health = 900 T.Poll()
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 0)
end)

test("explicit friendly or different hostile damage cancels health guesses", function()
    start()
    local friendly = opponent("friend") friendly.hostile = false groupSize = 2
    now = now + 1 unitData.player.health = 900 T.Poll()
    cle("SPELL_DAMAGE", friendly, unitData.player, -1, 16)
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 0 and total("aggressions") == 0)
    fixture() start()
    now = now + 1 unitData.player.health = 900 T.Poll()
    cle("SPELL_DAMAGE", opponent("different"), unitData.player, -1, 64)
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 0 and total("aggressions") == 1)
    assert(GL.Get(GL.Identity("target")) == nil)
end)

test("observed NPC pressure or max health change blocks health inference", function()
    start()
    unitData.mouseover = { hostile = true, combat = true, target = "player", isPlayer = false, dead = false }
    now = now + 1 unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll() assert(count() == 0)
    T.HandleEvent("PLAYER_ENTERING_WORLD") unitData.mouseover = nil start()
    now = now + 1 unitData.player.health = 800 unitData.player.maxHealth = 800 T.Poll()
    now = now + 1 T.Poll() assert(count() == 0)
end)

test("secret health and non-combat opponent cannot trigger inferred aggression", function()
    start()
    unitData.player.health = secret T.Poll()
    now = now + 1 unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll() assert(count() == 0)
    unitData.target.combat = false unitData.player.health = 800 T.Poll()
    now = now + 1 T.Poll() assert(count() == 0)
end)

test("explicit hostile damage is confirmed once per encounter", function()
    local e = opponent("damager")
    cle("DAMAGE_SHIELD", e, unitData.player, -1, 64)
    T.HandleEvent("PLAYER_REGEN_DISABLED")
    cle("SPELL_PERIODIC_DAMAGE", e, unitData.player, -1, 64)
    assert(total("aggressions") == 1 and total("probableAggressions") == 0)
    T.HandleEvent("PLAYER_REGEN_ENABLED")
    now = now + 5
    cle("SPELL_DAMAGE", e, unitData.player, -1, 64)
    assert(total("aggressions") == 2)
end)

test("resource and durability events cannot fabricate a lethal damage event", function()
    for _, event in ipairs({ "SPELL_LEECH", "SPELL_PERIODIC_LEECH", "SPELL_DRAIN", "SPELL_PERIODIC_DRAIN",
        "SPELL_ENERGIZE", "SPELL_PERIODIC_ENERGIZE", "SPELL_DURABILITY_DAMAGE", "SPELL_DURABILITY_DAMAGE_ALL" }) do
        fixture()
        local e = start()
        -- This position is powerType=0 (mana), not overkill=0.
        cle(event, e, unitData.player, 0, 64)
        assert(count() == 0, event .. " must not produce health aggression/death")
        cle("SPELL_DAMAGE", e, unitData.player, 0, 64)
        assert(total("deaths") == 1 and total("aggressions") == 1, event .. " must not latch death state")
    end
end)

test("real health damage keeps exact zero-overkill lethal attribution", function()
    for _, event in ipairs({ "SWING_DAMAGE", "RANGE_DAMAGE", "SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "DAMAGE_SHIELD", "DAMAGE_SPLIT" }) do
        fixture()
        local e = start()
        cle(event, e, unitData.player, -1, 64)
        assert(total("aggressions") == 1 and total("deaths") == 0, event)
        cle(event, e, unitData.player, 0, 64)
        assert(total("aggressions") == 1 and total("deaths") == 1, event)
    end
end)

test("lethal PvP attribution requires an explicitly hostile source flag", function()
    for _, event in ipairs({ "SPELL_DAMAGE", "SPELL_INSTAKILL" }) do
        for _, flagKind in ipairs({ "friendly", "unknown", "missing", "secret" }) do
            fixture()
            local e = start()
            local flags
            if flagKind == "friendly" then flags = 16
            elseif flagKind == "unknown" then flags = 0
            elseif flagKind == "secret" then flags = secret end
            T.OnCombatLog(now, event, false, e.guid, e.name .. " " .. e.surname, flags, 0,
                unitData.player.guid, "Testeur Exemple", 0, 0, 1, "Sort", 1, 1000, 0)
            assert(count() == 0, event .. " with " .. flagKind .. " source cannot identify a PvP killer")
            cle(event, e, unitData.player, 0, 64)
            assert(total("deaths") == 1 and total("aggressions") == 1, "true hostile lethal damage must still be recorded")
        end
    end
end)

test("explicit damage supersedes pending inference without double count", function()
    local e = start()
    now = now + 1 unitData.player.health = 900 T.Poll()
    cle("SWING_DAMAGE", e, unitData.player, -1, 64)
    now = now + 1 T.Poll()
    assert(total("aggressions") == 1 and total("probableAggressions") == 0)
end)

test("late confirmation does not double count already inferred aggression", function()
    local e = start()
    now = now + 1 unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll()
    cle("SWING_DAMAGE", e, unitData.player, -1, 64)
    assert(total("aggressions") + total("probableAggressions") == 1)
end)

test("duel and friendly damage do not produce aggression", function()
    local e = start()
    cle("SPELL_DAMAGE", e, unitData.player, -1, 16)
    assert(count() == 0)
    StartDuel("target")
    cle("SPELL_DAMAGE", e, unitData.player, -1, 64)
    unitData.player.health = 800 T.Poll() now = now + 1 T.Poll()
    assert(count() == 0)
end)

test("manual friend survives confirmed and probable attacks", function()
    local e = start()
    local identity = GL.Identity("target") GL.SetReaction(identity, "friend")
    cle("SPELL_DAMAGE", e, unitData.player, -1, 64)
    assert(GL.Relation(GL.Get(identity)) == "friend")
end)

test("three attackers exclude a merely selected passerby and share one death id", function()
    local first = start(opponent("one", "Alex", "Alpha"))
    unitData.focus = first -- another token for the same person must not count twice
    unitData.nameplate1 = opponent("two", "Alex", "Beta")
    unitData.nameplate2 = opponent("three", "Alex", "Gamma")
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
    local passerby = opponent("passerby") passerby.target = nil
    unitData.target = passerby
    T.HandleEvent("PLAYER_TARGET_CHANGED")
    now = now + 1 unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 3 and GL.Get("guid:" .. passerby.guid) == nil)
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_DEAD") T.Poll()
    assert(count() == 3 and total("probableDeaths") == 3 and total("deaths") == 0)
    local deathId
    for _, record in pairs(GL.db.players) do
        assert(record.pvp.probableAggressions == 1 and record.pvp.probableDeaths == 1)
        for _, event in ipairs(record.history) do
            if event.kind == "death" then
                assert(event.confidence == "probable" and event.evidence:find("Participation probable", 1, true))
                deathId = deathId or event.eventId
                assert(event.eventId == deathId, "three participants are one fatal encounter")
            end
        end
    end
end)

test("new arrivals cannot join a pending health-loss inference", function()
    local first = start()
    now = now + 1 unitData.player.health = 900 T.Poll()
    unitData.nameplate1 = opponent("late")
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 1 and GL.Get("guid:" .. first.guid))
    assert(GL.Get(GL.Identity("nameplate1")) == nil)
end)

test("pending death snapshots exclude players seen after death", function()
    local first = start()
    recapAPI({})
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0, "give native recap its bounded delivery window")
    unitData.target = opponent("late")
    T.HandleEvent("PLAYER_TARGET_CHANGED")
    T.HandleEvent("PLAYER_DEAD")
    now = now + 2 T.Poll()
    assert(total("probableDeaths") == 1 and GL.Get("guid:" .. first.guid))
    assert(GL.Get(GL.Identity("target")) == nil)
end)

test("GUID promotion does not duplicate aggression or fatal participation", function()
    local e = opponent("promoted") local guid = e.guid e.guid = nil
    start(e)
    now = now + 1 unitData.player.health = 900 T.Poll()
    e.guid = guid
    unitData.nameplate1 = e T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    now = now + 1 T.Poll()
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 1 and total("probableDeaths") == 1)
    assert(total("probableAggressions") <= 1, "promotion cannot duplicate a health-loss observation")
end)

test("explicit nonlethal damager replaces targeting-only death candidates", function()
    local selected = start(opponent("selected"))
    local attacker = opponent("actual")
    cle("SPELL_DAMAGE", attacker, unitData.player, -1, 64)
    T.HandleEvent("PLAYER_DEAD")
    local record = GL.Get("guid:" .. attacker.guid)
    assert(record and record.pvp.aggressions == 1 and record.pvp.probableDeaths == 1)
    assert(GL.Get("guid:" .. selected.guid) == nil and total("deaths") == 0)
end)

test("public recap identifies three unseen attackers and only the lethal source", function()
    local a, b, c = opponent("recapA"), opponent("recapB"), opponent("recapC")
    recapAPI({ recapRow(a), recapRow(a), recapRow(b), recapRow(c, 0) })
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_DEAD") T.Poll()
    assert(count() == 3 and total("aggressions") == 3)
    assert(total("deaths") == 1 and total("probableDeaths") == 2)
    assert(GL.Get("guid:" .. c.guid).pvp.deaths == 1)
    local batch
    for _, record in pairs(GL.db.players) do
        for _, event in ipairs(record.history) do
            if event.kind == "death" then batch = batch or event.eventId assert(batch == event.eventId) end
        end
    end
    now = now + 3 T.Poll()
    assert(total("aggressions") == 3 and total("deaths") + total("probableDeaths") == 3)
end)

test("fractional recap timestamps are valid health-damage evidence", function()
    local e = opponent("fractional-time")
    recapAPI({ recapRow(e, 0, now - 0.375) })
    T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1 and total("aggressions") == 1)
end)

test("delayed recap supersedes frozen guesses before the timeout", function()
    local guess = start()
    local rows = recapAPI({})
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0)
    now = now + 1
    local actual = opponent("delayed") rows[1] = recapRow(actual, 0)
    T.Poll()
    assert(total("deaths") == 1 and total("probableDeaths") == 0)
    assert(GL.Get("guid:" .. actual.guid) and GL.Get("guid:" .. guess.guid) == nil)
end)

test("delayed recap retains the frozen full identity after its unit disappears", function()
    local e = start(opponent("snapshot", "Alex", "Family"))
    local rows = recapAPI({})
    T.HandleEvent("PLAYER_DEAD")
    unitData.target = nil now = now + 1
    rows[1] = recapRow(e, 0) rows[1].sourceName = "Alex-SomeRealm"
    T.Poll()
    local record = GL.Get("guid:" .. e.guid)
    assert(record and record.name == "Alex" and record.surname == "Family")
end)

test("Given-Realm recap names never invent a Forever surname or merge GUIDs", function()
    local a, b = opponent("alexA"), opponent("alexB")
    local first, second = recapRow(a), recapRow(b, 0)
    first.sourceName, second.sourceName = "Alex-RealmOne", "Alex-RealmTwo"
    recapAPI({ first, second }) T.HandleEvent("PLAYER_DEAD")
    assert(count() == 2)
    for _, record in pairs(GL.db.players) do
        assert(record.name == "Alex" and record.fullName == "Alex" and record.surname == nil)
    end
end)

test("a previous recap cannot be reused for a rapidly following death", function()
    local a = opponent("previous")
    recapAPI({ recapRow(a, 0) }) T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1)
    T.HandleEvent("PLAYER_ALIVE")
    now = now + 1 local b = start(opponent("next"))
    T.HandleEvent("PLAYER_DEAD")
    now = now + 2 T.Poll()
    assert(GL.Get("guid:" .. a.guid).pvp.deaths == 1)
    assert(GL.Get("guid:" .. b.guid).pvp.probableDeaths == 1 and total("deaths") == 1)
end)

test("stale future or unavailable recap never fabricates a death", function()
    for _, age in ipairs({ -12, -3, 2, math.huge }) do
        fixture()
        recapAPI({ recapRow(opponent("wrong-time"), 0, now + age) })
        T.HandleEvent("PLAYER_DEAD") now = now + 2 T.Poll()
        assert(count() == 0, "invalid recap time " .. tostring(age))
    end
    fixture() local e = start()
    C_DeathRecap = { GetRecapEvents = function() error("temporarily unavailable") end }
    T.HandleEvent("PLAYER_DEAD") now = now + 2 T.Poll()
    assert(GL.Get("guid:" .. e.guid).pvp.probableDeaths == 1 and total("deaths") == 0)
end)

test("secret recap fields and collections are safely unavailable", function()
    for _, field in ipairs({ "event", "timestamp", "amount", "sourceGUID", "sourceName", "sourceFlags" }) do
        fixture()
        local row = recapRow(opponent("secret-recap"), 0) row[field] = secret
        recapAPI({ row })
        T.HandleEvent("PLAYER_DEAD") now = now + 2 T.Poll()
        assert(count() == 0, "secret " .. field .. " must not identify an attacker")
    end
    for _, collection in ipairs({ "row", "all" }) do
        fixture() recapAPI(collection == "all" and secret or { secret })
        T.HandleEvent("PLAYER_DEAD") now = now + 2 T.Poll()
        assert(count() == 0)
    end
end)

test("recap flags require a finite nonnegative 32-bit integer hostile flag", function()
    for _, flags in ipairs({ 64.5, -64, math.huge, 4294967360, 0, 16 }) do
        fixture()
        local row = recapRow(opponent("bad-flags"), 0) row.sourceFlags = flags
        recapAPI({ row }) T.HandleEvent("PLAYER_DEAD") now = now + 2 T.Poll()
        assert(count() == 0, "invalid or nonhostile flags " .. tostring(flags))
    end
end)

test("recap resource durability healing and zero damage cannot be fatal proof", function()
    for _, event in ipairs({ "SPELL_LEECH", "SPELL_PERIODIC_LEECH", "SPELL_DRAIN", "SPELL_PERIODIC_DRAIN",
        "SPELL_ENERGIZE", "SPELL_PERIODIC_ENERGIZE", "SPELL_DURABILITY_DAMAGE", "SPELL_DURABILITY_DAMAGE_ALL", "SPELL_HEAL" }) do
        fixture() recapAPI({ recapRow(opponent("resource"), 0, now, event) })
        T.HandleEvent("PLAYER_DEAD") now = now + 2 T.Poll()
        assert(count() == 0, event)
    end
    for _, amount in ipairs({ 0, -10, math.huge }) do
        fixture()
        local row = recapRow(opponent("not-damage"), 0) row.amount = amount
        recapAPI({ row }) T.HandleEvent("PLAYER_DEAD") now = now + 2 T.Poll()
        assert(count() == 0)
    end
end)

test("fatal NPC recap preserves player aggression without attributing PvP death", function()
    local e = start()
    local npc = { guid = "Creature-1-wolf", name = "Loup" }
    recapAPI({ recapRow(e), recapRow(npc, 0) })
    T.HandleEvent("PLAYER_DEAD")
    assert(total("aggressions") == 1 and count() == 1)
    assert(total("probableDeaths") == 0 and total("deaths") == 0)
    fixture() recapAPI({ recapRow(npc, 0) }) T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0, "a PvE-only recap never creates a player record")
end)

test("explicit CLE fatal source stays primary and recap cannot duplicate aggression", function()
    local a = start(opponent("cle")) local b = opponent("recap")
    local rows = recapAPI({})
    cle("SPELL_DAMAGE", a, unitData.player, -1, 64)
    cle("SPELL_DAMAGE", a, unitData.player, 0, 64)
    T.HandleEvent("PLAYER_DEAD")
    rows[1], rows[2] = recapRow(a), recapRow(b, 0)
    T.Poll()
    assert(GL.Get("guid:" .. a.guid).pvp.deaths == 1)
    assert(GL.Get("guid:" .. b.guid).pvp.probableDeaths == 1 and total("deaths") == 1)
    assert(total("aggressions") == 2, "CLE and recap report the same aggression once")
    cle("SPELL_DAMAGE", a, unitData.player, 0, 64) T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") + total("probableDeaths") == 2 and total("aggressions") == 2)
end)

test("world seed observes existing plates when combat starts after login", function()
    unitData.nameplate1, unitData.nameplate2 = opponent("seed1"), opponent("seed2")
    C_NamePlate = { GetNamePlates = function()
        return { { namePlateUnitToken = "nameplate1" }, { UnitFrame = { unit = "nameplate2" } } }
    end }
    T.HandleEvent("PLAYER_ENTERING_WORLD")
    assert(count() == 0)
    T.HandleEvent("PLAYER_REGEN_DISABLED") T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 2)
end)

test("reload while in combat seeds visible attackers without a new regen event", function()
    local saved = GL.db fixture(saved)
    unitData.player.combat = true unitData.nameplate1 = opponent("reload")
    C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" } } end }
    T.HandleEvent("PLAYER_ENTERING_WORLD") T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 1)
end)

test("resurrection and world changes cancel a pending death batch", function()
    for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
        fixture() local e = start() local rows = recapAPI({})
        unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
        unitData.player.dead = false T.HandleEvent(event)
        rows[1] = recapRow(e, 0)
        now = now + 2 T.Poll()
        assert(count() == 0, event .. " must cancel the old pending death")
    end
end)

test("ghost alive event does not rearm but real resurrection permits a new batch", function()
    local a = start() recapAPI({})
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_ALIVE")
    unitData.target = opponent("after-ghost")
    T.HandleEvent("PLAYER_TARGET_CHANGED") T.HandleEvent("PLAYER_DEAD")
    now = now + 2 T.Poll()
    assert(total("probableDeaths") == 1 and GL.Get("guid:" .. a.guid))
    unitData.player.dead = false T.HandleEvent("PLAYER_UNGHOST")
    local b = start(opponent("resurrected")) T.HandleEvent("PLAYER_DEAD")
    now = now + 2 T.Poll()
    assert(total("probableDeaths") == 2 and GL.Get("guid:" .. b.guid))
end)

test("reload while already dead cannot blame newly visible attackers", function()
    unitData.player.dead, unitData.player.combat = true, true
    unitData.nameplate1 = opponent("corpse-view")
    C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" } } end }
    recapAPI({ recapRow(unitData.nameplate1, 0) })
    T.HandleEvent("PLAYER_ENTERING_WORLD") T.HandleEvent("PLAYER_DEAD") T.Poll()
    assert(count() == 0)
end)

test("manual opinions override fatal inference but guild friendship does not", function()
    for _, manual in ipairs({ "friend", "warning" }) do
        fixture() start() local id = GL.Identity("target") GL.SetReaction(id, manual)
        T.HandleEvent("PLAYER_DEAD")
        assert(GL.Relation(GL.Get(id)) == manual and GL.Get(id).pvp.probableDeaths == 1)
    end
    fixture() start() local automatic = GL.SetReaction(GL.Identity("target"), "neutral")
    T.HandleEvent("PLAYER_DEAD")
    assert(GL.Relation(automatic) == "enemy" and automatic.reputation == -10)
    fixture() start() local id = GL.Identity("target") id.guild, id.realm = "Friendly Guild", "Forever"
    GL.Remember(id) GL.SetGuildReaction(id, "friend")
    T.HandleEvent("PLAYER_DEAD")
    assert(GL.Relation(GL.Get(id)) == "enemy" and GL.RelationSource(GL.Get(id)) == "pvp")
end)

test("tracking opt-out and duel start discard delayed native evidence", function()
    for _, mode in ipairs({ "disabled", "duel" }) do
        fixture() local e = start() local rows = recapAPI({})
        T.HandleEvent("PLAYER_DEAD")
        if mode == "disabled" then GL.SetSetting("pvpTracking", false) else T.HandleEvent("DUEL_REQUESTED") end
        rows[1] = recapRow(e, 0) now = now + 2 T.Poll()
        assert(count() == 0)
    end
end)

test("guild observed before combat survives recap-only identity and empty replies", function()
    local e = opponent("guild-cache") e.guild, e.realm, e.combat = "Old Guild", "Realm A", false
    unitData.mouseover = e T.HandleEvent("UPDATE_MOUSEOVER_UNIT")
    assert(count() == 0, "nearby bystanders must not enter the persistent journal")
    e.guild = nil now = now + 2
    unitData.mouseover = nil
    recapAPI({ recapRow(e, 0) }) T.HandleEvent("PLAYER_DEAD")
    local record = assert(GL.Get("guid:" .. e.guid))
    local death = record.history[#record.history]
    assert(record.guild == "Old Guild" and record.realm == "Realm A")
    assert(death.kind == "death" and death.guild == "Old Guild" and death.guildRealm == "Realm A")
    assert(death.guildObservedAt == 1000 and death.guildSource == "last-known")
    e.guild = "New Guild" unitData.target = e now = now + 1
    T.HandleEvent("PLAYER_GUILD_UPDATE", "target")
    assert(record.guild == "New Guild", "enrich after death without attributing another PvP event")
    assert(death.guild == "Old Guild" and total("deaths") == 1)
    e.guild = nil T.HandleEvent("UNIT_NAME_UPDATE", "target")
    assert(record.guild == "New Guild", "missing response is not proof of departure")
    fixture(GL.db)
    record = GL.Get("guid:" .. e.guid)
    assert(record.guild == "New Guild" and record.history[#record.history].guild == "Old Guild")
end)

test("unknown and old guild histories are never retroactively assigned", function()
    local e = opponent("guild-unknown")
    recapAPI({ recapRow(e, 0) }) T.HandleEvent("PLAYER_DEAD")
    local record = GL.Get("guid:" .. e.guid)
    local death = record.history[#record.history]
    assert(death.guild == nil and death.guildSource == "unknown")
    local legacy = { kind = "death", confidence = "probable", time = 900 }
    record.history[#record.history + 1] = legacy
    unitData.target = e e.guild = "Later Guild" now = now + 30
    T.HandleEvent("PLAYER_GUILD_UPDATE", "target")
    assert(record.guild == "Later Guild" and death.guild == nil and legacy.guild == nil)
    assert(GL.VoidPvP(record, death) and death.guildSource == "unknown" and death.voided)
end)

test("stale guild cache and recycled unit tokens cannot misidentify a killer", function()
    local e = opponent("guild-old") e.guild = "Old Guild" unitData.target = e
    T.HandleEvent("PLAYER_TARGET_CHANGED")
    local other = opponent("guild-new", e.name, e.surname) unitData.target = other
    assert(GL.Identity("target").guild == nil, "a shared full name is not a GUID match")
    now = now + 61 unitData.target = nil
    recapAPI({ recapRow(e, 0) }) T.HandleEvent("PLAYER_DEAD")
    assert(GL.Get("guid:" .. e.guid).guild == nil and count() == 1)
end)

test("guild cache has a fixed capacity without persisting unmarked people", function()
    local first = opponent("guild-first") first.guild = "Evicted Guild" unitData.target = first
    T.HandleEvent("PLAYER_TARGET_CHANGED") now = now + 1
    for i = 1, 256 do
        local e = opponent("guild-cap" .. i) e.guild = "Crowded Guild" unitData.target = e
        T.HandleEvent("PLAYER_TARGET_CHANGED")
    end
    assert(count() == 0)
    assert(GL.IdentityFromName(first.name, first.surname, first.guid).guild == nil)
end)

test("missing protected guild info preserves knowledge without leaking secret data", function()
    local e = start() e.guild = "Known Guild"
    T.Poll() cle("SPELL_DAMAGE", e, unitData.player, -1, 64)
    e.guild = secret now = now + 1 T.Poll()
    assert(GL.Get("guid:" .. e.guid).guild == "Known Guild")
    GetGuildInfo = function() error("unavailable") end
    T.HandleEvent("PLAYER_DEAD")
    local record = GL.Get("guid:" .. e.guid)
    assert(record.guild == "Known Guild" and record.history[#record.history].guild == "Known Guild")
    assert(#GL.errors == 0)
end)

test("all PvP event types snapshot guilds and multiple attackers share a death id", function()
    local a, b = opponent("guild-A"), opponent("guild-B") a.guild, b.guild = "One Guild", "One Guild"
    unitData.target, unitData.nameplate1 = a, b
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1") T.HandleEvent("PLAYER_TARGET_CHANGED")
    recapAPI({ recapRow(a, 0), recapRow(b) }) T.HandleEvent("PLAYER_DEAD")
    local ra, rb = GL.Get("guid:" .. a.guid), GL.Get("guid:" .. b.guid)
    local da, db = ra.history[#ra.history], rb.history[#rb.history]
    assert(da.eventId == db.eventId and da.guild == db.guild, "future guild counts can dedupe a shared death")
    assert(da.guildSource == "observed" and ra.history[1].guild == "One Guild")
    assert(da.confidence == "confirmed" and db.confidence == "probable")
    unitData.player.dead = false T.HandleEvent("PLAYER_ALIVE")
    a.guild = "Other Guild" now = now + 3
    cle("PARTY_KILL", unitData.player, a)
    assert(ra.history[#ra.history].kind == "kill" and ra.history[#ra.history].guild == "Other Guild")
    assert(da.guild == "One Guild")
end)

print("PASS: " .. passed .. " tracker scenarios (actual Core.lua + Tracker.lua).")
