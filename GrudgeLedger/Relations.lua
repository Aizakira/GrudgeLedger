-- Relations and Guilde, told as stories, in two books with the sheet's format: a narrow left column
-- with the entries, the page on the whole sheet. Relations opens on the Bilan (Recap.lua).
-- Everything here comes from the journal alone: no Armory archive, no studio photo, no guild needed.
local GL = GrudgeLedger
local UI, Panels, L = GL.UITheme, GL.DossierPanels, GL.L
local R = {}
GL.RelationsPages = R

local WEEK, MONTH = 7 * 86400, 30 * 86400
-- The pages were drawn on a column of 540 pixels that began 26 pixels into its page. They now take
-- the whole sheet of the narrow book: S() stretches a width, X() places from the sheet's left edge.
local SHEET_W, SHEET_H = 664, 510
local STRETCH = SHEET_W / 540
-- "1 ennemi", "2 ennemis": the right form for a count (review 0.58.5).
local function countForm(n, one, many)
    return (n == 1 and L(one) or L(many)):format(n)
end
local function S(value)
    return math.floor(value * STRETCH + 0.5)
end
local function X(value)
    return S(value - 26)
end
local DEBT_ROWS = 6 -- lines of the ledger shown at once. The rest turns as pages, never a scroll bar
local media = "Interface\\AddOns\\GrudgeLedger\\Media\\"

local function players()
    return GL.db and GL.db.players or {}
end
local function name(record)
    -- One value only: the escaping helper also returns how many characters it replaced.
    local escaped = UI.plain(record.fullName or record.name or "?")
    return escaped
end
local function day(at)
    return GL.Safe(date, "%d/%m", at) or "?"
end
local function count(record, field)
    return tonumber(record.pvp and record.pvp[field]) or 0
end
local function lastEvent(record, kind)
    local history = record.history or {}
    for i = #history, 1, -1 do
        local e = history[i]
        if type(e) == "table" and e.kind == kind and not e.voided and type(e.time) == "number" then return e end
    end
end

-- The player you beat most without ever dying to him (three victories at least).
function R.Prey()
    local prey
    for _, record in pairs(players()) do
        local kills = count(record, "kills")
        if kills >= 3 and count(record, "deaths") == 0 and (not prey or kills > count(prey, "kills")
            or kills == count(prey, "kills") and record.key < prey.key) then
            prey = record
        end
    end
    return prey
end

