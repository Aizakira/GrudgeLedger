-- Explicit, bounded experiment. No scans, tracking changes or alerts at login.
-- Independently implemented from public minimap API behavior; no NodeSight code.
local GL = GrudgeLedger
local BLANK = "Interface\\AddOns\\GrudgeLedger\\Media\\RadarBlank"
local running, restorationFailed
local check = "prérequis"
local driver = CreateFrame("Frame")
local reasons = {
    ready = "Prêt pour un essai en félin avec Pistage des humanoïdes actif.",
    class = "Ce test est réservé aux druides.", form = "Passe en forme de félin.",
    tracking = "Active Pistage des humanoïdes dans le menu de pistage.",
    api = "Une API nécessaire est absente, protégée ou illisible.",
    target = "Cible un autre joueur immobile, visible comme point sur ta minimap.",
    combat = "Combat : essai arrêté.", moving = "Déplacement du personnage : essai arrêté.",
    dead = "Personnage mort : essai arrêté.", instance = "Essai limité au monde extérieur.",
    mouse = "Mouvement ou clic de souris : essai arrêté.",
    focus = "Place la souris sur une zone vide du monde, hors fenêtres et minimap.",
    map = "Minimap masquée, protégée ou modifiée pendant l'essai.",
    conflict = "Un autre scanner est chargé : désactive-le pour isoler l'essai.",
    busy = "Un autre test est déjà en cours.", timeout = "Temps limite atteint : résultat incomplet.",
    cache = "Le témoin persiste sur un point vide : cache possible, résultat non validé.",
    missed = "Témoin non retrouvé : méthode non validée (point mobile, grille ou API possibles).",
    replay = "Témoin trouvé une fois mais pas relu : résultat non validé.",
    positive = "Témoin relu deux fois sans survol manuel ; contrôles vides réussis.",
    stopped = "Annulé par le joueur.", world = "Changement de zone ou déconnexion : essai arrêté.",
    restored = "Restauration incomplète : utilise /reload avant un nouvel essai.",
}
local function public(value, kind) return GL.Clean(value, kind) end
local function number(value)
    value = public(value, "number")
    return value and value == value and math.abs(value) < math.huge and value or nil
end
local function reject(code) error({ code = code }, 0) end
local function call(fn, ...)
    if type(fn) ~= "function" then reject("api") end
    return fn(...)
end
local function clock() return number(call(GetTime)) or reject("api") end
local function numeric(fn, ...)
    return number(call(fn, ...)) or reject("api")
end
local function yes(fn, ...)
    local value = public(call(fn, ...), "boolean")
    if value == nil then reject("api") end
    return value
end
local function build()
    local _, value = GL.Safe(GetBuildInfo)
    return type(value) == "string" and value:match("^%d+$") and value or "inconnu"
end
local function prerequisites()
    check = "classe et forme"
    local _, class = call(UnitClass, "player")
    if public(class, "string") ~= "DRUID" then reject("class") end
    if numeric(GetShapeshiftFormID) ~= (CAT_FORM or 1) then reject("form") end
    check = "combat et déplacement"
    if yes(InCombatLockdown) then reject("combat") end
    if yes(UnitIsDeadOrGhost, "player") then reject("dead") end
    if yes(IsInInstance) then reject("instance") end
    if numeric(GetUnitSpeed, "player") ~= 0 then reject("moving") end
    check = "API de pistage"
    if not C_Minimap then reject("api") end
    local count = numeric(C_Minimap.GetNumTrackingTypes)
    if count < 0 or count > 100 or count % 1 ~= 0 then reject("api") end
    local active = false
    for i = 1, count do
        local info = public(call(C_Minimap.GetTrackingInfo, i), "table")
        local spell = info and (number(info.spellID) or number(GL.Safe(C_Minimap.GetTrackingFilter, i)))
        if spell == 5225 then active = public(info.active, "boolean") == true end
    end
    if not active then reject("tracking") end
    check = "API et visibilité minimap"
    if not Minimap or not UIParent or not C_TooltipInfo or type(C_TooltipInfo.GetMinimapMouseover) ~= "function"
        or not C_Timer or type(C_Timer.After) ~= "function" then reject("api") end
    if not yes(Minimap.IsVisible, Minimap) or yes(Minimap.IsProtected, Minimap) then reject("map") end
    if yes(IsMouselooking) or yes(IsMouseButtonDown) then reject("mouse") end
