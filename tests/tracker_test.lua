-- Executes the actual Core and Tracker with deterministic WoW API fixtures.
local now, unitData, groupSize, honor, secret, instanceType, GL, T, nativeFrame
local passed = 0

local function fixture(saved, formats)
    now, groupSize, honor, secret = 1000, 0, 0, {}
    instanceType = "none"
    function IsInInstance() return instanceType ~= "none", instanceType end
    C_DeathRecap, C_NamePlate, C_CombatLog = nil, nil, nil
    C_TooltipInfo, Enum, UnitTokenFromGUID, UnitNameFromGUID, UnitPlayerControlled, GetTime = nil, nil, nil, nil, nil, nil
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
    -- Client-owned GlobalStrings (Forever 1.60.1.70938), independent of the addon language.
    formats = formats or {}
    COMBATLOG_HONORGAIN = formats[1] or "%s dies (Honorable Kill: %s). You gain %d Honor."
    COMBATLOG_HONORGAIN_NO_RANK = formats[2] or "%s dies (Honorable Kill). You gain %d Honor."
    COMBATLOG_HONORGAIN_EXHAUSTION1 = "%s dies (Honorable Kill: %s). You gain %d Honor (%s %s bonus)."
    COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1 = "%s dies (Honorable Kill). You gain %d Honor (%s %s bonus)."
    if formats.unavailable then
        COMBATLOG_HONORGAIN, COMBATLOG_HONORGAIN_NO_RANK, COMBATLOG_HONORGAIN_EXHAUSTION1, COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1 = nil, nil, nil, nil
    end
    PVP_RANK_7_0, PVP_RANK_LEADER = formats[3] or "Sergeant", formats[4] or "Leader"
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
    nativeFrame = nil
    function CreateFrame()
        return { scripts = {},
            RegisterEvent = function(frame, event)
                if event == "COMBAT_LOG_EVENT_UNFILTERED" and not formats.combatFeed then error("Forbidden on Forever") end
                if event == "PARTY_KILL" then nativeFrame = frame end
            end,
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
local function cle(kind, src, dst, overkill, sourceFlags, targetFlags)
    local args = { now, kind, false, src.guid, src.name .. " " .. src.surname, sourceFlags or 0, 0,
        dst.guid, dst.name .. " " .. dst.surname, targetFlags or 0, 0 }
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

test("native killer is counted once in each life, including after PLAYER_DEAD", function()
    local e = start()
    for life = 1, 2 do
        unitData.target = nil
        T.HandleEvent("PLAYER_DEAD")
        unitData.target = e
        T.HandleEvent("PARTY_KILL", e.guid, unitData.player.guid)
        T.HandleEvent("PLAYER_DEAD")
        assert(total("deaths") == life)
        T.HandleEvent("PLAYER_UNGHOST")
        now = now + 1
        start(e)
    end
end)

test("one recent hostile gives one death", function()
    start()
    T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1)
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
    assert(total("deaths") == 2 and count() == 2)
    T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 2, "duplicate death events must not repeat the batch")
end)

test("NPC pressure prevents mixed PvE guess", function()
    start()
    unitData.mouseover = { guid = "Creature-1-wolf", hostile = true, combat = true, target = "player", isPlayer = false, dead = false }
    T.Poll()
    T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 0)
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
    assert(total("deaths") == 1)
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
    assert(total("deaths") == 1)
end)

test("ignored duel request eventually stops suppressing tracking", function()
    StartDuel("target")
    now = now + 121
    start() T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1)
end)

test("ordinary combat cannot make an ignored duel request permanent", function()
    StartDuel("target")
    unitData.player.combat = true start()
    now = now + 121 T.Poll()
    unitData.player.combat = false T.HandleEvent("PLAYER_REGEN_ENABLED") T.Poll()
    start() T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1)
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
    start(e) T.HandleEvent("PLAYER_DEAD") assert(total("deaths") == 1)
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
    assert(total("kills") == 1)
end)

test("two identical first names never merged", function()
    cle("PARTY_KILL", unitData.player, opponent("one", "Alex", "Alpha"))
    cle("PARTY_KILL", unitData.player, opponent("two", "Alex", "Beta"))
    assert(count() == 2 and total("kills") == 2)
end)

test("solo observed death plus honor count gives probable kill", function()
    local e = start()
    killedTarget()
    assert(total("kills") == 1)
    T.HandleEvent("CHAT_MSG_COMBAT_HONOR_GAIN", e.name .. " " .. e.surname .. " dies.")
    cle("PARTY_KILL", unitData.player, e)
    T.Poll()
    assert(total("kills") == 1, "late confirmation must upgrade in place")
end)

