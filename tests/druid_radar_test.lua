-- Native minimap reads are modelled one/two rendered frames after repositioning.
-- These tests prove our protocol, not that Forever supplies the native tooltip.
local file = assert(io.open(TEST_ROOT .. "/DruidRadar.lua", "r"))
local source = file:read("*a"); file:close()
local checked = 0
local function run(mode, expected, options)
    options = options or {}
    local env = setmetatable({}, { __index = _G })
    local messages, events, scripts, mutations, calls = {}, {}, {}, 0, {}
    local now, frame, pending, rendered, hits = 0, 0, nil, { 0, 0 }, 0
    local secret = setmetatable({}, { __index = function() error("secret inspected") end })
    local target = { name = "Élodie", surname = "Testeur", fullName = "Élodie Testeur" }
    local flags, map = {}, {}
    env.UIParent, env.WorldFrame = {}, {}
    local other = {}
    local mapChild = { GetParent = function() return map end }
    local mapGrandchild = { GetParent = function() return mapChild end }
    local foreignChild = { GetParent = function() return other end }
    local unreadableParent = { GetParent = function() return secret end }
    local throwingParent = { GetParent = function() error("private frame parent") end }
    local cyclic = {}; cyclic.GetParent = function() return cyclic end
    local focusBlocked, obstructedReads = false, 0
    local original = { { "TOPRIGHT", env.UIParent, "TOPRIGHT", -12, -20 },
        { "BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 5, 6 } }
    local anchors = { original[1], original[2] }
    local initialMask = options.mask or "original-mask"
    local alpha, mask, clicks, wheel = 0.73, initialMask, true, false
    local scale, width, height = options.scale or 0.8, options.width or 180, options.height or 180
    local center, cursor = { 0, 0 }, { 800, 450 }
    local function mutation(method)
        mutations = mutations + 1
        calls[method] = (calls[method] or 0) + 1
        if not flags.initializing and options.fail == method and calls[method] == 1 then error("private Élodie failure") end
        if options.restoreFail == method and flags.restoring then error("private restore failure") end
    end
    env.Minimap = map
    local nativeCalls = 0
    env.SetCVar = function() error("preparation must never write settings") end
    env.C_CVar = { SetCVar = env.SetCVar }
    env.MinimapCluster = { MinimapContainer = { Minimap = map }, UpdateMinimapConfig = function(self)
        assert(self == env.MinimapCluster)
        nativeCalls = nativeCalls + 1
        if options.prepare == "throws" then error("private native error") end
        if options.prepare ~= "noop" then map:SetMaskTexture(options.prepare == "secret" and secret or initialMask) end
    end }
    map.IsVisible = function() return not flags.hidden end
    map.IsProtected = function() return flags.protected or false end
    map.GetEffectiveScale = function() return flags.scale or scale end
    map.GetWidth = function() return flags.width or width + (#anchors == 1 and (options.sizeRounding or 0) or 0) end
    map.GetHeight = function() return flags.height or height + (#anchors == 1 and (options.sizeRounding or 0) or 0) end
    map.GetZoom = function() return flags.zoom or 1 end
    map.GetAlpha = function() return alpha end
    -- Forever's Minimap supports SetMaskTexture, but has no GetMaskTexture.
    map.GetNumPoints = function() return #anchors end
    map.GetPoint = function(_, i) return unpack(anchors[i]) end
    map.GetCenter = function() return flags.secretCenter and secret or center[1] + (options.rounding or 0), center[2] + (flags.clampY and 20 or 0) end
    map.IsMouseClickEnabled = function() return clicks end
    map.IsMouseWheelEnabled = function() return wheel end
    map.ClearAllPoints = function() mutation("ClearAllPoints"); anchors = {} end
    map.SetPoint = function(_, p, relative, rp, x, y)
        mutation("SetPoint")
        anchors[#anchors + 1] = { p, relative, rp, x, y }
        center = { x + (flags.clamp and 20 or 0), y }
        pending = { x, y, due = frame + (options.latency or 1) }
    end
    map.SetAlpha = function(_, value) mutation("SetAlpha"); if not (options.silentRestore and flags.restoring) then alpha = value end end
    map.SetMaskTexture = function(_, value) mutation("SetMaskTexture"); mask = value end
    env.hooksecurefunc = function(object, method, hook)
        assert(object == map and method == "SetMaskTexture")
        if mode == "hook-failure" then error("private hook failure") end
        local originalMethod = object[method]
        object[method] = function(...)
            originalMethod(...)
            hook(...)
        end
    end
    map.SetMouseClickEnabled = function(_, value) mutation("SetMouseClickEnabled"); clicks = value end
    map.EnableMouseWheel = function(_, value) mutation("EnableMouseWheel"); wheel = value end
    env.GetCursorPosition = function() return flags.secretCursor and secret or cursor[1], cursor[2] end
    env.GetMouseFoci = function()
        if flags.focus then return { other } end
        if env.GrudgeLedger.DruidRadarActive and env.GrudgeLedger.DruidRadarActive() then
            local dx, dy = cursor[1] / scale - center[1], cursor[2] / scale - center[2]
            local scanPoint = math.abs(dx) <= width / 2 and math.abs(dy) <= height / 2
            local secondPoint = math.abs(dx + 6 * width / 15) < 1 and math.abs(dy + 7 * height / 15) < 1
            local replay = hits > 0 and math.abs(dx) < 1 and math.abs(dy) < 1
            focusBlocked = options.child and (secondPoint or options.child == "all" and scanPoint
                or options.child == "initial" and not scanPoint
                or options.child == "replay" and replay
                or options.child == "empty-after-hit" and hits > 0 and not scanPoint)
            if focusBlocked then
                if options.child == "mixed" then return { mapChild, other } end
                if options.child == "foreign" then return { foreignChild } end
                if options.child == "cycle" then return { cyclic } end
                if options.child == "secret" then return { secret } end
                if options.child == "secret-parent" then return { unreadableParent } end
                if options.child == "throwing-parent" then return { throwingParent } end
                return { env.WorldFrame, map, options.child == "nested" and mapGrandchild or mapChild }
            end
            return { env.WorldFrame, map }
        end
        return { env.WorldFrame }
    end
    env.UnitClass = function() return "Druide", flags.class or "DRUID" end
    env.UnitExists = function(unit) assert(unit == "target"); return flags.secretTarget and secret or target ~= nil end
    env.UnitIsPlayer = function(unit) assert(unit == "target"); return not flags.npc end
    env.UnitIsUnit = function(unit, otherUnit) assert(unit == "target" and otherUnit == "player"); return flags.self or false end
    env.GetShapeshiftFormID = function() return flags.form or 1 end
    env.InCombatLockdown = function() return flags.combat or false end
    env.UnitIsDeadOrGhost = function() return flags.dead or false end
    env.IsInInstance = function() return flags.instance or false end
    env.IsMouselooking = function() return flags.look or false end
    env.IsMouseButtonDown = function() return flags.click or false end
    env.GetUnitSpeed = function() return flags.moving and 1 or 0 end
    env.GetTime = function() return now end
    env.GetBuildInfo = function() return "1.60.1", "70888" end
    env.C_Minimap = {
        GetNumTrackingTypes = function() return 2 end,
        GetTrackingInfo = function(i) return { spellID = mode ~= "tracking-filter" and (i == 1 and 19883 or 5225) or nil, active = not flags.tracking } end,
        GetTrackingFilter = function(i) return i == 1 and 19883 or 5225, nil end,
        SetTracking = function() error("test must never change tracking") end,
    }
    env.CreateFrame = function() return {
        RegisterEvent = function(_, event) events[event] = true end,
        SetScript = function(_, name, fn) scripts[name] = fn end,
    } end
    env.SlashCmdList = {}
    local watchdog
    env.C_Timer = { After = function(delay, fn) assert(delay == 12); watchdog = fn end }
    local GL = { version = "0.5.7", db = { players = { person = { fullName = target.fullName, surname = target.surname, score = -9 } } } }
    env.GrudgeLedger = GL
    GL.Clean = function(value, kind)
        if value == secret or kind and type(value) ~= kind then return nil end
        return value
    end
    GL.Safe = function(fn, ...)
        if type(fn) ~= "function" then return end
        local ok, a, b, c, d = pcall(fn, ...)
        if ok then return GL.Clean(a), GL.Clean(b), GL.Clean(c), GL.Clean(d) end
    end
    GL.Now = function() return 12345 end
    GL.Print = function(s) messages[#messages + 1] = s end
    GL.Identity = function(unit) assert(unit == "target"); if not flags.noIdentity then return target end end
    GL.MinimapProbeActive = function() return flags.legacy or false end
    env.C_TooltipInfo = { GetMinimapMouseover = function()
        assert(frame > 0, "no same-frame reads")
        if focusBlocked then obstructedReads = obstructedReads + 1 end
        if mode == "throws" then error("Élodie raw error") end
        if mode == "secret" then return secret end
        if mode == "secret-lines" then return { lines = secret } end
        if mode == "secret-text" then return { lines = { { leftText = secret } } } end
        if mode == "malformed" then return { lines = "not a table" } end
        if mode == "empty" then return nil end
        if mode == "stale" or mode == "cache-after-hit" and hits > 0 then
            return { lines = { { leftText = "Élodie Testeur", type = 2 } } }
        end
        local dx, dy = cursor[1] / scale - rendered[1], cursor[2] / scale - rendered[2]
        local near = math.abs(dx - (options.dotX or 0)) < 4 and math.abs(dy - (options.dotY or 0)) < 4
        if not near then return nil end
        hits = hits + 1
        if mode == "one-hit" and hits > 1 then return nil end
        if mode == "pet-owner" then return { lines = { { leftText = "Pet" }, { leftText = "Élodie Testeur", type = 16 } } } end
        if mode == "metadata-first" then return { lines = { { leftText = "Élodie Testeur", type = 16 } } } end
        if mode == "substring" then return { lines = { { leftText = "Familier d'Élodie Testeur", type = 0 } } } end
        return { lines = { { leftText = "Autre Point", type = 0 }, { leftText = "|cffff0000Élodie Testeur|r", type = 0 } } }
    end }
    assert(loadstring(source, "DruidRadar.lua")); setfenv(assert(loadstring(source)), env)()
    assert(mutations == 0 and nativeCalls == 0 and not scripts.OnUpdate and #messages == 0, "dormant at login")
    assert(not GL.db.druidRadarTests and not GL.DruidRadarActive())
    -- The game's skin (or another addon) sets its mask after our observer loads.
    if mode ~= "unknown-mask" and mode ~= "observe-later" and not options.prepare then
        flags.initializing = true
        map:SetMaskTexture(initialMask)
        flags.initializing = nil
        mutations, calls = 0, {}
    end
    local slash = env.SlashCmdList.GRUDGELEDGERDRUIDRADAR
    slash(""); slash("rapport")
    assert(mutations == 0 and not GL.db.druidRadarTests, "help/report are read-only")
    if mode == "observe-later" then
        slash("test")
        assert(GL.db.druidRadarTests[1].code == "mask" and mutations == 0)
        map:SetMaskTexture(initialMask)
        mutations, calls, GL.db.druidRadarTests = 0, {}, nil
    elseif mode == "secret-mask" then
        map:SetMaskTexture(secret)
        mutations, calls = 0, {}
    end
    if mode == "class" then flags.class = "HUNTER" end
    if mode == "form" then flags.form = 5 end
    for _, key in ipairs({ "tracking", "combat", "dead", "instance", "moving", "focus", "hidden", "protected", "look", "click", "legacy", "secretCursor", "clamp", "clampY", "secretCenter", "npc", "self", "noIdentity", "secretTarget" }) do
        if mode == key then flags[key] = true end
    end
    if mode == "target" then target = nil end
    if mode == "surname" then target.surname = nil end
    if mode == "conflict" then env.NodeSightAPI = {} end
    if mode == "missing" then map.SetMaskTexture = nil end
    if mode == "missing-tooltip" then env.C_TooltipInfo = nil end
    if mode == "duplicate" then GL.db.players.other = { fullName = target.fullName, surname = target.surname, score = 0 } end
    if mode == "unlisted" then GL.db.players = {} end
    if options.prepare then
        if options.prepare == "missing" then env.MinimapCluster.UpdateMinimapConfig = nil end
        if options.prepare == "mismatch" then env.MinimapCluster.MinimapContainer.Minimap = other end
        if options.prepare == "combat" then flags.combat = true end
        if options.prepare == "protected" then flags.protected = true end
        if options.prepare == "legacy" then flags.legacy = true end
        local ok, message = GL.PrepareDruidRadar()
        assert(type(message) == "string" and not message:find("private", 1, true), "fixed public preparation message")
        assert(not GL.db.druidRadarTests and not scripts.OnUpdate, "preparation never launches a scan")
        assert(alpha == 0.73 and clicks and not wheel and #anchors == #original, "preparation does not move or hide the map")
        if expected == "prepare-failed" then
            assert(not ok and message:find(options.message, 1, true), options.prepare .. ": actionable preparation failure")
            local called = options.prepare == "throws" or options.prepare == "noop" or options.prepare == "secret"
            assert(nativeCalls == (called and 1 or 0), "guard failures must not call native refresh")
            checked = checked + 1
            return
        end
        assert(ok and message:find("prête", 1, true) and nativeCalls == 1 and mask == initialMask)
        assert(GL.PrepareDruidRadar() and nativeCalls == 1, "repeat preparation preserves the observed skin")
        mutations, calls = 0, {}
    elseif mode == "working" then
        assert(GL.PrepareDruidRadar() and nativeCalls == 0 and mutations == 0, "known custom skins are not reset")
    end
    slash("test")
    if mode == "legacy" then assert(mutations == 0 and not GL.db.druidRadarTests); checked = checked + 1; return end
    if GL.DruidRadarActive() then
        local before = mutations
        slash("test")
        assert(before == mutations, "no overlapping scans")
        local ok, message = GL.PrepareDruidRadar()
        assert(not ok and message:find("déjà en cours", 1, true) and before == mutations and nativeCalls == (options.prepare and 1 or 0), "preparation cannot disturb a running scan")
    end
    if mode == "hidden-driver" then now = 12; watchdog() end
    while scripts.OnUpdate do
        frame, now = frame + 1, now + (options.delta or 1 / 60)
        assert(frame < 900, "scan is bounded")
        if pending and pending.due <= frame then rendered, pending = pending, nil end
        if frame == 5 then
            if mode == "cursor-move" then cursor[1] = cursor[1] + 10 end
            if mode == "late-secret" then flags.secretCursor = true end
            if mode == "late-focus" then flags.focus = true end
            if mode == "zoom" then flags.zoom = 2 end
            if mode == "resize" then flags.width = width + 1 end
            if mode == "resize-height" then flags.height = height + 1 end
            if mode == "late-alpha" then alpha = 0.5 end
            if mode == "rescale" then flags.scale = scale + 0.1 end
            if mode == "late-combat" then flags.combat = true end
            if mode == "late-move" then flags.moving = true end
            if mode == "late-click" then flags.click = true end
            if mode == "late-mask" then map:SetMaskTexture("changed-by-other-addon") end
            if mode == "stop" or options.restoreFail or options.silentRestore then flags.restoring = true; slash("stop") end
            if options.event then assert(events[options.event]); scripts.OnEvent(nil, options.event) end
        end
        if scripts.OnUpdate then scripts.OnUpdate(nil, options.delta or 1 / 60) end
    end
    assert(not GL.DruidRadarActive())
    if watchdog then local before = mutations; watchdog(); assert(before == mutations, "expired watchdog cannot restore twice") end
    local saved = assert(GL.db.druidRadarTests and GL.db.druidRadarTests[1], mode)
    assert(saved.code == expected, mode .. ": expected " .. expected .. " got " .. saved.code .. " at " .. saved.phase)
    assert(saved.build == "70888" and saved.time == 12345 and saved.points <= 225)
    assert(saved.version == GL.version and messages[#messages]:find("addon " .. GL.version, 1, true), "identify the installed diagnostic revision")
    assert(saved.seconds >= 0 and saved.seconds <= 12.2, "bounded duration")
    if options.child then
        assert(obstructedReads == 0, "a minimap button's tooltip must never count as a radar read")
        assert(messages[#messages]:find(saved.skipped .. " points ignorés", 1, true), "show the obstruction count")
        if expected == "positive" then assert(saved.skipped == 1 and saved.points > 2, "skip the covered second point and continue") end
        if options.child == "all" then assert(saved.skipped == 225 and saved.reads == 1 and saved.texts == 0, "a fully obscured scan is inconclusive") end
    end
    local failedCheck = ({ clamp = "centre X", clampY = "centre Y", zoom = "zoom", resize = "largeur",
        ["resize-height"] = "hauteur", rescale = "échelle", ["late-alpha"] = "transparence" })[mode]
    if failedCheck then
        assert(saved.check == "minimap : " .. failedCheck and saved.detail:find("Reçu :", 1, true)
            and saved.detail:find("attendu :", 1, true), "precise measured failure instead of generic map error")
    end
    if mode == "secretCenter" then assert(saved.check == "minimap : centre X" and saved.detail == "Valeur reçue illisible.") end
    if mode == "late-mask" then assert(saved.check == "minimap : masque modifié" and not saved.detail) end
    if mode == "target" or mode == "npc" or mode == "self" or mode == "surname" or mode == "noIdentity" or mode == "secretTarget" then
        assert(mutations == 0 and saved.reads == 0 and saved.points == 0, "target preflight stays read-only")
    end
    if mode == "unknown-mask" or mode == "hook-failure" or mode == "secret-mask" then
        assert(mutations == 0 and saved.reads == 0 and saved.points == 0, "unknown restoration state must never mutate the map")
        assert(saved.check == "sauvegarde : observation de SetMaskTexture", "precise failure stage")
    end
    for k, v in pairs(saved) do
        assert(type(v) == "number" or type(v) == "string", "only scalar diagnostic fields")
        assert(not tostring(v):find("Élodie", 1, true) and not tostring(v):find("private", 1, true))
    end
    for _, text in ipairs(messages) do assert(not text:find("Élodie", 1, true) and not text:find("private", 1, true), "name-free messages") end
    if mode ~= "unlisted" then assert(GL.db.players.person.score == -9, "no relation changes") end
    local n = 0; for _ in pairs(GL.db.players) do n = n + 1 end
    assert(n == (mode == "duplicate" and 2 or mode == "unlisted" and 0 or 1), "no automatic player creation")
    if expected == "positive" then assert(saved.known == ((mode == "duplicate" or mode == "unlisted") and 0 or 1) and hits == 2 and saved.texts == 2) end
    if not options.restoreFail and not options.silentRestore then
        assert(alpha == 0.73 and mask == (mode == "secret-mask" and secret or initialMask) and clicks and not wheel, mode .. ": all map properties restored")
        assert(#anchors == #original, mode .. ": anchors restored")
        for i, anchor in ipairs(original) do for j = 1, 5 do assert(anchors[i][j] == anchor[j], mode .. ": original point restored") end end
    else
        assert(expected == "restored")
        for _, method in ipairs({ "ClearAllPoints", "SetPoint", "SetAlpha", "SetMaskTexture", "SetMouseClickEnabled", "EnableMouseWheel" }) do
            assert(calls[method] and calls[method] >= 2, "all restoration calls attempted")
        end
        local before = mutations; slash("test"); assert(before == mutations, "latch after failed restoration")
        local ok, message = GL.PrepareDruidRadar()
        assert(not ok and message:find("/reload", 1, true) and before == mutations, "preparation respects restoration latch")
    end
    if mode == "history" then
        flags.class = "HUNTER"
        for _ = 1, 20 do slash("test") end
        assert(#GL.db.druidRadarTests == 10, "bounded saved diagnostics")
    end
    slash("rapport")
    assert(messages[#messages]:find(saved.build, 1, true))
    saved.skipped = nil -- Reports saved by 0.5.6 remain readable.
    slash("rapport")
    assert(messages[#messages]:find("0 points ignorés", 1, true))
    checked = checked + 1
end

for mode, expected in pairs({ working = "positive", ["tracking-filter"] = "positive", duplicate = "positive", history = "positive", empty = "missed",
    stale = "cache", ["cache-after-hit"] = "cache", ["one-hit"] = "replay", ["pet-owner"] = "missed",
    ["metadata-first"] = "missed", substring = "missed", throws = "api", secret = "api", ["secret-lines"] = "api",
    ["secret-text"] = "api", malformed = "api", class = "class", form = "form", tracking = "tracking", combat = "combat",
    dead = "dead", instance = "instance", moving = "moving", focus = "focus", hidden = "map", protected = "map",
    look = "mouse", click = "mouse", legacy = "busy", secretCursor = "api", clamp = "map", clampY = "map", secretCenter = "api",
    target = "target_missing", surname = "target_name", npc = "target_npc", self = "target_self", noIdentity = "target_identity", secretTarget = "api",
    conflict = "conflict", missing = "api", ["missing-tooltip"] = "api", ["cursor-move"] = "mouse", ["late-secret"] = "api",
    ["unknown-mask"] = "mask", ["hook-failure"] = "api", ["secret-mask"] = "mask", ["observe-later"] = "positive",
    ["late-focus"] = "focus_changed", zoom = "map", resize = "map", ["resize-height"] = "map", ["late-alpha"] = "map", rescale = "map", ["late-combat"] = "combat",
    ["late-move"] = "moving", ["late-click"] = "mouse", ["late-mask"] = "map", stop = "stopped" }) do run(mode, expected) end
for _, scale in ipairs({ 0.5, 1, 1.5 }) do run("working", "positive", { scale = scale, latency = 2, width = 240, height = 180, dotX = 48, dotY = -36, rounding = 0.04 }) end
run("working", "positive", { mask = 12345 }) -- FileDataID masks survive unchanged.
-- Native frame extents can differ slightly after repositioning at another origin.
run("working", "positive", { sizeRounding = 0.00006103515625 })
run("unlisted", "positive") -- A valid witness does not need a journal entry.
run("working", "positive", { child = "direct" })
run("working", "positive", { child = "nested" })
run("working", "obstructed", { child = "direct", dotX = -72, dotY = -84, latency = 2 })
run("working", "obstructed", { child = "all" })
run("working", "map_focus", { child = "initial" })
run("working", "map_focus", { child = "replay" })
run("working", "map_focus", { child = "empty-after-hit" })
for _, child in ipairs({ "mixed", "foreign", "cycle", "secret", "secret-parent", "throwing-parent" }) do
    run("working", "focus_changed", { child = child })
end
run("working", "positive", { mask = "Interface\\AddOns\\CustomMap\\SquareMask" })
run("prepare", "positive", { prepare = "working" })
run("prepare", "positive", { prepare = "working", mask = 12345 })
for mode, message in pairs({ missing = "indisponible sur ce client", mismatch = "indisponible sur ce client",
    throws = "Échec", noop = "toujours inconnu", secret = "toujours inconnu", combat = "en combat",
    protected = "protégée", legacy = "déjà en cours" }) do
    run("prepare", "prepare-failed", { prepare = mode, message = message })
end
run("hook-failure", "prepare-failed", { prepare = "working", message = "API nécessaire" })
run("empty", "timeout", { delta = 1 / 20 })
run("hidden-driver", "timeout")
run("silent-restore-failure", "restored", { silentRestore = true })
for event, expected in pairs({ PLAYER_REGEN_DISABLED = "combat", PLAYER_STARTED_MOVING = "moving", PLAYER_DEAD = "dead",
    PLAYER_LEAVING_WORLD = "world", PLAYER_LOGOUT = "world", UPDATE_SHAPESHIFT_FORM = "form",
    MINIMAP_UPDATE_TRACKING = "tracking", MINIMAP_UPDATE_ZOOM = "map" }) do run("event", expected, { event = event }) end
for _, method in ipairs({ "ClearAllPoints", "SetPoint", "SetAlpha", "SetMaskTexture", "SetMouseClickEnabled", "EnableMouseWheel" }) do
    run("mutation-failure", "api", { fail = method })
    run("restore-failure", "restored", { restoreFail = method })
end
print("PASS druid radar: " .. checked .. " cases, rendered-frame geometry, cache rejection, privacy and restoration")