end
local function reason(err)
    return public(err, "table") and reasons[err.code] and err.code or "api"
end
local function report(entry)
    if not entry then return "Aucun essai druide sauvegardé. /glradar test pour commencer." end
    return string.format("Radar druide · build %s · %s · %s\n%s\n%d points, %d lectures, %d textes distincts, %d correspondances connues, %.1f s.",
        entry.build, entry.phase, entry.check or "non précisé", reasons[entry.code] or reasons.api,
        entry.points, entry.reads, entry.texts, entry.known, entry.seconds)
end
function GL.DruidRadarReport()
    local history = GL.db and GL.db.druidRadarTests
    return "\nRadar druide : expérimental, lancement manuel uniquement.\n" .. report(history and history[#history])
end
local function finish(code)
    local state = running
    if not state then return end
    running = nil
    driver:SetScript("OnUpdate", nil)
    local restored = true
    local function restore(fn, ...)
        if not pcall(fn, ...) then restored = false end
    end
    if state.modified then
        -- Attempt every restoration even when an individual API rejects its call.
        restore(Minimap.ClearAllPoints, Minimap)
        for _, point in ipairs(state.anchors) do restore(Minimap.SetPoint, Minimap, unpack(point, 1, 5)) end
        restore(Minimap.SetAlpha, Minimap, state.alpha)
        restore(Minimap.SetMaskTexture, Minimap, state.mask)
        restore(Minimap.SetMouseClickEnabled, Minimap, state.clicks)
        restore(Minimap.EnableMouseWheel, Minimap, state.wheel)
        local ok, matches = pcall(function()
            if numeric(Minimap.GetNumPoints, Minimap) ~= #state.anchors
                or numeric(Minimap.GetAlpha, Minimap) ~= state.alpha
                or public(call(Minimap.GetMaskTexture, Minimap)) ~= state.mask
                or yes(Minimap.IsMouseClickEnabled, Minimap) ~= state.clicks
                or yes(Minimap.IsMouseWheelEnabled, Minimap) ~= state.wheel then return false end
            for i, point in ipairs(state.anchors) do
                local p, relative, rp, x, y = Minimap:GetPoint(i)
                if public(p) ~= point[1] or public(relative) ~= point[2] or public(rp) ~= point[3]
                    or number(x) ~= point[4] or number(y) ~= point[5] then return false end
            end
            return true
        end)
        if not ok or not matches then restored = false end
    end
    if not restored then code, restorationFailed = "restored", true end
    local texts, known = 0, 0
    for name in pairs(state.names) do
        texts = texts + 1
        if state.known[name] then known = known + 1 end
    end
    local now = number(GL.Safe(GetTime)) or state.started
    local entry = { code = code, phase = state.phase, check = check, build = build(), time = GL.Now(),
        points = state.points, reads = state.reads, texts = texts, known = known,
        seconds = math.max(0, now - state.started) }
    if GL.db then
        local history = type(GL.db.druidRadarTests) == "table" and GL.db.druidRadarTests or {}
        history[#history + 1] = entry
        while #history > 10 do table.remove(history, 1) end
        GL.db.druidRadarTests = history
    end
    -- Only counts and fixed reason codes survive: never tooltip text or raw errors.
    GL.Print(report(entry))
end
local function names(state)
    check = "lecture de l'infobulle native"
    state.reads = state.reads + 1
    local data = call(C_TooltipInfo.GetMinimapMouseover)
    if data == nil then return {} end
    data = public(data, "table")
    if not data or not public(data.lines, "table") then reject("api") end
    local result = {}
    -- Minimap lists can contain several overlapping dots. Match whole text lines,
    -- never a substring (a pet owner or a guild line is not a player identity).
    for i = 1, math.min(#data.lines, 64) do
        local line = public(data.lines[i], "table")
        local text = line and public(line.leftText, "string")
        if not line or (line.leftText ~= nil and not text) then reject("api") end
        local kind = number(line.type)
        if line.type ~= nil and not kind then reject("api") end
        if text and #text <= 4096 and (kind == 0 or kind == 2 or (i == 1 and kind == nil)) then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            for value in text:gmatch("[^\n]+") do
                value = value:match("^%s*(.-)%s*$")
                if #value > 0 and #value <= 160 and not value:find("[|%c]") then result[value] = true end
            end
        end
    end
    return result
end
local function place(state, x, y)
    check = "positionnement minimap"
    Minimap:ClearAllPoints()
    -- Cursor coordinates are physical pixels; anchor offsets use the map's scale.
    Minimap:SetPoint("CENTER", UIParent, "BOTTOMLEFT", state.x / state.scale - x, state.y / state.scale - y)
    state.expectedX, state.expectedY = state.x / state.scale - x, state.y / state.scale - y
    state.wait = 0
end
local function emptyPoint(state) place(state, state.width * 2, state.height * 2) end
local function nextPoint(state)
    local point = state.grid[state.points + 1]
    if not point then finish("missed") return end
    state.points = state.points + 1
    state.phase = "balayage"
    place(state, point[1], point[2])
end
local function tick(state)
    if running ~= state then return end
    local ok, err = pcall(function()
        prerequisites()
        if clock() - state.started > 12 then reject("timeout") end
        check = "position et survol de souris"
        local x, y = call(GetCursorPosition)
        x, y = number(x), number(y)
        if not x or not y then reject("api") end
        if math.abs(x - state.x) > 2 or math.abs(y - state.y) > 2 then reject("mouse") end
        local focus = public(call(GetMouseFoci), "table")
        if not focus or #focus == 0 or #focus > 8 then reject("focus") end
        for _, frame in ipairs(focus) do
            -- Ignore the transparent map itself, but stop if a window/button takes
            -- the pointer. Do not disable another addon's controls to force a read.
            if frame ~= WorldFrame and frame ~= Minimap then reject("focus") end
        end
        check = "géométrie et masque minimap"
        local cx, cy = Minimap:GetCenter()
        cx, cy = number(cx), number(cy)
        if not cx or not cy or math.abs(cx - state.expectedX) > 0.1 or math.abs(cy - state.expectedY) > 0.1
            or numeric(Minimap.GetEffectiveScale, Minimap) ~= state.scale
            or numeric(Minimap.GetAlpha, Minimap) ~= 0
            or public(call(Minimap.GetMaskTexture, Minimap)) ~= BLANK
            or numeric(Minimap.GetZoom, Minimap) ~= state.zoom
            or numeric(Minimap.GetWidth, Minimap) ~= state.width
            or numeric(Minimap.GetHeight, Minimap) ~= state.height then reject("map") end
        -- A native hover read updates on a rendered frame, not in a tight Lua loop.
        state.wait = state.wait + 1
        if state.wait < 2 then return end
        local found = names(state)
        if state.phase == "vide initial" then
            if next(found) then reject("cache") end
            nextPoint(state)
        elseif state.phase == "balayage" then
            for name in pairs(found) do state.names[name] = true end
            if found[state.target] then
                state.hit = state.grid[state.points]
                state.phase = "vide intermédiaire"
                emptyPoint(state)
            else nextPoint(state) end
        elseif state.phase == "vide intermédiaire" then
            if next(found) then reject("cache") end
            state.phase = "seconde lecture"
            place(state, state.hit[1], state.hit[2])
        elseif state.phase == "seconde lecture" then
            if not found[state.target] then reject("replay") end
            state.phase = "vide final"
            emptyPoint(state)
        elseif state.phase == "vide final" then
            if next(found) then reject("cache") end
            finish("positive")
        end
    end)
    if not ok then finish(reason(err)) end
end
local function start()
    if running or (GL.MinimapProbeActive and GL.MinimapProbeActive()) then GL.Print(reasons.busy) return end
    if restorationFailed then GL.Print(reasons.restored) return end
    local state = { names = {}, known = {}, grid = {}, points = 0, reads = 0, phase = "préparation",
        started = number(GL.Safe(GetTime)) or 0 }
    local ok, err = pcall(function()
        prerequisites()
        if NodeSightAPI then reject("conflict") end
        check = "identité du joueur témoin"
        local identity = GL.Identity("target")
        if not identity or not identity.name or not identity.surname then reject("target") end
        state.target = identity.name .. " " .. identity.surname
        check = "survol de souris initial"
        local focus = public(call(GetMouseFoci), "table")
        if not focus or focus[1] ~= WorldFrame or #focus ~= 1 then reject("focus") end
        state.x, state.y = call(GetCursorPosition)
        state.x, state.y = number(state.x), number(state.y)
        if not state.x or not state.y then reject("api") end
        check = "sauvegarde de la minimap"
        state.scale = numeric(Minimap.GetEffectiveScale, Minimap)
        state.width, state.height = numeric(Minimap.GetWidth, Minimap), numeric(Minimap.GetHeight, Minimap)
        if state.scale <= 0 or state.width < 40 or state.height < 40 or state.width > 600 or state.height > 600 then reject("map") end
        state.zoom, state.alpha = numeric(Minimap.GetZoom, Minimap), numeric(Minimap.GetAlpha, Minimap)
        state.mask = public(call(Minimap.GetMaskTexture, Minimap))
        if not (type(state.mask) == "string" and state.mask ~= "" or number(state.mask)) then reject("api") end
        state.clicks, state.wheel = yes(Minimap.IsMouseClickEnabled, Minimap), yes(Minimap.IsMouseWheelEnabled, Minimap)
        for _, method in ipairs({ "ClearAllPoints", "SetPoint", "SetAlpha", "SetMaskTexture", "SetMouseClickEnabled", "EnableMouseWheel", "GetCenter" }) do
            if type(Minimap[method]) ~= "function" then reject("api") end
        end
        state.anchors = {}
        local count = numeric(Minimap.GetNumPoints, Minimap)
        if count < 1 or count > 8 or count % 1 ~= 0 then reject("map") end
        for i = 1, count do
            local p, relative, rp, x, y = Minimap:GetPoint(i)
            if not public(p, "string") or not public(rp, "string") or (relative ~= nil and not public(relative))
                or not number(x) or not number(y) then reject("api") end
            state.anchors[i] = { p, relative, rp, x, y }
        end
        -- ponytail: bounded 15x15 sampling, not exhaustive pixel coverage. A miss is
        -- inconclusive; finer/adaptive scanning comes only after real client proof.
        for row = -7, 7 do for col = -7, 7 do
            state.grid[#state.grid + 1] = { col * state.width / 15, row * state.height / 15 }
        end end
        local counts = {}
        for _, record in pairs(GL.db.players) do
            if record.fullName and record.surname then counts[record.fullName] = (counts[record.fullName] or 0) + 1 end
        end
        for name, count in pairs(counts) do if count == 1 then state.known[name] = true end end
        state.started = clock()
        running = state
        state.modified = true
        check = "masquage minimap"
        Minimap:SetMouseClickEnabled(false)
        Minimap:EnableMouseWheel(false)
        Minimap:SetAlpha(0)
        -- The native map renderer does not reliably inherit frame alpha.
        Minimap:SetMaskTexture(BLANK)
        state.phase = "vide initial"
        emptyPoint(state)
        driver:SetScript("OnUpdate", function() tick(state) end)
        -- Also restore if hiding the UI prevents our frame receiving OnUpdate.
        C_Timer.After(12, function() if running == state then finish("timeout") end end)
        GL.Print("Essai druide lancé : garde souris et personnage immobiles. Minimap masquée au maximum 12 s. /glradar stop pour annuler.")
    end)
    if not ok then
        running = state
        finish(reason(err))
    end
end
function GL.DruidRadarActive() return running ~= nil end
SLASH_GRUDGELEDGERDRUIDRADAR1 = "/glradar"
SlashCmdList.GRUDGELEDGERDRUIDRADAR = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "test" then start()
    elseif command == "stop" then finish("stopped")
    elseif command == "rapport" or command == "report" then GL.Print(GL.DruidRadarReport())
    else
        local ok, err = pcall(prerequisites)
        GL.Print(ok and reasons.ready or reasons[reason(err)])
        GL.Print("/glradar test : cible un joueur témoin immobile, puis garde la souris hors minimap et fenêtres. /glradar rapport : résultat anonyme. Aucun pistage ni radar automatique activé.")
    end
end
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_STARTED_MOVING", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT", "PLAYER_DEAD", "UPDATE_SHAPESHIFT_FORM", "MINIMAP_UPDATE_TRACKING", "MINIMAP_UPDATE_ZOOM" }) do driver:RegisterEvent(event) end
driver:SetScript("OnEvent", function(_, event)
    if not running then return end
    finish(({ PLAYER_REGEN_DISABLED = "combat", PLAYER_STARTED_MOVING = "moving", PLAYER_DEAD = "dead",
        UPDATE_SHAPESHIFT_FORM = "form", MINIMAP_UPDATE_TRACKING = "tracking", MINIMAP_UPDATE_ZOOM = "map" })[event] or "world")
end)