test("Forever native PARTY_KILL works even when the client rejects combat-log registration", function()
    local e = start()
    assert(T.nativeKillEvent and nativeFrame and nativeFrame.scripts.OnEvent)
    local function fire(attacker, victim) nativeFrame.scripts.OnEvent(nativeFrame, "PARTY_KILL", attacker, victim) end
    fire(secret, e.guid) fire(unitData.player.guid, secret)
    fire(nil, e.guid) fire("Player-1-stranger", e.guid)
    fire(unitData.player.guid, "Creature-1-npc") fire(unitData.player.guid, unitData.player.guid)
    assert(total("kills") == 0 and #GL.errors == 0)
    groupSize = 3
    fire(unitData.player.guid, e.guid)
    cle("PARTY_KILL", unitData.player, e)
    assert(total("kills") == 1 and #GL.errors == 0)
end)

test("only our verified pet killing blow counts for us", function()
    local e, pet = start(), {guid="Pet-1-mine", name="Loup", surname="Bleu"}
    unitData.pet = pet
    T.HandleEvent("PARTY_KILL", "Pet-1-foreign", e.guid)
    cle("SPELL_DAMAGE", {guid="Pet-1-foreign",name="Other",surname="Pet"}, e, 120, 0, 64)
    assert(total("kills") == 0)
    T.HandleEvent("PARTY_KILL", pet.guid, e.guid)
    cle("PARTY_KILL", pet, e)
    local r = GL.Get("guid:" .. e.guid)
    assert(r.pvp.kills == 1 and r.history[#r.history].evidence:find("familier",1,true))
end)

test("ambiguous, protected or non-health amounts cannot confirm an outgoing kill", function()
    local e = start()
    for _, kind in ipairs({"SPELL_DRAIN","SPELL_LEECH","SPELL_MISSED","ENVIRONMENTAL_DAMAGE"}) do
        cle(kind, unitData.player, e, 100, 0, 64)
    end
    for _, excess in ipairs({-1,0,301,secret,math.huge}) do cle("SWING_DAMAGE", unitData.player, e, excess, 0, 64) end
    cle("SPELL_DAMAGE", unitData.player, e, 5, 0, 16)
    assert(total("kills") == 0)
    cle("SPELL_PERIODIC_DAMAGE", unitData.player, e, 5, 0, 64)
    cle("PARTY_KILL", unitData.player, e)
    assert(total("kills") == 1)
    local second = opponent("next")
    cle("SWING_DAMAGE", unitData.player, second, 12, 0, 64)
    cle("SPELL_INSTAKILL", unitData.player, opponent("third"), nil, 0, 64)
    assert(total("kills") == 3)
end)

test("deferred native proof updates only the same defeat; a later life can earn another", function()
    local e = start()
    killedTarget()
    local r = GL.Get("guid:" .. e.guid)
    local first, n = r.history[#r.history], #r.history
    local time, id = first.time, first.eventId
    now = now + 6
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    assert(#r.history == n and r.pvp.kills == 1)
    assert(first.time == time and first.eventId == id and not first.playerConfirmedAt)
    e.dead = false
    T.Poll()
    killedTarget()
    assert(r.pvp.kills == 2)
    local second = r.history[#r.history]
    assert(second.eventId ~= first.eventId and GL.VoidPvP(r, second))
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    assert(r.pvp.kills == 1)
end)

test("native killing-blow attribution works without honor and respects opt-out and exclusions", function()
    local e = opponent("remote", "Feri", "Exemple")
    UnitNameFromGUID = function(guid) if guid == e.guid then return "Feri Exemple" end end
    for _, scope in ipairs({"pvp","arena"}) do
        instanceType = scope T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    end
    instanceType = "none"
    GL.SetSetting("pvpTracking", false) T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    GL.SetSetting("pvpTracking", true) T.HandleEvent("DUEL_INBOUNDS")
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    assert(count() == 0)
    T.HandleEvent("DUEL_FINISHED")
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    assert(total("kills") == 1 and GL.Get("guid:" .. e.guid).fullName == "Feri Exemple")
end)

test("a named probable then the victim's visible GUID point to the same event", function()
    local e = opponent("named")
    local guid = e.guid
    e.guid = nil
    start(e)
    killedTarget()
    assert(total("kills") == 1)
    e.guid = guid
    T.HandleEvent("PARTY_KILL", unitData.player.guid, guid)
    local r = assert(GL.Get("guid:" .. guid))
    assert(r.pvp.kills == 1 and total("kills") == 1 and count() == 1)
end)

test("native blows resolve exact victim GUIDs without a target, including two rapidly repeated wins", function()
    local victim = opponent("same-first", "Feri", "Second")
    local friend = opponent("friend", "Feri", "Premier")
    friend.hostile = false
    unitData.mouseover = friend
    GL.SetReaction(GL.Identity("mouseover"), "friend")
    UnitTokenFromGUID = function() return "mouseover" end -- recycled, unrelated unit
    T.HandleEvent("PARTY_KILL", unitData.player.guid, victim.guid)
    assert(total("kills") == 0 and count() == 1, "an unresolved GUID must never become the mouseover")
    UnitNameFromGUID = function(guid) if guid == victim.guid then return "Feri Second" end end
    T.HandleEvent("PARTY_KILL", unitData.player.guid, victim.guid)
    local r = assert(GL.Get("guid:" .. victim.guid))
    UnitNameFromGUID = nil
    now = now + 3
    T.HandleEvent("PARTY_KILL", unitData.player.guid, victim.guid)
    cle("PARTY_KILL", unitData.player, victim)
    assert(r.pvp.kills == 2 and GL.Get("guid:" .. friend.guid).pvp.kills == 0)
end)

test("a corpse first seen after death never qualifies", function()
    local e = opponent("corpse") e.dead = true
    start(e)
    honor = 1 T.HandleEvent("PLAYER_PVP_KILLS_CHANGED")
    T.OnHonorMessage("Alex corpse dies.")
    now = now + 1 T.Poll()
    assert(count() == 0)
end)

test("a different proven killer excludes the shared honor before or after inference", function()
    for _, late in ipairs({false, true}) do
        fixture()
        local e, other = start(), opponent("elsewhere")
        if not late then T.HandleEvent("PARTY_KILL", other.guid, e.guid) end
        killedTarget()
        if late then
            assert(total("kills") == 1)
            cle("SPELL_DAMAGE", other, e, 10, 64, 64)
            local r = GL.Get("guid:" .. e.guid)
            local revoked = r.history[#r.history]
            assert(revoked.voided and not revoked.voidedByGUID and not revoked.voidedByName)
            assert(revoked.voidReason == "other-killer" and revoked.evidence and not revoked.evidence:find("un autre joueur", 1, true))
        end
        T.Poll()
        assert(total("kills") == 0, "shared honor cannot beat an explicit foreign killing blow")
        assert(not GL.Get("guid:" .. other.guid), "another player's kill must not add the killer to the journal")
        e.dead = false
        T.Poll()
        killedTarget()
        assert(total("kills") == 1, "a different attack in the victim's next life can still qualify")
    end
end)

test("foreign killing evidence for another victim cannot remove this victim's win", function()
    local e, other = start(), opponent("elsewhere")
    killedTarget()
    T.HandleEvent("PARTY_KILL", other.guid, "Player-1-another")
    assert(total("kills") == 1)
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    T.HandleEvent("PARTY_KILL", other.guid, e.guid)
    assert(total("kills") == 1, "automatic reconciliation never overwrites a personal killing-blow confirmation")
end)

test("late CLE corroboration of a continuously observed corpse upgrades the same episode", function()
    local e = start()
    killedTarget()
    local r = assert(GL.Get("guid:" .. e.guid))
    local n = #r.history
    for i = 1, 12 do now = now + 1 T.Poll() end
    cle("PARTY_KILL", unitData.player, e)
    assert(#r.history == n and r.pvp.kills == 1, "one corpse must not yield two credits")
    T.HandleEvent("PLAYER_REGEN_ENABLED")
    for i = 1, 15 do now = now + 1 T.Poll() end
    cle("PARTY_KILL", unitData.player, e)
    assert(r.pvp.kills == 1, "the same visible corpse is still the same defeat after combat ends")
end)

test("a different kill with no continued observation cannot revoke an older estimate", function()
    local e = start()
    killedTarget()
    unitData.target = nil
    now = now + 8
    T.HandleEvent("PARTY_KILL", "Player-1-other", e.guid)
    assert(total("kills") == 1, "no observation connects this kill to the earlier defeat")
end)

test("seeing a corpse after a long polling gap cannot refresh an expired attribution", function()
    local e = start()
    killedTarget()
    now = now + 30
    T.Poll()
    T.HandleEvent("PARTY_KILL", "Player-1-other", e.guid)
    assert(total("kills") == 1)
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
    assert(total("kills") == 0)
    cle("PARTY_KILL", unitData.player, unitData.target)
    assert(total("kills") == 1)
end)

local function honorChat(text, lineID)
    nativeFrame.scripts.OnEvent(nativeFrame, "CHAT_MSG_COMBAT_HONOR_GAIN", text, "", "", "", "", "", 0, 0,
        "", 0, lineID, "Player-1-sender")
end

test("shared awards use the received integer exactly once independently of kills and bonus text", function()
    groupSize = 5
    local e = start(opponent("award", "Alex", "Verdant"))
    unitData.focus = opponent("bystander", "Alex", "Other")
    local text = COMBATLOG_HONORGAIN_EXHAUSTION1:format("Alex Verdant", "Sergeant", 18, "200%", "rested")
    honorChat(text, 501)
    honorChat(text, 502)
    honorChat(text, 501) -- redelivery after another award, at the same timestamp
    killedTarget()
    T.HandleEvent("PARTY_KILL", unitData.focus.guid, e.guid)
    honorChat(COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1:format("Alex Verdant", 4, "20%", "rested"), 503)
    local stats = GL.PersonalStatistics()
    assert(stats.honor == 40 and stats.honorAwards == 3 and stats.bestHonor == 18 and stats.unassignedHonor == 0)
    local contact = GL.ContactMatchup(GL.Get("guid:" .. e.guid))
    assert(contact.honor == 40 and contact.kills == 0 and contact.probableKills == nil)
    assert(count() == 1 and GL.Get("guid:Player-1-sender") == nil and GL.Get("guid:" .. unitData.focus.guid) == nil)
end)

test("real French and Spanish receipts plus reordered arguments retain the correct name and amount", function()
    for _, example in ipairs({
        {"%s meurt (victoire honorable : %s). Vous gagnez %d points d’honneur.", "Sergent",
            "Anaïs Sève meurt (victoire honorable : Sergent). Vous gagnez 23 points d’honneur."},
        {"%s muere (muerte con honor: %s). Obtienes %d p. de honor.", "Sargento",
            "Anaïs Sève muere (muerte con honor: Sargento). Obtienes 23 p. de honor."},
        {"%s murió (Muerte honorable: %s). Recibes %d p. de Honor.", "Sargento",
            "Anaïs Sève murió (Muerte honorable: Sargento). Recibes 23 p. de Honor."},
        {"%3$d [100%%] (%2$s) + %1$s.", "Sergent", "23 [100%] (Sergent) + Anaïs Sève."},
    }) do
        fixture(nil, {example[1], nil, example[2]})
        honorChat(example[3], 80)
        assert(GL.ContactMatchup(GL.Get(GL.IdentityFromName("Anaïs Sève"))).honor == 23, example[3])
        assert(GL.PersonalStatistics().unassignedHonor == 0 and count() == 1)
    end
end)

test("grammatical alternatives in native Russian and Korean receipts are expanded at load", function()
    local russian = "%s погибает (рейтинг почетной победы: %s). Вы получаете %d |4очко:очка:очков; чести."
    fixture(nil, {russian, nil, "Сержант"})
    for _, row in ipairs({{1, "очко"}, {2, "очка"}, {10, "очков"}}) do
        honorChat(("Анна Лес погибает (рейтинг почетной победы: Сержант). Вы получаете %d %s чести."):format(row[1], row[2]))
    end
    assert(GL.ContactMatchup(GL.Get(GL.IdentityFromName("Анна Лес"))).honor == 13)
    fixture(nil, {"%s|1이;가; 죽었습니다(명예 승수: %s). %d의 명예를 획득했습니다.", nil, "하사관"})
    for _, particle in ipairs({"이", "가"}) do
        honorChat("아나 숲" .. particle .. " 죽었습니다(명예 승수: 하사관). 7의 명예를 획득했습니다.")
    end
    assert(GL.ContactMatchup(GL.Get(GL.IdentityFromName("아나 숲"))).honor == 14)
end)

test("only a new verified named receipt signals an isolated probable kill when templates exist", function()
    local e = start()
    local msg = COMBATLOG_HONORGAIN_EXHAUSTION1:format("Alex enemy", "Sergeant", 0, "100%", "rested")
    honorChat(msg, 19)
    now = now + 5 T.Poll()
    e.dead = true T.Poll()
    honorChat(msg, 19)
    honorChat(COMBATLOG_HONORGAIN:format("Alex enemy", "Leader", 7), 20)
    honorChat("Alex enemy dies.", 21)
    now = now + 1 T.Poll()
    assert(GL.PersonalStatistics().honorAwards == 1 and total("kills") == 0)
    honorChat(msg, 22)
    assert(GL.PersonalStatistics().honorAwards == 2 and GL.PersonalStatistics().honor == 0 and total("kills") == 1)
    fixture(nil, {unavailable=true})
    e = start()
    now = now + 1 e.dead = true T.Poll()
    honorChat("Alex enemy dies.")
    now = now + 1 T.Poll()
    assert(GL.PersonalStatistics().honorAwards == 0 and total("kills") == 1)
end)

test("bare and colliding player names remain personal honor without a contact", function()
    local a, b = opponent("first", "Alex", "Same"), opponent("second", "Alex", "Same")
    unitData.target, unitData.focus = a, b
    honorChat(COMBATLOG_HONORGAIN:format("Alex", "Sergeant", 3), 40)
    honorChat(COMBATLOG_HONORGAIN_NO_RANK:format("Alex Same", 5), 41)
    assert(count() == 0)
    GL.Remember(GL.Identity("target")) GL.Remember(GL.Identity("focus"))
    unitData.target, unitData.focus = nil, nil
    honorChat(COMBATLOG_HONORGAIN:format("Alex Same", "Sergeant", 2), 42)
    honorChat(COMBATLOG_HONORGAIN_NO_RANK:format("|cffaaccdd|Hplayer:Alex-Forever:32|h[Alex]|h|r", 1), 43)
    local stats = GL.PersonalStatistics()
    assert(stats.honor == 11 and stats.unassignedHonor == 11 and stats.honorAwards == 4 and count() == 2)
    assert(GL.ContactMatchup(GL.Get("guid:" .. a.guid)).honor == 0 and GL.ContactMatchup(GL.Get("guid:" .. b.guid)).honor == 0)
end)

test("rankless text needs player evidence and a missing chat ID cannot erase successive awards", function()
    local msg = COMBATLOG_HONORGAIN_NO_RANK:format("Alex Green", 6)
    honorChat(msg)
    assert(GL.PersonalStatistics().honorAwards == 0)
    local e = start(opponent("known", "Alex", "Green"))
    T.HandleEvent("PLAYER_REGEN_ENABLED")
    unitData.target = nil -- the recently observed combatant still proves the name
    honorChat(msg) honorChat(msg)
    honorChat(COMBATLOG_HONORGAIN:format("Alex Green", "Sergeant", 0), 3)
    honorChat(COMBATLOG_HONORGAIN_NO_RANK:format("|cnHIGHLIGHT_FONT_COLOR:|Hplayer:Alex Green-Forever:7|h[Alex]|h|r", 1), 4)
    T.HandleEvent("PLAYER_ENTERING_WORLD")
    assert(GL.PersonalStatistics().honor == 13 and count() == 1)
    honorChat(COMBATLOG_HONORGAIN_NO_RANK:format("|cffbbccdd|Hplayer:New Name:7|h[Alex Green]|h|r", 2), 5)
    assert(GL.ContactMatchup(GL.Get("name:new name")).honor == 2, "only the native player link's destination owns the award")
    local stats = GL.PersonalStatistics()
    assert(stats.honor == 15 and stats.honorAwards == 5 and GL.ContactMatchup(GL.Get("guid:" .. e.guid)).honor == 13)
end)

test("NPCs, flat awards, secret or malformed receipts and restricted locations award no points", function()
    local msg = COMBATLOG_HONORGAIN:format("Alex Green", "Sergeant", 8)
    unitData.target = { guid = "Creature-1-leader", name = "Alex Green", isPlayer = false }
    honorChat(msg, 1)
    unitData.target = nil
    for i, text in ipairs({
        "You have been awarded 99 Honor.", "Alex Green dies.", "Reward: " .. msg, msg .. " extra",
        msg:gsub("8", "8.5"), msg:gsub("8", "8,5"), msg:gsub("8", "-8"), msg:gsub("8", "2147483648"),
        COMBATLOG_HONORGAIN:format("Alex Green", "Leader", 99),
        COMBATLOG_HONORGAIN:format("Testeur Exemple", "Sergeant", 99),
        COMBATLOG_HONORGAIN_NO_RANK:format("|Hunit:Creature-1-npc|h[Alex Green]|h", 99), secret,
    }) do honorChat(text, i + 10) end
    for i, kind in ipairs({"pvp", "arena", "party", "raid", "scenario"}) do instanceType = kind honorChat(msg, 30 + i) end
    instanceType = "none"
    T.HandleEvent("DUEL_INBOUNDS") honorChat(msg, 41) T.HandleEvent("DUEL_FINISHED")
    GL.Settings().pvpTracking = false honorChat(msg, 42) GL.Settings().pvpTracking = true
    T.HandleEvent("PLAYER_LEAVING_WORLD") honorChat(msg, 43) T.HandleEvent("PLAYER_ENTERING_WORLD")
    local old = IsInInstance
    IsInInstance = function() return secret, secret end
    honorChat(msg, 44)
    IsInInstance = old
    assert(GL.PersonalStatistics().honorAwards == 0 and count() == 0)
    honorChat(msg, 45)
    assert(GL.PersonalStatistics().honor == 8)
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
    assert(total("kills") == 0)
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
    assert(total("deaths") == 1)
    T.HandleEvent("PLAYER_ALIVE")
    start(e)
    cle("SPELL_DAMAGE", e, unitData.player, -1, 64)
    T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 2)
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
    assert(total("deaths") == 1)
    T.HandleEvent("PLAYER_ALIVE")
    start() T.HandleEvent("PLAYER_REGEN_ENABLED")
    now = now + 4 T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1)
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
    assert(total("aggressions") == 0 and count() == 0)
end)

test("one recent attacker plus health loss records probable aggression once", function()
    start()
    now = now + 1 unitData.player.health = 900 T.HandleEvent("UNIT_HEALTH", "player")
    now = now + 1 T.Poll()
    assert(total("aggressions") == 1)
    assert(GL.Relation(GL.Get(GL.Identity("target"))) == "enemy")
    unitData.player.health = 800 T.Poll() now = now + 1 T.Poll()
    assert(total("aggressions") == 1)
end)

test("health loss under multiple targeting attackers records probable participation", function()
    start()
    unitData.nameplate1 = opponent("second") T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    now = now + 1 unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll()
    assert(total("aggressions") == 2)
end)

test("a dead opponent cannot explain a fresh health drop", function()
    local e = start()
    now = now + 1 e.dead = true unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll()
    assert(total("aggressions") == 0)
end)

test("post-death health updates and pending guesses cannot create aggression", function()
    start()
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    now = now + 1 unitData.player.health = 0 T.Poll()
    now = now + 1 T.Poll()
    assert(total("aggressions") == 0)
    fixture() start()
    now = now + 1 unitData.player.health = 900 T.Poll()
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    now = now + 1 T.Poll()
    assert(total("aggressions") == 0)
end)

test("explicit friendly or different hostile damage cancels health guesses", function()
    start()
    local friendly = opponent("friend") friendly.hostile = false groupSize = 2
    now = now + 1 unitData.player.health = 900 T.Poll()
    cle("SPELL_DAMAGE", friendly, unitData.player, -1, 16)
    now = now + 1 T.Poll()
    assert(total("aggressions") == 0)
    fixture() start()
    now = now + 1 unitData.player.health = 900 T.Poll()
    cle("SPELL_DAMAGE", opponent("different"), unitData.player, -1, 64)
    now = now + 1 T.Poll()
    assert(total("aggressions") == 1)
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
    assert(total("aggressions") == 1)
    T.HandleEvent("PLAYER_REGEN_ENABLED")
    now = now + 5
    cle("SPELL_DAMAGE", e, unitData.player, -1, 64)
    assert(total("aggressions") == 2)
end)

local function idlePair(e)
    e = e or opponent("opening", "Asha", "Brightvale")
    unitData.target = e
    e.combat, unitData.player.combat = false, false
    T.Poll()
    e.combat, unitData.player.combat = true, true
    return e
end

local function entries(e, kind)
    local record, rows = GL.Get("guid:" .. e.guid), {}
    for _, entry in ipairs(record and record.history or {}) do
        if entry.kind == kind then rows[#rows + 1] = entry end
    end
    return rows
end

test("first incoming damage before regen records an independent opening and keeps the pre-hit opinion", function()
    fixture(nil, {combatFeed=true})
    local e = idlePair()
    CombatLogGetCurrentEventInfo = function()
        -- Optional name/raid flag slots may be nil; the observed GUID is enough.
        return now, "SWING_DAMAGE", false, e.guid, nil, 64, nil, unitData.player.guid, nil, 16, nil, 85, -1
    end
    nativeFrame.scripts.OnEvent(nativeFrame, "COMBAT_LOG_EVENT_UNFILTERED")
    nativeFrame.scripts.OnEvent(nativeFrame, "PLAYER_REGEN_DISABLED")
    cle("SPELL_DAMAGE", e, unitData.player, -1, 64)
    assert(#entries(e, "opening") == 1 and #entries(e, "aggression") == 1 and total("kills") == 0)
    local stats = GL.PersonalStatistics()
    assert(stats.responded == 1 and stats.attackers == 1 and stats.victims == 0)
    local opening = entries(e, "opening")[1]
    assert(opening.opener == "opponent" and opening.hadGrudge == false and opening.priorDeath == false)
    GL.SetReaction(GL.Identity("target"), "enemy")
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    local c = entries(e, "kill")[1].combat
    assert(c.opener == "opponent" and c.hadGrudge == false and c.priorDeath == false and c.encounterId == opening.encounterId)
    now = now + 1
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    assert(not entries(e, "kill")[2].combat.opener, "a second death cannot inherit the first life’s opening")
end)

test("outgoing opener snapshots guild hostility, prior death and new encounter without creating an aggression", function()
    fixture(nil, {combatFeed=true})
    local e = opponent("remembered", "Alex", "Aube")
    e.guild = "Guild"
    local id = GL.IdentityFromName(e.name, e.surname, e.guid)
    local oldRecord = GL.RecordPvP(id, "death", "confirmed", "test", "earlier-death")
    GL.SetGuildReaction("Guild", "enemy")
    now = now + 5
    idlePair(e)
    T.HandleEvent("PLAYER_REGEN_DISABLED")
    cle("SPELL_DAMAGE", unitData.player, e, -1, 0, 64)
    assert(#entries(e, "opening") == 1 and oldRecord.pvp.aggressions == 0 and total("kills") == 0)
    GL.SetReaction(GL.Identity("target"), "friend")
    cle("SPELL_DAMAGE", e, unitData.player, 1, 64)
    local c = entries(e, "death")[2].combat
    assert(c.opener == "player" and c.hadGrudge == true and c.priorDeath == true)
    T.HandleEvent("PLAYER_ALIVE")
    now = now + 3
    idlePair(e)
    cle("RANGE_DAMAGE", e, unitData.player, -1, 64)
    T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
    local again = entries(e, "kill")[1].combat
    assert(again.encounterId ~= c.encounterId and again.opener == "opponent" and again.hadGrudge == false)
end)

test("owner-verified combat pets can open in either direction", function()
    for _, direction in ipairs({"player", "opponent", "own summon", "opponent hit pet"}) do
        fixture(nil, {combatFeed=true})
        local e = idlePair()
        local own = {guid="Pet-1-own", name="Loup", surname=""}
        local other = {guid="Pet-1-other", name="Loup", surname=""}
        unitData.pet = own
        cle("SPELL_SUMMON", e, other, nil, 64)
        if direction == "own summon" then
            own = {guid="Creature-1-totem", name="Totem", surname=""}
            cle("SPELL_SUMMON", unitData.player, own, nil, 16)
        end
        local outgoing = direction == "player" or direction == "own summon"
        if outgoing then cle("SPELL_DAMAGE", own, other, -1, 16, 64)
        else cle("SWING_DAMAGE", other, direction == "opponent hit pet" and own or unitData.player, -1, 64) end
        T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
        local c = entries(e, "kill")[1].combat
        assert(#entries(e, "opening") == 1 and c.opener == (outgoing and "player" or "opponent"), direction)
    end
end)

test("a guild grudge without a past defeat and a manual exception survive as separate opening facts", function()
    for _, friend in ipairs({false, true}) do
        fixture(nil, {combatFeed=true})
        local e = opponent("guild", "Alex", "Garde")
        GL.SetGuildReaction("Enemies", "enemy")
        idlePair(e)
        GL.Remember(GL.Identity("target"))
        e.guild = "Enemies" -- new guild visible on first damage, after prior idle observation
        if friend then GL.SetReaction(GL.Identity("target"), "friend") end
        cle("SWING_DAMAGE", unitData.player, e, -1, 16, 64)
        local opening = entries(e, "opening")[1]
        assert(opening and opening.priorDeath == false and opening.hadGrudge == (not friend))
        assert(total("aggressions") == 0 and total("kills") == 0)
    end
end)

test("rapid separate defeats of the same GUID retain each observed opening", function()
    fixture(nil, {combatFeed=true})
    local e = idlePair()
    cle("SWING_DAMAGE", unitData.player, e, 1, 16, 64)
    T.HandleEvent("PLAYER_REGEN_ENABLED")
    now = now + 1
    idlePair(e)
    cle("SWING_DAMAGE", e, unitData.player, -1, 64)
    cle("SWING_DAMAGE", unitData.player, e, 1, 16, 64)
    local outcomes = entries(e, "kill")
    assert(#outcomes == 2 and outcomes[1].combat.opener == "player" and outcomes[2].combat.opener == "opponent")
    assert(outcomes[1].combat.encounterId ~= outcomes[2].combat.encounterId)
end)

test("late, indirect, obscured or mixed beginnings never turn retaliation into an opening", function()
    for _, reason in ipairs({"in-progress", "already fighting", "expired", "third party", "periodic", "crowd control", "missed opener", "unowned pet",
        "prior health loss", "opaque damage", "group", "instance", "duel", "world change", "restricted feed", "same first name"}) do
        fixture(nil, {combatFeed=reason ~= "restricted feed"})
        local e = idlePair()
        local other = opponent("other", e.name, "Elsewhere")
        if reason == "in-progress" or reason == "world change" then T.HandleEvent("PLAYER_ENTERING_WORLD")
        elseif reason == "already fighting" then unitData.player.combat = false T.Poll() unitData.player.combat = true
        elseif reason == "expired" then now = now + 4
        elseif reason == "third party" then cle("SPELL_DAMAGE", other, e, -1, 64, 64)
        elseif reason == "periodic" then cle("SPELL_PERIODIC_DAMAGE", e, unitData.player, -1, 64)
        elseif reason == "crowd control" then cle("SPELL_AURA_APPLIED", e, unitData.player, nil, 64)
        elseif reason == "missed opener" then cle("SWING_MISSED", e, unitData.player, nil, 64)
        elseif reason == "unowned pet" then
            cle("SPELL_DAMAGE", {guid="Pet-1-missing", name="Loup", surname=""}, unitData.player, -1, 64)
        elseif reason == "opaque damage" then
            T.OnCombatLog(now, "SWING_DAMAGE", false, unitData.player.guid, "", 16, 0, e.guid, "", 64, 0, secret, -1)
        elseif reason == "group" then groupSize = 2
        elseif reason == "instance" then instanceType = "party"
        elseif reason == "duel" then T.HandleEvent("DUEL_INBOUNDS")
        elseif reason == "same first name" then unitData.target = other e = other end
        T.HandleEvent("PLAYER_REGEN_DISABLED")
        if reason == "prior health loss" then unitData.player.health = 800 T.Poll() end
        cle("SWING_DAMAGE", e, unitData.player, -1, 64)
        cle("SWING_DAMAGE", unitData.player, e, -1, 0, 64)
        assert(#entries(e, "opening") == 0, reason)
        T.HandleEvent("PARTY_KILL", unitData.player.guid, e.guid)
        local kill = entries(e, "kill")[1]
        assert(not kill or not kill.combat or not kill.combat.opener, reason)
    end
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
    assert(total("aggressions") == 1)
end)

test("late confirmation does not double count already inferred aggression", function()
    local e = start()
    now = now + 1 unitData.player.health = 900 T.Poll()
    now = now + 1 T.Poll()
    cle("SWING_DAMAGE", e, unitData.player, -1, 64)
    assert(total("aggressions") == 1)
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
    assert(total("aggressions") == 3 and GL.Get("guid:" .. passerby.guid) == nil)
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_DEAD") T.Poll()
    assert(count() == 3 and total("deaths") == 3)
    local deathId
    for _, record in pairs(GL.db.players) do
        assert(record.pvp.aggressions == 1 and record.pvp.deaths == 1)
        for _, event in ipairs(record.history) do
            if event.kind == "death" then
                assert(event.confidence == "confirmed" and event.evidence:find("Participation", 1, true))
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
    assert(total("aggressions") == 1 and GL.Get("guid:" .. first.guid))
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
    assert(total("deaths") == 1 and GL.Get("guid:" .. first.guid))
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
    assert(count() == 1 and total("deaths") == 1)
    assert(total("aggressions") <= 1, "promotion cannot duplicate a health-loss observation")
end)

test("explicit nonlethal damager replaces targeting-only death candidates", function()
    local selected = start(opponent("selected"))
    local attacker = opponent("actual")
    cle("SPELL_DAMAGE", attacker, unitData.player, -1, 64)
    T.HandleEvent("PLAYER_DEAD")
    local record = GL.Get("guid:" .. attacker.guid)
    assert(record and record.pvp.aggressions == 1 and record.pvp.deaths == 1)
    assert(GL.Get("guid:" .. selected.guid) == nil and total("deaths") == 1)
end)

test("public recap identifies three unseen attackers and only the lethal source", function()
    local a, b, c = opponent("recapA"), opponent("recapB"), opponent("recapC")
    recapAPI({ recapRow(a), recapRow(a), recapRow(b), recapRow(c, 0) })
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_DEAD") T.Poll()
    assert(count() == 3 and total("aggressions") == 3)
    assert(total("deaths") == 3)
    assert(GL.Get("guid:" .. c.guid).pvp.deaths == 1)
    local batch
    for _, record in pairs(GL.db.players) do
        for _, event in ipairs(record.history) do
            if event.kind == "death" then batch = batch or event.eventId assert(batch == event.eventId) end
        end
    end
    now = now + 3 T.Poll()
    assert(total("aggressions") == 3 and total("deaths") == 3)
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
    assert(total("deaths") == 1)
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
    assert(GL.Get("guid:" .. b.guid).pvp.deaths == 1 and total("deaths") == 2)
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
    assert(GL.Get("guid:" .. e.guid).pvp.deaths == 1 and total("deaths") == 1)
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

test("a full recap name identifies a known hostile in mixed combat without source flags", function()
    local foe = start()
    local npc = {guid="Creature-1-wolf", name="Loup"}
    local row = recapRow(foe)
    row.sourceFlags, row.sourceGUID = nil, nil
    recapAPI({row, recapRow(npc, 0)})
    T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1 and total("aggressions") == 1)
end)

test("fatal NPC recap credits the hostile player who dealt damage", function()
    local e = start()
    local npc = { guid = "Creature-1-wolf", name = "Loup" }
    recapAPI({ recapRow(e), recapRow(npc, 0) })
    T.HandleEvent("PLAYER_DEAD")
    assert(total("aggressions") == 1 and count() == 1)
    assert(total("deaths") == 1)
    fixture() recapAPI({ recapRow(npc, 0) }) T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0, "a PvE-only recap never creates a player record")
end)

local function petTooltip(pet, owner)
    Enum = { TooltipDataLineType = { UnitOwner = 16 } }
    local data = { guid = pet.guid, lines = {
        { type = 2, guid = pet.guid }, { type = 16, guid = owner.guid } } }
    C_TooltipInfo = {
        GetHyperlink = function(link) if link == "unit:" .. pet.guid then return data end end,
        GetUnit = function(unit) if UnitGUID(unit) == pet.guid then return data end end,
    }
    UnitNameFromGUID = function(guid) if guid == owner.guid then return owner.name .. " " .. owner.surname end end
    return data
end

test("pet-only attack with no combat log or owner in sight resolves the lethal recap", function()
    local owner = opponent("hunter", "Denis", "Chassebois")
    local pet = { guid = "Pet-1-wolf", name = "Griffe" }
    petTooltip(pet, owner)
    GetTime = function() return 32.5 end
    local first, last = recapRow(pet, -1, 32.1), recapRow(pet, -1, 32.4)
    last.currentHP = 0 -- exact lethal damage even when no overkill was supplied
    recapAPI({last, first})
    T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_DEAD")
    local record = assert(GL.Get("guid:" .. owner.guid))
    assert(count() == 1 and record.pvp.deaths == 1 and record.pvp.aggressions == 1)
    assert(GL.Relation(record) == "enemy" and record.history[2].evidence:find("familier", 1, true))
end)

test("hunter and multiple summons in the same attack leave one aggression and death", function()
    local owner = opponent("bm")
    local a, b = {guid="Pet-1-A", name="Féroce", surname=""}, {guid="Creature-1-B", name="Féroce", surname=""}
    for _, pet in ipairs({a, b}) do cle("SPELL_SUMMON", owner, pet, nil, 64) end
    cle("SWING_DAMAGE", a, unitData.player, -1, 64)
    cle("SPELL_DAMAGE", owner, unitData.player, -1, 64)
    recapAPI({recapRow(a), recapRow(b, 1)})
    cle("SPELL_DAMAGE", b, unitData.player, 1, 64)
    T.HandleEvent("PLAYER_DEAD")
    local record = assert(GL.Get("guid:" .. owner.guid))
    assert(count() == 1 and record.pvp.deaths == 1 and record.pvp.aggressions == 1)
    assert(record.history[2].evidence:find("familier", 1, true))
end)

test("late owner on a recycled unit token is retried before finalizing a recap", function()
    local owner = opponent("late-owner")
    local pet = {guid="Pet-1-late", name="Griffe"}
    petTooltip(pet, owner)
    unitData.nameplate1 = opponent("unrelated")
    UnitTokenFromGUID = function() return "nameplate1" end
    C_TooltipInfo.GetHyperlink = nil
    recapAPI({recapRow(pet, 0)})
    T.HandleEvent("PLAYER_DEAD")
    assert(count() == 0)
    unitData.nameplate1 = pet
    now = now + 1
    T.Poll()
    assert(GL.Get("guid:" .. owner.guid).pvp.deaths == 1 and total("aggressions") == 1 and count() == 1)
end)

test("hostile pet independently targeting the player supports only a probable death", function()
    local owner = opponent("away") owner.combat, owner.target = false, nil
    local pet = {guid="Pet-1-visible",name="Griffe",hostile=true,combat=true,target="player",dead=false,isPlayer=false}
    UnitPlayerControlled = function(u) return UnitGUID(u) == pet.guid end
    start(owner)
    unitData.nameplate1 = pet
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    now = now + 1
    petTooltip(pet, owner)
    T.Poll()
    unitData.player.health = 850
    now = now + 1
    T.Poll()
    now = now + 1
    T.Poll()
    unitData.nameplate1, unitData.target = nil, nil -- captured before both leave
    T.HandleEvent("PLAYER_DEAD")
    local r = assert(GL.Get("guid:" .. owner.guid))
    assert(count() == 1 and r.pvp.deaths == 1)
    assert(r.pvp.aggressions == 1 and r.history[1].evidence:find("familier", 1, true))
end)

test("unknown pet, recycled tooltip, secret owner and friendly pets never accuse a nearby hunter", function()
    for _, failure in ipairs({"no-owner", "recycled", "friendly", "secret", "npc-owner", "untrusted-line", "instance", "duel"}) do
        fixture()
        local bystander = start(opponent("bystander"))
        local pet = {guid="Pet-1-mystery",name="Griffe"}
        local data = petTooltip(pet, bystander)
        if failure == "no-owner" then C_TooltipInfo = nil
        elseif failure == "recycled" then data.guid = "Pet-1-recycled"
        elseif failure == "secret" then data.lines[2].guid = secret
        elseif failure == "npc-owner" then data.lines[2].guid = "Creature-1-villager"
        elseif failure == "untrusted-line" then data.lines[2].type = 0
        elseif failure == "instance" then instanceType = "pvp"
        elseif failure == "duel" then T.HandleEvent("DUEL_INBOUNDS") end
        local fatal = recapRow(pet, 1)
        if failure == "friendly" then fatal.sourceFlags = 16 end
        recapAPI({fatal})
        T.HandleEvent("PLAYER_DEAD")
        now = now + 2 T.Poll()
        assert(count() == 0, failure)
    end
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
    assert(GL.Get("guid:" .. b.guid).pvp.deaths == 1 and total("deaths") == 2)
    assert(total("aggressions") == 2, "CLE and recap report the same aggression once")
    cle("SPELL_DAMAGE", a, unitData.player, 0, 64) T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 2 and total("aggressions") == 2)
end)

test("world seed observes existing plates when combat starts after login", function()
    unitData.nameplate1, unitData.nameplate2 = opponent("seed1"), opponent("seed2")
    C_NamePlate = { GetNamePlates = function()
        return { { namePlateUnitToken = "nameplate1" }, { UnitFrame = { unit = "nameplate2" } } }
    end }
    T.HandleEvent("PLAYER_ENTERING_WORLD")
    assert(count() == 0)
    T.HandleEvent("PLAYER_REGEN_DISABLED") T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 2)
end)

test("reload while in combat seeds visible attackers without a new regen event", function()
    local saved = GL.db fixture(saved)
    unitData.player.combat = true unitData.nameplate1 = opponent("reload")
    C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" } } end }
    T.HandleEvent("PLAYER_ENTERING_WORLD") T.HandleEvent("PLAYER_DEAD")
    assert(total("deaths") == 1)
end)

test("resurrection and world changes cancel a pending death batch", function()
    for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
        fixture() local e = start() local rows = recapAPI({})
        unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
        unitData.player.dead = false T.HandleEvent(event)
        rows[1] = recapRow(e, 0)
        now = now + 2 T.Poll()
        local expected = (event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST") and 1 or 0
        assert(total("deaths") == expected, event .. " handles the frozen encounter exactly once")
    end
end)

test("ghost alive event does not rearm but real resurrection permits a new batch", function()
    local a = start() recapAPI({})
    unitData.player.dead = true T.HandleEvent("PLAYER_DEAD")
    T.HandleEvent("PLAYER_ALIVE")
    unitData.target = opponent("after-ghost")
    T.HandleEvent("PLAYER_TARGET_CHANGED") T.HandleEvent("PLAYER_DEAD")
    now = now + 2 T.Poll()
    assert(total("deaths") == 1 and GL.Get("guid:" .. a.guid))
    unitData.player.dead = false T.HandleEvent("PLAYER_UNGHOST")
    local b = start(opponent("resurrected")) T.HandleEvent("PLAYER_DEAD")
    now = now + 2 T.Poll()
    assert(total("deaths") == 2 and GL.Get("guid:" .. b.guid))
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
        assert(GL.Relation(GL.Get(id)) == manual and GL.Get(id).pvp.deaths == 1)
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
    local legacy = { kind = "death", confidence = "confirmed", time = 900 }
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
    assert(da.confidence == "confirmed" and db.confidence == "confirmed")
    unitData.player.dead = false T.HandleEvent("PLAYER_ALIVE")
    a.guild = "Other Guild" now = now + 3
    cle("PARTY_KILL", unitData.player, a)
    assert(ra.history[#ra.history].kind == "kill" and ra.history[#ra.history].guild == "Other Guild")
    assert(da.guild == "One Guild")
end)

for _, kind in ipairs({ "pvp", "arena" }) do
    test(kind .. " ignores combat, death recap, honor and group memories, then resumes outdoors", function()
        local enemy = opponent("instance-enemy")
        local friend = opponent("instance-friend")
        unitData.party1, groupSize = friend, 2
        local identity = GL.Identity("party1")
        local record = GL.SetReaction(identity, "friend")
        local historyCount = #record.history
        instanceType = kind
        T.HandleEvent("PLAYER_ENTERING_WORLD")
        start(enemy)
        cle("SPELL_DAMAGE", enemy, unitData.player, -1, 64)
        cle("PARTY_KILL", unitData.player, enemy)
        recapAPI({ recapRow(enemy, 0) })
        unitData.player.dead = true
        T.HandleEvent("PLAYER_DEAD")
        now = now + 3
        T.Poll()
        killedTarget()
        T.HandleEvent("GROUP_ROSTER_UPDATE")
        assert(count() == 1 and #record.history == historyCount and record.groupCount == 0,
            "instance activity must not add players or alter existing memories")
        assert(total("deaths") + total("kills") == 0)
        instanceType, unitData.player.dead, enemy.dead = "none", false, false
        T.HandleEvent("PLAYER_ENTERING_WORLD")
        now = now + 3
        cle("SPELL_DAMAGE", enemy, unitData.player, -1, 64)
        cle("PARTY_KILL", unitData.player, enemy)
        assert(total("aggressions") == 1 and total("kills") == 1 and total("deaths") == 0,
            "world PvP resumes without replaying the instance death recap")
        assert(record.groupCount == 1, "ordinary group memories resume outside")
    end)
end

test("entering PvP clears a pending world death before it can be replayed", function()
    local enemy = opponent("delayed-recap")
    -- With no visible combatant or recap yet, resolution waits for a late recap.
    T.HandleEvent("PLAYER_DEAD")
    instanceType = "pvp"
    T.Poll()
    recapAPI({ recapRow(enemy, 0) })
    instanceType = "none"
    now = now + 3
    T.Poll()
    assert(count() == 0, "an interrupted death must not survive the instance boundary")
end)

test("fight context snapshots the first observed PvP signal and only evidenced combatants", function()
    UnitLevel = function(unit) return unitData[unit] and unitData[unit].level end
    unitData.player.health, unitData.player.level = 550, 35
    local hunter, other = opponent("hunter"), opponent("second")
    hunter.level, other.level = 41, 33
    start(hunter)
    cle("SPELL_DAMAGE", hunter, unitData.player, -1, 64)
    local hunterRecord = assert(GL.Get("guid:" .. hunter.guid))
    local hit = hunterRecord.history[#hunterRecord.history].combat
    assert(hit.healthPct == 55 and hit.playerLevel == 35 and hit.opponentLevel == 41 and hit.opponents == 1 and not hit.pve)
    local observer = opponent("observer") observer.target = nil
    unitData.nameplate1 = observer
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    unitData.player.health = 30
    unitData.nameplate2 = other
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
    local mob = { guid="Creature-1-wolf", name="Loup", surname="", hostile=true, combat=true, target="player", isPlayer=false }
    unitData.nameplate3 = mob
    UnitPlayerControlled = function(unit) return unit ~= "nameplate3" end
    T.HandleEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
    cle("SPELL_DAMAGE", other, unitData.player, 5, 64)
    local e = assert(GL.Get("guid:" .. other.guid)).history
    local death = e[#e]
    assert(death.kind == "death" and death.confidence == "confirmed")
    assert(death.combat.healthPct == 55 and death.combat.opponentLevel == 33 and death.combat.opponents == 2 and death.combat.pve)
    assert(hit.opponents == 1 and not hit.pve, "later observations must not change the original aggression")
    assert(not GL.Get("guid:" .. observer.guid))
end)

test("recap context attributes multiple pets to one owner and omits unobserved health and levels", function()
    local hunter = opponent("hunter")
    local wolf = {guid="Pet-1-wolf", name="Loup"}
    petTooltip(wolf, hunter)
    local a, b = recapRow(wolf, -1), recapRow(wolf, 1)
    recapAPI({a,b})
    T.HandleEvent("PLAYER_DEAD")
    local h = assert(GL.Get("guid:" .. hunter.guid)).history
    assert(h[1].combat.pet and h[2].combat.pet and h[2].combat.opponents == 1)
    assert(not h[2].combat.healthPct and not h[2].combat.playerLevel and not h[2].combat.opponentLevel)
end)

test("protected health and unknown levels produce no guessed fight context", function()
    local e = opponent("unknown")
    UnitLevel = function() return -1 end
    unitData.player.health = secret
    start(e)
    unitData.player.health = 25
    cle("SWING_DAMAGE", e, unitData.player, 1, 64)
    local h = assert(GL.Get("guid:" .. e.guid)).history
    assert(h[1].combat.opponents == 1 and not h[1].combat.healthPct and not h[1].combat.playerLevel and not h[1].combat.opponentLevel)
end)

print("PASS: " .. passed .. " tracker scenarios (actual Core.lua + Tracker.lua).")
