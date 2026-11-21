-- The Bilan (0.53.0): your player's card, told in five pages you turn like stories. Who you are,
-- your numbers, your two people, your territory, your guild. One choice of period on the left,
-- nothing else to set. The detailed tables of the old Bilan stay one click away.
-- Journal data only: it works with the addon alone. The guild page needs the guild vision.
local GL = GrudgeLedger
local L = GL.L
local UI = GL.UITheme
local Panels = GL.DossierPanels
local R = {}
GL.Recap = R

local SHEET_W, SHEET_H = 664, 510
local CARDS = 5
local PERIODS = { { "week", L("Cette semaine") }, { "month", L("Ce mois-ci") }, { "year", L("Cette année") }, { "all", L("Depuis le début") } }
local SCOPES = { { "character", L("Ce personnage") }, { "all", L("Tout le compte") } }
local SCOPE_BUTTONS = { character = L("Personnage : celui-ci"), all = L("Personnages : tout le compte") }
local DAY = 86400

local function plain(text)
    return (UI.plain(text or ""))
end
local function centered(parent, y, size, bold, color, height)
    local text = Panels.Text(parent, 40, y, SHEET_W - 80, size, bold, color)
    text:SetJustifyH("CENTER")
    if height then
        text:SetHeight(height)
        GL.Safe(text.SetWordWrap, text, true)
        GL.Safe(text.SetJustifyV, text, "TOP")
    end
    return text
end
local function labelOf(choices, key)
    for _, choice in ipairs(choices) do
        if choice[1] == key then return choice[2] end
    end
    return ""
end
-- Seconds back from now for the chosen period, for the guild's fights (0: since the beginning).
local function periodSeconds(period)
    if period == "week" then return 7 * DAY end
    if period == "month" then return 30 * DAY end
    if period == "year" then
        local now = GL.Now()
        local start = type(time) == "function" and time({ year = tonumber(date("%Y", now)), month = 1, day = 1, hour = 0 })
        return math.max(1, now - (tonumber(start) or now - 365 * DAY))
    end
    return 0
end

