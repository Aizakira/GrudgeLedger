-- Relations, told as a story: the overview ("Votre monde") and the ledger of debts. Both are drawn
-- over the right page of the Relations book. The fourteen rankings stay underneath, one click away.
-- Everything here comes from the journal alone: no Armory archive, no studio photo, no guild needed.
local GL = GrudgeLedger
local UI, Panels, L = GL.UITheme, GL.DossierPanels, GL.L
local R = {}
GL.RelationsPages = R

local WEEK, MONTH = 7 * 86400, 30 * 86400
local DEBT_ROWS = 6 -- lines of the ledger shown at once. The rest turns as pages, never a scroll bar
local media = "Interface\\AddOns\\GrudgeLedger\\Media\\"

local function players()
    return GL.db and GL.db.players or {}
end
local function name(record)
    return UI.plain(record.fullName or record.name or "?")
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
    page.title = Panels.Text(page, 26, -18, 540, 21, true)
    page.lead = Panels.Text(page, 26, -47, 540, 13, false, UI.theme.inkMuted)
    page.cards = { podiumCard(page, 26, 172), podiumCard(page, 210, 172), podiumCard(page, 394, 172) }
    page.weekTitle = Panels.Text(page, 26, -284, 262, 16, true, UI.theme.red)
    page.week = Panels.Text(page, 26, -308, 262, 13)
    page.week:SetHeight(120)
    GL.Safe(page.week.SetWordWrap, page.week, true)
    GL.Safe(page.week.SetJustifyV, page.week, "TOP")
    page.debtTitle = Panels.Text(page, 304, -284, 262, 16, true, UI.theme.red)
    page.debts = {}
    for i = 1, 3 do
        local row = CreateFrame("Button", nil, page)
        row:SetPoint("TOPLEFT", 304, -308 - (i - 1) * 34)
        row:SetSize(262, 32)
        row.name = Panels.Text(row, 0, -2, 206, 13, true)
        GL.Safe(row.name.SetWordWrap, row.name, false)
        row.nick = Panels.Text(row, 0, -17, 206, 11, false, UI.theme.inkMuted)
        GL.Safe(row.nick.SetWordWrap, row.nick, false)
        row.amount = Panels.Text(row, 208, -6, 54, 17, true, { 0.55, 0.12, 0.12 })
        row.amount:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self) openSheet(self.record) end)
        page.debts[i] = row
    end
    page.noDebt = Panels.Text(page, 304, -308, 262, 13, false, UI.theme.inkMuted)
    page.allDebts = Panels.Link(page, 304, -416, 262, function() GL.ShowRelations("debts") end)
    return page
end
local function paintOverview(page)
    page.title:SetText(L("Votre monde"))
    page.lead:SetText(L("Ceux qui comptent, en bien ou en mal. Un clic ouvre leur fiche."))
    local nemesisKey, companionKey = GL.Titles()
    local nemesis, companion, prey = nemesisKey and GL.Get(nemesisKey), companionKey and GL.Get(companionKey), R.Prey()
    fillCard(page.cards[1], L("Votre compagnon"), companion,
        companion and L("%d groupes ensemble"):format(tonumber(companion.groupCount) or 0), L("Trois groupes avec le même joueur."))
    fillCard(page.cards[2], L("Votre némésis"), nemesis,
        nemesis and L("Vous a tué %d fois · vous doit %d"):format(count(nemesis, "deaths"), GL.Debt(nemesis)), L("Deux morts face au même joueur."))
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
            Panels.Fit(row.name, name(record), 206, 13, 10, true)
            Panels.Fit(row.nick, nickname(record), 206, 11, 8)
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
    row:SetPoint("TOPLEFT", 26, -112 - (i - 1) * 58)
    row:SetSize(540, 56)
    local rule = row:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
    row.date = Panels.Text(row, 0, -8, 46, 12, false, UI.theme.inkMuted)
    row.name = Panels.Text(row, 50, -6, 290, 15, true)
    GL.Safe(row.name.SetWordWrap, row.name, false)
    row.detail = Panels.Text(row, 50, -28, 290, 12, false, UI.theme.inkMuted)
    GL.Safe(row.detail.SetWordWrap, row.detail, false)
    -- A settled debt is struck through with the pen.
    row.strike = row:CreateTexture(nil, "OVERLAY")
    row.strike:SetPoint("LEFT", row.name, "LEFT", -2, -1)
    row.strike:SetHeight(2)
    row.strike:SetColorTexture(0.42, 0.23, 0.12, 0.9)
    row.amount = Panels.Text(row, 344, -10, 56, 20, true)
    row.amount:SetJustifyH("RIGHT")
    row.state = Panels.Text(row, 410, -16, 130, 12, false, { 0.18, 0.37, 0.20 })
    row.state:SetJustifyH("RIGHT")
    row.bounty = UI.button(row, L("Prime"), 470, -13, 70, function()
        if row.record and row.record.guid and GL.OpenContactBounty then GL.OpenContactBounty(row.record.guid) end
    end, nil, true)
    row.sheet = UI.button(row, L("Fiche"), 410, -13, 56, function() openSheet(row.record) end, nil, true)
    row:SetScript("OnClick", function(self) openSheet(self.record) end)
    return row
