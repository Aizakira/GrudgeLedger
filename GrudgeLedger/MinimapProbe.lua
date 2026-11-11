-- Explicitly invoked capability test, never an automatic radar. No tracking changes or saved names.
local active, latest
local function public(value, kind)
    return not (issecretvalue and issecretvalue(value)) and type(value) == kind
end
local function say(text) print("[GL Probe] " .. text) end
local function fail(reason) error({ reason = reason }, 0) end
local function readNames()
    local data = C_TooltipInfo.GetMinimapMouseover()
    local names = {}
    if not public(data, "table") then return names end
    if not public(data.lines, "table") then return names end
    -- Only the name line: shared guild/class/level text must not count as a match.
    local line = data.lines[1]
    if public(line, "table") and public(line.leftText, "string") then
        for text in line.leftText:gmatch("[^\n]+") do
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            text = text:match("^%s*(.-)%s*$")
            if text ~= "" then names[text] = true end
        end
    end
    return names
end
local function matches(a, b)
    for text in pairs(a) do if b[text] then return true end end
    return false
end
local function cleanup(state)
    if state and state.soft then
        pcall(Minimap.UpdateMouseoverAtPoint, Minimap, -10000, -10000)
        local ok = pcall(Minimap.SetUsingSoftCursor, Minimap, false)
        if not ok then say("Impossible de restaurer le curseur virtuel : utilise /reload.") end
        state.soft = nil
    end
end
local function finish(text)
    local state = active
    active = nil
    cleanup(state)
    latest = text
    local GL = GrudgeLedger
    if GL and GL.db then
        local _, build = GetBuildInfo()
        GL.db.minimapProbe = { time = GL.Now(), result = text,
            build = public(build, "string") and build:match("^%d+$") and build or "inconnu" }
    end
    say(text)
end
local function check(state, offMap)
    if not Minimap:IsVisible() then fail("La minimap n'est pas visible.") end
    if InCombatLockdown() then fail("Tu es en combat.") end
    if UnitIsDeadOrGhost("player") then fail("Ton personnage est mort.") end
    local speed = GetUnitSpeed("player")
    if not public(speed, "number") then fail("Le jeu ne fournit pas une vitesse lisible.") end
    if speed ~= 0 then fail("Ton personnage se deplace.") end
    if offMap and Minimap:IsMouseOver() then fail("La souris est revenue sur la minimap pendant la relecture.") end
    if state.scale then
        local x, y = Minimap:GetCenter()
        local scale, zoom = Minimap:GetEffectiveScale(), Minimap:GetZoom()
        if not public(x, "number") or not public(y, "number") or
            not public(scale, "number") or not public(zoom, "number") or
            x ~= state.cx or y ~= state.cy or scale ~= state.scale or zoom ~= state.zoom then
            fail("La position, l'echelle ou le zoom de la minimap a change, ou est protege.")
        end
    end
end
local function aborted(state, err)
    local reason = public(err, "table") and public(err.reason, "string") and err.reason
        or "Appel API refuse ou erreur Lua."
    finish("ANNULE [" .. (state.step or "preparation") .. "] : " .. reason .. " Aucun resultat exploitable.")
end
local function later(state, seconds, offMap, fn)
    C_Timer.After(seconds, function()
        if active ~= state then return end
        local ok, err = pcall(function() check(state, offMap); fn() end)
        if not ok then aborted(state, err) end
    end)