-- Open debts, heaviest first, then the debts settled in the last thirty days, newest first.
function R.Debts()
    local open, settled, total = GL.SearchPlayers({ relation = "debt" }), {}, 0
    for _, record in ipairs(open) do
        total = total + GL.Debt(record)
    end
    local now = GL.Now()
    for _, record in pairs(players()) do
        if GL.Debt(record) == 0 and count(record, "deaths") > 0 and count(record, "kills") > 0 and GL.Relation(record) ~= "friend" then
            local revenge, death = lastEvent(record, "kill"), lastEvent(record, "death")
            if revenge and death and revenge.time >= death.time and now - revenge.time <= MONTH then
                settled[#settled + 1] = { record = record, at = revenge.time, zone = revenge.zone }
            end
        end
    end
    table.sort(settled, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.record.key < b.record.key
    end)
    return open, settled, total
end

local function nickname(record)
    local I = GL.CharacterInsights
    local nick = I and I.Nickname and I.Nickname(record)
    return nick and ("« " .. nick .. " »") or ""
end
local function openSheet(record)
    if not record or not GL.OpenPlayerDossier then return end
    GL.OpenPlayerDossier(record.guid or record.key, function() GL.ShowRelations(R.page) end, record.fullName or record.name)
end

local function face(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame.raceIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.raceIcon:SetAllPoints()
    frame.classIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.classIcon:SetSize(16, 16)
    frame.classIcon:SetPoint("BOTTOMRIGHT")
    return frame
end
local function centered(parent, y, width, size, bold, color)
    local text = Panels.Text(parent, 8, y, width - 16, size, bold, color)
    text:SetJustifyH("CENTER")
    GL.Safe(text.SetWordWrap, text, false)
    return text
end
local function debtRow(page, i)
    local row = CreateFrame("Button", nil, page)
    row:SetPoint("TOPLEFT", X(26), -112 - (i - 1) * 58)
    row:SetSize(S(540), 56)
    local rule = row:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
    row.date = Panels.Text(row, S(0), -8, S(46), 12, false, UI.theme.inkMuted)
    row.name = Panels.Text(row, S(50), -6, S(290), 15, true)
    GL.Safe(row.name.SetWordWrap, row.name, false)
    row.detail = Panels.Text(row, S(50), -28, S(290), 12, false, UI.theme.inkMuted)
    GL.Safe(row.detail.SetWordWrap, row.detail, false)
    -- A settled debt is struck through with the pen.
    row.strike = row:CreateTexture(nil, "OVERLAY")
    row.strike:SetPoint("LEFT", row.name, "LEFT", -2, -1)
    row.strike:SetHeight(2)
    row.strike:SetColorTexture(0.42, 0.23, 0.12, 0.9)
    row.amount = Panels.Text(row, S(344), -10, S(56), 20, true)
    row.amount:SetJustifyH("RIGHT")
    row.state = Panels.Text(row, S(410), -16, S(130), 12, false, { 0.18, 0.37, 0.20 })
    row.state:SetJustifyH("RIGHT")
    row.bounty = UI.button(row, L("Prime"), S(470), -13, S(70), function()
        if row.record and row.record.guid and GL.OpenContactBounty then GL.OpenContactBounty(row.record.guid) end
    end, nil, true)
    row.sheet = UI.button(row, L("Fiche"), S(410), -13, S(56), function() openSheet(row.record) end, nil, true)
    row:SetScript("OnClick", function(self) openSheet(self.record) end)
    return row
end
local function buildDebts(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(400), 13, false, UI.theme.inkMuted)
    page.totalCaption = Panels.Text(page, X(436), -18, S(130), 11, false, UI.theme.inkMuted)
    page.totalCaption:SetJustifyH("RIGHT")
    page.total = Panels.Text(page, X(436), -32, S(130), 26, true, { 0.55, 0.12, 0.12 })
    page.total:SetJustifyH("RIGHT")
    local band = page:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT", X(26), -84)
    band:SetSize(S(540), 24)
    band:SetColorTexture(0.44, 0.28, 0.13, 0.18)
    page.columns = Panels.Text(page, X(30), -89, S(300), 12, false, UI.theme.inkMuted)
    page.columnDebt = Panels.Text(page, X(370), -89, S(56), 12, false, UI.theme.inkMuted)
    page.columnDebt:SetJustifyH("RIGHT")
    page.rows = {}
    for i = 1, DEBT_ROWS do page.rows[i] = debtRow(page, i) end
    page.empty = Panels.Text(page, X(26), -130, S(540), 13, false, UI.theme.inkMuted)
    page.offset = 0
    page.previous = UI.button(page, "‹", X(26), -464, S(40), function()
        page.offset = math.max(0, page.offset - DEBT_ROWS)
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", X(526), -464, S(40), function()
        page.offset = page.offset + DEBT_ROWS
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(76), -470, S(440), 12, false, UI.theme.inkMuted)
    page.count:SetJustifyH("CENTER")
    return page
end
local function debtDetail(record)
    local parts = {}
    local deaths, aggressions = count(record, "deaths"), count(record, "aggressions")
    if deaths == 1 then
        parts[#parts + 1] = L("1 mort")
    elseif deaths > 1 then
        parts[#parts + 1] = L("%d morts"):format(deaths)
    end
    if aggressions == 1 then
        parts[#parts + 1] = L("1 agression")
    elseif aggressions > 1 then
        parts[#parts + 1] = L("%d agressions"):format(aggressions)
    end
    local nick = nickname(record)
    if nick ~= "" then parts[#parts + 1] = nick end
    return table.concat(parts, " · ")
end
local function paintDebts(page)
    page.title:SetText(L("Le registre des dettes"))
    page.lead:SetText(L("Ce qu’on vous doit. Une ligne se raye quand vous prenez votre revanche."))
    page.totalCaption:SetText(L("Reste dû"))
    page.columns:SetText(L("Depuis · Débiteur"))
    page.columnDebt:SetText(L("Dette"))
    local open, settled, total = R.Debts()
    page.total:SetText(tostring(total))
    local lines = {}
    for _, record in ipairs(open) do
        local since = lastEvent(record, "death") or lastEvent(record, "aggression")
        lines[#lines + 1] = { record = record, at = since and since.time or record.lastEncounterAt }
    end
    for _, entry in ipairs(settled) do
        lines[#lines + 1] = { record = entry.record, at = entry.at, settled = true, zone = entry.zone }
    end
    page.offset = math.min(page.offset, math.max(0, math.floor((#lines - 1) / DEBT_ROWS) * DEBT_ROWS))
    for i, row in ipairs(page.rows) do
        local line = lines[page.offset + i]
        row.record = line and line.record
        if line then
            local record = line.record
            row.date:SetText(line.at and day(line.at) or "")
            Panels.Fit(row.name, name(record), S(290), 15, 11, true)
            row.name:SetTextColor(unpack(line.settled and UI.theme.inkMuted or UI.theme.ink))
            if line.settled then
                row.strike:SetWidth(math.min(S(290), (GL.Safe(row.name.GetStringWidth, row.name) or 120) + 4))
                row.strike:Show()
                local zone = type(line.zone) == "string" and line.zone ~= "?" and line.zone
                row.detail:SetText(zone and L("Vengé le %s · %s"):format(day(line.at), UI.plain(zone)) or L("Vengé le %s"):format(day(line.at)))
                row.amount:SetText("")
                row.state:SetText(L("Réglée"))
                row.bounty:Hide()
                row.sheet:Hide()
            else
                row.strike:Hide()
                Panels.Fit(row.detail, debtDetail(record), S(290), 12, 9)
                row.amount:SetText(tostring(GL.Debt(record)))
                row.amount:SetTextColor(0.55, 0.12, 0.12)
                row.state:SetText("")
                -- Only when a bounty can be posted or read for this player (review 0.58.5).
                if GL.ContactBountyMode and GL.ContactBountyMode(record) then row.bounty:Show() else row.bounty:Hide() end
                row.sheet:Show()
            end
            row:Show()
        else
            row:Hide()
        end
    end
    page.empty:SetText(#lines == 0 and L("Personne ne vous doit rien. Le registre se remplit quand un joueur vous attaque ou vous tue.") or "")
    page.previous:SetEnabled(page.offset > 0)
    page.next:SetEnabled(page.offset + DEBT_ROWS < #lines)
    page.count:SetText(L("%s · %s ce mois-ci"):format(countForm(#open, "%d dette ouverte", "%d dettes ouvertes"),
        countForm(#settled, "%d réglée", "%d réglées")))
end

-- Rivalries: the players you fought twice or more (two finished fights).
function R.Rivals()
    local list = {}
    for _, record in pairs(players()) do
        local fights = count(record, "kills") + count(record, "deaths")
        if fights >= 2 then
            list[#list + 1] = { record = record, weight = fights * 10 + count(record, "aggressions") }
        end
    end
    table.sort(list, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.record.key < b.record.key
    end)
    return list
end
-- Rivalries (owner's brief of 25/11): five strips of parchment a page, each with the rival, what
-- stands out between you (GL.RivalryRules), your victories and deaths, and where it last happened.
-- A click unfolds the strip in place: you facing the rival, the score, a sentence of what turned,
-- the debt, the last five fights from oldest to newest, the sheet and the bounty. A second click,
-- or another strip, folds it. A search reads every name and guild before the pages.
-- Six a page, closer together (owner, 25/11: the gaps were too wide).
local RIVAL_PAGE = 6
local RIVAL_STEPS = 5 -- fights shown when unfolded, the latest ones, oldest on the left
local RIVAL_TOP, RIVAL_H, RIVAL_GAP = -60, 62, 4
-- Unfolded: the five strips get narrow and the sheet opens under its own (page 510 high: the
-- strips, the sheet and the gaps end at 464, above the worn bottom of the page).
local RIVAL_SMALL, RIVAL_SMALL_GAP, RIVAL_SHEET = 36, 3, 210
local GREEN, RED = { 0.18, 0.37, 0.20 }, { 0.55, 0.12, 0.12 }
-- Plain score when the rules cannot read a sheet (damaged data): the page keeps going.
local function plainAnalysis(record)
    local kills, deaths = count(record, "kills"), count(record, "deaths")
    return { key = record.key, kills = kills, deaths = deaths, volume = kills + deaths, debt = GL.Debt(record), eligible = true,
        timeline = {}, chronology = {}, motifs = {}, narrative = { id = "aucune_issue_datee", params = {} }, categoryRank = 5 }
end
-- The analyses, kept until a sheet changes, or for ten minutes (a recent fact leaves its week).
local rivalCache, rivalCacheAt = {}, 0
local function analyse(record, now)
    local signature = table.concat({ #(record.history or {}), count(record, "kills"), count(record, "deaths"),
        count(record, "aggressions"), tostring(record.assists), GL.Debt(record) }, ":")
    local kept = rivalCache[record.key]
    if kept and kept.signature == signature then return kept.analysis end
    local Rules = GL.RivalryRules
    local ok, analysis = pcall(function() return Rules.FromRecord(record, GL, now) end)
    if not ok or type(analysis) ~= "table" then analysis = plainAnalysis(record) end
    analysis.record = record
    local told, tell = pcall(GL.RivalryLines.Tell, record, analysis, now)
    analysis.tell = told and type(tell) == "table" and tell or nil
    rivalCache[record.key] = { signature = signature, analysis = analysis }
    return analysis
end
-- Every rival, ranked by what stands out, then filtered by the search (names and guilds, any case
-- or accents), the order kept.
function R.RivalStories(query)
    local now = GL.Now()
    if now - rivalCacheAt > 600 then rivalCache, rivalCacheAt = {}, now end
    local analyses = {}
    for _, item in ipairs(R.Rivals()) do analyses[#analyses + 1] = analyse(item.record, now) end
    local ok, ranked = pcall(GL.RivalryRules.Rank, analyses)
    if not ok then ranked = analyses end
    local folded = GL.FoldName and GL.FoldName(query or "") or ""
    if folded == "" then return ranked end
    local found = {}
    for _, a in ipairs(ranked) do
        local record = a.record
        for _, text in ipairs({ record.fullName, record.name, record.guild }) do
            local value = type(text) == "string" and GL.FoldName(text)
            if value and value:find(folded, 1, true) then
                found[#found + 1] = a
                break
            end
        end
    end
    return found
end
-- The short title of a strip, and the sentence of the unfolded sheet.
local function motifTitle(a)
    local n = a.narrative or {}
    local p = n.params or {}
    if n.id == "issue_mixte" then return L("Combat mixte") end
    if n.id == "serie_victoires_interrompue" then
        return p.egaliteAvantDernier and L("Égalité rompue au dernier combat") or L("Série de victoires interrompue")
    end
    if n.id == "serie_morts_interrompue" then return L("Série noire interrompue") end
    if n.id == "serie_victoires" then return L("Série de victoires") end
    if n.id == "serie_morts" then return L("Série noire") end
    if n.id == "duel_dispute" then return L("Duel disputé") end
    if n.id == "rencontres_jours_distincts" then return L("Rencontres répétées") end
    if n.id == "victoire_apres_mort" then return L("Revanche prise") end
    if n.id == "premiere_victoire_a_prendre" then return L("Première victoire à prendre") end
    return L("Bilan")
end
function R.RivalSentence(a)
    local n = a.narrative or {}
    local p = n.params or {}
    if n.id == "issue_mixte" then
        return p.kind == "mort_assistance" and L("Une mort et un coup de main dans le même combat.")
            or L("Une mort et une victoire dans le même combat.")
    end
    if n.id == "serie_victoires_interrompue" then
        if p.egaliteAvantDernier then
            return L("%d victoires vous avaient ramenés à égalité. Au dernier combat, votre rival a repris l’avantage."):format(p.count)
        end
        return L("%d victoires de suite, puis une mort au dernier combat."):format(p.count)
    end
    if n.id == "serie_morts_interrompue" then return L("%d morts de suite, puis une victoire au dernier combat."):format(p.count) end
    if n.id == "serie_victoires" then return L("Vos %d derniers combats se sont terminés par des victoires."):format(p.count) end
    if n.id == "serie_morts" then return L("Vos %d derniers combats se sont terminés par des morts."):format(p.count) end
    if n.id == "duel_dispute" then return L("Le bilan reste partagé : %d victoires et %d morts."):format(p.kills, p.deaths) end
    if n.id == "rencontres_jours_distincts" then return L("Des combats sur %d jours différents ces sept derniers jours."):format(p.days) end
    if n.id == "victoire_apres_mort" then return L("Votre dernière victoire suit un combat perdu.") end
    if n.id == "premiere_victoire_a_prendre" then return L("Aucune victoire face à ce rival pour l’instant : %d morts au bilan."):format(p.deaths) end
    if n.id == "historique_incomplet" then return L("Le journal ne garde pas le détail de tous vos combats contre ce rival.") end
    if n.id == "historique_simple" then
        return L("Votre journal garde %s et %s face à ce rival."):format(countForm(a.kills, "%d victoire", "%d victoires"),
            countForm(a.deaths, "%d mort", "%d morts"))
    end
    return L("Aucun combat détaillé dans le journal.")
end
-- A day and its hour: "22/11 à 21:40" (owner, 25/11: the day alone did not say when).
local function stamp(at)
    local hour = GL.Safe(date, "%H:%M", at)
    return hour and L("%s à %s"):format(day(at), hour) or day(at)
end
local function whenWhere(a)
    if not a.lastOutcomeAt then return "" end
    return a.lastOutcomeZone and (stamp(a.lastOutcomeAt) .. " · " .. UI.plain(a.lastOutcomeZone)) or stamp(a.lastOutcomeAt)
end
-- A score in two texts, each in its own colour, around a dot: centred on x.
local function scorePair(parent, size)
    local pair = { kills = Panels.Text(parent, 0, 0, 140, size, true), deaths = Panels.Text(parent, 0, 0, 140, size, true), size = size }
    GL.Safe(pair.kills.SetWordWrap, pair.kills, false)
    GL.Safe(pair.deaths.SetWordWrap, pair.deaths, false)
    pair.kills:SetJustifyH("RIGHT")
    pair.deaths:SetJustifyH("LEFT")
    -- A small drawn dot between the figures: the font's "·" sat at their top.
    pair.dot = parent:CreateTexture(nil, "ARTWORK")
    pair.dot:SetSize(4, 4)
    pair.dot:SetColorTexture(0.55, 0.40, 0.20, 0.9)
    return pair
end
local function placePair(pair, parent, x, y, kills, deaths, light)
    pair.dot:ClearAllPoints()
    pair.dot:SetPoint("CENTER", parent, "TOPLEFT", x, y - math.floor(pair.size * 0.55 + 0.5))
    pair.kills:ClearAllPoints()
    pair.kills:SetPoint("TOPRIGHT", parent, "TOPLEFT", x - 9, y)
    pair.kills:SetText(kills)
    pair.deaths:ClearAllPoints()
    pair.deaths:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 9, y)
    pair.deaths:SetText(deaths)
    if light then
        pair.kills:SetTextColor(0.56, 0.85, 0.6)
        pair.deaths:SetTextColor(0.94, 0.48, 0.42)
    else
        pair.kills:SetTextColor(unpack(GREEN))
        pair.deaths:SetTextColor(unpack(RED))
    end
end
-- One step of the thread: what happened, in a word and a mark, then how.
local function stepLook(entry)
    local cause = entry.deathCause
    local how = cause == "killing_blow" and L("Coup fatal") or cause == "pet_killing_blow" and L("Coup fatal de son familier")
        or cause == "contributed" and L("Avec d’autres joueurs") or ""
    if entry.outcome == "mort" then
        if how == "" and entry.aggressions > 0 then how = L("Agression") end
        return L("Mort"), RED, GL.Art.DeathSeal, how
    elseif entry.outcome == "victoire" then
        return L("Victoire"), GREEN, GL.Art.VictorySeal, ""
    elseif entry.outcome == "mixte" then
        return L("Combat mixte"), UI.theme.brass, GL.Art.Swords, how
    elseif entry.outcome == "assistance" then
        return L("Coup de main"), UI.theme.brass, GL.Art.Swords, ""
    end
    return L("Agression"), UI.theme.inkMuted, GL.Art.Swords, ""
end
-- The Journal's paper arrow, turned down to unfold (folded) or up to fold (unfolded).
local function chevron(texture, open)
    if open then
        GL.Safe(texture.SetTexCoord, texture, 1, 0, 0, 0, 1, 1, 0, 1)
    else
        GL.Safe(texture.SetTexCoord, texture, 0, 1, 1, 1, 0, 0, 1, 0)
    end
end
local function arrowButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b.art = b:CreateTexture(nil, "ARTWORK")
    b.art:SetAllPoints()
    b.art:SetTexture(media .. "JournalReferenceArrowRight")
    chevron(b.art, false)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.91, 0.77, 0.48, 0.18)
    b:SetScript("OnClick", onClick)
    return b
end
local function buildRivals(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(150), 21, true)
    -- The search, like the guild journal's, on a parchment field.
    page.search = CreateFrame("EditBox", nil, page)
    page.search:SetPoint("TOPLEFT", X(170), -20)
    page.search:SetSize(S(176), 24)
    page.search:SetAutoFocus(false)
    page.search:SetMaxLetters(40)
    UI.styleInput(page.search, false, true)
    page.search:SetTextInsets(8, 6, 3, 3)
    page.searchHint = UI.label(page.search, L("Rechercher un rival…"), nil, 8, -5, S(160))
    page.searchHint:SetTextColor(unpack(UI.theme.muted))
    local function apply()
        page.query = page.search:GetText():match("^%s*(.-)%s*$")
        page.number, page.open = 1, nil
        R.Refresh()
    end
    page.search:SetScript("OnEnterPressed", function(self)
        apply()
        self:ClearFocus()
    end)
    page.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.search:SetScript("OnTextChanged", function(self)
        if self:GetText():find("%S") then page.searchHint:Hide() else page.searchHint:Show() end
        apply()
    end)
    page.previous = UI.button(page, "‹", X(402), -18, S(40), function()
        page.number, page.open = page.number - 1, nil
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(444), -24, S(80), 12, false, UI.theme.inkMuted)
    page.count:SetJustifyH("CENTER")
    page.next = UI.button(page, "›", X(526), -18, S(40), function()
        page.number, page.open = page.number + 1, nil
        R.Refresh()
    end, nil, true)
    page.number = 1
    page.strips = {}
    for i = 1, RIVAL_PAGE do
        local strip = CreateFrame("Button", nil, page)
        strip:SetSize(S(548), RIVAL_H)
        strip.paper = strip:CreateTexture(nil, "BACKGROUND")
        strip.paper:SetAllPoints()
        strip.paper:SetTexture(GL.Art.RivalStrip)
        strip.face = face(strip, 44)
        strip.name = Panels.Text(strip, 0, 0, S(300), 19, true)
        GL.Safe(strip.name.SetWordWrap, strip.name, false)
        -- Why this rival matters, in a line that names what happened (RivalryLines.lua).
        strip.motif = Panels.Text(strip, 0, 0, S(300), 12, false, UI.theme.red)
        GL.Safe(strip.motif.SetWordWrap, strip.motif, false)
        strip.score = scorePair(strip, 17)
        strip.when = Panels.Text(strip, 0, 0, S(150), 11, false, UI.theme.inkMuted)
        strip.when:SetJustifyH("CENTER")
        GL.Safe(strip.when.SetWordWrap, strip.when, false)
        strip.rule = strip:CreateTexture(nil, "ARTWORK")
        strip.rule:SetColorTexture(0.49, 0.32, 0.13, 0.35)
        strip.rule:SetWidth(1)
        local hover = strip:CreateTexture(nil, "HIGHLIGHT")
        hover:SetPoint("TOPLEFT", 8, -8)
        hover:SetPoint("BOTTOMRIGHT", -8, 8)
        hover:SetColorTexture(0.91, 0.77, 0.48, 0.12)
        -- The Journal's paper button folds and unfolds, as a click on the strip does (owner's kit).
        local function toggle()
            if not strip.key then return end
            page.open = page.open ~= strip.key and strip.key or nil
            R.Refresh()
        end
        strip:SetScript("OnClick", toggle)
        strip.fold = arrowButton(strip, toggle)
        strip.fold:SetPoint("RIGHT", strip, "RIGHT", -16, 0)
        page.strips[i] = strip
    end
    -- The unfolded sheet, one for the page: a sheet of parchment, and the band where you face your
    -- rival, Alliance blue on your side, Horde red on theirs (owner, 25/11).
    local sheet = CreateFrame("Frame", nil, page)
    page.sheet = sheet
    sheet:SetSize(S(548), RIVAL_SHEET)
    sheet.paper = sheet:CreateTexture(nil, "BACKGROUND")
    sheet.paper:SetAllPoints()
    sheet.paper:SetTexture(GL.Art.RivalSheet)
    sheet.band = sheet:CreateTexture(nil, "ARTWORK")
    sheet.band:SetPoint("TOPLEFT", 12, -10)
    sheet.band:SetPoint("TOPRIGHT", -12, -10)
    sheet.band:SetHeight(66)
    sheet.band:SetTexture(GL.Art.RivalDuel)
    local light, pale = { 0.95, 0.9, 0.78 }, { 0.8, 0.72, 0.58 }
    sheet.you = face(sheet, 52)
    sheet.you:SetPoint("TOPLEFT", 24, -17)
    sheet.youName = Panels.Text(sheet, 86, -22, S(130), 16, true, light)
    sheet.youClass = Panels.Text(sheet, 86, -43, S(130), 11, false, pale)
    GL.Safe(sheet.youClass.SetWordWrap, sheet.youClass, false)
    sheet.caption = Panels.Text(sheet, S(180), -20, S(188), 11, false, UI.theme.brass)
    sheet.caption:SetJustifyH("CENTER")
    sheet.score = scorePair(sheet, 18)
    sheet.rival = face(sheet, 52)
    sheet.rival:SetPoint("TOPRIGHT", -24, -17)
    sheet.rivalName = Panels.Text(sheet, S(548) - 86 - S(150), -22, S(150), 16, true, light)
    sheet.rivalName:SetJustifyH("RIGHT")
    GL.Safe(sheet.rivalName.SetWordWrap, sheet.rivalName, false)
    sheet.rivalClass = Panels.Text(sheet, S(548) - 86 - S(150), -43, S(150), 11, false, pale)
    sheet.rivalClass:SetJustifyH("RIGHT")
    GL.Safe(sheet.rivalClass.SetWordWrap, sheet.rivalClass, false)
    -- A click on the rival (name or face) opens their sheet.
    sheet.rivalHit = CreateFrame("Button", nil, sheet)
    sheet.rivalHit:SetPoint("TOPRIGHT", -14, -12)
    sheet.rivalHit:SetSize(S(150) + 76, 62)
    local glow = sheet.rivalHit:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(0.91, 0.77, 0.48, 0.10)
    sheet.rivalHit:SetScript("OnClick", function() openSheet(sheet.record) end)
    sheet.rivalHit:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("Ouvrir sa fiche"))
        GameTooltip:Show()
    end)
    sheet.rivalHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- What happened, then a line that pushes you; the debt on the right.
    sheet.story = Panels.Text(sheet, 20, -84, S(330), 12, false, UI.theme.ink)
    sheet.story:SetHeight(44)
    GL.Safe(sheet.story.SetWordWrap, sheet.story, true)
    GL.Safe(sheet.story.SetJustifyV, sheet.story, "TOP")
    sheet.debt = Panels.Text(sheet, S(548) - 20 - S(140), -86, S(140), 13, true)
    sheet.debt:SetJustifyH("RIGHT")
    local rule = sheet:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 20, -134)
    rule:SetPoint("TOPRIGHT", -20, -134)
    rule:SetHeight(1)
    rule:SetColorTexture(0.55, 0.40, 0.20, 0.35)
    sheet.threadTitle = Panels.Text(sheet, 20, -141, S(116), 13, true)
    sheet.threadWhen = Panels.Text(sheet, 20 + S(112), -142, S(150), 11, false, UI.theme.inkMuted)
    GL.Safe(sheet.threadWhen.SetWordWrap, sheet.threadWhen, false)
    sheet.fold = arrowButton(sheet, function()
        page.open = nil
        R.Refresh()
    end)
    sheet.fold:SetPoint("TOPRIGHT", -16, -137)
    chevron(sheet.fold.art, true)
    -- The bounty under the debt (owner, 25/11): no button left in the way of the thread.
    sheet.bounty = UI.button(sheet, L("Poser une prime"), S(548) - 20 - S(120), -106, S(120), function()
        if sheet.record and sheet.record.guid and GL.OpenContactBounty then GL.OpenContactBounty(sheet.record.guid) end
    end, nil, true)
    sheet.empty = Panels.Text(sheet, 20, -172, S(480), 12, false, UI.theme.inkMuted)
    sheet.line = sheet:CreateTexture(nil, "BORDER")
    sheet.line:SetHeight(1)
    sheet.line:SetColorTexture(0.52, 0.38, 0.20, 0.55)
    sheet.steps = {}
    for i = 1, RIVAL_STEPS do
        local step = CreateFrame("Frame", nil, sheet)
        step:SetSize(S(100), 42)
        step.mark = step:CreateTexture(nil, "ARTWORK")
        step.mark:SetSize(22, 22)
        step.mark:SetPoint("TOP", 0, 0)
        step.word = centered(step, -22, S(100), 12, true)
        step.how = centered(step, -36, S(100), 10, false, UI.theme.inkMuted)
        GL.Safe(step.EnableMouse, step, true)
        -- The game's own words for the fight, on hover, with its day and hour.
        step:SetScript("OnEnter", function(self)
            if not (self.tip and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tip[1])
            GameTooltip:AddLine(self.tip[2], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        step:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        sheet.steps[i] = step
    end
    sheet:Hide()
    page.empty = Panels.Text(page, X(26), -72, S(540), 13, false, UI.theme.inkMuted)
    page.clear = UI.button(page, L("Effacer la recherche"), X(26), -100, S(150), function()
        page.search:SetText("")
        page.query, page.number, page.open = nil, 1, nil
        R.Refresh()
    end, nil, true)
    return page
end
local function paintStrip(strip, a, small, open)
    local record = a.record
    strip.key = record.key
    strip:SetHeight(small and RIVAL_SMALL or RIVAL_H)
    local portrait = small and 30 or 50
    strip.face:SetSize(portrait, portrait)
    strip.face:ClearAllPoints()
    strip.face:SetPoint("LEFT", 18, 0)
    GL.PaintBookPortrait(strip.face, record)
    local left = 18 + portrait + 12
    -- The score and its date sit before the button; the name and the line take the rest.
    local right = S(548) - 16 - 26 - 12 - S(150)
    strip.name:ClearAllPoints()
    strip.name:SetPoint("TOPLEFT", left, small and -4 or -9)
    Panels.Fit(strip.name, name(record), right - left - 12, small and 14 or 19, 11, true)
    strip.motif:ClearAllPoints()
    strip.motif:SetPoint("TOPLEFT", left, small and -20 or -33)
    local tell = a.tell or {}
    Panels.Fit(strip.motif, tell.headline or motifTitle(a), right - left - 12, small and 10 or 13, 9)
    placePair(strip.score, strip, right + S(75), small and -4 or -12, L("%d V"):format(a.kills), L("%d M"):format(a.deaths))
    strip.when:ClearAllPoints()
    strip.when:SetPoint("TOPLEFT", right, small and -20 or -34)
    Panels.Fit(strip.when, whenWhere(a), S(150), 11, 8)
    strip.rule:ClearAllPoints()
    strip.rule:SetPoint("TOPLEFT", right - 6, small and -6 or -10)
    strip.rule:SetHeight(small and 24 or 42)
    strip.fold:SetSize(small and 22 or 26, small and 22 or 26)
    chevron(strip.fold.art, open)
    strip:Show()
end
local function paintSheet(sheet, a)
    local record = a.record
    sheet.record = record
    sheet.youName:SetText(L("Vous"))
    local me = GL.Safe(UnitName, "player")
    local class = GL.Safe(UnitClass, "player")
    Panels.Fit(sheet.youClass, UI.plain(type(me) == "string" and me or (type(class) == "string" and class or "")), S(130), 11, 8)
    local guid = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    local race, raceFile = GL.Safe(UnitRace, "player")
    local className, classFile = GL.Safe(UnitClass, "player")
    sheet.self = sheet.self or {}
    local self = sheet.self
    self.key, self.guid, self.name, self.fullName = "player", guid, me, me
    self.race, self.raceName, self.class, self.className = raceFile, race, classFile, className
    self.faction = GL.Clean(GL.Safe(UnitFactionGroup, "player"), "string")
    GL.PaintBookPortrait(sheet.you, self)
    sheet.caption:SetText(L("Votre bilan"))
    placePair(sheet.score, sheet, S(274), -38, countForm(a.kills, "%d victoire", "%d victoires"),
        countForm(a.deaths, "%d mort", "%d morts"), true)
    GL.PaintBookPortrait(sheet.rival, record)
    Panels.Fit(sheet.rivalName, name(record), S(150), 15, 10, true)
    local identity = {}
    if record.className then identity[#identity + 1] = UI.plain(record.className) end
    if record.guild then identity[#identity + 1] = UI.plain(record.guild) end
    Panels.Fit(sheet.rivalClass, table.concat(identity, " · "), S(150), 11, 8)
    -- The fact that names what happened (or what the score tells), then the push.
    local tell = a.tell or {}
    local story = tell.fact or R.RivalSentence(a)
    if tell.push and tell.push ~= "" then story = story .. " " .. tell.push end
    sheet.story:SetText(story)
    local debt = a.debt or 0
    local short = UI.plain(record.name or record.fullName or "?")
    if debt > 0 then
        Panels.Fit(sheet.debt, (debt == 1 and L("%s vous doit %d point") or L("%s vous doit %d points")):format(short, debt), S(132), 13, 9, true)
        sheet.debt:SetTextColor(unpack(RED))
    else
        sheet.debt:SetText(L("Comptes réglés"))
        sheet.debt:SetTextColor(unpack(GREEN))
    end
    sheet.threadTitle:SetText(L("Derniers combats"))
    local timeline = a.timeline or {}
    local latest = timeline[1]
    sheet.threadWhen:SetText(latest and (stamp(latest.last) .. (latest.zone and (" · " .. UI.plain(latest.zone)) or "")) or "")
    if GL.ContactBountyMode and GL.ContactBountyMode(record) then sheet.bounty:Show() else sheet.bounty:Hide() end
    local shown = math.min(RIVAL_STEPS, #timeline)
    sheet.empty:SetText(shown == 0 and L("Aucun combat détaillé dans le journal.") or "")
    -- Oldest on the left: the latest five, turned around, spread over the sheet.
    local span = S(548) - 40
    local width = shown > 0 and math.floor(span / shown) or 0
    sheet.line:ClearAllPoints()
    sheet.line:SetPoint("TOPLEFT", 20 + width / 2, -165)
    sheet.line:SetWidth(math.max(1, width * (shown - 1)))
    if shown > 1 then sheet.line:Show() else sheet.line:Hide() end
    for i, step in ipairs(sheet.steps) do
        local entry = i <= shown and timeline[shown - i + 1]
        if entry then
            local word, color, mark, how = stepLook(entry)
            step:ClearAllPoints()
            step:SetPoint("TOPLEFT", 20 + (i - 1) * width, -154)
            step:SetWidth(width)
            step.mark:SetTexture(mark)
            -- The seals are coloured already: shown as they are.
            step.mark:SetVertexColor(1, 1, 1)
            step.word:SetText(word)
            step.word:SetTextColor(unpack(color))
            Panels.Fit(step.how, how, width - 8, 10, 8)
            local where = entry.zone and (" · " .. UI.plain(entry.zone)) or ""
            step.tip = { stamp(entry.at) .. where, entry.title }
            step:Show()
        else
            step:Hide()
        end
    end
    sheet:Show()
end
local function paintRivals(page)
    page.title:SetText(L("Rivalités"))
    local all = R.RivalStories(page.query)
    local pages = math.max(1, math.ceil(#all / RIVAL_PAGE))
    page.number = math.max(1, math.min(page.number or 1, pages))
    -- The strip that was open stays open while it is on this page.
    local first = (page.number - 1) * RIVAL_PAGE
    local openAt
    for i = 1, RIVAL_PAGE do
        local a = all[first + i]
        if a and a.record.key == page.open then openAt = i end
    end
    if not openAt then page.open = nil end
    local y = RIVAL_TOP
    for i, strip in ipairs(page.strips) do
        local a = all[first + i]
        if a then
            if i == openAt then
                strip.key = a.record.key
                strip:Hide()
                page.sheet:ClearAllPoints()
                page.sheet:SetPoint("TOPLEFT", X(22), y)
                paintSheet(page.sheet, a)
                y = y - RIVAL_SHEET - RIVAL_SMALL_GAP
            else
                strip:ClearAllPoints()
                strip:SetPoint("TOPLEFT", X(22), y)
                paintStrip(strip, a, openAt ~= nil, false)
                y = y - (openAt and RIVAL_SMALL + RIVAL_SMALL_GAP or RIVAL_H + RIVAL_GAP)
            end
        else
            strip:Hide()
        end
    end
    if not openAt then page.sheet:Hide() end
    page.bottom = y
    local searching = page.query and page.query ~= ""
    if #all == 0 then
        page.empty:SetText(searching and L("Aucun rival ne correspond à « %s ».")
            :format(UI.plain(page.query)) or L("Aucune rivalité pour l’instant. Il en faut deux combats terminés contre le même joueur."))
    else
        page.empty:SetText("")
    end
    if #all == 0 and searching then page.clear:Show() else page.clear:Hide() end
    page.previous:SetEnabled(page.number > 1)
    page.next:SetEnabled(page.number < pages)
    page.count:SetText(#all > 0 and L("Page %d sur %d"):format(page.number, pages) or "")
end

-- Guild crests: the guilds that weigh in your book, hostile or friendly, six at most.
local CRESTS = 6
local crestColors = { enemy = { 0.35, 0.08, 0.08 }, hostile = { 0.45, 0.16, 0.10 }, warning = { 0.42, 0.29, 0.08 },
    friend = { 0.18, 0.37, 0.20 }, neutral = { 0.23, 0.16, 0.11 } }
function R.Guilds()
    local list = {}
    for _, row in ipairs(GL.GuildStatistics()) do
        local hostile = (row.deaths or 0) + (row.aggressions or 0) + (row.grudges or 0)
        local weight = hostile + (row.friends or 0) + (row.kills or 0)
        if weight > 0 then
            local rule = GL.GetGuildRule(row.name, row.realm)
            -- "En guerre" is your own word (a guild rule). Without a rule the facts only say hostile or friendly.
            local stance = rule and rule.reaction or hostile > 0 and "hostile" or (row.friends or 0) > 0 and "friend" or "neutral"
            list[#list + 1] = { row = row, weight = weight, stance = stance, ruled = rule ~= nil }
        end
    end
    table.sort(list, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return tostring(a.row.key) < tostring(b.row.key)
    end)
    return list
end
-- "Ok Bodycount" gives "OB", "ducks" gives "D": the first letter of the first two words, whole
-- UTF-8 letters only.
function R.Initials(guild)
    local letters = {}
    for word in tostring(guild or ""):gmatch("%S+") do
        local letter = word:match("^[%z\1-\127\194-\244][\128-\191]*")
        if letter and #letters < 2 and not letter:match("^[%p%d]$") then letters[#letters + 1] = letter:upper() end
    end
    return UI.plain(table.concat(letters))
end
local function buildGuilds(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(540), 13, false, UI.theme.inkMuted)
    page.cards = {}
    for i = 1, CRESTS do
        local card = CreateFrame("Button", nil, page)
        card:SetPoint("TOPLEFT", X(26) + ((i - 1) % 2) * S(274), -80 - math.floor((i - 1) / 2) * 124)
        card:SetSize(S(266), 116)
        UI.surface(card, { 0.79, 0.66, 0.42 })
        UI.surface(card, { 0.96, 0.91, 0.78 }, 1, 1)
        card.crestRim = card:CreateTexture(nil, "ARTWORK")
        card.crestRim:SetPoint("TOPLEFT", S(12), -14)
        card.crestRim:SetSize(44, 54)
        card.crestRim:SetColorTexture(0.52, 0.38, 0.20)
        card.crest = card:CreateTexture(nil, "OVERLAY")
        card.crest:SetPoint("TOPLEFT", S(14), -16)
        card.crest:SetSize(40, 50)
        card.initials = Panels.Text(card, S(14), -28, S(40), 20, true, UI.theme.brass)
        card.initials:SetJustifyH("CENTER")
        GL.Safe(card.initials.SetDrawLayer, card.initials, "OVERLAY", 7)
        card.name = Panels.Text(card, S(66), -12, S(190), 15, true)
        GL.Safe(card.name.SetWordWrap, card.name, false)
        card.stance = Panels.Text(card, S(66), -33, S(190), 12, true, UI.theme.red)
        card.lines = Panels.Text(card, S(66), -52, S(190), 11, false, UI.theme.inkMuted)
        card.lines:SetHeight(54)
        GL.Safe(card.lines.SetWordWrap, card.lines, true)
        GL.Safe(card.lines.SetJustifyV, card.lines, "TOP")
        card:SetScript("OnClick", function() R.OpenRankings(true) end)
        page.cards[i] = card
    end
    page.empty = Panels.Text(page, X(26), -86, S(540), 13, false, UI.theme.inkMuted)
    page.all = Panels.Link(page, X(304), -464, S(262), function() R.OpenRankings(true) end)
    return page
end
local function paintGuilds(page)
    page.title:SetText(L("Guildes"))
    local guilds = R.Guilds()
    page.lead:SetText(#guilds > 0 and L("Celles qui pèsent dans votre livre, en mal comme en bien.") or "")
    local stances = { enemy = L("En guerre"), hostile = L("Hostile"), warning = L("Méfiance"), friend = L("Amie"), neutral = L("Neutre") }
    for i, card in ipairs(page.cards) do
        local entry = guilds[i]
        if entry then
            local row = entry.row
            Panels.Fit(card.name, UI.plain(row.name), S(190), 15, 10, true)
            card.crest:SetColorTexture(unpack(crestColors[entry.stance] or crestColors.neutral))
            card.initials:SetText(R.Initials(row.name))
            card.stance:SetText((stances[entry.stance] or stances.neutral) .. (entry.ruled and (" · " .. L("votre règle")) or ""))
            local lines = {}
            if (row.grudges or 0) > 0 then
                lines[#lines + 1] = countForm(row.grudges, "%d membre vous doit quelque chose", "%d membres vous doivent quelque chose")
            end
            if (row.deaths or 0) + (row.aggressions or 0) > 0 then
                lines[#lines + 1] = L("%d morts · %d agressions"):format(row.deaths or 0, row.aggressions or 0)
            end
            if (row.kills or 0) > 0 then lines[#lines + 1] = L("Vaincue %d fois"):format(row.kills) end
            if (row.friends or 0) > 0 then lines[#lines + 1] = countForm(row.friends, "%d ami parmi eux", "%d amis parmi eux") end
            card.lines:SetText(table.concat(lines, "\n"))
            card:Show()
        else
            card:Hide()
        end
    end
    page.empty:SetText(#guilds == 0 and L("Aucune guilde ne pèse encore dans votre livre.") or "")
    page.all:SetText(#guilds > 0 and L("Tous les classements de guildes") or "")
end

-- The guild's active members (owner 25/11): who uses the addon, which version, connected or when
-- last heard, whether they share their fights. You first, then those connected, then the others.
local MEMBER_ROWS = 8
local function heardSince(at)
    local delta = math.max(0, GL.Now() - (tonumber(at) or 0))
    if delta < 3600 then return L("il y a %d min"):format(math.max(1, math.floor(delta / 60))) end
    if delta < 86400 then return L("il y a %d h"):format(math.floor(delta / 3600)) end
    return L("il y a %d j"):format(math.floor(delta / 86400))
end
local function buildMembers(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.offset = 0
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(540), 13, false, UI.theme.inkMuted)
    page.lead:SetHeight(30)
    local band = page:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT", X(26), -84)
    band:SetSize(S(540), 22)
    band:SetColorTexture(0.44, 0.28, 0.13, 0.18)
    page.columnName = Panels.Text(page, X(30), -88, S(300), 12, false, UI.theme.inkMuted)
    page.columnSeen = Panels.Text(page, X(416), -88, S(146), 12, false, UI.theme.inkMuted)
    page.columnSeen:SetJustifyH("RIGHT")
    page.rows = {}
    for i = 1, MEMBER_ROWS do
        local row = CreateFrame("Frame", nil, page)
        row:SetPoint("TOPLEFT", X(26), -108 - (i - 1) * 44)
        row:SetSize(S(540), 42)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
        row.name = Panels.Text(row, S(6), -4, S(330), 14, true)
        GL.Safe(row.name.SetWordWrap, row.name, false)
        row.meta = Panels.Text(row, S(6), -23, S(390), 11, false, UI.theme.inkMuted)
        GL.Safe(row.meta.SetWordWrap, row.meta, false)
        row.seen = Panels.Text(row, S(396), -12, S(142), 14, true)
        row.seen:SetJustifyH("RIGHT")
        page.rows[i] = row
    end
    -- Under your own line, which is always there (owner report 25/11: it was written over it).
    page.empty = Panels.Text(page, X(26), -164, S(540), 13, false, UI.theme.inkMuted)
    page.previous = UI.button(page, "‹", X(26), -464, S(40), function()
        page.offset = math.max(0, page.offset - MEMBER_ROWS)
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", X(526), -464, S(40), function()
        page.offset = page.offset + MEMBER_ROWS
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(76), -470, S(440), 12, false, UI.theme.inkMuted)
    page.count:SetJustifyH("CENTER")
    return page
end
local function paintMembers(page)
    page.title:SetText(L("Membres actifs"))
    local list = GL.GuildMap and GL.GuildMap.Members and GL.GuildMap.Members() or {}
    local current = 0
    for _, m in ipairs(list) do if m.current then current = current + 1 end end
    page.lead:SetText(#list > 0 and L("Les membres dont l’addon a parlé ces 60 derniers jours : %d à jour sur %d."):format(current, #list) or "")
    page.columnName:SetText(L("Membre"))
    page.columnSeen:SetText(L("Vu"))
    -- The first name heard for each player mark: alts say whose they are.
    local firstOfMark = {}
    for _, m in ipairs(list) do
        if m.mark and not firstOfMark[m.mark] then firstOfMark[m.mark] = m end
    end
    page.offset = math.min(page.offset, math.max(0, math.floor((#list - 1) / MEMBER_ROWS) * MEMBER_ROWS))
    for i, row in ipairs(page.rows) do
        local m = list[page.offset + i]
        if m then
            Panels.Fit(row.name, UI.plain(m.you and (m.name .. " · " .. L("Vous")) or m.name), S(330), 14, 10, true)
            local parts = {}
            if m.version then
                parts[#parts + 1] = (m.current and L("Version %s · à jour") or L("Version %s · ancienne version")):format(m.version)
            else
                parts[#parts + 1] = L("Version inconnue (avant la 0.58)")
            end
            if m.shares then parts[#parts + 1] = L("partage ses combats") end
            local main = m.mark and firstOfMark[m.mark]
            if main and main ~= m then parts[#parts + 1] = L("même joueur que %s"):format(UI.plain(main.name)) end
            Panels.Fit(row.meta, table.concat(parts, " · "), S(390), 11, 8)
            row.meta:SetTextColor(unpack(m.version and not m.current and UI.theme.red or UI.theme.inkMuted))
            row.seen:SetText(m.online and L("En ligne") or heardSince(m.at))
            row.seen:SetTextColor(unpack(m.online and { 0.18, 0.42, 0.20 } or UI.theme.ink))
            row:Show()
        else
            row:Hide()
        end
    end
    page.empty:SetText(#list <= 1 and L("Aucun autre membre n’a encore été entendu. Ils apparaissent dès que leur addon parle.") or "")
    page.previous:SetEnabled(page.offset > 0)
    page.next:SetEnabled(page.offset + MEMBER_ROWS < #list)
    page.count:SetText(#list > 0 and L("%d à %d sur %d"):format(page.offset + 1, math.min(page.offset + MEMBER_ROWS, #list), #list) or "")
end

-- Dangerous lands: where you die, zone by zone, and to whom. A list today, the world map later.
local LAND_ROWS = 8
-- Your deaths and victories, each fight once (owner report 25/11). A death is written in the sheet
-- of every attacker, under one event ID: counted once per attacker, three attackers made three
-- deaths in Tanaris for a single marker. Events without an ID stay separate. Each entry: the
-- event, the sheet it was found in, and every sheet of the same death ("records").
local function fights()
    local list, byId = {}, {}
    for _, record in pairs(players()) do
        for _, e in ipairs(record.history or {}) do
            if type(e) == "table" and not e.voided and e.voidReason ~= "battleground" and (e.kind == "death" or e.kind == "kill") then
                local id = e.kind == "death" and e.eventId ~= nil and tostring(e.eventId) or nil
                local known = id and byId[id]
                if known then
                    known.records[#known.records + 1] = record
                    -- The place is the one written down: any sheet of the death may carry it.
                    if type(known.event.mapX) ~= "number" and type(e.mapX) == "number" then known.event, known.record = e, record end
                else
                    local entry = { event = e, record = record, records = { record } }
                    list[#list + 1] = entry
                    if id then byId[id] = entry end
                end
            end
        end
    end
    return list
end
R.Fights = fights
function R.Lands()
    local zones, list = {}, {}
    for _, fight in ipairs(fights()) do
        local e = fight.event
        local zone = type(e.zone) == "string" and e.zone
        if zone and zone ~= "" and zone ~= "?" then
            local entry = zones[zone]
            if not entry then
                entry = { zone = zone, deaths = 0, kills = 0, killers = {} }
                zones[zone] = entry
                list[#list + 1] = entry
            end
            if e.kind == "death" then
                entry.deaths = entry.deaths + 1
                for _, record in ipairs(fight.records) do entry.killers[record] = (entry.killers[record] or 0) + 1 end
            else
                entry.kills = entry.kills + 1
            end
        end
    end
    table.sort(list, function(a, b)
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.zone < b.zone
    end)
    return list
end
local function killers(entry)
    local ranked = {}
    for record, times in pairs(entry.killers) do ranked[#ranked + 1] = { record = record, times = times } end
    table.sort(ranked, function(a, b)
        if a.times ~= b.times then return a.times > b.times end
        return a.record.key < b.record.key
    end)
    local parts = {}
    for i = 1, math.min(2, #ranked) do
        parts[i] = name(ranked[i].record) .. (ranked[i].times > 1 and (" ×" .. ranked[i].times) or "")
    end
    return table.concat(parts, ", ")
end
-- The map of dangerous lands, in this page only (never on the game's world map).
-- One canvas for the whole world, as OpenMap does (credited in CREDITS.txt; its code is not copied):
-- every picture is placed by its rectangle on the world map, so the wheel closes in from the
-- world to a zone without ever switching maps. Bottom to top, and when each one comes in:
--   world picture        always
--   continent pictures   as you close in, their frame feathered away by a mask
--   zone detail          the pieces of a zone you have explored, when the zone is wide enough
--   regions              the game's own shape of each zone, lit by your share of deaths there
--   fights               each one where it happened (kept since 0.45.0), once zones are readable
-- Everything comes from the game's own pictures: the addon ships one small mask and no map.
-- 555 by 370 (owner report 25/11): at 600 by 400 the line under the map fell on the worn bottom
-- edge of the page and could not be read. Page 510 high: title and counts 70, map 370, frame 5,
-- the line 12 + 26; the curl of the sheet starts about 32 units from its bottom.
local MAP_W, MAP_H = 555, 370
local MAP_POINTS = 40 -- fights drawn in one zone, the latest ones: more would be noise
local ZOOM_MAX = 40 -- times the whole world: a zone fills the view well before
local ZOOM_STEP = 1.3
local CONTINENT_IN = { 1.25, 2.1 } -- zoom where the continent pictures start and finish coming in
local DETAIL_IN = { 150, 260 } -- width of a zone on screen where its explored pieces come in
local ZONES_KEPT = 8 -- zones whose detail stays loaded at once
-- The marks of a fight, from the addon's one list of pictures (Art.lua).
local SKULL, SWORD = GL.Art.Death, GL.Art.Victory
local ARROW = "Interface\\Minimap\\MinimapArrow"
local FEATHER = "Interface\\AddOns\\GrudgeLedger\\Media\\MapFeather"
local fitHint -- below, with the map's caption
local function mapInfo(id)
    local info = id and C_Map and GL.Safe(C_Map.GetMapInfo, id)
    return type(info) == "table" and info or nil
end
local function playerPlace()
    if not C_Map then return nil end
    local id = GL.Clean(GL.Safe(C_Map.GetBestMapForUnit, "player"), "number")
    local position = id and GL.Safe(C_Map.GetPlayerMapPosition, id, "player")
    local x, y
    if type(position) == "table" and type(position.GetXY) == "function" then x, y = GL.Safe(position.GetXY, position) end
    return id, GL.Clean(x, "number"), GL.Clean(y, "number")
end
local function rectOn(child, parent)
    local left, right, top, bottom = GL.Safe(C_Map.GetMapRectOnMap, child, parent)
    if type(left) == "number" and type(right) == "number" and type(top) == "number" and type(bottom) == "number"
        and right > left and bottom > top then
        return { left = left, right = right, top = top, bottom = bottom }
    end
end
local function hasArt(id)
    local files = GL.Safe(C_Map.GetMapArtLayerTextures, id, 1)
    return type(files) == "table" and #files > 0
end
-- The map everything is drawn on: the world above where you stand, or its continent when the
-- client has no picture of the world.
local function rootOf(id)
    local continent
    for _ = 1, 6 do
        local info = mapInfo(id)
        if not info then break end
        if info.mapType == 1 and hasArt(id) then return id end
        if info.mapType == 2 and hasArt(id) then continent = continent or id end
        id = info.parentMapID
    end
    return continent
end
-- The game's own highlight of a zone on its continent: a texture, the part of it used, and its
-- rectangle on the continent. A point of the zone's land is looked for inside its rectangle.
local function zoneShape(continent, zone, rect)
    if type(C_Map.GetMapHighlightInfoAtPosition) ~= "function" then return nil end
    for row = 1, 5 do
        for column = 1, 5 do
            local x = rect.left + (rect.right - rect.left) * (column - 0.5) / 5
            local y = rect.top + (rect.bottom - rect.top) * (row - 0.5) / 5
            local under = GL.Safe(C_Map.GetMapInfoAtPosition, continent, x, y)
            if type(under) == "table" and under.mapID == zone then
                local ok, file, atlas, usedX, usedY, width, height, left, top = pcall(C_Map.GetMapHighlightInfoAtPosition, continent, x, y)
                file, atlas = GL.Clean(file), GL.Clean(atlas)
                width, height, left, top = GL.Clean(width, "number"), GL.Clean(height, "number"), GL.Clean(left, "number"), GL.Clean(top, "number")
                if ok and (atlas or type(file) == "number" and file > 0) and width and height and left and top and width > 0 and height > 0 then
                    return { file = file, atlas = atlas, usedX = GL.Clean(usedX, "number") or 1, usedY = GL.Clean(usedY, "number") or 1,
                        left = left, top = top, width = width, height = height }
                end
                return nil
            end
        end
    end
end
-- The zones drawn on a map, each with its place on it: the zones of a continent, or on the world
-- the zones of every continent, moved through the continent's own rectangle. Shapes never change,
-- so they are worked out once a map.
local function zonesOf(id, cache)
    if cache[id] then return cache[id] end
    local zones = {}
    local info = mapInfo(id)
    local function add(continent, into)
        local children = GL.Safe(C_Map.GetMapChildrenInfo, continent, 3)
        for _, child in ipairs(type(children) == "table" and children or {}) do
            local rect = rectOn(child.mapID, continent)
            if rect then
                local shape = zoneShape(continent, child.mapID, rect)
                local zone = { mapID = child.mapID, name = child.name, rect = rect, shape = shape, continent = continent }
                if into then
                    local w, h = into.right - into.left, into.bottom - into.top
                    zone.rect = { left = into.left + rect.left * w, right = into.left + rect.right * w,
                        top = into.top + rect.top * h, bottom = into.top + rect.bottom * h }
                    if shape then
                        zone.shape = { file = shape.file, atlas = shape.atlas, usedX = shape.usedX, usedY = shape.usedY,
                            left = into.left + shape.left * w, top = into.top + shape.top * h, width = shape.width * w, height = shape.height * h }
                    end
                end
                zones[#zones + 1] = zone
            end
        end
    end
    if info and info.mapType == 2 then
        add(id)
    elseif info and info.mapType ~= 3 then
        local continents = GL.Safe(C_Map.GetMapChildrenInfo, id, 2)
        for _, continent in ipairs(type(continents) == "table" and continents or {}) do
            local rect = rectOn(continent.mapID, id)
            if rect then add(continent.mapID, rect) end
        end
    end
    cache[id] = zones
    return zones
end
local function tip(owner, title, line)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
    GameTooltip:Show()
end
local function hideTip()
    if GameTooltip then GameTooltip:Hide() end
end
local function marker(view, pool, i)
    local button = pool[i]
    if not button then
        button = CreateFrame("Button", nil, view.canvas)
        button.fill = button:CreateTexture(nil, "ARTWORK")
        button.fill:SetAllPoints()
        button.count = Panels.Text(button, 0, 0, 40, 12, true, UI.theme.paper)
        button.count:ClearAllPoints()
        button.count:SetPoint("CENTER")
        button.count:SetJustifyH("CENTER")
        button:SetScript("OnLeave", hideTip)
        pool[i] = button
    end
    return button
end
local function mapView()
    return R.window and R.window.host.pages.lands.map
end
local function between(value, range)
    return math.max(0, math.min(1, (value - range[1]) / (range[2] - range[1])))
end
-- Where a point of the world (0 to 1) falls in the view, in pixels from its top left corner.
local function place(view, u, v)
    return (u - view.cx) * view.width * view.zoom + view.width / 2, (v - view.cy) * view.height * view.zoom + view.height / 2
end
local function clampCentre(view)
    local half = 0.5 / view.zoom
    view.cx = math.max(half, math.min(1 - half, view.cx))
    view.cy = math.max(half, math.min(1 - half, view.cy))
end
-- The pointer on the world (0 to 1), or nil when the client does not say where the view is.
local function pointer(view)
    local cx, cy = GL.Safe(GetCursorPosition)
    local scale = GL.Safe(view.canvas.GetEffectiveScale, view.canvas)
    local left, top = GL.Safe(view.canvas.GetLeft, view.canvas), GL.Safe(view.canvas.GetTop, view.canvas)
    if not (type(cx) == "number" and type(cy) == "number" and type(scale) == "number" and scale > 0 and type(left) == "number"
        and type(top) == "number") then return nil end
    local px, py = cx / scale - left, top - cy / scale
    return (px - view.width / 2) / (view.width * view.zoom) + view.cx, (py - view.height / 2) / (view.height * view.zoom) + view.cy, px, py
end
-- A map's picture, from the game's own pieces, to be placed on a rectangle of the world.
local function loadArt(view, id, rect, level, feathered)
    local layers = GL.Safe(C_Map.GetMapArtLayers, id)
    local layer = type(layers) == "table" and layers[1]
    local files = GL.Safe(C_Map.GetMapArtLayerTextures, id, 1)
    if type(layer) ~= "table" or type(files) ~= "table" or #files == 0 then return nil end
    local art = { rect = rect, textures = {}, count = #files, width = tonumber(layer.layerWidth) or 1002,
        height = tonumber(layer.layerHeight) or 668, tile = tonumber(layer.tileWidth) or 256 }
    art.columns = math.max(1, math.ceil(art.width / art.tile))
    -- The frame of a continent's picture would show as a rectangle on the world: a soft mask hides it.
    if feathered and type(view.canvas.CreateMaskTexture) == "function" then
        local ok, mask = pcall(view.canvas.CreateMaskTexture, view.canvas)
        if ok and mask then
            GL.Safe(mask.SetTexture, mask, FEATHER, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            art.mask = mask
        end
    end
    for i = 1, #files do
        local piece = view.canvas:CreateTexture(nil, "BACKGROUND", nil, level)
        piece:SetTexture(files[i])
        -- The last column and the last row are cut where the picture ends.
        local column, row = (i - 1) % art.columns, math.floor((i - 1) / art.columns)
        piece.fx = math.min(1, (art.width - column * art.tile) / art.tile)
        piece.fy = math.min(1, (art.height - row * art.tile) / art.tile)
        piece:SetTexCoord(0, piece.fx, 0, piece.fy)
        if art.mask then GL.Safe(piece.AddMaskTexture, piece, art.mask) end
        art.textures[i] = piece
    end
    return art
end
local function placeArt(view, art, alpha, shade)
    if alpha <= 0 then
        if not art.hidden then
            for _, piece in ipairs(art.textures) do piece:Hide() end
            art.hidden = true
        end
        return
    end
    local rect = art.rect
    local sx, sy = (rect.right - rect.left) * view.width * view.zoom, (rect.bottom - rect.top) * view.height * view.zoom
    local w, h = art.tile / art.width * sx, art.tile / art.height * sy
    local x0, y0 = place(view, rect.left, rect.top)
    for i, piece in ipairs(art.textures) do
        piece:ClearAllPoints()
        piece:SetPoint("TOPLEFT", view.canvas, "TOPLEFT", x0 + ((i - 1) % art.columns) * w, -(y0 + math.floor((i - 1) / art.columns) * h))
        piece:SetSize(w * piece.fx, h * piece.fy)
        piece:SetAlpha(alpha)
        if piece.shade ~= shade then
            piece.shade = shade
            piece:SetVertexColor(shade or 1, shade or 1, shade or 1)
        end
        piece:Show()
    end
    art.hidden = nil
    if art.mask then
        art.mask:ClearAllPoints()
        art.mask:SetPoint("TOPLEFT", view.canvas, "TOPLEFT", x0, -y0)
        art.mask:SetSize(sx, sy)
    end
end
-- The world drawn in the view: its picture, its continents with theirs, and every zone.
local function buildWorld(view, root)
    local art = loadArt(view, root, { left = 0, right = 1, top = 0, bottom = 1 }, 0)
    if not art then return nil end
    local world = { root = root, art = art, continents = {}, rects = {}, zones = zonesOf(root, view.cache) }
    local children = GL.Safe(C_Map.GetMapChildrenInfo, root, 2)
    for _, continent in ipairs(type(children) == "table" and children or {}) do
        local rect = rectOn(continent.mapID, root)
        if rect then
            world.rects[continent.mapID] = rect
            world.continents[#world.continents + 1] = { mapID = continent.mapID, name = continent.name, rect = rect,
                art = loadArt(view, continent.mapID, rect, 1, true) }
        end
    end
    local total = 0
    for _, zone in ipairs(world.zones) do
        world.rects[zone.mapID] = zone.rect
        total = total + (zone.rect.right - zone.rect.left)
    end
    world.zoneWidth = #world.zones > 0 and total / #world.zones or 0.25
    return world
end
local function powerOfTwo(n)
    local p = 16
    while p < n do p = p * 2 end
    return p
end
-- The pieces of a zone the player has explored, each with its place on the world. The game gives
-- them cut the way its own map lays them: pieces of 256, the last of a row or a column smaller.
local function detailOf(view, zone)
    local known = view.detail[zone.mapID]
    if known then return known end
    local tiles = {}
    local explored = C_MapExplorationInfo and GL.Safe(C_MapExplorationInfo.GetExploredMapTextures, zone.mapID)
    local layers = GL.Safe(C_Map.GetMapArtLayers, zone.mapID)
    local layer = type(layers) == "table" and layers[1]
    local zw, zh = tonumber(type(layer) == "table" and layer.layerWidth) or 1002, tonumber(type(layer) == "table" and layer.layerHeight) or 668
    local rect = zone.rect
    local rw, rh = rect.right - rect.left, rect.bottom - rect.top
    -- First the zone's own map, at its resolution, as the game draws it before the explored pieces:
    -- without it, what you never explored showed the continent's picture blown up into big blurred
    -- squares (owner report 25/11, Burning Steppes, Ironforge).
    local base = GL.Safe(C_Map.GetMapArtLayerTextures, zone.mapID, 1)
    local tile = tonumber(type(layer) == "table" and layer.tileWidth) or 256
    local columns = math.max(1, math.ceil(zw / tile))
    for i, file in ipairs(type(base) == "table" and base or {}) do
        local column, row = (i - 1) % columns, math.floor((i - 1) / columns)
        local pw, ph = math.min(tile, zw - column * tile), math.min(tile, zh - row * tile)
        if pw > 0 and ph > 0 and #tiles < 160 then
            tiles[#tiles + 1] = { file = file, base = true, u = rect.left + column * tile / zw * rw, v = rect.top + row * tile / zh * rh,
                w = pw / zw * rw, h = ph / zh * rh, tx = pw / tile, ty = ph / tile }
        end
    end
    for _, info in ipairs(type(explored) == "table" and explored or {}) do
        local tw, th = tonumber(info.textureWidth), tonumber(info.textureHeight)
        local ox, oy, files = tonumber(info.offsetX), tonumber(info.offsetY), info.fileDataIDs
        if tw and th and ox and oy and tw > 0 and th > 0 and type(files) == "table" and not info.isShownByMouseOver then
            local wide, tall = math.ceil(tw / 256), math.ceil(th / 256)
            for j = 1, tall do
                local ph = (j < tall or th % 256 == 0) and 256 or th % 256
                local fh = j < tall and 256 or powerOfTwo(ph)
                for k = 1, wide do
                    local pw = (k < wide or tw % 256 == 0) and 256 or tw % 256
                    local fw = k < wide and 256 or powerOfTwo(pw)
                    local file = files[(j - 1) * wide + k]
                    if file and #tiles < 160 then
                        tiles[#tiles + 1] = { file = file, u = rect.left + (ox + 256 * (k - 1)) / zw * rw, v = rect.top + (oy + 256 * (j - 1)) / zh * rh,
                            w = pw / zw * rw, h = ph / zh * rh, tx = pw / fw, ty = ph / fh }
                    end
                end
            end
        end
    end
    view.detail[zone.mapID] = tiles
    return tiles
end
local function dropDetail(view, id)
    local live = view.live[id]
    if not live then return end
    for _, texture in ipairs(live.textures) do
        texture:Hide()
        view.spare[#view.spare + 1] = texture
    end
    view.live[id] = nil
end
local function showDetail(view, zone, alpha)
    local live = view.live[zone.mapID]
    if not live then
        local tiles = detailOf(view, zone)
        if #tiles == 0 then return end
        -- Only a few zones keep their detail: the one looked at longest ago gives its textures back.
        local kept, oldestID, oldest = 0, nil, nil
        for id, other in pairs(view.live) do
            kept = kept + 1
            if not oldest or other.stamp < oldest.stamp then oldestID, oldest = id, other end
        end
        if kept >= ZONES_KEPT and oldest.stamp < view.stamp then dropDetail(view, oldestID) end
        live = { textures = {}, tiles = tiles }
        for i, tile in ipairs(tiles) do
            local texture = table.remove(view.spare) or view.canvas:CreateTexture(nil, "BORDER")
            texture:SetTexture(tile.file)
            texture:SetTexCoord(0, tile.tx, 0, tile.ty)
            -- The zone's map under its explored pieces, never over them.
            GL.Safe(texture.SetDrawLayer, texture, "BORDER", tile.base and -1 or 1)
            live.textures[i] = texture
        end
        view.live[zone.mapID] = live
    end
    live.stamp = view.stamp
    local sx, sy = view.width * view.zoom, view.height * view.zoom
    for i, tile in ipairs(live.tiles) do
        local texture = live.textures[i]
        local x, y = place(view, tile.u, tile.v)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", view.canvas, "TOPLEFT", x, -y)
        texture:SetSize(tile.w * sx, tile.h * sy)
        texture:SetAlpha(alpha)
        texture:Show()
    end
end
-- Where you stand, on the world.
local function locate(view)
    local mine, x, y = playerPlace()
    view.here = nil
    if not (x and y and view.world) then return end
    if mine == view.root then
        view.here = { x = x, y = y }
        return
    end
    local rect = view.world.rects[mine]
    if rect then view.here = { x = rect.left + x * (rect.right - rect.left), y = rect.top + y * (rect.bottom - rect.top), zone = mine } end
end
-- What the view is looking at: the zone under its centre once zones are readable, else the
-- continent, else the world. Counts follow.
local function bars(text)
    return (tostring(text or ""):gsub(" · ", "   |cffa07b44|||r   "))
end
-- The line under the map: "Ma position" (after "Monde" once you zoomed in), then how to move and
-- the counts, at a size that reads (owner report 25/11: shrunk to fit, it could not be read).
-- Without room for all of it, the counts alone.
fitHint = function(view)
    if not view.hintFull then return end
    local out = view.out:IsShown()
    view.mine:ClearAllPoints()
    view.mine:SetPoint("TOPLEFT", view.canvas, "BOTTOMLEFT", out and 92 or 0, -12)
    local room = (view.width or MAP_W) - (out and 222 or 130)
    view.hint:SetWidth(room)
    local font = GL.Safe(view.hint.GetFont, view.hint)
    if font then GL.Safe(view.hint.SetFont, view.hint, font, 12) end
    view.hint:SetText(view.hintFull)
    local wide = tonumber(GL.Safe(view.hint.GetStringWidth, view.hint)) or 0
    if wide > room then view.hint:SetText(view.hintShort) end
    view.hint:SetTextColor(unpack(UI.theme.ink))
end
local function describe(view)
    local world, best, distance = view.world, nil, nil
    for _, zone in ipairs(world.zones) do
        local rect = zone.rect
        if view.cx >= rect.left and view.cx <= rect.right and view.cy >= rect.top and view.cy <= rect.bottom
            and (rect.right - rect.left) * view.width * view.zoom >= 220 then
            local d = math.abs((rect.left + rect.right) / 2 - view.cx) + math.abs((rect.top + rect.bottom) / 2 - view.cy)
            if not best or d < distance then best, distance = zone, d end
        end
    end
    local title, deaths, kills, inside = nil, 0, 0, nil
    if best then
        local entry = view.tallyOf and view.tallyOf[best.mapID]
        return best.name, entry and entry.deaths or 0, entry and entry.kills or 0
    end
    if view.zoom >= CONTINENT_IN[2] then
        for _, continent in ipairs(world.continents) do
            local rect = continent.rect
            if view.cx >= rect.left and view.cx <= rect.right and view.cy >= rect.top and view.cy <= rect.bottom then
                title, inside = continent.name, continent.mapID
            end
        end
    end
    for _, entry in ipairs(view.tallies or {}) do
        if not inside or entry.zone.continent == inside then deaths, kills = deaths + entry.deaths, kills + entry.kills end
    end
    local info = mapInfo(world.root)
    return title or (info and info.name) or "", deaths, kills
end
local function buildMap(page)
    local view = CreateFrame("Frame", nil, page)
    view:SetPoint("TOPLEFT", X(26), -70)
    view:SetSize(S(540), 440)
    view.canvas = CreateFrame("Frame", nil, view)
    view.canvas:SetPoint("TOP", view, "TOP", 0, 0)
    view.canvas:SetSize(MAP_W, MAP_H)
    GL.Safe(view.canvas.SetClipsChildren, view.canvas, true)
    view.regions, view.labels, view.points, view.cache = {}, {}, {}, {}
    view.worlds, view.detail, view.live, view.spare, view.stamp = {}, {}, {}, {}, 0
    view.zoom, view.cx, view.cy = 1, 0.5, 0.5
    -- You: the arrow of the minimap, turned the way you face, above everything on the map.
    view.me = CreateFrame("Frame", nil, view.canvas)
    view.me:SetSize(30, 30)
    GL.Safe(view.me.SetFrameLevel, view.me, (GL.Safe(view.canvas.GetFrameLevel, view.canvas) or 1) + 6)
    view.dot = view.me:CreateTexture(nil, "OVERLAY")
    view.dot:SetAllPoints()
    view.dot:SetTexture(ARROW)
    GL.Safe(view.canvas.EnableMouseWheel, view.canvas, true)
    GL.Safe(view.canvas.EnableMouse, view.canvas, true)
    view.canvas:SetScript("OnMouseWheel", function(_, delta) R.MapWheel(delta) end)
    -- Hold the left button and move: the map follows the pointer.
    view.canvas:SetScript("OnMouseDown", function()
        local _, _, px, py = pointer(view)
        view.goal = nil
        view.drag = px and { px = px, py = py, cx = view.cx, cy = view.cy } or nil
    end)
    view.canvas:SetScript("OnMouseUp", function() view.drag = nil end)
    view.canvas:SetScript("OnHide", function() view.drag, view.goal = nil, nil end)
    view.canvas:SetScript("OnUpdate", function(_, elapsed)
        local drag = view.drag
        if drag then
            local _, _, px, py = pointer(view)
            if px then
                view.cx = drag.cx - (px - drag.px) / (view.width * view.zoom)
                view.cy = drag.cy - (py - drag.py) / (view.height * view.zoom)
                R.MapLayout()
            end
        elseif view.goal then
            R.MapStep(elapsed)
        end
        -- You move: the arrow follows, a few times a second.
        view.since = (view.since or 0) + (tonumber(elapsed) or 0)
        if view.since >= 0.3 and view.world and not view.drag and not view.goal then
            view.since = 0
            locate(view)
            R.MapLayout()
        end
    end)
    -- A brass frame around the map (the owner's kit, 25/11), its line just outside the map's edge so
    -- that the map stops where the frame starts; the leaves of the corners reach in a little. Four
    -- corners at their own size and four straight edges that stretch (tools/slice_map_frame.py):
    -- stretched whole, the corners took the map's shape (owner report). It takes no click.
    local frame = CreateFrame("Frame", nil, view)
    view.frame = frame
    frame:SetPoint("TOPLEFT", view.canvas, "TOPLEFT", -5.5, 7.5)
    frame:SetPoint("BOTTOMRIGHT", view.canvas, "BOTTOMRIGHT", 6, -5)
    GL.Safe(frame.SetFrameLevel, frame, (GL.Safe(view.canvas.GetFrameLevel, view.canvas) or 1) + 10)
    frame.pieces = {}
    local function piece(name, layer)
        local t = frame:CreateTexture(nil, "OVERLAY", nil, layer)
        t:SetTexture(GL.Art.MapFrame .. (name:gsub("^cadre%-", "")))
        frame.pieces[name] = t
        return t
    end
    local top, bottom = piece("cadre-haut", 0), piece("cadre-bas", 0)
    top:SetPoint("TOPLEFT", 63, 0)
    top:SetPoint("TOPRIGHT", -63, 0)
    top:SetHeight(16)
    bottom:SetPoint("BOTTOMLEFT", 63, 0)
    bottom:SetPoint("BOTTOMRIGHT", -63, 0)
    bottom:SetHeight(16)
    local left, right = piece("cadre-gauche", 0), piece("cadre-droite", 0)
    left:SetPoint("TOPLEFT", 0, -63)
    left:SetPoint("BOTTOMLEFT", 0, 63)
    left:SetWidth(16)
    right:SetPoint("TOPRIGHT", 0, -63)
    right:SetPoint("BOTTOMRIGHT", 0, 63)
    right:SetWidth(16)
    for name, at in pairs({ ["cadre-hg"] = { "TOPLEFT", -1, 1 }, ["cadre-hd"] = { "TOPRIGHT", 1, 1 },
        ["cadre-bg"] = { "BOTTOMLEFT", -1, -1 }, ["cadre-bd"] = { "BOTTOMRIGHT", 1, -1 } }) do
        local corner = piece(name, 1)
        corner:SetSize(64, 64)
        corner:SetPoint(at[1], at[2], at[3])
    end
    -- Under the map, one line (owner's mockup, 25/11): the buttons, then how to move and the count.
    view.out = UI.button(view, L("Monde"), 0, 0, 84, function() R.MapOut() end, nil, true)
    view.mine = UI.button(view, L("Ma position"), 0, 0, 118, function() R.MapHere() end, nil, true)
    view.out:ClearAllPoints()
    view.out:SetPoint("TOPLEFT", view.canvas, "BOTTOMLEFT", 0, -12)
    view.mine:ClearAllPoints()
    view.mine:SetPoint("TOPLEFT", view.canvas, "BOTTOMLEFT", 0, -12)
    -- Where you look and its counts, under the page's title, as in the owner's mockup (25/11).
    view.caption = Panels.Text(view, 0, 20, S(540), 13, true)
    GL.Safe(view.caption.SetWordWrap, view.caption, false)
    view.hint = Panels.Text(view, 0, 0, MAP_W - 220, 12, true)
    view.hint:ClearAllPoints()
    view.hint:SetPoint("TOPRIGHT", view.canvas, "BOTTOMRIGHT", 0, -17)
    view.hint:SetJustifyH("RIGHT")
    GL.Safe(view.hint.SetWordWrap, view.hint, false)
    return view
end
-- The fights that kept their position, placed on this map: its own, or those of the zones it
-- shows, moved through each zone's rectangle. The latest first.
-- What the map counts and what it draws come from one pass (owner report 25/11): the counts were
-- read by zone name and the marks by map, the counts had each death once per attacker, the marks
-- had the "coups de main" the counts left out, and only the latest 80 fights of the whole world
-- were drawn. Now a fight belongs to the zone of its map, or, when it kept no place, to the zone
-- of its name; it is counted there, and drawn there when it kept its place. Each zone draws its
-- latest MAP_POINTS. The guild's fights (guild vision) are counted and drawn the same way.
-- Returns the zones fought in (list and by map) and the marks, yours then the guild's.
function R.MapTally(id, zones, guild)
    local byMap, byName, where = {}, {}, { [id] = false }
    for _, zone in ipairs(zones or {}) do
        byMap[zone.mapID], where[zone.mapID] = zone, zone.rect
        if type(zone.name) == "string" and byName[zone.name] == nil then byName[zone.name] = zone end
    end
    local tallies, tallyOf, drawn = {}, {}, {}
    local function count(zone, kind)
        local tally = tallyOf[zone.mapID]
        if not tally then
            tally = { zone = zone, deaths = 0, kills = 0, unplaced = 0 }
            tallyOf[zone.mapID] = tally
            tallies[#tallies + 1] = tally
        end
        if kind == "death" then tally.deaths = tally.deaths + 1 else tally.kills = tally.kills + 1 end
    end
    local function place(list, key, rect, x, y, mark)
        if rect then x, y = rect.left + x * (rect.right - rect.left), rect.top + y * (rect.bottom - rect.top) end
        mark.x, mark.y, mark.key = x, y, key
        list[#list + 1] = mark
    end
    local own, others = {}, {}
    for _, fight in ipairs(fights()) do
        local e = fight.event
        local placed = type(e.mapX) == "number" and type(e.mapY) == "number" and type(e.time) == "number"
        local zone = byMap[e.mapID] or (type(e.zone) == "string" and byName[e.zone]) or nil
        if zone then count(zone, e.kind) end
        -- Counted without a mark: said in the zone's tooltip (owner report 25/11, Rive-Claire).
        if zone and not (placed and byMap[e.mapID]) then tallyOf[zone.mapID].unplaced = tallyOf[zone.mapID].unplaced + 1 end
        if placed and where[e.mapID] ~= nil then
            place(own, e.mapID, where[e.mapID], e.mapX, e.mapY, { record = fight.record, event = e })
        end
    end
    for _, point in ipairs(guild or {}) do
        local zone = byMap[point.mapID]
        if zone and type(point.x) == "number" and type(point.y) == "number" then
            count(zone, point.kind)
            place(others, point.mapID, zone.rect, point.x, point.y,
                { guild = point.actor, enemy = point.name, event = { kind = point.kind, time = point.time } })
        end
    end
    -- The latest first, then MAP_POINTS a zone at most.
    local function trim(list)
        table.sort(list, function(a, b) return (a.event.time or 0) > (b.event.time or 0) end)
        local per, kept = {}, {}
        for _, mark in ipairs(list) do
            per[mark.key] = (per[mark.key] or 0) + 1
            if per[mark.key] <= MAP_POINTS then kept[#kept + 1] = mark end
        end
        return kept
    end
    return tallies, tallyOf, trim(own), trim(others)
end
-- From -1 (four deaths or more for a victory: deep red) to 1 (four victories or more for a death:
-- strong green), 0 when even (the map's own colour). The owner's rule, 25/11.
function R.ZoneBalance(kills, deaths)
    kills, deaths = math.max(0, tonumber(kills) or 0), math.max(0, tonumber(deaths) or 0)
    local ratio = (kills > 0 and deaths > 0) and kills / deaths or (kills + 1) / (deaths + 1)
    return math.max(-1, math.min(1, math.log(ratio) / math.log(4)))
end
function R.MapPoints(id, zones)
    local _, _, points = R.MapTally(id, zones)
    return points
end
-- Re-places everything for the current zoom and centre. Cheap: a few dozen regions at most.
function R.MapLayout()
    local view = mapView()
    local world = view and view.world
    if not world or not view.width then return end
    clampCentre(view)
    local zoom, canvas = view.zoom, view.canvas
    view.stamp = view.stamp + 1
    -- A light added to a bright map hardly shows (owner report, 0.48.0: no zone looked red). While
    -- the regions speak, the map under them is dimmed, so a lit zone stands out; closing in on a
    -- zone gives the map its full colours back.
    local mute = view.shapes and #view.shapes > 0 and 1 - between(world.zoneWidth * view.width * zoom, DETAIL_IN) or 0
    local shade = 1 - 0.6 * mute
    placeArt(view, world.art, 1, shade)
    local continentAlpha = between(zoom, CONTINENT_IN)
    local half = 0.5 / zoom
    local left, right, top, bottom = view.cx - half, view.cx + half, view.cy - half, view.cy + half
    for _, continent in ipairs(world.continents) do
        local rect = continent.rect
        local seen = rect.right > left and rect.left < right and rect.bottom > top and rect.top < bottom
        if continent.art then placeArt(view, continent.art, seen and continentAlpha or 0, shade) end
    end
    -- The detail of the zones in sight, once they are wide enough on screen.
    for _, zone in ipairs(world.zones) do
        local rect = zone.rect
        local alpha = between((rect.right - rect.left) * view.width * zoom, DETAIL_IN)
        if alpha > 0 and rect.right > left and rect.left < right and rect.bottom > top and rect.top < bottom then
            showDetail(view, zone, alpha)
        end
    end
    for _, live in pairs(view.live) do
        if live.stamp ~= view.stamp then
            for _, texture in ipairs(live.textures) do texture:Hide() end
        end
    end
    -- Regions say where; they fade as a zone grows on screen, and the fights take over.
    local showPoints = zoom >= view.pointZoom
    for i, region in ipairs(view.regions) do
        local entry = view.shapes and view.shapes[i]
        if entry and region:IsShown() then
            local shape = entry.zone.shape
            local x, y = place(view, shape.left, shape.top)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
            region:SetSize(shape.width * view.width * zoom, shape.height * view.height * zoom)
            local wide = (entry.zone.rect.right - entry.zone.rect.left) * view.width * zoom
            local alpha = entry.alpha * (0.2 + 0.8 * (1 - between(wide, DETAIL_IN)))
            region:SetAlpha(alpha)
            -- A second light over the deadliest zones: added light is faint on parchment, and the
            -- owner wanted them to stand out (0.51.0).
            local boost = region.boost
            if boost and boost:IsShown() then
                boost:ClearAllPoints()
                boost:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
                boost:SetSize(shape.width * view.width * zoom, shape.height * view.height * zoom)
                boost:SetAlpha(alpha * entry.boost)
            end
        end
    end
    for i, label in ipairs(view.labels) do
        local entry = view.tallies and view.tallies[i]
        if entry and label.used then
            local rect = entry.zone.rect
            local x, y = place(view, (rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2)
            label:ClearAllPoints()
            label:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
            if zoom >= view.pointZoom * 1.7 then label:Hide() else label:Show() end
        end
    end
    for i, point in ipairs(view.points) do
        local entry = view.placed and view.placed[i]
        if entry and point.used then
            local x, y = place(view, entry.x, entry.y)
            point:ClearAllPoints()
            point:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
            if showPoints then point:Show() else point:Hide() end
        end
    end
    if view.here then
        local x, y = place(view, view.here.x, view.here.y)
        view.me:ClearAllPoints()
        view.me:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
        local facing = GL.Clean(GL.Safe(GetPlayerFacing), "number")
        if facing then GL.Safe(view.dot.SetRotation, view.dot, facing) end
        view.me:Show()
        view.mine:Show()
    else
        view.me:Hide()
        view.mine:Hide()
    end
    if zoom > 1.02 then view.out:Show() else view.out:Hide() end
    fitHint(view)
    local title, deaths, kills = describe(view)
    view.caption:SetText(bars(UI.plain(title) .. " · " .. L("%d morts · %d victoires"):format(deaths, kills)))
end
local function paintMap(view, byName)
    local mine = playerPlace()
    local root = rootOf(mine) or view.root
    if not root then return false end
    local world = view.worlds[root]
    if not world then
        world = buildWorld(view, root)
        if not world then return false end
        view.worlds[root] = world
    end
    if view.root ~= root then
        -- Another world (rare: another family of continents): the previous pictures step aside.
        if view.world then
            placeArt(view, view.world.art, 0)
            for _, continent in ipairs(view.world.continents) do
                if continent.art then placeArt(view, continent.art, 0) end
            end
        end
        for id in pairs(view.live) do dropDetail(view, id) end
        view.root, view.world, view.detail = root, world, {}
        local scale = math.min(MAP_W / world.art.width, MAP_H / world.art.height)
        view.width, view.height = world.art.width * scale, world.art.height * scale
        view.canvas:SetSize(view.width, view.height)
        -- It opens on your continent, whole.
        view.zoom, view.cx, view.cy, view.goal = 1, 0.5, 0.5, nil
        local rect
        for _, continent in ipairs(world.continents) do
            if continent.mapID == mine then rect = continent.rect end
        end
        for _, zone in ipairs(world.zones) do
            if zone.mapID == mine then rect = world.rects[zone.continent] end
        end
        if rect then
            view.zoom = math.max(1, math.min(ZOOM_MAX, 1 / math.max(rect.right - rect.left, rect.bottom - rect.top)))
            view.cx, view.cy = (rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2
        end
    end
    -- What you have explored may have grown since the last visit of the page.
    view.detail = {}
    local zones = world.zones
    view.byName = byName
    -- Fights show once an ordinary zone is about a hundred pixels wide.
    view.pointZoom = math.max(1.4, 110 / math.max(1, world.zoneWidth * view.width))
    -- Every zone you fought in, tinted by the ratio of your victories to your deaths (below).
    -- Guild vision: the fights of the members who share theirs are counted and drawn with yours.
    local tallies, tallyOf, ownPlaced, guildPlaced = R.MapTally(root, zones, view.guildOn and GL.GuildMap and GL.GuildMap.Points() or nil)
    local shapes = {}
    view.tallyOf = tallyOf
    for _, region in ipairs(view.regions) do
        region:Hide()
        if region.boost then region.boost:Hide() end
    end
    for _, label in ipairs(view.labels) do
        label.used = nil
        label:Hide()
    end
    for i, entry in ipairs(tallies) do
        -- The owner's rule (25/11): the colour says the ratio of victories to deaths. Even, the map
        -- keeps its own colour; four times more on one side, the colour is full, deep red or strong
        -- green; in between it grows with the ratio (on a log scale, so 2 to 1 is half way).
        -- A side with nothing counts one more, so three victories without a death are full green.
        local kills, deaths = entry.kills, entry.deaths
        local balance = R.ZoneBalance(kills, deaths)
        entry.balance, entry.losing = balance, balance < 0
        if entry.zone.shape then
            local n = #shapes + 1
            local region = view.regions[n] or view.canvas:CreateTexture(nil, "ARTWORK")
            view.regions[n] = region
            local shape = entry.zone.shape
            if shape.atlas and region.SetAtlas then region:SetAtlas(shape.atlas) else region:SetTexture(shape.file) end
            region:SetTexCoord(0, shape.usedX, 0, shape.usedY)
            -- The game lights a zone by adding this texture to the map: its dark surroundings add
            -- nothing. Drawn any other way they showed as black squares (owner report, 0.47.0).
            GL.Safe(region.SetDesaturated, region, true)
            GL.Safe(region.SetBlendMode, region, "ADD")
            -- Green is added to a map already green and brown: it needs a brighter tint than red to read
            -- as clearly (owner report 25/11, a zone won 3 to 0 looked barely lit).
            if entry.losing then
                region:SetVertexColor(1, 0.06, 0.03)
            else
                region:SetVertexColor(0.30, 1, 0.22)
            end
            region:Show()
            -- A second light makes the colour deep, red or green alike: added light is faint on the map
            -- (0.51.0; green too since the owner's report of 25/11).
            local boost = region.boost or view.canvas:CreateTexture(nil, "ARTWORK")
            region.boost = boost
            if balance ~= 0 then
                if shape.atlas and boost.SetAtlas then boost:SetAtlas(shape.atlas) else boost:SetTexture(shape.file) end
                boost:SetTexCoord(0, shape.usedX, 0, shape.usedY)
                GL.Safe(boost.SetDesaturated, boost, true)
                GL.Safe(boost.SetBlendMode, boost, "ADD")
                if entry.losing then boost:SetVertexColor(1, 0.04, 0.02) else boost:SetVertexColor(0.22, 0.95, 0.16) end
                boost:Show()
            else
                boost:Hide()
            end
            shapes[n] = { zone = entry.zone, alpha = math.abs(balance), boost = math.abs(balance) }
        end
        local label = marker(view, view.labels, i)
        label.used = true
        label:SetSize(30, 34)
        -- The ratio as a small fraction (owner, 25/11): your victories in green above a thin rule,
        -- your deaths in red below, outlined so they read on any part of the map.
        label.fill:SetColorTexture(0, 0, 0, 0)
        if not label.fraction then
            label.fraction = true
            label.count:SetText("")
            local function number(y)
                local text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                local font = GL.Safe(label.count.GetFont, label.count)
                if font then GL.Safe(text.SetFont, text, font, 12, "OUTLINE") end
                text:SetPoint("CENTER", 0, y)
                text:SetJustifyH("CENTER")
                return text
            end
            label.kills, label.deaths = number(8), number(-8)
            label.kills:SetTextColor(0.35, 1, 0.4)
            label.deaths:SetTextColor(1, 0.3, 0.22)
            label.shade = label:CreateTexture(nil, "ARTWORK")
            label.shade:SetSize(18, 3)
            label.shade:SetPoint("CENTER", 0, 0)
            label.shade:SetColorTexture(0, 0, 0, 0.55)
            label.rule = label:CreateTexture(nil, "OVERLAY")
            label.rule:SetSize(16, 1)
            label.rule:SetPoint("CENTER", 0, 0)
            label.rule:SetColorTexture(0.96, 0.86, 0.62, 0.95)
        end
        label.kills:SetText(tostring(kills))
        label.deaths:SetText(tostring(deaths))
        label.zone = entry.zone.mapID
        label:SetScript("OnEnter", function(self)
            local line = L("%d morts · %d victoires"):format(entry.deaths, entry.kills)
            if (entry.unplaced or 0) > 0 then
                local hidden = L("Dont %d sans position : un combat d’avant la carte (0.45.0), ou dont le jeu cachait l’endroit.")
                line = line .. "\n" .. hidden:format(entry.unplaced)
            end
            tip(self, UI.plain(entry.zone.name), line)
        end)
        label:SetScript("OnClick", function(self) R.MapFocus(self.zone) end)
    end
    local points, own = {}, #ownPlaced
    for _, entry in ipairs(ownPlaced) do points[#points + 1] = entry end
    for _, entry in ipairs(guildPlaced) do points[#points + 1] = entry end
    for _, point in ipairs(view.points) do
        point.used = nil
        point:Hide()
    end
    for i, entry in ipairs(points) do
        local point = marker(view, view.points, i)
        local kind = entry.event.kind
        point.used = true
        point:SetSize(16, 16)
        -- Yours: a red skull, a green sword. The guild's: an orange skull, a blue sword.
        if kind == "death" then
            point.fill:SetTexture(SKULL)
            if entry.guild then point.fill:SetVertexColor(1, 0.72, 0.25) else point.fill:SetVertexColor(1, 0.35, 0.3) end
        else
            point.fill:SetTexture(SWORD)
            if entry.guild then point.fill:SetVertexColor(0.55, 0.8, 1) else point.fill:SetVertexColor(0.5, 1, 0.5) end
            if kind == "assist" then point:SetSize(12, 12) end
        end
        point.count:SetText("")
        point:SetScript("OnEnter", function(self)
            if entry.guild then
                local member = GL.Bounties and GL.Bounties.MemberName and GL.Bounties.MemberName(entry.guild)
                local what = kind == "death" and L("Mort d’un membre de la guilde") or L("Victoire d’un membre de la guilde")
                if entry.enemy then what = (kind == "death" and L("Tué par %s") or L("A tué %s")):format(UI.plain(entry.enemy)) end
                tip(self, UI.plain(member or L("Un membre de la guilde")), what .. " · " .. day(entry.event.time))
            else
                tip(self, name(entry.record), (GL.HistoryTitle and GL.HistoryTitle(entry.event) or "") .. " · " .. day(entry.event.time))
            end
        end)
        point:SetScript("OnClick", function()
            if entry.guild then return end
            if GL.InspectEvent then GL.InspectEvent(entry.record, entry.event) else openSheet(entry.record) end
        end)
    end
    locate(view)
    view.tallies, view.shapes, view.placed = tallies, shapes, points
    local hint = L("Molette : zoomer · glisser : se déplacer · %d combats placés"):format(own)
    local counts = hint:match("[^·]+$"):gsub("^%s+", "")
    if view.guildOn then
        local guild = " · " .. L("guilde : %d"):format(#guildPlaced)
        hint, counts = hint .. guild, counts .. guild
    end
    view.hintFull, view.hintShort = bars(hint), bars(counts)
    fitHint(view)
    R.MapLayout()
    return true
end
-- Glides to a zone (or a continent) until it fills the view. The map never switches.
function R.MapFocus(id)
    local view = mapView()
    local rect = view and view.world and view.world.rects[id]
    if not rect then return false end
    local zoom = 0.85 * math.min(1 / (rect.right - rect.left), 1 / (rect.bottom - rect.top))
    view.goal = { zoom = math.max(1, math.min(ZOOM_MAX, zoom)), cx = (rect.left + rect.right) / 2, cy = (rect.top + rect.bottom) / 2 }
    return true
end
-- Back to the whole world.
function R.MapOut()
    local view = mapView()
    if not view or not view.world or view.zoom <= 1.001 then return false end
    view.goal = { zoom = 1, cx = 0.5, cy = 0.5 }
    return true
end
-- To where you stand.
function R.MapHere()
    local view = mapView()
    if not view or not view.here then return false end
    if view.here.zone and R.MapFocus(view.here.zone) then return true end
    view.goal = { zoom = math.min(ZOOM_MAX, view.pointZoom * 2), cx = view.here.x, cy = view.here.y }
    return true
end
-- The wheel: away from you closes in on the pointer, towards you backs out, from the whole world
-- down to a zone. It sets where the view is going; MapStep glides there.
function R.MapWheel(delta)
    local view = mapView()
    -- While the map is held, the wheel waits: otherwise the view jumps when the button is let go.
    if not view or not view.world or not view.width or view.drag then return false end
    local from = view.goal and view.goal.zoom or view.zoom
    local zoom = math.max(1, math.min(ZOOM_MAX, delta > 0 and from * ZOOM_STEP or from / ZOOM_STEP))
    if math.abs(zoom - from) < 0.0001 then return false end
    local u, v, px, py = pointer(view)
    view.goal = { zoom = zoom, u = u, v = v, px = px, py = py }
    return true
end
-- One frame of the glide. With a pointer the point under it stays under it.
function R.MapStep(elapsed)
    local view = mapView()
    local goal = view and view.goal
    if not goal or not view.width then return false end
    local k = math.min(1, (tonumber(elapsed) or 0) * 12)
    local zoom = view.zoom * (goal.zoom / view.zoom) ^ k
    local done = math.abs(zoom - goal.zoom) < goal.zoom * 0.005
    if done then zoom = goal.zoom end
    view.zoom = zoom
    if goal.cx then
        view.cx = done and goal.cx or view.cx + (goal.cx - view.cx) * k
        view.cy = done and goal.cy or view.cy + (goal.cy - view.cy) * k
    elseif goal.u then
        view.cx = goal.u - (goal.px - view.width / 2) / (view.width * zoom)
        view.cy = goal.v - (goal.py - view.height / 2) / (view.height * zoom)
    end
    if done then view.goal = nil end
    R.MapLayout()
    return true
end
local function buildLands(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -54, S(400), 13, false, UI.theme.inkMuted)
    -- Under the title, the owner's separator (kit of 25/11).
    page.rule = page:CreateTexture(nil, "ARTWORK")
    page.rule:SetTexture(GL.Art.Separator)
    page.rule:SetPoint("TOPLEFT", X(18), -38)
    page.rule:SetSize(256, 16)
    page.mode = "map"
    page.map = buildMap(page)
    page.toggle = UI.button(page, "", X(446), -22, S(120), function()
        page.mode = page.mode == "map" and "list" or "map"
        R.Refresh()
    end, nil, true)
    -- Guild vision: one box. Ticked, you see the fights of the members who ticked it and they see yours.
    page.guild = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.guild:SetPoint("TOPLEFT", X(286), -19)
    page.guild:SetSize(24, 24)
    page.guildLabel = Panels.Text(page, X(312), -25, S(110), 12, true)
    page.guild:SetScript("OnClick", function(self)
        if GL.GuildMap then GL.GuildMap.Enable(self:GetChecked() and true or false) end
        R.Refresh()
    end)
    page.guild:SetScript("OnEnter", function(self)
        tip(self, L("Vision de guilde"), L("Cochée : vous voyez sur la carte les victoires et les morts des membres qui l’ont cochée, et ils voient "
            .. "les vôtres (la zone et l’endroit). Décochée : rien n’est envoyé, rien n’est gardé, et la guilde oublie vos combats."))
    end)
    page.guild:SetScript("OnLeave", hideTip)
    page.rows = {}
    for i = 1, LAND_ROWS do
        local row = CreateFrame("Frame", nil, page)
        row:SetPoint("TOPLEFT", X(26), -84 - (i - 1) * 46)
        row:SetSize(S(540), 44)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
        row.zone = Panels.Text(row, S(0), -5, S(200), 14, true)
        GL.Safe(row.zone.SetWordWrap, row.zone, false)
        row.who = Panels.Text(row, S(0), -24, S(330), 11, false, UI.theme.inkMuted)
        GL.Safe(row.who.SetWordWrap, row.who, false)
        row.track = row:CreateTexture(nil, "BORDER")
        row.track:SetPoint("TOPLEFT", S(210), -10)
        row.track:SetSize(S(200), 8)
        row.track:SetColorTexture(0.85, 0.75, 0.55)
        row.fill = row:CreateTexture(nil, "ARTWORK")
        row.fill:SetPoint("TOPLEFT", S(210), -10)
        row.fill:SetHeight(8)
        row.fill:SetColorTexture(0.55, 0.12, 0.12)
        row.counts = Panels.Text(row, S(420), -6, S(120), 12, true)
        row.counts:SetJustifyH("RIGHT")
        page.rows[i] = row
    end
    page.empty = Panels.Text(page, X(26), -86, S(540), 13, false, UI.theme.inkMuted)
    page.note = Panels.Text(page, X(26), -470, S(540), 11, false, UI.theme.inkMuted)
    return page
end
local function paintLands(page)
    page.title:SetText(L("Carte des combats"))
    local lands = R.Lands()
    local guildOn, inGuild = false, false
    if GL.GuildMap then guildOn, inGuild = GL.GuildMap.Enabled() end
    page.map.guildOn = guildOn
    page.lead:SetText(guildOn and L("Vos combats et ceux de la guilde.") or #lands > 0 and L("Où vous mourez, et à cause de qui.") or "")
    page.guildLabel:SetText(L("Vision de guilde"))
    GL.Safe(page.guild.SetChecked, page.guild, guildOn)
    -- The map first, when the game gives its pictures. The list is one click away and is all there is
    -- on a client without them.
    local mapped = false
    if page.mode == "map" and C_Map then
        local byName = {}
        for _, entry in ipairs(lands) do byName[entry.zone] = entry end
        mapped = paintMap(page.map, byName)
    end
    if mapped then page.map:Show() else page.map:Hide() end
    -- With the map, its place and counts take the lead's line.
    if mapped then page.lead:Hide() else page.lead:Show() end
    if mapped and inGuild then
        page.guild:Show()
        page.guildLabel:Show()
    else
        page.guild:Hide()
        page.guildLabel:Hide()
    end
    page.toggle:SetText(mapped and L("Voir la liste") or L("Voir la carte"))
    if C_Map then page.toggle:Show() else page.toggle:Hide() end
    local worst = lands[1] and math.max(1, lands[1].deaths) or 1
    for i, row in ipairs(page.rows) do
        local entry = not mapped and lands[i]
        if entry then
            Panels.Fit(row.zone, UI.plain(entry.zone), S(200), 14, 10, true)
            Panels.Fit(row.who, killers(entry), S(330), 11, 8)
            row.fill:SetWidth(math.max(0.01, S(200) * entry.deaths / worst))
            if entry.deaths > 0 then row.fill:Show() else row.fill:Hide() end
            row.counts:SetText(L("%d morts · %d victoires"):format(entry.deaths, entry.kills))
            row:Show()
        else
            row:Hide()
        end
    end
    page.empty:SetText(not mapped and #lands == 0
        and L("Aucun combat terminé pour l’instant : cette page se remplit avec vos morts et vos victoires.") or "")
    page.note:SetText(not mapped and #lands > LAND_ROWS and L("Les %d zones les plus meurtrières sur %d."):format(LAND_ROWS, #lands) or "")
end

-- Rankings: the fourteen lists of the old Relations window, on one page of this book. Four tabs
-- (three kinds of players, then guilds), the lists of the tab as chips, six lines, pages to turn.
local RANK_ROWS = 6
local function rankingGroups()
    local choices = GL.RankingChoices
    local groups = {}
    for _, group in ipairs(choices.players) do
        groups[#groups + 1] = { name = group.name, entries = group.entries }
    end
    local guilds = { name = L("Guildes"), entries = {}, guild = true }
    for _, group in ipairs(choices.guilds) do
        for _, entry in ipairs(group.entries) do guilds.entries[#guilds.entries + 1] = entry end
    end
    groups[#groups + 1] = guilds
    return groups
end
function R.RankingRows(group, choice)
    local rows = {}
    if group.guild then
        for _, row in ipairs(GL.GuildStatistics()) do
            local kept
            if choice[1] == "rules" then
                kept = GL.GetGuildRule(row.name, row.realm) ~= nil
            else
                kept = (row[choice[1]] or 0) > 0
            end
            if kept then rows[#rows + 1] = row end
        end
        table.sort(rows, function(a, b)
            if choice[1] ~= "rules" and a[choice[1]] ~= b[choice[1]] then return a[choice[1]] > b[choice[1]] end
            if a.name ~= b.name then return a.name < b.name end
            return tostring(a.key) < tostring(b.key)
        end)
        return rows
    end
    return GL.PlayerStatistics(choice[1])
end
local function buildRankings(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.group, page.choice, page.offset = 1, 1, 0
    page.groups = rankingGroups()
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(540), 13, false, UI.theme.inkMuted)
    page.lead:SetHeight(30)
    page.tabs = {}
    for i, group in ipairs(page.groups) do
        page.tabs[i] = UI.button(page, group.name, X(26) + (i - 1) * S(136), -84, S(132), function()
            page.group, page.choice, page.offset = i, 1, 0
            R.Refresh()
        end, true, true)
    end
    page.chips = {}
    for i = 1, 6 do
        page.chips[i] = UI.button(page, "", X(26) + ((i - 1) % 3) * S(181), -116 - math.floor((i - 1) / 3) * 30, S(178), function()
            page.choice, page.offset = i, 0
            R.Refresh()
        end, true, true)
    end
    local band = page:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT", X(26), -180)
    band:SetSize(S(540), 22)
    band:SetColorTexture(0.44, 0.28, 0.13, 0.18)
    page.columnName = Panels.Text(page, X(30), -184, S(300), 12, false, UI.theme.inkMuted)
    page.columnValue = Panels.Text(page, X(416), -184, S(146), 12, false, UI.theme.inkMuted)
    page.columnValue:SetJustifyH("RIGHT")
    page.rows = {}
    for i = 1, RANK_ROWS do
        local row = CreateFrame("Button", nil, page)
        row:SetPoint("TOPLEFT", X(26), -204 - (i - 1) * 44)
        row:SetSize(S(540), 42)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
        row.rank = Panels.Text(row, S(0), -12, S(18), 12, false, UI.theme.inkMuted)
        row.face = face(row, 34)
        row.face:SetPoint("TOPLEFT", S(24), -4)
        row.crest = row:CreateTexture(nil, "ARTWORK")
        row.crest:SetPoint("TOPLEFT", S(24), -4)
        row.crest:SetSize(34, 34)
        row.initials = Panels.Text(row, S(24), -12, S(34), 14, true, UI.theme.brass)
        row.initials:SetJustifyH("CENTER")
        row.name = Panels.Text(row, S(60), -4, S(250), 14, true)
        GL.Safe(row.name.SetWordWrap, row.name, false)
        row.meta = Panels.Text(row, S(60), -23, S(330), 11, false, UI.theme.inkMuted)
        GL.Safe(row.meta.SetWordWrap, row.meta, false)
        row.value = Panels.Text(row, S(396), -10, S(142), 16, true)
        row.value:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            local item = self.item
            if not item then return end
            if item.record then
                openSheet(item.record)
            elseif GL.ShowGuilds then
                GL.ShowGuilds({ guild = item.name, realm = item.realm })
            end
        end)
        page.rows[i] = row
    end
    page.empty = Panels.Text(page, X(26), -212, S(540), 13, false, UI.theme.inkMuted)
    page.previous = UI.button(page, "‹", X(26), -464, S(40), function()
        page.offset = math.max(0, page.offset - RANK_ROWS)
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", X(526), -464, S(40), function()
        page.offset = page.offset + RANK_ROWS
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(76), -470, S(440), 12, false, UI.theme.inkMuted)
    page.count:SetJustifyH("CENTER")
    return page
end
local function paintRankings(page)
    local group = page.groups[page.group] or page.groups[1]
    page.choice = math.max(1, math.min(page.choice, #group.entries))
    local choice = group.entries[page.choice]
    page.title:SetText(choice[2])
    page.lead:SetText(choice[3])
    for i, tab in ipairs(page.tabs) do UI.selectButton(tab, i == page.group) end
    for i, chip in ipairs(page.chips) do
        local entry = group.entries[i]
        if entry then
            chip:SetText(entry[2])
            Panels.Fit(chip.caption, entry[2], S(166), 12, 8)
            UI.selectButton(chip, i == page.choice)
            chip:Show()
        else
            chip:Hide()
        end
    end
    page.columnName:SetText(group.guild and L("Guilde") or L("Joueur"))
    page.columnValue:SetText(choice[5])
    local rows = R.RankingRows(group, choice)
    page.offset = math.min(page.offset, math.max(0, math.floor((#rows - 1) / RANK_ROWS) * RANK_ROWS))
    local inks, names = GL.RelationInks, GL.RelationNames
    for i, row in ipairs(page.rows) do
        local item = rows[page.offset + i]
        row.item = item
        if item then
            row.rank:SetText(tostring(page.offset + i))
            if group.guild then
                row.face:Hide()
                row.crest:Show()
                local rule = GL.GetGuildRule(item.name, item.realm)
                row.crest:SetColorTexture(unpack(crestColors[rule and rule.reaction or "neutral"] or crestColors.neutral))
                row.initials:SetText(R.Initials(item.name))
                Panels.Fit(row.name, UI.plain(item.name), S(250), 14, 10, true)
                row.name:SetTextColor(unpack(UI.theme.ink))
                row.meta:SetText(GL.RealmLabel(item.realm))
                row.value:SetText(choice[1] == "rules" and (names[rule and rule.reaction] or "") or tostring(item[choice[1]] or 0))
            else
                local record = item.record
                local relation = GL.Relation(record)
                row.crest:Hide()
                row.initials:SetText("")
                row.face:Show()
                GL.PaintBookPortrait(row.face, record)
                Panels.Fit(row.name, name(record), S(250), 14, 10, true)
                row.name:SetTextColor(unpack(inks[relation] or UI.theme.ink))
                local faction, _, class = GL.IdentityLabels(record)
                local meta = { (UI.plain(faction)), (UI.plain(class)) }
                if record.guild then meta[#meta + 1] = UI.plain(record.guild) end
                local nick = nickname(record)
                if nick ~= "" then meta[#meta + 1] = nick end
                Panels.Fit(row.meta, table.concat(meta, " · "), S(330), 11, 8)
                row.value:SetText(GL.RankingValueText(choice, item.value or 0))
            end
            row:Show()
        else
            row:Hide()
        end
    end
    page.empty:SetText(#rows == 0 and L("Personne dans ce classement pour l’instant.") or "")
    page.previous:SetEnabled(page.offset > 0)
    page.next:SetEnabled(page.offset + RANK_ROWS < #rows)
    page.count:SetText(#rows > 0 and L("%d à %d sur %d"):format(page.offset + 1, math.min(page.offset + RANK_ROWS, #rows), #rows) or "")
end

-- /gl carte: what this client lets an addon do with maps, measured in the game before the map of
-- dangerous lands is built. It prints the facts and draws the current zone in a small window of
-- ours, with a dot where you stand.
local function answerOf(value)
    if value == nil then return L("absent") end
    if type(value) == "table" then return L("oui") end
    return tostring(value)
end
function R.MapProbe()
    local api = C_Map
    if type(api) ~= "table" then
        GL.Print(L("Carte : le jeu n’offre pas les fonctions de carte à un addon."))
        return false
    end
    local map = GL.Clean(GL.Safe(api.GetBestMapForUnit, "player"), "number")
    local info = map and GL.Safe(api.GetMapInfo, map)
    local parent = type(info) == "table" and GL.Safe(api.GetMapInfo, info.parentMapID)
    GL.Print(L("Carte · zone n° %s · %s · type %s · dans %s"):format(tostring(map), UI.plain(type(info) == "table" and info.name or "?"),
        tostring(type(info) == "table" and info.mapType), UI.plain(type(parent) == "table" and parent.name or "?")))
    local x, y
    if map and type(api.GetPlayerMapPosition) == "function" then
        local ok, position = pcall(api.GetPlayerMapPosition, map, "player")
        if ok and type(position) == "table" and type(position.GetXY) == "function" then x, y = GL.Safe(position.GetXY, position) end
        if not ok or position == nil then GL.Print(L("Position : le jeu ne la donne pas ici.")) end
    end
    x, y = GL.Clean(x, "number"), GL.Clean(y, "number")
    GL.Print(L("Position : %s · en combat : %s"):format(x and y and ("%.3f ; %.3f"):format(x, y) or L("cachée ou absente"),
        GL.Safe(InCombatLockdown) == true and L("oui") or L("non")))
    local layers = map and GL.Safe(api.GetMapArtLayers, map)
    local layer = type(layers) == "table" and layers[1]
    local textures = map and GL.Safe(api.GetMapArtLayerTextures, map, 1)
    local tiles = type(textures) == "table" and #textures or 0
    GL.Print(L("Image de la carte : %d morceaux · %s × %s · morceau de %s"):format(tiles, tostring(layer and layer.layerWidth),
        tostring(layer and layer.layerHeight), tostring(layer and layer.tileWidth)))
    local children = type(info) == "table" and GL.Safe(api.GetMapChildrenInfo, info.parentMapID)
    local rectangle = type(info) == "table" and { GL.Safe(api.GetMapRectOnMap, map, info.parentMapID) }
    GL.Print(L("Carte du dessus : %s zones · rectangle de cette zone : %s"):format(type(children) == "table" and #children or 0,
        answerOf(rectangle and rectangle[1])))
    local explored = map and C_MapExplorationInfo and GL.Safe(C_MapExplorationInfo.GetExploredMapTextures, map)
    GL.Print(L("Détail des zones : %s morceaux explorés ici · masque : %s"):format(type(explored) == "table" and #explored or L("absent"),
        type(UIParent) == "table" and type(UIParent.CreateMaskTexture) == "function" and L("oui") or L("non")))
    local above = type(info) == "table" and info.parentMapID
    local zoneRect = above and map and rectOn(map, above)
    local shape = zoneRect and zoneShape(above, map, zoneRect)
    GL.Print(L("Surbrillance de la zone : %s"):format(shape and (tostring(shape.atlas or shape.file) .. " · "
        .. ("%.2f × %.2f"):format(shape.usedX, shape.usedY)) or L("absent")))
    if tiles == 0 or not layer then return true end
    -- The zone, drawn from the game's own pieces in our window, and the dot.
    local w = GrudgeLedgerMapProbe or UI.window("GrudgeLedgerMapProbe", L("Sonde : carte"), 468, 372)
    if not w.canvas then
        w.canvas = CreateFrame("Frame", nil, w)
        w.canvas:SetPoint("TOPLEFT", 14, -50)
        w.canvas:SetSize(440, 300)
        GL.Safe(w.canvas.SetClipsChildren, w.canvas, true)
        w.pieces = {}
        w.dot = w.canvas:CreateTexture(nil, "OVERLAY")
        w.dot:SetSize(10, 10)
        w.dot:SetColorTexture(0.85, 0.1, 0.1)
    end
    local scale = 440 / math.max(1, tonumber(layer.layerWidth) or 1)
    local size = (tonumber(layer.tileWidth) or 256) * scale
    local columns = math.max(1, math.ceil((tonumber(layer.layerWidth) or 1) / (tonumber(layer.tileWidth) or 256)))
    for i, piece in ipairs(w.pieces) do piece:Hide() end
    for i = 1, tiles do
        local piece = w.pieces[i] or w.canvas:CreateTexture(nil, "ARTWORK")
        w.pieces[i] = piece
        piece:ClearAllPoints()
        piece:SetPoint("TOPLEFT", ((i - 1) % columns) * size, -math.floor((i - 1) / columns) * size)
        piece:SetSize(size, size)
        piece:SetTexture(textures[i])
        piece:Show()
    end
    if x and y then
        w.dot:ClearAllPoints()
        w.dot:SetPoint("CENTER", w.canvas, "TOPLEFT", x * 440, -y * (tonumber(layer.layerHeight) or 1) * scale)
        w.dot:Show()
    else
        w.dot:Hide()
    end
    w:Show()
    GL.Print(L("Carte dessinée dans la petite fenêtre : dites-moi si l’image est juste et si le point rouge est sur vous."))
    return true
end

-- The guild's journal (0.51.0; its filters work like the Journal's since 0.52.1): what happens to
-- the members who share their fights, yours included, the latest first. One line a fight: who,
-- against whom, where, when. Above the lines, the Journal's three controls: a search (a member or
-- an opponent), one button naming the current list with its count (a click shows the next one),
-- and "Filtres", a panel of grouped choices opened on demand. Pages turn, nothing scrolls.
local GUILD_ROWS = 6
local GROUP_NAMES = 5 -- names offered in a group of the panel, after "everyone": the search finds the rest
local PERIODS = { { 0, "Toujours" }, { 86400, "24 h" }, { 7 * 86400, "7 jours" }, { 30 * 86400, "30 jours" } }
local VIEWS = { { "all", "Tous" }, { "death", "Morts" }, { "kill", "Victoires" }, { "mine", "Mes combats" } }
local function elapsed(at)
    local delta = math.max(0, GL.Now() - at)
    if delta < 3600 then return L("il y a %d min"):format(math.max(1, math.floor(delta / 60))) end
    if delta < 86400 then return L("il y a %d h"):format(math.floor(delta / 3600)) end
    return L("il y a %d j"):format(math.floor(delta / 86400))
end
-- Shortens a name on a character boundary, for the buttons of the panel.
local function short(text, most)
    local out, count = {}, 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > most then return table.concat(out) .. "…" end
        out[count] = char
    end
    return text
end
local function foeKey(point)
    return point.target or (point.name and "name:" .. point.name) or nil
end
local function memberName(point)
    if point.mine then return L("Vous") end
    local member = GL.Bounties and GL.Bounties.MemberName and GL.Bounties.MemberName(point.actor)
    return UI.plain(member or L("Un membre de la guilde"))
end
local function foeName(point)
    return UI.plain(point.name or L("un joueur inconnu"))
end
-- The guild's fights that pass the filters: view ("death", "kill", "mine" or "all"), who (member
-- identifier), foe (opponent key), period (seconds back from now, 0 for always) and query (part of
-- a member's or an opponent's name). "skip" leaves one filter out, for the counts of the panel.
function R.GuildLog(filter, skip)
    filter = filter or {}
    local all = GL.GuildMap and GL.GuildMap.Points(true) or {}
    local since = (filter.period or 0) > 0 and skip ~= "period" and GL.Now() - filter.period or nil
    local who = skip ~= "who" and filter.who or nil
    local foe = skip ~= "foe" and filter.foe or nil
    local view = skip ~= "view" and filter.view ~= "all" and filter.view or nil
    local query = type(filter.query) == "string" and filter.query ~= "" and filter.query:lower() or nil
    if not (since or who or foe or view or query) then return all end
    local out = {}
    for _, point in ipairs(all) do
        local keep = (not who or point.actor == who) and (not since or point.time >= since) and (not foe or foeKey(point) == foe)
            and (not view or (view == "mine" and point.mine) or point.kind == view)
        if keep and query then
            keep = memberName(point):lower():find(query, 1, true) ~= nil or foeName(point):lower():find(query, 1, true) ~= nil
        end
        if keep then out[#out + 1] = point end
    end
    return out
end
-- The names the panel offers for "who" or "foe", with how many fights each, the most first.
function R.GuildLogChoices(filter, field)
    local counts, list = {}, {}
    for _, point in ipairs(R.GuildLog(filter, field)) do
        local key = field == "who" and point.actor or foeKey(point)
        if key then
            local entry = counts[key]
            if not entry then
                entry = { key = key, count = 0, label = field == "who" and memberName(point) or foeName(point), mine = point.mine }
                counts[key] = entry
                list[#list + 1] = entry
            end
            entry.count = entry.count + 1
        end
    end
    table.sort(list, function(a, b)
        if (a.mine == true) ~= (b.mine == true) then return a.mine == true end
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    return list
end
local function openOpponent(row)
    if row.target and GL.OpenPlayerDossier then GL.OpenPlayerDossier(row.target, nil, row.enemy) end
end
-- A wanted notice on the opponent of a line: a bounty without gold, in one click. The guild sees
-- it in Primes and is alerted when one of its members meets that player.
local function wanted(row)
    if not (row.target and row.enemy and GL.Bounties and GL.Bounties.Post) then return end
    local id, err = GL.Bounties.Post(row.target, row.enemy, 0)
    if id then
        GL.Print(L("Avis de recherche publié : %s. Sans or, valable 7 jours."):format(UI.plain(row.enemy)))
    elseif err == "duplicate" then
        GL.Print(L("Une prime ou un avis de recherche existe déjà sur ce joueur."))
    elseif err == "ally" then
        GL.Print(L("Ce joueur est de votre faction : pas d’avis de recherche."))
    else
        GL.Print(L("L’avis de recherche n’a pas pu être publié."))
    end
    R.Refresh()
end
-- The panel of filters, drawn like the Journal's: a caption per group naming the current choice,
-- the choices in two columns, then "Effacer" and "Fermer".
local function buildFilterPanel(page)
    local panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", X(283), -102)
    panel:SetSize(283, 344)
    panel:EnableMouse(true)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetToplevel(true)
    -- Above the lines and their buttons, as the Journal's panel is above its list.
    GL.Safe(panel.SetFrameLevel, panel, (GL.Safe(page.GetFrameLevel, page) or 1) + 20)
    UI.surface(panel, UI.theme.gold)
    UI.surface(panel, UI.theme.panel, 1)
    panel:Hide()
    local function group(y, count, onChoose)
        local caption = UI.label(panel, "", nil, 8, -y, 267)
        caption:SetTextColor(unpack(UI.theme.brass))
        local choices = {}
        for i = 1, count do
            local index = i
            choices[i] = UI.button(panel, "", 8 + ((i - 1) % 2) * 135, -(y + 18) - math.floor((i - 1) / 2) * 28, 133, function()
                onChoose(index)
                page.offset = 0
                R.Refresh()
            end, true)
        end
        return caption, choices
    end
    panel.periodCaption, panel.periods = group(8, #PERIODS, function(i) page.filter.period = PERIODS[i][1] end)
    panel.whoCaption, panel.who = group(90, GROUP_NAMES + 1, function(i)
        page.filter.who = i > 1 and panel.whoKeys[i] or nil
    end)
    panel.foeCaption, panel.foe = group(200, GROUP_NAMES + 1, function(i)
        page.filter.foe = i > 1 and panel.foeKeys[i] or nil
    end)
    panel.clear = UI.button(panel, L("Effacer"), 143, -310, 65, function()
        page.filter = { view = "all" }
        page.search:SetText("")
        page.offset = 0
        R.Refresh()
    end)
    panel.close = UI.button(panel, L("Fermer"), 211, -310, 65, function() panel:Hide() end)
    return panel
end
-- Fills a group of names: "everyone" first, then the members (or opponents) with the most fights.
local function fillNames(choices, everyone, entries, chosen)
    local keys = {}
    for i, button in ipairs(choices) do
        local entry = i > 1 and entries[i - 1]
        if i == 1 then
            button:SetText(everyone)
            UI.selectButton(button, chosen == nil)
            button:Show()
        elseif entry then
            keys[i] = entry.key
            button:SetText(short(entry.label, 14) .. " · " .. entry.count)
            UI.selectButton(button, chosen == entry.key)
            button:Show()
        else
            button:Hide()
        end
    end
    return keys
end
local function paintFilterPanel(page)
    local panel, filter = page.filterPanel, page.filter
    local periodName = PERIODS[1][2]
    for i, button in ipairs(panel.periods) do
        button:SetText(L(PERIODS[i][2]))
        UI.selectButton(button, (filter.period or 0) == PERIODS[i][1])
        if (filter.period or 0) == PERIODS[i][1] then periodName = PERIODS[i][2] end
    end
    panel.periodCaption:SetText(L("Période : %s"):format(L(periodName)))
    local members, foes = R.GuildLogChoices(filter, "who"), R.GuildLogChoices(filter, "foe")
    panel.whoKeys = fillNames(panel.who, L("Tous les membres"), members, filter.who)
    panel.foeKeys = fillNames(panel.foe, L("Tous les ennemis"), foes, filter.foe)
    local whoName, foeLabel = L("Tous les membres"), L("Tous les ennemis")
    for _, entry in ipairs(members) do
        if entry.key == filter.who then whoName = entry.label end
    end
    for _, entry in ipairs(foes) do
        if entry.key == filter.foe then foeLabel = entry.label end
    end
    panel.whoCaption:SetText(L("Membre : %s"):format(whoName))
    panel.foeCaption:SetText(L("Ennemi : %s"):format(foeLabel))
end
local function buildGuildJournal(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(540), 13, false, UI.theme.inkMuted)
    page.filter, page.offset = { view = "all" }, 0
    -- The Journal's three controls, in the same order: search, list, filters.
    page.search = CreateFrame("EditBox", nil, page)
    page.search:SetPoint("TOPLEFT", X(26), -72)
    page.search:SetSize(S(196), 26)
    page.search:SetAutoFocus(false)
    page.search:SetMaxLetters(60)
    UI.styleInput(page.search, false, false)
    page.search:SetTextInsets(8, 6, 3, 3)
    local function applySearch()
        page.filter.query = page.search:GetText():match("^%s*(.-)%s*$")
        page.offset = 0
        page.search:ClearFocus()
        R.Refresh()
    end
    page.search:SetScript("OnEnterPressed", applySearch)
    page.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.searchHint = UI.label(page.search, L("Rechercher…"), nil, 8, -5, S(180))
    page.searchHint:SetTextColor(unpack(UI.theme.muted))
    page.search:SetScript("OnTextChanged", function(self)
        if self:GetText():find("%S") then
            page.searchHint:Hide()
        else
            page.searchHint:Show()
            if page.filter.query and page.filter.query ~= "" then
                page.filter.query, page.offset = nil, 0
                R.Refresh()
            end
        end
    end)
    -- One button names the current list with its count; a click shows the next one. A list always
    -- starts clean: the other filters are put back, as in the Journal.
    page.viewCycle = UI.button(page, "", X(226), -72, S(196), function()
        local following = VIEWS[1][1]
        for i, view in ipairs(VIEWS) do
            if view[1] == page.filter.view then following = VIEWS[i % #VIEWS + 1][1] end
        end
        page.filter, page.offset = { view = following }, 0
        page.search:SetText("")
        page.filterPanel:Hide()
        R.Refresh()
    end)
    page.openFilters = UI.button(page, L("Filtres"), X(426), -72, S(140), function()
        if page.filterPanel:IsShown() then
            page.filterPanel:Hide()
        else
            page.filterPanel:Show()
            page.filterPanel:Raise()
            R.Refresh()
        end
    end)
    page.rows = {}
    for i = 1, GUILD_ROWS do
        local row = CreateFrame("Button", nil, page)
        row:SetPoint("TOPLEFT", X(26), -108 - (i - 1) * 56)
        row:SetSize(S(540), 54)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetPoint("TOPLEFT", S(2), -13)
        row.mark:SetSize(22, 22)
        row.story = Panels.Text(row, S(32), -7, S(340), 15, true)
        GL.Safe(row.story.SetWordWrap, row.story, false)
        row.where = Panels.Text(row, S(32), -29, S(340), 12, false, UI.theme.inkMuted)
        GL.Safe(row.where.SetWordWrap, row.where, false)
        row.wanted = UI.button(row, L("Rechercher"), S(380), -14, S(92), function() wanted(row) end, nil, true)
        row.sheet = UI.button(row, L("Fiche"), S(476), -14, S(64), function() openOpponent(row) end, nil, true)
        row:SetScript("OnClick", openOpponent)
        page.rows[i] = row
    end
    page.filterPanel = buildFilterPanel(page)
    page:SetScript("OnHide", function() page.filterPanel:Hide() end)
    page.empty = Panels.Text(page, X(26), -124, S(540), 13, false, UI.theme.inkMuted)
    page.previous = UI.button(page, "‹", X(26), -464, S(40), function()
        page.offset = math.max(0, page.offset - GUILD_ROWS)
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", X(526), -464, S(40), function()
        page.offset = page.offset + GUILD_ROWS
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(76), -470, S(440), 12, false, UI.theme.inkMuted)
    page.count:SetJustifyH("CENTER")
    return page
end
local function paintGuildJournal(page)
    page.title:SetText(L("Journal de guilde"))
    local sharing, inGuild = false, false
    if GL.GuildMap then sharing, inGuild = GL.GuildMap.Enabled() end
    local filter = page.filter
    local lines = sharing and R.GuildLog(filter) or {}
    page.lead:SetText(sharing and L("Les victoires et les morts des membres qui partagent leurs combats.") or "")
    -- The list button: its name and how many lines it holds, as in the Journal.
    local viewName = VIEWS[1][2]
    for _, view in ipairs(VIEWS) do
        if view[1] == filter.view then viewName = view[2] end
    end
    page.viewCycle:SetText(L("%s · %d"):format(L(viewName), #lines))
    UI.selectButton(page.viewCycle, filter.view ~= "all")
    local active = (filter.who and 1 or 0) + (filter.foe and 1 or 0) + ((filter.period or 0) > 0 and 1 or 0)
    page.openFilters:SetText(active > 0 and (L("Filtres") .. " · " .. active) or L("Filtres"))
    UI.selectButton(page.openFilters, active > 0)
    for _, control in ipairs({ page.search, page.viewCycle, page.openFilters }) do
        if sharing then control:Show() else control:Hide() end
    end
    if not sharing then page.filterPanel:Hide() end
    if page.filterPanel:IsShown() then paintFilterPanel(page) end
    page.offset = math.min(page.offset, math.max(0, math.floor((#lines - 1) / GUILD_ROWS) * GUILD_ROWS))
    local deaths = 0
    for _, point in ipairs(lines) do
        if point.kind == "death" then deaths = deaths + 1 end
    end
    for i, row in ipairs(page.rows) do
        local point = lines[page.offset + i]
        if point then
            local member, enemy = memberName(point), foeName(point)
            local died = point.kind == "death"
            local story
            if point.mine then
                story = (died and L("Vous avez été tué par %s") or L("Vous avez tué %s")):format(enemy)
            else
                story = (died and L("%s a été tué par %s") or L("%s a tué %s")):format(member, enemy)
            end
            Panels.Fit(row.story, story, S(340), 15, 10, true)
            if died then row.story:SetTextColor(0.55, 0.12, 0.12) else row.story:SetTextColor(0.18, 0.37, 0.20) end
            row.mark:SetTexture(died and SKULL or SWORD)
            local info = mapInfo(point.mapID)
            local zone = info and type(info.name) == "string" and UI.plain(info.name)
            row.where:SetText(zone and (zone .. " · " .. elapsed(point.time)) or elapsed(point.time))
            row.target, row.enemy = point.target, point.name
            if point.target then row.sheet:Show() else row.sheet:Hide() end
            -- Wanted: only on a player known by name, and not while a notice or a bounty already runs.
            local open = point.target and GL.Bounties and GL.Bounties.OpenFor and GL.Bounties.OpenFor(point.target)
            if point.target and point.name and not open then row.wanted:Show() else row.wanted:Hide() end
            row:Show()
        else
            row.target, row.enemy = nil, nil
            row:Hide()
        end
    end
    local filtered = active > 0 or filter.view ~= "all" or (filter.query and filter.query ~= "")
    local empty = ""
    if not inGuild then
        empty = L("Vous n’êtes dans aucune guilde : ce journal raconte les combats de la vôtre.")
    elseif not sharing then
        empty = L("La vision de guilde est décochée. Cochez-la à gauche pour lire ce journal et y figurer.")
    elseif #lines == 0 and filtered then
        empty = L("Aucun combat ne correspond. « Effacer » dans les filtres remet tout.")
    elseif #lines == 0 then
        empty = L("Aucun combat partagé pour l’instant. Le journal se remplit quand un membre gagne ou meurt.")
    end
    page.empty:SetText(empty)
    page.previous:SetEnabled(page.offset > 0)
    page.next:SetEnabled(page.offset + GUILD_ROWS < #lines)
    if #lines > GUILD_ROWS then
        page.previous:Show()
        page.next:Show()
    else
        page.previous:Hide()
        page.next:Hide()
    end
    page.count:SetText(#lines > 0 and L("%d combats · %d morts"):format(#lines, deaths) or "")
end

-- The guild's enemies (0.55.0): the players who killed members of the guild, the deadliest first.
-- One line each: how many deaths, how many members, how many times the guild won, when last. The
-- Journal's list button chooses the period. A click opens the sheet; "Rechercher" posts a wanted
-- notice. Pages turn, nothing scrolls.
local ENEMY_ROWS = 6
local ENEMY_PERIODS = { { 0, "Toujours" }, { 30 * 86400, "30 jours" }, { 7 * 86400, "7 jours" } }
function R.GuildEnemies(period)
    local enemies, list = {}, {}
    local points = R.GuildLog({ view = "all", period = period or 0 })
    for _, point in ipairs(points) do
        local key = foeKey(point)
        if key and point.kind == "death" then
            local enemy = enemies[key]
            if not enemy then
                enemy = { key = key, target = point.target, name = point.name, deaths = 0, kills = 0, victims = {}, members = 0,
                    last = point.time, mapID = point.mapID }
                enemies[key] = enemy
                list[#list + 1] = enemy
            end
            enemy.deaths = enemy.deaths + 1
            if not enemy.victims[point.actor] then
                enemy.victims[point.actor] = true
                enemy.members = enemy.members + 1
            end
        end
    end
    for _, point in ipairs(points) do
        local enemy = point.kind == "kill" and enemies[foeKey(point) or ""]
        if enemy then enemy.kills = enemy.kills + 1 end
    end
    table.sort(list, function(a, b)
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        if a.last ~= b.last then return a.last > b.last end
        return a.key < b.key
    end)
    return list
end
local function buildEnemies(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(540), 13, false, UI.theme.inkMuted)
    page.period, page.offset = 1, 0
    page.viewCycle = UI.button(page, "", X(26), -72, S(196), function()
        page.period, page.offset = page.period % #ENEMY_PERIODS + 1, 0
        R.Refresh()
    end)
    page.rows = {}
    for i = 1, ENEMY_ROWS do
        local row = CreateFrame("Button", nil, page)
        row:SetPoint("TOPLEFT", X(26), -108 - (i - 1) * 56)
        row:SetSize(S(540), 54)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
        row.deaths = Panels.Text(row, S(0), -10, S(30), 20, true, { 0.55, 0.12, 0.12 })
        row.deaths:SetJustifyH("RIGHT")
        row.story = Panels.Text(row, S(40), -7, S(332), 15, true)
        GL.Safe(row.story.SetWordWrap, row.story, false)
        row.where = Panels.Text(row, S(40), -29, S(332), 12, false, UI.theme.inkMuted)
        GL.Safe(row.where.SetWordWrap, row.where, false)
        row.wanted = UI.button(row, L("Rechercher"), S(380), -14, S(92), function() wanted(row) end, nil, true)
        row.sheet = UI.button(row, L("Fiche"), S(476), -14, S(64), function() openOpponent(row) end, nil, true)
        row:SetScript("OnClick", openOpponent)
        page.rows[i] = row
    end
    page.empty = Panels.Text(page, X(26), -124, S(540), 13, false, UI.theme.inkMuted)
    page.previous = UI.button(page, "‹", X(26), -464, S(40), function()
        page.offset = math.max(0, page.offset - ENEMY_ROWS)
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", X(526), -464, S(40), function()
        page.offset = page.offset + ENEMY_ROWS
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(76), -470, S(440), 12, false, UI.theme.inkMuted)
    page.count:SetJustifyH("CENTER")
    return page
end
local function paintEnemies(page)
    page.title:SetText(L("Ennemis de la guilde"))
    local sharing, inGuild = false, false
    if GL.GuildMap then sharing, inGuild = GL.GuildMap.Enabled() end
    local list = sharing and R.GuildEnemies(ENEMY_PERIODS[page.period][1]) or {}
    page.lead:SetText(sharing and L("Les joueurs qui tuent vos compagnons, les plus meurtriers d’abord.") or "")
    page.viewCycle:SetText(L("%s · %d"):format(L(ENEMY_PERIODS[page.period][2]), #list))
    UI.selectButton(page.viewCycle, page.period ~= 1)
    if sharing then page.viewCycle:Show() else page.viewCycle:Hide() end
    page.offset = math.min(page.offset, math.max(0, math.floor((#list - 1) / ENEMY_ROWS) * ENEMY_ROWS))
    for i, row in ipairs(page.rows) do
        local enemy = list[page.offset + i]
        if enemy then
            row.deaths:SetText(tostring(enemy.deaths))
            Panels.Fit(row.story, UI.plain(enemy.name or L("un joueur inconnu")), S(332), 15, 10, true)
            local parts = { enemy.members > 1 and L("%d membres tués"):format(enemy.members) or L("1 membre tué") }
            if enemy.kills > 0 then parts[#parts + 1] = L("vaincu %d fois par la guilde"):format(enemy.kills) end
            local info = mapInfo(enemy.mapID)
            parts[#parts + 1] = (info and type(info.name) == "string" and (UI.plain(info.name) .. ", ") or "") .. elapsed(enemy.last)
            row.where:SetText(table.concat(parts, " · "))
            row.target, row.enemy = enemy.target, enemy.name
            if enemy.target then row.sheet:Show() else row.sheet:Hide() end
            local open = enemy.target and GL.Bounties and GL.Bounties.OpenFor and GL.Bounties.OpenFor(enemy.target)
            if enemy.target and enemy.name and not open then row.wanted:Show() else row.wanted:Hide() end
            row:Show()
        else
            row.target, row.enemy = nil, nil
            row:Hide()
        end
    end
    local empty = ""
    if not inGuild then
        empty = L("Vous n’êtes dans aucune guilde : cette page dit qui tue les membres de la vôtre.")
    elseif not sharing then
        empty = L("La vision de guilde est décochée. Cochez-la à gauche pour voir cette page.")
    elseif #list == 0 then
        empty = L("Aucun membre de la guilde n’a été tué sur cette période.")
    end
    page.empty:SetText(empty)
    page.previous:SetEnabled(page.offset > 0)
    page.next:SetEnabled(page.offset + ENEMY_ROWS < #list)
    if #list > ENEMY_ROWS then
        page.previous:Show()
        page.next:Show()
    else
        page.previous:Hide()
        page.next:Hide()
    end
    page.count:SetText(#list > 0 and countForm(#list, "%d ennemi", "%d ennemis") or "")
end

-- The books: the narrow format of the player sheet. Left, the entries and the key figures. Right,
-- the page. Two books are built the same way (0.55.0): Relations (your own story: the Bilan, the
-- debts, the rivalries, the map, the rankings) and Guilde (the guild's journal, its enemies, the
-- other guilds), each with its tab at the top.
local TALLY_LINES = 6
local BOOKS = {
    relations = { frame = "GrudgeLedgerRelations", nav = "players",
        entries = { { "recap", "Bilan", "bilan" }, { "honor", "Tableaux détaillés", "tableaux-detailles" }, { "debts", "Dettes", "dettes" },
            { "rivals", "Rivalités", "rivalites" }, { "lands", "Carte", "carte" }, { "rankings", "Classements", "classements" } } },
    guild = { frame = "GrudgeLedgerGuild", nav = "guild",
        entries = { { "guildlog", "Journal de guilde" }, { "enemies", "Ennemis de la guilde" }, { "guilds", "Guildes" },
            { "members", "Membres actifs" } } },
}
-- The detailed tables live in UI.lua, next to the statistics they read; their figures go to the key
-- figures of the left column, repainted whenever a filter of the page changes.
local function buildHonor(host)
    local page = GL.BuildHonorPage(host)
    page.paintTally = function() if R.PaintTally then R.PaintTally(host:GetParent()) end end
    return page
end
local builders = { recap = function(host) return GL.Recap.BuildPage(host) end, honor = buildHonor, debts = buildDebts, rivals = buildRivals, lands = buildLands,
    rankings = buildRankings, guildlog = buildGuildJournal, enemies = buildEnemies, guilds = buildGuilds, members = buildMembers }
local painters = { recap = function(page) GL.Recap.PaintPage(page) end, honor = function() GL.PaintHonorPage() end,
    debts = paintDebts, rivals = paintRivals, lands = paintLands,
    rankings = paintRankings, guildlog = paintGuildJournal, enemies = paintEnemies, guilds = paintGuilds, members = paintMembers }
local pageBook = {}
for key, spec in pairs(BOOKS) do
    for _, entry in ipairs(spec.entries) do pageBook[entry[1]] = key end
end
R.books = {}
local function book(key)
    if R.books[key] then return R.books[key] end
    local spec = BOOKS[key]
    local f = UI.bookWindow(spec.frame, "Grudge Ledger", true)
    R.books[key] = f
    f.bookKey = key
    if key == "relations" then R.window = f else R.guildWindow = f end
    GL.SetupBookNavigation(f, spec.nav)
    f.tabs = {}
    for i, entry in ipairs(spec.entries) do
        local page = entry[1]
        local tab = UI.button(f, L(entry[2]), 38, -158 - (i - 1) * 36, 168, function()
            R.Open(page)
        end, true)
        tab:SetHeight(30)
        -- Each entry of Relations carries its icon (the owner's kit, 25/11): 18 units near the left
        -- edge; the label moves right just enough to clear it.
        if entry[3] then
            tab.icon = tab:CreateTexture(nil, "OVERLAY")
            tab.icon:SetTexture(GL.Art.EntryIcon .. entry[3])
            tab.icon:SetSize(18, 18)
            tab.icon:SetPoint("LEFT", 8, 0)
            if tab.caption then
                tab.caption:ClearAllPoints()
                tab.caption:SetPoint("CENTER", 10, 0)
                tab.caption:SetSize(168 - 48, 22)
            end
        end
        f.tabs[page] = tab
    end
    -- The guild's book carries the guild vision's box under its entries: sharing your fights is what
    -- fills its pages.
    local figuresTop = -424
    if key == "guild" then
        f.vision = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        f.vision:SetPoint("TOPLEFT", 36, -308)
        f.vision:SetSize(24, 24)
        f.visionLabel = Panels.Text(f, 64, -314, 142, 12, true, UI.theme.paper)
        f.vision:SetScript("OnClick", function(self)
            if GL.GuildMap then GL.GuildMap.Enable(self:GetChecked() and true or false) end
            R.Refresh()
        end)
        f.vision:SetScript("OnEnter", function(self)
            tip(self, L("Vision de guilde"), L("Cochée : vous voyez sur la carte les victoires et les morts des membres qui l’ont cochée, et ils voient "
                .. "les vôtres (la zone et l’endroit). Décochée : rien n’est envoyé, rien n’est gardé, et la guilde oublie vos combats."))
        end)
        f.vision:SetScript("OnLeave", hideTip)
        figuresTop = -366
    end
    -- The key figures, drawn like those of the player sheet's left column: a caption, then one
    -- line each, the name on the left and the number on the right. Each line opens its page.
    f.keyHeading = Panels.Text(f, 40, figuresTop, 166, 12, true, UI.theme.brass)
    f.tally = {}
    for i = 1, TALLY_LINES do
        local cell = CreateFrame("Button", nil, f)
        cell:SetPoint("TOPLEFT", 40, figuresTop - 20 - (i - 1) * 22)
        cell:SetSize(166, 20)
        cell.label = UI.label(cell, "", nil, 0, -3, 126)
        GL.Safe(cell.label.SetWordWrap, cell.label, false)
        UI.journalFont(cell.label, "GameFontHighlight", 11)
        cell.label:SetTextColor(unpack(UI.theme.brass))
        cell.value = UI.label(cell, "", nil, 122, 0, 44)
        UI.journalFont(cell.value, "GameFontNormalLarge", 13)
        cell.value:SetJustifyH("RIGHT")
        -- Large print grows the figure: its box takes the whole line.
        cell.value:SetHeight(20)
        GL.Safe(cell.value.SetJustifyV, cell.value, "MIDDLE")
        local rule = cell:CreateTexture(nil, "BACKGROUND")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetSize(166, 1)
        rule:SetColorTexture(0.55, 0.40, 0.20, 0.30)
        local hover = cell:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.91, 0.77, 0.48, 0.10)
        cell:SetScript("OnClick", function(self)
            if type(self.page) == "function" then self.page() elseif self.page then R.Open(self.page) end
        end)
        f.tally[i] = cell
    end
    -- The map's legend, under the key figures while the map shows (owner's mockup, 25/11): what the
    -- colours of the zones and the marks of the guild mean.
    if key == "relations" then
        f.legend = CreateFrame("Frame", nil, f)
        f.legend:SetSize(166, 100)
        f.legend.heading = Panels.Text(f.legend, 0, 0, 166, 12, true, UI.theme.brass)
        local rule = f.legend:CreateTexture(nil, "BACKGROUND")
        rule:SetPoint("TOPLEFT", 0, -18)
        rule:SetSize(166, 1)
        rule:SetColorTexture(0.55, 0.40, 0.20, 0.30)
        f.legend.lines = {}
        -- The marks of the map, in their colours: your skull red, your sword green, the guild's
        -- skull yellow and sword blue (owner report 25/11: squares said nothing).
        local kinds = { { texture = SKULL, color = { 1, 0.35, 0.3 } }, { texture = SWORD, color = { 0.5, 1, 0.5 } },
            { texture = SKULL, color = { 1, 0.72, 0.25 } }, { texture = SWORD, color = { 0.55, 0.8, 1 } } }
        for i, kind in ipairs(kinds) do
            local line = CreateFrame("Frame", nil, f.legend)
            line:SetPoint("TOPLEFT", 0, -26 - (i - 1) * 22)
            line:SetSize(166, 20)
            line.mark = line:CreateTexture(nil, "ARTWORK")
            line.mark:SetTexture(kind.texture)
            line.mark:SetSize(18, 18)
            line.mark:SetPoint("LEFT", 0, 0)
            line.mark:SetVertexColor(unpack(kind.color))
            line.label = UI.label(line, "", nil, 26, -3, 140)
            UI.journalFont(line.label, "GameFontHighlight", 12)
            line.label:SetTextColor(unpack(UI.theme.paper))
            f.legend.lines[i] = line
        end
        f.legend:Hide()
    end
    f.figuresTop = figuresTop
    local host = CreateFrame("Frame", nil, f)
    host:SetPoint("TOPLEFT", 240, -152)
    host:SetSize(SHEET_W, SHEET_H)
    host.pages = {}
    for _, entry in ipairs(spec.entries) do host.pages[entry[1]] = builders[entry[1]](host) end
    f.host = host
    return f
end
-- How many members heard this session run your version or a newer one (0.58.0).
local function versionLine()
    local current, total = 0, 0
    if GL.GuildMap and GL.GuildMap.Versions then current, total = GL.GuildMap.Versions() end
    if total == 0 then return nil end
    return { L("Versions à jour"), current .. "/" .. total, "members" }
end
-- How many players of the guild were heard with the addon this session, you included (0.61.0):
-- three characters of the same player count once.
local function playersLine()
    if not (GL.GuildMap and GL.GuildMap.Players) then return nil end
    local count, characters = GL.GuildMap.Players()
    if characters <= 1 then return nil end
    return { L("Joueurs avec l’addon"), count, "members" }
end
-- The key figures of a book's left column, each with the page it opens. Relations: what is owed,
-- the debts and the rivalries. Guilde: the guild's week, when it shares its fights.
function R.Tally(key)
    if key == "guild" then
        if not (GL.GuildMap and GL.GuildMap.Enabled()) then return {} end
        local week = 7 * 86400
        local members = {}
        local sharing = 0
        for _, point in ipairs(R.GuildLog({ view = "all" })) do
            if not members[point.actor] then
                members[point.actor] = true
                sharing = sharing + 1
            end
        end
        return { { L("Morts · 7 j"), #R.GuildLog({ view = "death", period = week }), "guildlog" },
            { L("Victoires · 7 j"), #R.GuildLog({ view = "kill", period = week }), "guildlog" },
            { L("Ennemis · 7 j"), #R.GuildEnemies(week), "enemies" }, { L("Membres partageant"), sharing, "guildlog" },
            versionLine(), playersLine() }
    end
    local open, settled, total = R.Debts()
    return { { L("Reste dû"), total, "debts" }, { L("Dettes ouvertes"), #open, "debts" },
        { L("Réglées ce mois-ci"), #settled, "debts" }, { L("Rivalités"), #R.Rivals(), "rivals" } }
end
local function paintTally(f)
    local honor = f.page == "honor"
    local lines = honor and GL.HonorTally() or R.Tally(f.bookKey)
    f.keyHeading:SetText(#lines > 0 and L("Chiffres clés") or "")
    for i, cell in ipairs(f.tally) do
        local line = lines[i]
        if line then
            cell.label:SetText(line[1])
            cell.value:SetText(tostring(line[2]))
            -- What is owed reads in red, like the ledger's total.
            local owed = f.bookKey == "relations" and not honor and i == 1 and line[2] > 0
            if owed then cell.value:SetTextColor(0.85, 0.30, 0.25) else cell.value:SetTextColor(unpack(UI.theme.paper)) end
            cell.page = line[3]
            cell:Show()
        else
            cell:Hide()
        end
    end
end
local function paintLegend(f)
    local legend = f.legend
    if not legend then return end
    local page = f.host and f.host.pages and f.host.pages.lands
    local map = page and page.map
    if f.page ~= "lands" or not map or not map:IsShown() then
        legend:Hide()
        return
    end
    local shown = 0
    for _, cell in ipairs(f.tally) do if cell:IsShown() then shown = shown + 1 end end
    legend:ClearAllPoints()
    legend:SetPoint("TOPLEFT", 40, f.figuresTop - 20 - shown * 22 - 22)
    legend.heading:SetText(L("Légende"))
    local labels = { L("Vos morts"), L("Vos victoires"), L("Morts de la guilde"), L("Victoires de la guilde") }
    for i, line in ipairs(legend.lines) do
        line.label:SetText(labels[i])
        if i <= 2 or map.guildOn then line:Show() else line:Hide() end
    end
    legend:Show()
end
R.PaintLegend = paintLegend
R.PaintTally = paintTally
-- Opens a page in its book: Relations by default, Guilde for the guild's pages.
function R.Open(key)
    local bookKey = pageBook[key] or "relations"
    local f = book(bookKey)
    local first = BOOKS[bookKey].entries[1][1]
    f.page = pageBook[key] and key or f.page or first
    for pageKey, page in pairs(f.host.pages) do
        if pageKey == f.page then
            page:Show()
        else
            page:Hide()
        end
    end
    for tabKey, tab in pairs(f.tabs) do UI.selectButton(tab, tabKey == f.page) end
    R.page = f.page
    UI.paintStains(f, f.page)  -- each page keeps its own stains
    GL.ShowBookPage(f)
    R.Refresh()
    return f
end
function R.OpenGuild(key)
    return R.Open(pageBook[key] == "guild" and key or (R.guildWindow and R.guildWindow.page) or "guildlog")
end
-- Opens the rankings on the guild tab (from the crests) or where they were left.
function R.OpenRankings(guilds)
    local f = book("relations")
    local page = f.host.pages.rankings
    if guilds then page.group, page.choice, page.offset = #page.groups, 1, 0 end
    return R.Open("rankings")
end
function R.Refresh()
    for _, f in pairs(R.books) do
        if f:IsShown() and f.page then
            if f.vision then
                local sharing, inGuild = false, false
                if GL.GuildMap then sharing, inGuild = GL.GuildMap.Enabled() end
                GL.Safe(f.vision.SetChecked, f.vision, sharing)
                f.visionLabel:SetText(L("Vision de guilde"))
                if inGuild then
                    f.vision:Show()
                    f.visionLabel:Show()
                else
                    f.vision:Hide()
                    f.visionLabel:Hide()
                end
            end
            painters[f.page](f.host.pages[f.page])
            paintTally(f)
            R.PaintLegend(f)
        end
    end
end
GL.On("CHANGED", function() R.Refresh() end)
