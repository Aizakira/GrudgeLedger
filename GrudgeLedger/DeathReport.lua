-- Why did I die: a death report in the fight detail, and a text export of recent deaths to
-- paste into an AI assistant. The export names no player: classes, levels and builds only.
local GL = GrudgeLedger
local L = GL.L
local UI = GL.UITheme
local D = {}
GL.DeathReport = D

local MAX_EXPORT = 10
local SLOTS = {
    {"head", "Tête"}, {"neck", "Cou"}, {"shoulder", "Épaules"}, {"back", "Dos"}, {"chest", "Torse"},
    {"wrist", "Poignets"}, {"hand", "Mains"}, {"waist", "Taille"}, {"leg", "Jambes"}, {"foot", "Pieds"},
    {"leftfinger", "Anneau 1"}, {"rightfinger", "Anneau 2"}, {"lefttrinket", "Bijou 1"}, {"righttrinket", "Bijou 2"},
    {"weapon", "Main droite"}, {"offhand", "Main gauche"}, {"ranged", "À distance"},
}

local function rowsOf(event)
    local report = type(event.report) == "table" and event.report
    local rows = report and (report.live or report.recap)
    return type(rows) == "table" and #rows > 0 and rows or nil
end
local function spellName(hit)
    if hit.kind == "SWING_DAMAGE" then
        return L("Attaque de mêlée")
    end
    if hit.kind == "ENVIRONMENTAL_DAMAGE" then
        return L("Environnement")
    end
    return type(hit.spell) == "string" and hit.spell or L("Sort non identifié")
