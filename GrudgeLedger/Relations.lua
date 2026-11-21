-- Relations, told as a story, in its own book with the sheet's format: a narrow left column with
-- the six entries, the page on the whole sheet. The fourteen rankings are the sixth entry.
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

-- What happened in the last seven days, as short sentences.
function R.Week()
    local now, lines = GL.Now(), {}
    local enemies, worst, assists = 0, nil, 0
    for _, record in pairs(players()) do
        if type(record.firstSeen) == "number" and now - record.firstSeen <= WEEK and GL.Relation(record) == "enemy" then
            enemies = enemies + 1
            if not worst or count(record, "deaths") > count(worst, "deaths") then worst = record end
        end
        for _, e in ipairs(record.history or {}) do
            if type(e) == "table" and e.kind == "assist" and type(e.time) == "number" and now - e.time <= WEEK then
                assists = assists + 1
            end
        end
    end
    if enemies == 1 then
        lines[#lines + 1] = L("1 nouvel ennemi : %s."):format(name(worst))
    elseif enemies > 1 then
        lines[#lines + 1] = L("%d nouveaux ennemis, dont %s."):format(enemies, name(worst))
    end
    local _, settled = R.Debts()
    local paid = 0
    for _, entry in ipairs(settled) do
        if now - entry.at <= WEEK then paid = paid + 1 end
    end
    if paid == 1 then
        lines[#lines + 1] = L("1 dette réglée.")
    elseif paid > 1 then
        lines[#lines + 1] = L("%d dettes réglées."):format(paid)
    end
    if assists == 1 then
        lines[#lines + 1] = L("1 coup de main.")
    elseif assists > 1 then
        lines[#lines + 1] = L("%d coups de main."):format(assists)
    end
    if #lines == 0 then lines[1] = L("Rien de notable ces sept derniers jours.") end
    return lines
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
-- One of the three portraits of the overview: who, the nickname, one sentence.
local function podiumCard(parent, x, width)
    local card = CreateFrame("Button", nil, parent)
    card:SetPoint("TOPLEFT", x, -78)
    card:SetSize(width, 188)
    UI.surface(card, { 0.79, 0.66, 0.42 })
    UI.surface(card, { 0.96, 0.91, 0.78 }, 1, 1)
    card.caption = centered(card, -8, width, 11, false, UI.theme.inkMuted)
    card.face = face(card, 72)
    card.face:SetPoint("TOP", card, "TOP", 0, -28)
    card.name = centered(card, -106, width, 15, true)
    card.nick = centered(card, -127, width, 11, false, UI.theme.red)
    card.line = centered(card, -146, width, 11, false, UI.theme.inkMuted)
    card.line:SetHeight(34)
    GL.Safe(card.line.SetWordWrap, card.line, true)
    card:SetScript("OnClick", function(self) openSheet(self.record) end)
    return card
end
local function fillCard(card, caption, record, line, empty)
    card.record = record
    card.caption:SetText(caption)
    if record then
        card.face:Show()
        GL.PaintBookPortrait(card.face, record)
        Panels.Fit(card.name, name(record), card:GetWidth() - 16, 15, 10, true)
        Panels.Fit(card.nick, nickname(record), card:GetWidth() - 16, 11, 8)
        card.line:SetText(line)
    else
        card.face:Hide()
        Panels.Fit(card.name, L("Personne pour l’instant"), card:GetWidth() - 16, 15, 10, true)
        card.nick:SetText("")
        card.line:SetText(empty)
    end
end

local function buildOverview(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(540), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(540), 13, false, UI.theme.inkMuted)
    page.cards = { podiumCard(page, X(26), S(172)), podiumCard(page, X(210), S(172)), podiumCard(page, X(394), S(172)) }
    page.weekTitle = Panels.Text(page, X(26), -284, S(262), 16, true, UI.theme.red)
    page.week = Panels.Text(page, X(26), -308, S(262), 13)
    page.week:SetHeight(120)
    GL.Safe(page.week.SetWordWrap, page.week, true)
    GL.Safe(page.week.SetJustifyV, page.week, "TOP")
    page.debtTitle = Panels.Text(page, X(304), -284, S(262), 16, true, UI.theme.red)
    page.debts = {}
    for i = 1, 3 do
        local row = CreateFrame("Button", nil, page)
        row:SetPoint("TOPLEFT", X(304), -308 - (i - 1) * 34)
        row:SetSize(S(262), 32)
        row.name = Panels.Text(row, S(0), -2, S(206), 13, true)
        GL.Safe(row.name.SetWordWrap, row.name, false)
        row.nick = Panels.Text(row, S(0), -17, S(206), 11, false, UI.theme.inkMuted)
        GL.Safe(row.nick.SetWordWrap, row.nick, false)
        row.amount = Panels.Text(row, S(208), -6, S(54), 17, true, { 0.55, 0.12, 0.12 })
        row.amount:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self) openSheet(self.record) end)
        page.debts[i] = row
    end
    page.noDebt = Panels.Text(page, X(304), -308, S(262), 13, false, UI.theme.inkMuted)
    page.allDebts = Panels.Link(page, X(304), -416, S(262), function() GL.ShowRelations("debts") end)
    return page
end
local function paintOverview(page)
    page.title:SetText(L("Votre monde"))
    page.lead:SetText(L("Ceux qui comptent, en bien ou en mal. Un clic ouvre leur fiche."))
    local nemesisKey, companionKey = GL.Titles()
    local nemesis, companion, prey = nemesisKey and GL.Get(nemesisKey), companionKey and GL.Get(companionKey), R.Prey()
    fillCard(page.cards[1], L("Votre compagnon"), companion,
        companion and L("%d groupes ensemble"):format(tonumber(companion.groupCount) or 0),
        L("Un ami avec qui vous groupez, ou trois groupes cette semaine."))
    fillCard(page.cards[2], L("Votre némésis"), nemesis,
        nemesis and L("Vous a tué %d fois · vous doit %d"):format(count(nemesis, "deaths"), GL.Debt(nemesis)),
        L("Trois morts récentes face au même joueur."))
    fillCard(page.cards[3], L("Votre proie favorite"), prey,
        prey and L("Vaincu %d fois, jamais l’inverse"):format(count(prey, "kills")), L("Trois victoires sans une seule mort."))
    page.weekTitle:SetText(L("Cette semaine"))
    page.week:SetText(table.concat(R.Week(), "\n"))
    page.debtTitle:SetText(L("À régler en premier"))
    local open = R.Debts()
    for i, row in ipairs(page.debts) do
        local record = open[i]
        row.record = record
        if record then
            Panels.Fit(row.name, name(record), S(206), 13, 10, true)
            Panels.Fit(row.nick, nickname(record), S(206), 11, 8)
            row.amount:SetText(tostring(GL.Debt(record)))
            row:Show()
        else
            row:Hide()
        end
    end
    page.noDebt:SetText(#open == 0 and L("Personne ne vous doit rien.") or "")
    page.allDebts:SetText(#open > 0 and L("Tout le registre (%d)"):format(#open) or "")
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
    page.previous = UI.button(page, "‹", X(26), -474, S(40), function()
        page.offset = math.max(0, page.offset - DEBT_ROWS)
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", X(526), -474, S(40), function()
        page.offset = page.offset + DEBT_ROWS
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(76), -480, S(440), 12, false, UI.theme.inkMuted)
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
                row.bounty:Show()
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
    page.count:SetText(L("%d dettes ouvertes · %d réglées ce mois-ci"):format(#open, #settled))
end

-- Rivalries: the players you fought most, one at a time, with the score and the dated thread.
local RIVAL_STEPS = 5 -- fights shown on the thread, the latest ones
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
local function openingShare(record)
    local total, his = 0, 0
    for _, e in ipairs(record.history or {}) do
        if type(e) == "table" and e.kind == "opening" and not e.voided then
            total = total + 1
            his = his + (e.opener == "opponent" and 1 or 0)
        end
    end
    return his, total
end
local function buildRivals(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(540), 13, false, UI.theme.inkMuted)
    local card = CreateFrame("Frame", nil, page)
    page.card = card
    card:SetPoint("TOPLEFT", X(26), -76)
    card:SetSize(S(540), 150)
    UI.surface(card, { 0.79, 0.66, 0.42 })
    UI.surface(card, { 0.96, 0.91, 0.78 }, 1, 1)
    page.you = Panels.Text(card, S(14), -18, S(150), 17, true)
    page.yours = Panels.Text(card, S(14), -42, S(150), 12, false, UI.theme.inkMuted)
    page.score = Panels.Text(card, S(170), -10, S(200), 30, true)
    page.score:SetJustifyH("CENTER")
    page.scoreCaption = Panels.Text(card, S(170), -50, S(200), 11, false, UI.theme.inkMuted)
    page.scoreCaption:SetJustifyH("CENTER")
    page.face = face(card, 56)
    page.face:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -12)
    page.name = Panels.Text(card, S(300), -14, S(166), 15, true)
    page.name:SetJustifyH("RIGHT")
    GL.Safe(page.name.SetWordWrap, page.name, false)
    page.nick = Panels.Text(card, S(300), -34, S(166), 11, false, UI.theme.red)
    page.nick:SetJustifyH("RIGHT")
    GL.Safe(page.nick.SetWordWrap, page.nick, false)
    page.identity = Panels.Text(card, S(300), -50, S(166), 11, false, UI.theme.inkMuted)
    page.identity:SetJustifyH("RIGHT")
    GL.Safe(page.identity.SetWordWrap, page.identity, false)
    page.bar = Panels.Bar(card, S(512))
    page.bar:SetPoint("TOPLEFT", S(14), -84)
    page.bar:SetHeight(10)
    page.facts = {}
    for i = 1, 3 do
        local fact = Panels.Text(card, S(14) + (i - 1) * S(172), -108, S(168), 12)
        fact:SetJustifyH(i == 1 and "LEFT" or i == 2 and "CENTER" or "RIGHT")
        GL.Safe(fact.SetWordWrap, fact, false)
        page.facts[i] = fact
    end
    page.threadTitle = Panels.Text(page, X(26), -244, S(400), 16, true, UI.theme.red)
    local line = page:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", X(60), -283)
    line:SetSize(S(472), 2)
    line:SetColorTexture(0.52, 0.38, 0.20, 0.6)
    page.steps = {}
    for i = 1, RIVAL_STEPS do
        local step = CreateFrame("Frame", nil, page)
        step:SetPoint("TOPLEFT", X(26) + (i - 1) * S(108), -274)
        step:SetSize(S(104), 120)
        step.dot = step:CreateTexture(nil, "ARTWORK")
        step.dot:SetSize(18, 18)
        step.dot:SetPoint("TOP", step, "TOP", 0, 0)
        step.date = centered(step, -24, S(104), 12, true)
        step.story = centered(step, -42, S(104), 11, false, UI.theme.inkMuted)
        step.story:SetHeight(64)
        GL.Safe(step.story.SetWordWrap, step.story, true)
        GL.Safe(step.story.SetJustifyV, step.story, "TOP")
        page.steps[i] = step
    end
    page.empty = Panels.Text(page, X(26), -86, S(540), 13, false, UI.theme.inkMuted)
    page.index = 1
    page.bounty = UI.button(page, L("Poser une prime"), X(26), -474, S(150), function()
        if page.record and page.record.guid and GL.OpenContactBounty then GL.OpenContactBounty(page.record.guid) end
    end, nil, true)
    page.sheet = UI.button(page, L("Ouvrir sa fiche"), X(182), -474, S(140), function() openSheet(page.record) end, nil, true)
    page.previous = UI.button(page, "‹", X(440), -474, S(40), function()
        page.index = page.index - 1
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", X(526), -474, S(40), function()
        page.index = page.index + 1
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(480), -480, S(46), 12, false, UI.theme.inkMuted)
    page.count:SetJustifyH("CENTER")
    return page
end
local function paintRivals(page)
    page.title:SetText(L("Rivalités"))
    local rivals = R.Rivals()
    page.index = math.max(1, math.min(page.index, #rivals))
    local rival = rivals[page.index]
    local record = rival and rival.record
    page.record = record
    for _, region in ipairs({ page.card, page.threadTitle, page.bounty, page.sheet, page.previous, page.next, page.count }) do
        if record then region:Show() else region:Hide() end
    end
    page.empty:SetText(record and "" or L("Aucune rivalité pour l’instant. Il en faut deux combats terminés contre le même joueur."))
    page.lead:SetText(record and L("Vos adversaires les plus tenaces, un par un.") or "")
    for _, step in ipairs(page.steps) do step:Hide() end
    if not record then return end
    local kills, deaths = count(record, "kills"), count(record, "deaths")
    page.you:SetText(L("Vous"))
    local mine = GL.Safe(UnitClass, "player")
    page.yours:SetText(type(mine) == "string" and UI.plain(mine) or "")
    page.score:SetText(("|cff2e5e33%d|r – |cff8b1e1e%d|r"):format(kills, deaths))
    page.scoreCaption:SetText(L("victoires · morts"))
    GL.PaintBookPortrait(page.face, record)
    Panels.Fit(page.name, name(record), S(166), 15, 10, true)
    Panels.Fit(page.nick, nickname(record), S(166), 11, 8)
    local identity = {}
    if record.className then identity[#identity + 1] = UI.plain(record.className) end
    if record.guild then identity[#identity + 1] = UI.plain(record.guild) end
    Panels.Fit(page.identity, table.concat(identity, " · "), S(166), 11, 8)
    page.bar:Set(kills, deaths)
    local his, openings = openingShare(record)
    page.facts[1]:SetText(openings >= 2 and L("Il ouvre le combat %d fois sur %d"):format(his, openings) or "")
    local debt = GL.Debt(record)
    page.facts[2]:SetText(debt > 0 and L("Il vous doit encore %d"):format(debt) or L("Comptes réglés"))
    local fights = GL.Fights(record)
    page.facts[3]:SetText(fights[1] and L("Dernier combat le %s"):format(day(fights[1].last or fights[1].at)) or "")
    page.threadTitle:SetText(L("Le fil de la rivalité"))
    local shown = math.min(RIVAL_STEPS, #fights)
    for i = 1, shown do
        local fight, step = fights[shown - i + 1], page.steps[i]
        if fight.deaths > 0 then
            step.dot:SetColorTexture(0.55, 0.12, 0.12)
        elseif fight.kills > 0 then
            step.dot:SetColorTexture(0.18, 0.37, 0.20)
        else
            step.dot:SetColorTexture(0.42, 0.29, 0.08)
        end
        step.date:SetText(day(fight.at))
        local zone = fight.main and type(fight.main.zone) == "string" and fight.main.zone ~= "?" and fight.main.zone
        step.story:SetText(GL.FightTitle(fight) .. (zone and ("\n" .. UI.plain(zone)) or ""))
        step:Show()
    end
    page.previous:SetEnabled(page.index > 1)
    page.next:SetEnabled(page.index < #rivals)
    page.count:SetText(("%d / %d"):format(page.index, #rivals))
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
    page.all = Panels.Link(page, X(304), -474, S(262), function() R.OpenRankings(true) end)
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
            if (row.grudges or 0) > 0 then lines[#lines + 1] = L("%d membres vous doivent quelque chose"):format(row.grudges) end
            if (row.deaths or 0) + (row.aggressions or 0) > 0 then
                lines[#lines + 1] = L("%d morts · %d agressions"):format(row.deaths or 0, row.aggressions or 0)
            end
            if (row.kills or 0) > 0 then lines[#lines + 1] = L("Vaincue %d fois"):format(row.kills) end
            if (row.friends or 0) > 0 then lines[#lines + 1] = L("%d amis parmi eux"):format(row.friends) end
            card.lines:SetText(table.concat(lines, "\n"))
            card:Show()
        else
            card:Hide()
        end
    end
    page.empty:SetText(#guilds == 0 and L("Aucune guilde ne pèse encore dans votre livre.") or "")
    page.all:SetText(#guilds > 0 and L("Tous les classements de guildes") or "")
end

-- Dangerous lands: where you die, zone by zone, and to whom. A list today, the world map later.
local LAND_ROWS = 8
function R.Lands()
    local zones, list = {}, {}
    for _, record in pairs(players()) do
        for _, e in ipairs(record.history or {}) do
            local zone = type(e) == "table" and not e.voided and e.voidReason ~= "battleground" and type(e.zone) == "string" and e.zone
            if zone and zone ~= "" and zone ~= "?" and (e.kind == "death" or e.kind == "kill") then
                local entry = zones[zone]
                if not entry then
                    entry = { zone = zone, deaths = 0, kills = 0, killers = {} }
                    zones[zone] = entry
                    list[#list + 1] = entry
                end
                if e.kind == "death" then
                    entry.deaths = entry.deaths + 1
                    entry.killers[record] = (entry.killers[record] or 0) + 1
                else
                    entry.kills = entry.kills + 1
                end
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
local function buildLands(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, X(26), -18, S(400), 21, true)
    page.lead = Panels.Text(page, X(26), -47, S(540), 13, false, UI.theme.inkMuted)
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
    page.note = Panels.Text(page, X(26), -480, S(540), 11, false, UI.theme.inkMuted)
    return page
end
local function paintLands(page)
    page.title:SetText(L("Terres dangereuses"))
    local lands = R.Lands()
    page.lead:SetText(#lands > 0 and L("Où vous mourez, et à cause de qui.") or "")
    local worst = lands[1] and math.max(1, lands[1].deaths) or 1
    for i, row in ipairs(page.rows) do
        local entry = lands[i]
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
    page.empty:SetText(#lands == 0 and L("Aucun combat terminé pour l’instant : cette page se remplit avec vos morts et vos victoires.") or "")
    page.note:SetText(#lands > LAND_ROWS and L("Les %d zones les plus meurtrières sur %d."):format(LAND_ROWS, #lands) or "")
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
    page.previous = UI.button(page, "‹", X(26), -474, S(40), function()
        page.offset = math.max(0, page.offset - RANK_ROWS)
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", X(526), -474, S(40), function()
        page.offset = page.offset + RANK_ROWS
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, X(76), -480, S(440), 12, false, UI.theme.inkMuted)
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

-- The book: the narrow format of the player sheet. Left, the six entries and a few figures. Right,
-- the page.
local entries = { { "overview", "Vue d’ensemble" }, { "debts", "Dettes" }, { "rivals", "Rivalités" }, { "guilds", "Guildes" },
    { "lands", "Terres" }, { "rankings", "Classements" } }
local function book()
    if R.window then return R.window end
    local f = UI.bookWindow("GrudgeLedgerRelations", "Grudge Ledger", true)
    R.window = f
    GL.SetupBookNavigation(f, "players")
    f.tabs = {}
    for i, entry in ipairs(entries) do
        local key = entry[1]
        local tab = UI.button(f, L(entry[2]), 38, -158 - (i - 1) * 36, 168, function()
            R.Open(key)
        end, true)
        tab:SetHeight(30)
        f.tabs[key] = tab
    end
    f.figures = Panels.Text(f, 40, -396, 164, 12, false, UI.theme.muted)
    f.figures:SetHeight(150)
    GL.Safe(f.figures.SetWordWrap, f.figures, true)
    GL.Safe(f.figures.SetJustifyV, f.figures, "TOP")
    local host = CreateFrame("Frame", nil, f)
    host:SetPoint("TOPLEFT", 240, -152)
    host:SetSize(SHEET_W, SHEET_H)
    host.pages = { overview = buildOverview(host), debts = buildDebts(host), rivals = buildRivals(host),
        guilds = buildGuilds(host), lands = buildLands(host), rankings = buildRankings(host) }
    f.host = host
    return f
end
-- The few figures of the left column: what is owed, how many debts and rivalries.
local function figures()
    local open, settled, total = R.Debts()
    local lines = { L("Reste dû : %d"):format(total), L("%d dettes ouvertes · %d réglées ce mois-ci"):format(#open, #settled) }
    local rivals = #R.Rivals()
    if rivals == 1 then
        lines[#lines + 1] = L("1 rivalité")
    elseif rivals > 1 then
        lines[#lines + 1] = L("%d rivalités"):format(rivals)
    end
    return table.concat(lines, "\n\n")
end
function R.Open(key)
    local f = book()
    R.page = f.host.pages[key] and key or "overview"
    for pageKey, page in pairs(f.host.pages) do
        if pageKey == R.page then
            page:Show()
        else
            page:Hide()
        end
    end
    for tabKey, tab in pairs(f.tabs) do UI.selectButton(tab, tabKey == R.page) end
    GL.ShowBookPage(f)
    R.Refresh()
    return f
end
-- Opens the rankings on the guild tab (from the crests) or where they were left.
function R.OpenRankings(guilds)
    local f = book()
    local page = f.host.pages.rankings
    if guilds then page.group, page.choice, page.offset = #page.groups, 1, 0 end
    return R.Open("rankings")
end
function R.Refresh()
    local f = R.window
    if not f or not R.page or not f:IsShown() then return end
    local painters = { overview = paintOverview, debts = paintDebts, rivals = paintRivals, guilds = paintGuilds, lands = paintLands,
        rankings = paintRankings }
    painters[R.page](f.host.pages[R.page])
    f.figures:SetText(figures())
end
GL.On("CHANGED", function() R.Refresh() end)