end
local function buildDebts(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, 26, -18, 400, 21, true)
    page.lead = Panels.Text(page, 26, -47, 400, 13, false, UI.theme.inkMuted)
    page.totalCaption = Panels.Text(page, 436, -18, 130, 11, false, UI.theme.inkMuted)
    page.totalCaption:SetJustifyH("RIGHT")
    page.total = Panels.Text(page, 436, -32, 130, 26, true, { 0.55, 0.12, 0.12 })
    page.total:SetJustifyH("RIGHT")
    local band = page:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT", 26, -84)
    band:SetSize(540, 24)
    band:SetColorTexture(0.44, 0.28, 0.13, 0.18)
    page.columns = Panels.Text(page, 30, -89, 300, 12, false, UI.theme.inkMuted)
    page.columnDebt = Panels.Text(page, 370, -89, 56, 12, false, UI.theme.inkMuted)
    page.columnDebt:SetJustifyH("RIGHT")
    page.rows = {}
    for i = 1, DEBT_ROWS do page.rows[i] = debtRow(page, i) end
    page.empty = Panels.Text(page, 26, -130, 540, 13, false, UI.theme.inkMuted)
    page.offset = 0
    page.previous = UI.button(page, "‹", 26, -474, 40, function()
        page.offset = math.max(0, page.offset - DEBT_ROWS)
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", 526, -474, 40, function()
        page.offset = page.offset + DEBT_ROWS
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, 76, -480, 440, 12, false, UI.theme.inkMuted)
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
            Panels.Fit(row.name, name(record), 290, 15, 11, true)
            row.name:SetTextColor(unpack(line.settled and UI.theme.inkMuted or UI.theme.ink))
            if line.settled then
                row.strike:SetWidth(math.min(290, (GL.Safe(row.name.GetStringWidth, row.name) or 120) + 4))
                row.strike:Show()
                local zone = type(line.zone) == "string" and line.zone ~= "?" and line.zone
                row.detail:SetText(zone and L("Vengé le %s · %s"):format(day(line.at), UI.plain(zone)) or L("Vengé le %s"):format(day(line.at)))
                row.amount:SetText("")
                row.state:SetText(L("Réglée"))
                row.bounty:Hide()
                row.sheet:Hide()
            else
                row.strike:Hide()
                Panels.Fit(row.detail, debtDetail(record), 290, 12, 9)
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
    page.title = Panels.Text(page, 26, -18, 400, 21, true)
    page.lead = Panels.Text(page, 26, -47, 540, 13, false, UI.theme.inkMuted)
    local card = CreateFrame("Frame", nil, page)
    page.card = card
    card:SetPoint("TOPLEFT", 26, -76)
    card:SetSize(540, 150)
    UI.surface(card, { 0.79, 0.66, 0.42 })
    UI.surface(card, { 0.96, 0.91, 0.78 }, 1, 1)
    page.you = Panels.Text(card, 14, -18, 150, 17, true)
    page.yours = Panels.Text(card, 14, -42, 150, 12, false, UI.theme.inkMuted)
    page.score = Panels.Text(card, 170, -10, 200, 30, true)
    page.score:SetJustifyH("CENTER")
    page.scoreCaption = Panels.Text(card, 170, -50, 200, 11, false, UI.theme.inkMuted)
    page.scoreCaption:SetJustifyH("CENTER")
    page.face = face(card, 56)
    page.face:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -12)
    page.name = Panels.Text(card, 300, -14, 166, 15, true)
    page.name:SetJustifyH("RIGHT")
    GL.Safe(page.name.SetWordWrap, page.name, false)
    page.nick = Panels.Text(card, 300, -34, 166, 11, false, UI.theme.red)
    page.nick:SetJustifyH("RIGHT")
    GL.Safe(page.nick.SetWordWrap, page.nick, false)
    page.identity = Panels.Text(card, 300, -50, 166, 11, false, UI.theme.inkMuted)
    page.identity:SetJustifyH("RIGHT")
    GL.Safe(page.identity.SetWordWrap, page.identity, false)
    page.bar = Panels.Bar(card, 512)
    page.bar:SetPoint("TOPLEFT", 14, -84)
    page.bar:SetHeight(10)
    page.facts = {}
    for i = 1, 3 do
        local fact = Panels.Text(card, 14 + (i - 1) * 172, -108, 168, 12)
        fact:SetJustifyH(i == 1 and "LEFT" or i == 2 and "CENTER" or "RIGHT")
        GL.Safe(fact.SetWordWrap, fact, false)
        page.facts[i] = fact
    end
    page.threadTitle = Panels.Text(page, 26, -244, 400, 16, true, UI.theme.red)
    local line = page:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", 60, -283)
    line:SetSize(472, 2)
    line:SetColorTexture(0.52, 0.38, 0.20, 0.6)
    page.steps = {}
    for i = 1, RIVAL_STEPS do
        local step = CreateFrame("Frame", nil, page)
        step:SetPoint("TOPLEFT", 26 + (i - 1) * 108, -274)
        step:SetSize(104, 120)
        step.dot = step:CreateTexture(nil, "ARTWORK")
        step.dot:SetSize(18, 18)
        step.dot:SetPoint("TOP", step, "TOP", 0, 0)
        step.date = centered(step, -24, 104, 12, true)
        step.story = centered(step, -42, 104, 11, false, UI.theme.inkMuted)
        step.story:SetHeight(64)
        GL.Safe(step.story.SetWordWrap, step.story, true)
        GL.Safe(step.story.SetJustifyV, step.story, "TOP")
        page.steps[i] = step
    end
    page.empty = Panels.Text(page, 26, -86, 540, 13, false, UI.theme.inkMuted)
    page.index = 1
    page.bounty = UI.button(page, L("Poser une prime"), 26, -474, 150, function()
        if page.record and page.record.guid and GL.OpenContactBounty then GL.OpenContactBounty(page.record.guid) end
    end, nil, true)
    page.sheet = UI.button(page, L("Ouvrir sa fiche"), 182, -474, 140, function() openSheet(page.record) end, nil, true)
    page.previous = UI.button(page, "‹", 440, -474, 40, function()
        page.index = page.index - 1
        R.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", 526, -474, 40, function()
        page.index = page.index + 1
        R.Refresh()
    end, nil, true)
    page.count = Panels.Text(page, 480, -480, 46, 12, false, UI.theme.inkMuted)
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
    Panels.Fit(page.name, name(record), 166, 15, 10, true)
    Panels.Fit(page.nick, nickname(record), 166, 11, 8)
    local identity = {}
    if record.className then identity[#identity + 1] = UI.plain(record.className) end
    if record.guild then identity[#identity + 1] = UI.plain(record.guild) end
    Panels.Fit(page.identity, table.concat(identity, " · "), 166, 11, 8)
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
            -- "En guerre" is your own word (a guild rule); without a rule the facts only say hostile or friendly.
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
local function buildGuilds(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.title = Panels.Text(page, 26, -18, 400, 21, true)
    page.lead = Panels.Text(page, 26, -47, 540, 13, false, UI.theme.inkMuted)
    page.cards = {}
    for i = 1, CRESTS do
        local card = CreateFrame("Button", nil, page)
        card:SetPoint("TOPLEFT", 26 + ((i - 1) % 2) * 274, -80 - math.floor((i - 1) / 2) * 124)
        card:SetSize(266, 116)
        UI.surface(card, { 0.79, 0.66, 0.42 })
        UI.surface(card, { 0.96, 0.91, 0.78 }, 1, 1)
        card.crestRim = card:CreateTexture(nil, "ARTWORK")
        card.crestRim:SetPoint("TOPLEFT", 12, -14)
        card.crestRim:SetSize(44, 54)
        card.crestRim:SetColorTexture(0.52, 0.38, 0.20)
        card.crest = card:CreateTexture(nil, "OVERLAY")
        card.crest:SetPoint("TOPLEFT", 14, -16)
        card.crest:SetSize(40, 50)
        card.name = Panels.Text(card, 66, -12, 190, 15, true)
        GL.Safe(card.name.SetWordWrap, card.name, false)
        card.stance = Panels.Text(card, 66, -33, 190, 12, true, UI.theme.red)
        card.lines = Panels.Text(card, 66, -52, 190, 11, false, UI.theme.inkMuted)
        card.lines:SetHeight(54)
        GL.Safe(card.lines.SetWordWrap, card.lines, true)
        GL.Safe(card.lines.SetJustifyV, card.lines, "TOP")
        card:SetScript("OnClick", function() GL.ShowStatistics("guilds") end)
        page.cards[i] = card
    end
    page.empty = Panels.Text(page, 26, -86, 540, 13, false, UI.theme.inkMuted)
    page.all = Panels.Link(page, 304, -474, 262, function() GL.ShowStatistics("guilds") end)
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
            Panels.Fit(card.name, UI.plain(row.name), 190, 15, 10, true)
            card.crest:SetColorTexture(unpack(crestColors[entry.stance] or crestColors.neutral))
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
    page.title = Panels.Text(page, 26, -18, 400, 21, true)
    page.lead = Panels.Text(page, 26, -47, 540, 13, false, UI.theme.inkMuted)
    page.rows = {}
    for i = 1, LAND_ROWS do
        local row = CreateFrame("Frame", nil, page)
        row:SetPoint("TOPLEFT", 26, -84 - (i - 1) * 46)
        row:SetSize(540, 44)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
        row.zone = Panels.Text(row, 0, -5, 200, 14, true)
        GL.Safe(row.zone.SetWordWrap, row.zone, false)
        row.who = Panels.Text(row, 0, -24, 330, 11, false, UI.theme.inkMuted)
        GL.Safe(row.who.SetWordWrap, row.who, false)
        row.track = row:CreateTexture(nil, "BORDER")
        row.track:SetPoint("TOPLEFT", 210, -10)
        row.track:SetSize(200, 8)
        row.track:SetColorTexture(0.85, 0.75, 0.55)
        row.fill = row:CreateTexture(nil, "ARTWORK")
        row.fill:SetPoint("TOPLEFT", 210, -10)
        row.fill:SetHeight(8)
        row.fill:SetColorTexture(0.55, 0.12, 0.12)
        row.counts = Panels.Text(row, 420, -6, 120, 12, true)
        row.counts:SetJustifyH("RIGHT")
        page.rows[i] = row
    end
    page.empty = Panels.Text(page, 26, -86, 540, 13, false, UI.theme.inkMuted)
    page.note = Panels.Text(page, 26, -480, 540, 11, false, UI.theme.inkMuted)
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
            Panels.Fit(row.zone, UI.plain(entry.zone), 200, 14, 10, true)
            Panels.Fit(row.who, killers(entry), 330, 11, 8)
            row.fill:SetWidth(math.max(0.01, 200 * entry.deaths / worst))
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

-- The host covers the right page of the Relations book with the same parchment.
local function hostFor(book)
    if book.storyHost then return book.storyHost end
    local host = CreateFrame("Frame", nil, book)
    host:SetPoint("TOPLEFT", 345, -145)
    host:SetSize(593, 525)
    host:EnableMouse(true)
    if host.SetFrameLevel and book.GetFrameLevel then host:SetFrameLevel(book:GetFrameLevel() + 20) end
    local sheet = host:CreateTexture(nil, "BACKGROUND")
    sheet:SetAllPoints()
    sheet:SetTexture(media .. "JournalBookSurface")
    sheet:SetTexCoord(345 / 960, 938 / 960, 145 / 700, 670 / 700)
    host.pages = { overview = buildOverview(host), debts = buildDebts(host), rivals = buildRivals(host),
        guilds = buildGuilds(host), lands = buildLands(host) }
    book.storyHost = host
    return host
end
function R.Show(book, key)
    local host = hostFor(book)
    R.book, R.page = book, host.pages[key] and key or "overview"
    for pageKey, page in pairs(host.pages) do
        if pageKey == R.page then
            page:Show()
        else
            page:Hide()
        end
    end
    host:Show()
    R.Refresh()
end
function R.Hide(book)
    if book.storyHost then book.storyHost:Hide() end
    if R.book == book then R.page = nil end
end
function R.Refresh()
    local host = R.book and R.book.storyHost
    if not host or not R.page or not host:IsShown() then return end
    local painters = { overview = paintOverview, debts = paintDebts, rivals = paintRivals, guilds = paintGuilds, lands = paintLands }
    painters[R.page](host.pages[R.page])
end
GL.On("CHANGED", function() R.Refresh() end)