end
local function sorted(map)
    local list = {}
    for name, amount in pairs(map) do
        list[#list + 1] = {name = name, amount = amount}
    end
    table.sort(list, function(a, b)
        if a.amount ~= b.amount then
            return a.amount > b.amount
        end
        return a.name < b.name
    end)
    return list
end

-- Damage received by source then by spell, the killing blow and the length of the fight.
-- name(hit) labels a source; the detail window names players, the export does not.
function D.Analyse(event, opponent, name)
    local result = {received = 0, sources = {}}
    local rows = rowsOf(event)
    if not rows then
        return result
    end
    local me, first, last, sources = event.actorGUID, nil, nil, {}
    for _, hit in ipairs(rows) do
        if type(hit.at) == "number" then
            first, last = math.min(first or hit.at, hit.at), math.max(last or hit.at, hit.at)
        end
        if hit.dst == me and type(hit.amount) == "number" then
            local key = hit.kind == "ENVIRONMENTAL_DAMAGE" and "environment" or hit.src or "unknown"
            local source = sources[key]
            if not source then
                source = {label = name(hit, key == opponent), total = 0, spells = {}, opponent = key == opponent}
                sources[key] = source
            end
            local spell = spellName(hit)
            source.total = source.total + hit.amount
            source.spells[spell] = (source.spells[spell] or 0) + hit.amount
            result.received = result.received + hit.amount
        end
        if hit.dst == me and hit.fatal then
            result.fatal = {spell = spellName(hit), amount = hit.amount, opponent = hit.src == opponent, label = name(hit, hit.src == opponent)}
        end
    end
    for _, source in pairs(sources) do
        source.spellList = sorted(source.spells)
        result.sources[#result.sources + 1] = source
    end
    table.sort(result.sources, function(a, b) return a.total > b.total end)
    result.duration = first and math.floor(last - first + .5)
    result.rows = #rows
    return result
end

local function spells(source, limit)
    local parts = {}
    for i = 1, math.min(limit, #source.spellList) do
        parts[i] = source.spellList[i].name .. " " .. source.spellList[i].amount
    end
    return table.concat(parts, ", ")
end
local function contextLine(event, analysis)
    local combat = type(event.combat) == "table" and event.combat or {}
    local parts = {}
    if analysis.duration then
        parts[#parts + 1] = L("Durée : %d s"):format(analysis.duration)
    end
    if combat.healthPct then
        parts[#parts + 1] = L("vie au début : %d %%"):format(combat.healthPct)
    end
    if combat.opponents then
        parts[#parts + 1] = L("adversaires : %d"):format(combat.opponents)
    end
    if combat.pve then
        parts[#parts + 1] = L("monstres aussi présents")
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end
local function analysisLines(event, analysis, lines)
    local context = contextLine(event, analysis)
    if context then
        lines[#lines + 1] = context
    end
    if #analysis.sources == 0 then
        lines[#lines + 1] = L("Aucun dégât reçu dans le déroulé enregistré.")
        return
    end
    lines[#lines + 1] = L("Dégâts reçus : %d"):format(analysis.received)
    for _, source in ipairs(analysis.sources) do
        lines[#lines + 1] = "  " .. L("%s : %s"):format(source.label, source.total .. " (" .. spells(source, 4) .. ")")
    end
    local fatal = analysis.fatal
    if fatal then
        local amount = fatal.amount and (" " .. fatal.amount) or ""
        lines[#lines + 1] = L("Coup fatal : %s par %s"):format(fatal.spell .. amount, fatal.label)
    end
end

-- The death report shown in the fight detail, after the builds and before the blow-by-blow.
function D.Text(event, opponent, opponentName)
    if type(event) ~= "table" or event.kind ~= "death" then
        return
    end
    local lines = {L("Rapport de mort")}
    if not rowsOf(event) then
        lines[2] = L("Aucun déroulé enregistré pour ce combat.")
        return table.concat(lines, "\n")
    end
    local analysis = D.Analyse(event, opponent, function(hit, isOpponent)
        if isOpponent then
            return opponentName
        end
        if hit.kind == "ENVIRONMENTAL_DAMAGE" then
            return L("Environnement")
        end
        return UI.plain(hit.from or L("Source inconnue"))
    end)
    analysisLines(event, analysis, lines)
    lines[#lines + 1] = L("Les soins, les contrôles et les auras ne sont pas relevés.")
    return table.concat(lines, "\n")
end

local function className(record)
    local _, _, class = GL.IdentityLabels(record)
    return type(class) == "string" and class or L("classe inconnue")
end
local statLabels = {{"HEALTH", L("vie %s")}, {"MANA", L("mana %s")}, {"RAGE", L("rage %s")},
    {"ENERGY", L("énergie %s")}, {"ARMOR", L("armure %s")}}
local function buildLine(build)
    if type(build) ~= "table" then
        return L("build non relevé")
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
    for _, stat in ipairs(statLabels) do
        local value = build.stats and build.stats[stat[1]]
        if value then
            parts[#parts + 1] = stat[2]:format(value)
        end
    end
    return #parts > 0 and table.concat(parts, " · ") or L("build non relevé")
end
local function itemName(id)
    local name = GL.Safe(GetItemInfo, id)
    return type(name) == "string" and name or L("objet n° %d"):format(id)
end
local function gearLine(build)
    local parts = {}
    for _, slot in ipairs(SLOTS) do
        local id = type(build) == "table" and type(build.gear) == "table" and tonumber(build.gear[slot[1]])
        if id then
            parts[#parts + 1] = L("%s : %s"):format(L(slot[2]), itemName(id))
        end
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

-- Our recent deaths, most recent first; only those of the character playing now.
function D.Deaths(guid)
    local me, list = GL.Safe(UnitGUID, "player"), {}
    for _, item in ipairs(GL.JournalEvents()) do
        local e = item.event
        if e.kind == "death" and not e.voided and e.voidReason ~= "battleground" and e.actorGUID == me
            and item.record and (not guid or item.record.guid == guid) then
            list[#list + 1] = {record = item.record, event = e}
        end
    end
    table.sort(list, function(a, b) return (a.event.time or 0) > (b.event.time or 0) end)
    return list
end

-- Plain text for an AI assistant: the question, our character and gear, then each death.
function D.Export(guid)
    local deaths = D.Deaths(guid)
    local lines = {L("Grudge Ledger · mes morts en JcJ dans World of Warcraft Classic"),
        L("Question : qu’est-ce qui me tue le plus souvent, et comment adapter mon équipement, mes talents et ma façon de jouer ?"),
        L("Les noms des joueurs sont retirés. Les soins, les contrôles et les auras ne sont pas relevés."), ""}
    if #deaths == 0 then
        lines[#lines + 1] = L("Aucune mort enregistrée.")
        return table.concat(lines, "\n"), 0
    end
    local killers = {}
    for _, d in ipairs(deaths) do
        local class = className(d.record)
        killers[class] = (killers[class] or 0) + 1
    end
    local summary = {}
    for _, k in ipairs(sorted(killers)) do
        summary[#summary + 1] = k.name .. " " .. k.amount
    end
    local latest = deaths[1].event.build or {}
    lines[#lines + 1] = L("Mon personnage : %s"):format(buildLine(latest.me))
    local gear = gearLine(latest.me)
    if gear then
        lines[#lines + 1] = L("Mon équipement : %s"):format(gear)
    end
    lines[#lines + 1] = L("Morts : %d · tueurs par classe : %s"):format(#deaths, table.concat(summary, ", "))
    for i = 1, math.min(MAX_EXPORT, #deaths) do
        local d, e = deaths[i], deaths[i].event
        local build = type(e.build) == "table" and e.build or {}
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("%d. %s · %s"):format(i, GL.Safe(date, "%d/%m/%Y %H:%M", e.time) or "?", type(e.zone) == "string" and e.zone or "?")
        lines[#lines + 1] = L("Tueur : %s · %s"):format(className(d.record), buildLine(build.opponent))
        lines[#lines + 1] = L("Moi : %s"):format(buildLine(build.me))
        local analysis = D.Analyse(e, d.record.guid, function(hit, isOpponent)
            if isOpponent then
                return L("le tueur")
            end
            return hit.kind == "ENVIRONMENTAL_DAMAGE" and L("Environnement") or L("autre joueur")
        end)
        if rowsOf(e) then
            analysisLines(e, analysis, lines)
        else
            lines[#lines + 1] = L("Aucun déroulé enregistré pour ce combat.")
        end
    end
    if #deaths > MAX_EXPORT then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L("%d morts plus anciennes non incluses."):format(#deaths - MAX_EXPORT)
    end
    return table.concat(lines, "\n"), #deaths
end

-- A window holding the export, selected and ready to copy.
local window
function D.ShowExport(guid)
    local text = D.Export(guid)
    if not window then
        window = UI.window("GrudgeLedgerDeathExport", L("Exporter mes morts"), 620, 470)
        local w = window
        -- Parchment, as in the fight detail window.
        local backing = UI.surface(w, UI.theme.paper, 12, 1)
        backing:ClearAllPoints()
        backing:SetPoint("TOPLEFT", 12, -48)
        backing:SetPoint("BOTTOMRIGHT", -12, 12)
        local paper = w:CreateTexture(nil, "BACKGROUND", nil, 2)
        paper:SetAllPoints(backing)
        paper:SetTexture("Interface\\AddOns\\GrudgeLedger\\Media\\JournalPaper")
        w.help = UI.label(w, L("Le texte est sélectionné : copiez-le (Ctrl+C) et collez-le dans Claude ou ChatGPT."), nil, 28, -62, 560)
        w.help:SetTextColor(unpack(UI.theme.inkMuted))
        w.scroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
        w.scroll:SetPoint("TOPLEFT", 28, -92)
        w.scroll:SetSize(536, 300)
        w.box = CreateFrame("EditBox", nil, w.scroll)
        w.box:SetMultiLine(true)
        w.box:SetAutoFocus(false)
        w.box:SetFontObject(ChatFontNormal or GameFontHighlight)
        w.box:SetTextColor(unpack(UI.theme.ink))
        w.box:SetSize(530, 300)
        w.box:SetScript("OnEscapePressed", function() w:Hide() end)
        w.scroll:SetScrollChild(w.box)
        w.close = UI.button(w, L("Fermer"), 28, -412, 120, function() w:Hide() end, true, true)
    end
    window.box:SetText(text)
    window:Show()
    window.box:SetFocus()
    window.box:HighlightText()
    return window
end
