local PROBE_FILE = TEST_ROOT .. "/MinimapProbe.lua"
-- Run with Lua 5.1 (or Lupa); no game client or network required.
local file = assert(io.open(PROBE_FILE, "r"))
local source = file:read("*a")
file:close()
local function run(mode)
    local env = setmetatable({}, { __index = _G })
    local messages, queue, events = {}, {}, {}
    local over, soft, point, moving, combat = mode ~= "no-hover" and mode ~= "late-hover", false, 0, false, false
    local captured, captureTick, ticks, speedReads = false, nil, 0, 0
    env.print = function(s)
        messages[#messages + 1] = s
        if s:find("Point capture", 1, true) then captured = true; captureTick = ticks end
    end
    local secret = {}
    env.issecretvalue = function(v) return v == secret end
    env.SlashCmdList = {}
    env.GrudgeLedger = { db = {}, Now = function() return 1000 end }
    env.InCombatLockdown = function() return combat end
    env.UnitIsDeadOrGhost = function() return false end
    env.GetUnitSpeed = function()
        speedReads = speedReads + 1
        if mode == "secret-speed" and speedReads > 1 then return secret end
        return moving and 1 or 0
    end
    env.GetCursorPosition = function() return mode == "secret-coordinate" and secret or 120, 180 end
    env.GetBuildInfo = function() return "1.60.1", "70888" end
    -- Forever removed this global. A mock must not silently bring it back.
    env.MouseIsOver = false
    env.CreateFrame = function() return {
        RegisterEvent = function() end,
        SetScript = function(_, _, f) events.fire = f end,
    } end
    env.C_Timer = { After = function(_, f) queue[#queue + 1] = f end }
    env.Minimap = {
        IsVisible = function() return true end,
        IsMouseOver = function() return over end,
        GetCenter = function() return 100, 150 end,
        GetEffectiveScale = function() return 0.8 end,
        GetZoom = function() return 1 end,
        SetUsingSoftCursor = function(_, on) soft = on end,
        UpdateMouseoverAtPoint = function(_, x)
            point = x
            if mode == "throws" and x > 0 then error("blocked") end
        end,
    }
    if mode == "missing-hover-api" then env.Minimap.IsMouseOver = nil end
    local reads = 0
    env.C_TooltipInfo = { GetMinimapMouseover = function()
        reads = reads + 1
        if mode == "tooltip-throws" then error("private Testeur error") end
        if mode == "secret" then return secret end
        if mode == "empty" then return nil end
        if mode == "metadata" and soft and point > 0 then
            return { lines = { { leftText = "Autre Joueur" }, { leftText = "Classe commune" } } }
        end
        if mode == "stale" or over or (soft and point > 0 and mode ~= "broken") or
            (mode == "blank-cache" and soft) then
            return { lines = { { leftText = "|cffff0000Testeur Exemple|r" }, { leftText = "Classe commune" } } }
        end
    end }
    assert(loadstring(source, "Probe.lua")); setfenv(assert(loadstring(source)), env)()
    assert(#messages == 0 and #queue == 0 and not soft, "must be dormant at load")
    env.GrudgeLedger.DruidRadarActive = function() return true end
    env.SlashCmdList.GRUDGELEDGERPROBE("test")
    assert(#queue == 0 and not soft, "druid and virtual cursor experiments are mutually exclusive")
    env.GrudgeLedger.DruidRadarActive = function() return false end
    env.SlashCmdList.GRUDGELEDGERPROBE("test")
    if mode ~= "missing-hover-api" then
        assert(#queue == 1)
        env.SlashCmdList.GRUDGELEDGERPROBE("test")
        assert(#queue == 1, "no parallel tests")
    end
    while #queue > 0 do
        ticks = ticks + 1
        assert(ticks < 150, "bounded wait")
        table.remove(queue, 1)()
        if mode == "late-hover" and ticks >= 8 and not captured then over = true end
        if captured then
            if mode ~= "stay-over" and (mode ~= "delayed-leave" or ticks >= captureTick + 8) then over = false end
            if mode == "moving" then moving = true; events.fire(nil, "PLAYER_STARTED_MOVING") end
        end
        if mode == "stop" and soft then env.SlashCmdList.GRUDGELEDGERPROBE("stop") end
        if mode == "combat" and soft then combat = true; events.fire(nil, "PLAYER_REGEN_DISABLED") end
        if mode == "cursor-return" and soft then over = true end
    end
    assert(not soft, "always restore soft cursor")
    local last = messages[#messages]
    local saved = assert(env.GrudgeLedger.db.minimapProbe)
    assert(saved.build == "70888" and saved.time == 1000 and saved.result)
    assert(not saved.result:find("Testeur", 1, true), "no names saved")
    local expected = ({ working = "POSITIF", broken = "NEGATIF", stale = "INCONCLUANT",
        ["blank-cache"] = "INCONCLUANT", secret = "SANS TEMOIN", empty = "SANS TEMOIN",
        throws = "ANNULE [positionnement virtuel du point]", moving = "ANNULE : Ton personnage a commence a bouger",
        ["stay-over"] = "ANNULE : la souris est restee", stop = "ANNULE", combat = "ANNULE : Debut du combat",
        metadata = "NEGATIF", ["late-hover"] = "POSITIF", ["delayed-leave"] = "POSITIF", ["no-hover"] = "SANS TEMOIN",
        ["missing-hover-api"] = "INDISPONIBLE", ["secret-speed"] = "vitesse lisible", ["secret-coordinate"] = "Coordonnee indisponible",
        ["tooltip-throws"] = "ANNULE [lecture de l'infobulle]", ["cursor-return"] = "souris est revenue" })[mode]
    assert(last:find(expected, 1, true), mode .. ": " .. last)
    for _, message in ipairs(messages) do assert(not message:find("Testeur", 1, true), "no names in report") end
    env.SlashCmdList.GRUDGELEDGERPROBE("")
    assert(messages[#messages] == last, "report can be shown again")
    print("PASS " .. mode)
end
for _, mode in ipairs({"working", "broken", "stale", "blank-cache", "secret", "empty", "throws", "moving", "stay-over", "stop", "combat", "metadata",
    "late-hover", "delayed-leave", "no-hover", "missing-hover-api", "secret-speed", "secret-coordinate", "tooltip-throws", "cursor-return"}) do run(mode) end