-- What the cards say, worked out from the journal: the period's statistics, the zones, the
-- archetype. Exported for the tests and for the copied text.
function R.Facts(period, scope)
    local options = { period = period, year = tonumber(date("%Y", GL.Now())), scope = scope, kind = "pvp", query = "" }
    local stats = GL.PersonalStatistics(options)
    local zones = GL.PvPBreakdown(options, "zone")
    local facts = { stats = stats, kills = stats.kills or 0, deaths = stats.deaths or 0, honor = stats.honor or 0 }
    -- The zones where you die and where you win most. When both are the same place, the second is
    -- the next zone where you won, so the card never says the same name twice.
    for _, zone in ipairs(zones) do
        if zone.key ~= "unknown" and zone.key ~= "mixed" then
            if zone.deaths > 0 and (not facts.deadly or zone.deaths > facts.deadly.deaths) then facts.deadly = zone end
            if zone.kills > 0 and (not facts.home or zone.kills > facts.home.kills) then facts.home = zone end
        end
    end
    for _, zone in ipairs(zones) do
        if zone.key ~= "unknown" and zone.key ~= "mixed" and zone ~= facts.deadly and zone.kills > 0
            and (not facts.winning or zone.kills > facts.winning.kills) then
            facts.winning = zone
        end
    end
    local k, d = facts.kills, facts.deaths
    local opened, answered, revenge = stats.initiated or 0, stats.responded or 0, stats.revengeKills or 0
    -- The archetype: one word for the way you fought over the period.
    local archetype, sentence
    if k + d < 3 then
        archetype = L("Le Voyageur")
        sentence = L("Peu de combats sur cette période : vous traversez le monde sans faire de vagues.")
    elseif revenge >= 3 and revenge * 3 >= k then
        archetype = L("Le Vengeur")
        sentence = L("Vous n’oubliez rien : %d de vos victoires sont des revanches."):format(revenge)
    elseif k >= 2 * d and opened >= answered then
        archetype = L("Le Prédateur")
        sentence = L("Vous frappez le premier, et vous gagnez : %d victoires pour %d morts."):format(k, d)
    elseif k >= 2 * d then
        archetype = L("Le Rempart")
        sentence = L("On vous attaque, et vous tenez : %d victoires pour %d morts."):format(k, d)
    elseif d >= 2 * k then
        archetype = L("La Cible")
        sentence = L("On vous chasse : %d morts pour %d victoires. Les dettes s’accumulent."):format(d, k)
    else
        archetype = L("Le Duelliste")
        sentence = L("Combat après combat, l’équilibre : %d victoires, %d morts."):format(k, d)
    end
    facts.archetype, facts.sentence = archetype, sentence
    -- A title earned in one place: most of your victories in the same zone.
    if facts.home and facts.home.kills >= 3 and facts.home.kills * 5 >= k * 2 then
        facts.title = L("Le Fléau de %s"):format(plain(facts.home.label))
    end
    local details = {}
    if opened + answered > 0 then
        details[#details + 1] = L("Premier à frapper : %d fois sur %d"):format(opened, opened + answered)
    end
    if revenge == 1 then
        details[#details + 1] = L("1 revanche")
    elseif revenge > 1 then
        details[#details + 1] = L("%d revanches"):format(revenge)
    end
    if stats.aggressions == 1 then
        details[#details + 1] = L("1 agression sans issue")
    elseif (stats.aggressions or 0) > 1 then
        details[#details + 1] = L("%d agressions sans issue"):format(stats.aggressions)
    end
    facts.details = table.concat(details, " · ")
    if d == 0 and k > 0 then
        facts.ratio = L("Invaincu sur cette période.")
    elseif d > 0 then
        local comma = not GetLocale or GL.Safe(GetLocale) ~= "enUS" and GL.Safe(GetLocale) ~= "enGB"
        local ratio = ("%.1f"):format(k / d):gsub("%.", comma and "," or ".")
        facts.ratio = L("%s victoire par mort."):format(ratio)
    else
        facts.ratio = ""
    end
    -- The guild: your share of its victories, its deaths and its worst enemy over the period.
    local sharing = GL.GuildMap and GL.GuildMap.Enabled()
    if sharing and GL.RelationsPages and GL.RelationsPages.GuildLog then
        local guild = { kills = 0, deaths = 0, mine = 0, members = 0 }
        local members, enemies = {}, {}
        for _, point in ipairs(GL.RelationsPages.GuildLog({ view = "all", period = periodSeconds(period) })) do
            if not members[point.actor] then
                members[point.actor] = true
                guild.members = guild.members + 1
            end
            if point.kind == "kill" then
                guild.kills = guild.kills + 1
                if point.mine then guild.mine = guild.mine + 1 end
            else
                guild.deaths = guild.deaths + 1
                local key = point.target or (point.name and "name:" .. point.name)
                if key then
                    local enemy = enemies[key] or { name = point.name, target = point.target, deaths = 0 }
                    enemies[key] = enemy
                    enemy.deaths = enemy.deaths + 1
                    if not guild.enemy or enemy.deaths > guild.enemy.deaths then guild.enemy = enemy end
                end
            end
        end
        facts.guild = guild
    end
    return facts
end
-- The card as text, for a guild chat or a forum.
function R.Text(facts, period, who)
    local lines = { L("Grudge Ledger · Bilan · %s"):format(labelOf(PERIODS, period)),
        who .. " : " .. facts.archetype .. (facts.title and (" (" .. facts.title .. ")") or ""),
        L("%d victoires · %d morts · %d d’honneur"):format(facts.kills, facts.deaths, facts.honor) }
    local stats = facts.stats
    if stats.mostDeaths then
        lines[#lines + 1] = L("Némésis : %s (%d morts)"):format(plain(stats.mostDeaths.record.fullName), stats.mostDeaths.value)
    end
    if stats.mostKilled then
        lines[#lines + 1] = L("Proie favorite : %s (%d victoires)"):format(plain(stats.mostKilled.record.fullName), stats.mostKilled.value)
    end
    if facts.deadly then
        lines[#lines + 1] = L("Zone la plus dangereuse : %s (%d morts)"):format(plain(facts.deadly.label), facts.deadly.deaths)
    end
    return table.concat(lines, "\n")
end

-- The five cards.
local function buildWho(card)
    card.eyebrow = centered(card, -36, 13, false, UI.theme.inkMuted)
    card.name = centered(card, -62, 18, true)
    card.archetype = centered(card, -124, 34, true, { 0.55, 0.12, 0.12 })
    card.sentence = centered(card, -184, 15, false, nil, 60)
    card.title = centered(card, -264, 17, true, { 0.45, 0.30, 0.10 })
    card.details = centered(card, -320, 13, false, UI.theme.inkMuted, 40)
end
local function paintWho(card, facts, period, scope)
    card.eyebrow:SetText(labelOf(SCOPES, scope) .. " · " .. labelOf(PERIODS, period))
    card.name:SetText(plain(scope == "character" and facts.stats.actorName or L("Tous vos personnages")))
    card.archetype:SetText(facts.archetype)
    card.sentence:SetText(facts.sentence)
    card.title:SetText(facts.title and ("« " .. facts.title .. " »") or "")
    card.details:SetText(facts.details)
end
local function buildNumbers(card)
    card.heading = centered(card, -36, 21, true)
    card.values, card.captions = {}, {}
    for i = 1, 3 do
        local x = 40 + (i - 1) * 200
        card.values[i] = Panels.Text(card, x, -110, 196, 46, true)
        card.values[i]:SetJustifyH("CENTER")
        card.captions[i] = Panels.Text(card, x, -172, 196, 14, false, UI.theme.inkMuted)
        card.captions[i]:SetJustifyH("CENTER")
    end
    card.ratio = centered(card, -250, 17, true)
    card.extra = centered(card, -290, 13, false, UI.theme.inkMuted, 40)
end
local function paintNumbers(card, facts)
    card.heading:SetText(L("Vos chiffres"))
    local values = { facts.kills, facts.deaths, facts.honor }
    local captions = { L("Victoires"), L("Morts"), L("Honneur gagné") }
    local colors = { { 0.18, 0.37, 0.20 }, { 0.55, 0.12, 0.12 }, { 0.45, 0.30, 0.10 } }
    for i = 1, 3 do
        card.values[i]:SetText(tostring(values[i]))
        card.values[i]:SetTextColor(unpack(colors[i]))
        card.captions[i]:SetText(captions[i])
    end
    card.ratio:SetText(facts.ratio)
    card.extra:SetText(facts.details)
end
local function person(card, x)
    local box = CreateFrame("Button", nil, card)
    box:SetPoint("TOPLEFT", x, -86)
    box:SetSize(260, 230)
    box.face = CreateFrame("Frame", nil, box)
    box.face:SetSize(96, 96)
    box.face:SetPoint("TOP", box, "TOP", 0, 0)
    box.face.raceIcon = box.face:CreateTexture(nil, "ARTWORK")
    box.face.raceIcon:SetAllPoints()
    box.face.classIcon = box.face:CreateTexture(nil, "OVERLAY")
    box.face.classIcon:SetSize(22, 22)
    box.face.classIcon:SetPoint("BOTTOMRIGHT")
    box.tag = Panels.Text(box, 0, -108, 260, 13, true)
    box.tag:SetJustifyH("CENTER")
    box.name = Panels.Text(box, 0, -130, 260, 17, true)
    box.name:SetJustifyH("CENTER")
    GL.Safe(box.name.SetWordWrap, box.name, false)
    box.line = Panels.Text(box, 0, -156, 260, 13, false, UI.theme.inkMuted)
    box.line:SetJustifyH("CENTER")
    box:SetScript("OnClick", function(self)
        if self.record and GL.ShowLedger then GL.ShowLedger(self.record.key) end
    end)
    return box
end
local function buildPeople(card)
    card.heading = centered(card, -36, 21, true)
    card.people = { person(card, 64), person(card, 352) }
end
local function paintPeople(card, facts)
    card.heading:SetText(L("Vos deux personnes"))
    local stats = facts.stats
    local entries = {
        { stats.mostDeaths, L("Votre némésis"), { 0.55, 0.12, 0.12 }, L("Vous a tué %d fois"), L("Personne ne vous a tué sur cette période.") },
        { stats.mostKilled, L("Votre proie favorite"), { 0.18, 0.37, 0.20 }, L("Vaincu %d fois"), L("Aucune victoire sur cette période.") },
    }
    for i, box in ipairs(card.people) do
        local entry = entries[i]
        local item = entry[1]
        box.record = item and item.record
        box.tag:SetText(entry[2])
        box.tag:SetTextColor(unpack(entry[3]))
        if item then
            box.name:SetText(plain(item.record.fullName))
            box.line:SetText(entry[4]:format(item.value))
            box.face:Show()
            if GL.PaintBookPortrait then GL.PaintBookPortrait(box.face, item.record) end
        else
            box.name:SetText("")
            box.line:SetText(entry[5])
            box.face:Hide()
        end
    end
end
local function buildTerritory(card)
    card.heading = centered(card, -36, 21, true)
    card.deadlyCaption = centered(card, -96, 13, false, UI.theme.inkMuted)
    card.deadly = centered(card, -120, 30, true, { 0.55, 0.12, 0.12 })
    card.deadlyCounts = centered(card, -162, 14)
    card.winningCaption = centered(card, -226, 13, false, UI.theme.inkMuted)
    card.winning = centered(card, -250, 24, true, { 0.18, 0.37, 0.20 })
    card.winningCounts = centered(card, -286, 14)
    card.map = UI.button(card, L("Voir sur la carte"), (SHEET_W - 220) / 2, -360, 220, function()
        if GL.ShowRelations then GL.ShowRelations("lands") end
    end, nil, true)
end
local function paintTerritory(card, facts)
    card.heading:SetText(L("Votre territoire"))
    local deadly, winning = facts.deadly, facts.winning
    card.deadlyCaption:SetText(L("Là où vous mourez le plus"))
    card.deadly:SetText(deadly and plain(deadly.label) or L("Nulle part"))
    card.deadlyCounts:SetText(deadly and L("%d morts · %d victoires"):format(deadly.deaths, deadly.kills) or "")
    card.winningCaption:SetText(L("Là où vous gagnez le plus"))
    card.winning:SetText(winning and plain(winning.label) or L("Nulle part ailleurs"))
    card.winningCounts:SetText(winning and L("%d victoires · %d morts"):format(winning.kills, winning.deaths) or "")
    if C_Map and (deadly or winning) then card.map:Show() else card.map:Hide() end
end
local function buildGuild(card)
    card.heading = centered(card, -36, 21, true)
    card.share = centered(card, -100, 46, true, { 0.45, 0.30, 0.10 })
    card.shareCaption = centered(card, -160, 14, false, UI.theme.inkMuted)
    card.totals = centered(card, -220, 15, true)
    card.enemy = centered(card, -256, 15, false, { 0.55, 0.12, 0.12 })
    card.note = centered(card, -110, 15, false, nil, 80)
    card.open = UI.button(card, L("Ouvrir le Journal de guilde"), (SHEET_W - 260) / 2, -360, 260, function()
        if GL.ShowRelations then GL.ShowRelations("guildlog") end
    end, nil, true)
end
local function paintGuild(card, facts)
    card.heading:SetText(L("Votre guilde"))
    local guild = facts.guild
    local shown = guild ~= nil and guild.kills + guild.deaths > 0
    for _, control in ipairs({ card.share, card.shareCaption, card.totals, card.enemy, card.open }) do
        if shown then control:Show() else control:Hide() end
    end
    if not shown then
        card.note:Show()
        local _, inGuild = false, false
        if GL.GuildMap then _, inGuild = GL.GuildMap.Enabled() end
        card.note:SetText(not inGuild and L("Pas de guilde : cette page raconte ce que vous apportez à la vôtre.")
            or not guild and L("La vision de guilde est décochée : cochez-la sur la carte pour voir cette page.")
            or L("Aucun combat de la guilde sur cette période."))
        return
    end
    card.note:Hide()
    local share = guild.kills > 0 and math.floor(guild.mine * 100 / guild.kills + 0.5) or 0
    card.share:SetText(share .. " %")
    card.shareCaption:SetText(L("des victoires de la guilde sont les vôtres"))
    card.totals:SetText(L("La guilde : %d victoires · %d morts · %d membres"):format(guild.kills, guild.deaths, guild.members))
    card.enemy:SetText(guild.enemy and L("Son pire ennemi : %s, %d morts"):format(plain(guild.enemy.name or L("un joueur inconnu")),
        guild.enemy.deaths) or "")
end
local cards = {
    { build = buildWho, paint = paintWho }, { build = buildNumbers, paint = paintNumbers },
    { build = buildPeople, paint = paintPeople }, { build = buildTerritory, paint = paintTerritory },
    { build = buildGuild, paint = paintGuild },
}

-- The book: the narrow format of Relations. Left, the four periods and the two choices. Right,
-- one card, turned with the arrows.
local function book()
    if R.window then return R.window end
    local f = UI.bookWindow("GrudgeLedgerRecap", "Grudge Ledger", true)
    R.window = f
    f.period, f.scope, f.card = "month", "character", 1
    GL.SetupBookNavigation(f, "journal")
    f.periods = {}
    for i, entry in ipairs(PERIODS) do
        local key = entry[1]
        local tab = UI.button(f, entry[2], 38, -158 - (i - 1) * 36, 168, function()
            f.period = key
            R.Refresh()
        end, true)
        tab:SetHeight(30)
        f.periods[key] = tab
    end
    f.scopeButton = UI.button(f, "", 38, -318, 168, function()
        f.scope = f.scope == "character" and "all" or "character"
        R.Refresh()
    end, true)
    f.scopeButton:SetHeight(30)
    f.copy = UI.button(f, L("Copier le bilan"), 38, -372, 168, function()
        if f.copyBox:IsShown() then
            f.copyBox:Hide()
            return
        end
        f.copyBox:Show()
        f.copyField:SetText(f.copyText or "")
        f.copyField:SetFocus()
        f.copyField:HighlightText()
    end, true)
    f.copy:SetHeight(30)
    f.details = UI.button(f, L("Tableaux détaillés"), 38, -408, 168, function() GL.ShowJournal("summary") end, true)
    f.details:SetHeight(30)
    f.copyBox = CreateFrame("Frame", nil, f)
    f.copyBox:SetPoint("TOPLEFT", 38, -448)
    f.copyBox:SetSize(168, 150)
    f.copyField = CreateFrame("EditBox", nil, f.copyBox)
    f.copyField:SetPoint("TOPLEFT")
    f.copyField:SetSize(168, 124)
    f.copyField:SetMultiLine(true)
    f.copyField:SetAutoFocus(false)
    UI.styleInput(f.copyField, true)
    f.copyField:SetScript("OnEscapePressed", function() f.copyBox:Hide() end)
    -- Hidden, the box keeps no text.
    f.copyBox:SetScript("OnHide", function()
        f.copyField:ClearFocus()
        f.copyField:SetText("")
    end)
    f.copyHint = UI.label(f.copyBox, L("Ctrl+C pour copier."), nil, 0, -128, 168)
    f.copyHint:SetTextColor(unpack(UI.theme.muted))
    f.copyBox:Hide()
    local host = CreateFrame("Frame", nil, f)
    host:SetPoint("TOPLEFT", 240, -152)
    host:SetSize(SHEET_W, SHEET_H)
    host.cards = {}
    for i, entry in ipairs(cards) do
        local card = CreateFrame("Frame", nil, host)
        card:SetAllPoints()
        entry.build(card)
        card:Hide()
        host.cards[i] = card
    end
    f.host = host
    f.previous = UI.button(host, "‹", 26, -464, 48, function()
        f.card = (f.card - 2) % CARDS + 1
        R.Refresh()
    end, nil, true)
    f.next = UI.button(host, "›", SHEET_W - 74, -464, 48, function()
        f.card = f.card % CARDS + 1
        R.Refresh()
    end, nil, true)
    -- One dot a card, the current one in red: you see where you are in the story.
    f.dots = {}
    for i = 1, CARDS do
        local dot = CreateFrame("Button", nil, host)
        dot:SetPoint("TOPLEFT", SHEET_W / 2 - CARDS * 11 + (i - 1) * 22, -474)
        dot:SetSize(14, 14)
        dot.fill = dot:CreateTexture(nil, "ARTWORK")
        dot.fill:SetAllPoints()
        local index = i
        dot:SetScript("OnClick", function()
            f.card = index
            R.Refresh()
        end)
        f.dots[i] = dot
    end
    return f
end
function R.Open(card)
    local f = book()
    if type(card) == "number" and card >= 1 and card <= CARDS then f.card = card end
    GL.ShowBookPage(f)
    R.Refresh()
    return f
end
function R.Refresh()
    local f = R.window
    if not f or not f:IsShown() then return end
    for key, tab in pairs(f.periods) do UI.selectButton(tab, key == f.period) end
    f.scopeButton:SetText(SCOPE_BUTTONS[f.scope])
    local facts = R.Facts(f.period, f.scope)
    for i, card in ipairs(f.host.cards) do
        if i == f.card then
            card:Show()
            cards[i].paint(card, facts, f.period, f.scope)
        else
            card:Hide()
        end
    end
    for i, dot in ipairs(f.dots) do
        if i == f.card then dot.fill:SetColorTexture(0.55, 0.12, 0.12, 1) else dot.fill:SetColorTexture(0.49, 0.32, 0.13, 0.45) end
    end
    local who = plain(f.scope == "character" and facts.stats.actorName or L("Tous vos personnages"))
    f.copyText = R.Text(facts, f.period, who)
    if f.copyBox:IsShown() then f.copyField:SetText(f.copyText) end
end
GL.On("CHANGED", function() R.Refresh() end)
