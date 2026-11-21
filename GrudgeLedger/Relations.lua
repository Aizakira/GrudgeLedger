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
    host.pages = { overview = buildOverview(host), debts = buildDebts(host) }
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
    if R.page == "debts" then paintDebts(host.pages.debts) else paintOverview(host.pages.overview) end
end
GL.On("CHANGED", function() R.Refresh() end)
