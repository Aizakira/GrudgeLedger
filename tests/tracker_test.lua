-- Executes the actual Core and Tracker with deterministic WoW API fixtures.
local now, unitData, groupSize, honor, secret, GL, T
local passed = 0

local function fixture(saved)
    now, groupSize, honor, secret = 1000, 0, 0, {}
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

test("ambiguous multiple enemies are not blamed", function()
    start()
    unitData.nameplate1 = opponent("second")
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    T.HandleEvent("PLAYER_DEAD")
    assert(total("probableDeaths") == 0 and count() == 0)
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
    unitData.party1 = opponent("companion") groupSize = 2 T.ScanGroup()
    local record = GL.Get(GL.Identity("party1"))
    unitData.party1 = nil T.ScanGroup()
    unitData.party1 = opponent("companion") T.ScanGroup()
    assert(record.groupCount == 1)
end)

test("GUID availability changes do not duplicate group history", function()
    local p = opponent("companion") p.guid = nil
    unitData.party1 = p groupSize = 2 T.ScanGroup()
    local record = GL.Get(GL.Identity("party1"))
    assert(record.groupCount == 1)
    p.guid = "Player-1-companion" T.ScanGroup()
    assert(record.groupCount == 1 and record.guid == p.guid)
    p.guid = secret T.ScanGroup()
    p.guid = "Player-1-companion" T.ScanGroup()
    assert(record.groupCount == 1)
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

test("health loss under multiple attackers remains unattributed", function()
    start()
    unitData.nameplate1 = opponent("second") T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    now = now + 1 unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll()
    assert(total("probableAggressions") == 0)
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

print("PASS: " .. passed .. " tracker scenarios (actual Core.lua + Tracker.lua).")