end
local function start()
    if GrudgeLedger and GrudgeLedger.DruidRadarActive and GrudgeLedger.DruidRadarActive() then say("Essai druide en cours : /glradar stop pour annuler."); return end
    if active then say("Test deja en cours. /glprobe stop pour annuler."); return end
    if not Minimap or not Minimap.UpdateMouseoverAtPoint or not Minimap.SetUsingSoftCursor or
        not C_TooltipInfo or not C_TooltipInfo.GetMinimapMouseover or not C_Timer then
        finish("INDISPONIBLE : API de lecture absente."); return
    end
    if type(Minimap.IsMouseOver) ~= "function" then
        finish("INDISPONIBLE : Minimap:IsMouseOver absent."); return
    end
    -- ponytail: one stationary point, not a grid scan. A positive result needs further live tests.
    local state = { step = "preparation" }
    local ok, err = pcall(check, state, false)
    if not ok then aborted(state, err); return end
    active = state
    local _, build = GetBuildInfo()
    say("v0.2.0 / Build " .. (public(build, "string") and build or "inconnu") ..
        " : tu as 30 secondes pour survoler le POINT d'un joueur IMMOBILE dans la minimap en haut a droite. Reste immobile aussi.")
    local attempts = 0
    local function capture()
        attempts = attempts + 1
        state.step = "survol du point"
        if not Minimap:IsMouseOver() then
            if attempts >= 120 then finish("SANS TEMOIN : la souris n'a pas survole la minimap en 30 secondes.")
            else later(state, 0.25, false, capture) end
            return
        end
        state.step = "lecture de l'infobulle"
        state.names = readNames()
        if not next(state.names) then
            if attempts >= 120 then finish("SANS TEMOIN : aucun nom lisible en 30 secondes. Survole un point qui affiche un nom.")
            else later(state, 0.25, false, capture) end
            return
        end
        state.step = "coordonnees du point"
        state.x, state.y = GetCursorPosition()
        state.cx, state.cy = Minimap:GetCenter()
        state.scale, state.zoom = Minimap:GetEffectiveScale(), Minimap:GetZoom()
        for _, key in ipairs({ "x", "y", "cx", "cy", "scale", "zoom" }) do
            if not public(state[key], "number") then fail("Coordonnee indisponible ou protegee : " .. key .. ".") end
        end
        say("Point capture. Retire la souris de la minimap maintenant, sans bouger ton personnage. Attends le resultat.")
        local leaveAttempts = 0
        local function replay()
            state.step = "sortie de la souris"
            if Minimap:IsMouseOver() then
                leaveAttempts = leaveAttempts + 1
                if leaveAttempts >= 80 then finish("ANNULE : la souris est restee sur la minimap pendant 20 secondes.")
                else later(state, 0.25, false, replay) end
                return
            end
            state.step = "controle du cache"
            if matches(state.names, readNames()) then
                finish("INCONCLUANT : l'ancien nom reste en cache avant le test. Aucun succes annonce."); return
            end
            state.soft = true -- Also clean up if the API throws partway through.
            state.step = "activation du curseur virtuel"
            Minimap:SetUsingSoftCursor(true)
            state.step = "positionnement virtuel du point"
            Minimap:UpdateMouseoverAtPoint(state.x, state.y)
            state.step = "relecture automatique"
            state.hit = matches(state.names, readNames())
            later(state, 0.2, true, function()
                state.hit = state.hit or matches(state.names, readNames())
                later(state, 0.3, true, function()
                    state.hit = state.hit or matches(state.names, readNames())
                    state.step = "controle du point vide"
                    Minimap:UpdateMouseoverAtPoint(-10000, -10000)
                    later(state, 0.2, true, function()
                        if matches(state.names, readNames()) then
                            finish("INCONCLUANT : le nom persiste sur un point vide. Cache possible.")
                        elseif state.hit then
                            finish("POSITIF : meme texte relu sans survol reel, controle vide OK. A confirmer sur un autre joueur immobile.")
                        else
                            finish("NEGATIF : aucune relecture du texte temoin. Si le point est reste immobile, la methode ne fonctionne pas dans ce test.")
                        end
                    end)
                end)
            end)
        end
        later(state, 0.5, false, replay)
    end
    later(state, 0.5, false, capture)
end
SLASH_GRUDGELEDGERPROBE1 = "/glprobe"
if GrudgeLedger then function GrudgeLedger.MinimapProbeActive() return active ~= nil end end
SlashCmdList.GRUDGELEDGERPROBE = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "test" then start()
    elseif command == "stop" then if active then finish("ANNULE par le joueur.") end
    else say(latest or (GrudgeLedger and GrudgeLedger.db and GrudgeLedger.db.minimapProbe and GrudgeLedger.db.minimapProbe.result) or "v0.2.0 /glprobe test : survole un point, puis retire la souris au message. /glprobe stop : annuler. Aucun changement de pistage.") end
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_STARTED_MOVING")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:SetScript("OnEvent", function(_, event)
    if not active then return end
    local reasons = { PLAYER_REGEN_DISABLED = "Debut du combat.", PLAYER_STARTED_MOVING = "Ton personnage a commence a bouger.",
        PLAYER_LEAVING_WORLD = "Changement de zone ou deconnexion." }
    finish("ANNULE : " .. (reasons[event] or "Evenement inattendu."))
end)
