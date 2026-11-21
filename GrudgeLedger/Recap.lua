-- The Bilan (0.53.0, first page of Relations since 0.55.0): your player's card, told in cards you
-- turn like stories. Who you are, your numbers, your three people, your territory, the classes and
-- the races that kill you, who strikes first, your honor, your guild. Above, the period and the
-- characters. The detailed tables of the old Bilan stay one click away.
-- Journal data only: it works with the addon alone. The guild page needs the guild vision.
local GL = GrudgeLedger
local L = GL.L
local UI = GL.UITheme
local Panels = GL.DossierPanels
local R = {}
GL.Recap = R

local SHEET_W, SHEET_H = 664, 510
local PERIODS = { { "week", L("Cette semaine") }, { "month", L("Ce mois-ci") }, { "year", L("Cette année") }, { "all", L("Depuis le début") } }
local SCOPES = { { "character", L("Ce personnage") }, { "all", L("Tout le compte") } }
local SCOPE_BUTTONS = { character = L("Personnage : celui-ci"), all = L("Personnages : tout le compte") }
local DAY = 86400

-- "1 mort", "2 morts": the right form for a count (review 0.58.5).
local function count(n, one, many)
    return (n == 1 and L(one) or L(many)):format(n)
end
local function wins(n) return count(n, "%d victoire", "%d victoires") end
local function deaths(n) return count(n, "%d mort", "%d morts") end
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
    -- The classes and the races of your opponents, the deadliest first, five of each.
    for field, dimension in pairs({ classes = "class", races = "race" }) do
        local items = {}
        for _, item in ipairs(GL.PvPBreakdown(options, dimension)) do
            if item.key ~= "unknown" and item.key ~= "mixed" and item.kills + item.deaths > 0 then items[#items + 1] = item end
        end
        table.sort(items, function(x, y)
            if x.deaths ~= y.deaths then return x.deaths > y.deaths end
            if x.kills ~= y.kills then return x.kills > y.kills end
            return x.label < y.label
        end)
        for i = #items, 6, -1 do items[i] = nil end
        facts[field] = items
    end
    -- Your companion: the time-weighted title of the journal, the same as on the player sheet.
    local _, companion = GL.Titles()
    facts.companion = companion and GL.Get(companion) or nil
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
        sentence = L("Vous frappez le premier, et vous gagnez : %s pour %s."):format(wins(k), deaths(d))
        -- Who struck first is not known for these fights: say only what is.
        if opened + answered == 0 then
            sentence = L("Vous gagnez bien plus que vous ne tombez : %s pour %s."):format(wins(k), deaths(d))
        end
    elseif k >= 2 * d then
        archetype = L("Le Rempart")
        sentence = L("On vous attaque, et vous tenez : %s pour %s."):format(wins(k), deaths(d))
    elseif d >= 2 * k then
        archetype = L("La Cible")
        sentence = L("On vous chasse : %s pour %s. Les dettes s’accumulent."):format(deaths(d), wins(k))
    else
        archetype = L("Le Duelliste")
        sentence = L("Combat après combat, l’équilibre : %s, %s."):format(wins(k), deaths(d))
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
        facts.ratio = (k / d >= 2 and L("%s victoires par mort.") or L("%s victoire par mort.")):format(ratio)
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
        local value = stats.mostDeaths.value
        local form = value == 1 and L("Némésis : %s (1 mort)") or L("Némésis : %s (%d morts)")
        lines[#lines + 1] = form:format(plain(stats.mostDeaths.record.fullName or stats.mostDeaths.record.name), value)
    end
    if stats.mostKilled then
        local value = stats.mostKilled.value
        local form = value == 1 and L("Proie favorite : %s (1 victoire)") or L("Proie favorite : %s (%d victoires)")
        lines[#lines + 1] = form:format(plain(stats.mostKilled.record.fullName or stats.mostKilled.record.name), value)
    end
    if facts.companion then
        lines[#lines + 1] = L("Compagnon : %s"):format(plain(facts.companion.fullName or facts.companion.name))
    end
    if facts.deadly then
        local value = facts.deadly.deaths
        local form = value == 1 and L("Zone la plus dangereuse : %s (1 mort)") or L("Zone la plus dangereuse : %s (%d morts)")
        lines[#lines + 1] = form:format(plain(facts.deadly.label), value)
    end
    return table.concat(lines, "\n")
end

-- The cards. Each one has a heading and a few large lines, nothing to read twice.
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
local function bigNumbers(card, y)
    card.values, card.captions = {}, {}
    for i = 1, 3 do
        local x = 32 + (i - 1) * 200
        card.values[i] = Panels.Text(card, x, y, 196, 46, true)
        card.values[i]:SetJustifyH("CENTER")
        card.captions[i] = Panels.Text(card, x, y - 62, 196, 14, false, UI.theme.inkMuted)
        card.captions[i]:SetJustifyH("CENTER")
    end
end
local function buildNumbers(card)
    card.heading = centered(card, -36, 21, true)
    bigNumbers(card, -110)
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
    box:SetSize(200, 230)
    box.face = CreateFrame("Frame", nil, box)
    box.face:SetSize(88, 88)
    box.face:SetPoint("TOP", box, "TOP", 0, 0)
    box.face.raceIcon = box.face:CreateTexture(nil, "ARTWORK")
    box.face.raceIcon:SetAllPoints()
    box.face.classIcon = box.face:CreateTexture(nil, "OVERLAY")
    box.face.classIcon:SetSize(22, 22)
    box.face.classIcon:SetPoint("BOTTOMRIGHT")
    box.tag = Panels.Text(box, 0, -100, 200, 13, true)
    box.tag:SetJustifyH("CENTER")
    box.name = Panels.Text(box, 0, -122, 200, 16, true)
    box.name:SetJustifyH("CENTER")
    GL.Safe(box.name.SetWordWrap, box.name, false)
    box.line = Panels.Text(box, 0, -146, 200, 13, false, UI.theme.inkMuted)
    box.line:SetJustifyH("CENTER")
    box.line:SetHeight(40)
    GL.Safe(box.line.SetWordWrap, box.line, true)
    GL.Safe(box.line.SetJustifyV, box.line, "TOP")
    box:SetScript("OnClick", function(self)
        if self.record and GL.ShowLedger then GL.ShowLedger(self.record.key) end
    end)
    return box
end
local function buildPeople(card)
    card.heading = centered(card, -36, 21, true)
    card.people = { person(card, 22), person(card, 232), person(card, 442) }
end
local function paintPeople(card, facts)
    card.heading:SetText(L("Vos trois personnes"))
    local stats, companion = facts.stats, facts.companion
    local entries = {
        { stats.mostDeaths, L("Votre némésis"), { 0.55, 0.12, 0.12 }, L("Vous a tué %d fois"), L("Personne ne vous a tué sur cette période.") },
        { companion and { record = companion, value = tonumber(companion.groupCount) or 0 }, L("Votre compagnon"), { 0.20, 0.35, 0.55 },
            L("%d groupes ensemble"), L("Un ami avec qui vous groupez, ou trois groupes cette semaine.") },
        { stats.mostKilled, L("Votre proie favorite"), { 0.18, 0.37, 0.20 }, L("Vaincu %d fois"), L("Aucune victoire sur cette période.") },
    }
    for i, box in ipairs(card.people) do
        local entry = entries[i]
        local item = entry[1]
        box.record = item and item.record
        box.tag:SetText(entry[2])
        box.tag:SetTextColor(unpack(entry[3]))
        if item then
            Panels.Fit(box.name, plain(item.record.fullName or item.record.name), 200, 16, 11, true)
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
    card.map = UI.button(card, L("Voir sur la carte"), (SHEET_W - 220) / 2, -350, 220, function()
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
-- A card of five lines: the classes or the races of your opponents, the deadliest first.
local LIST_ROWS = 5
local function buildList(card)
    card.heading = centered(card, -36, 21, true)
    card.lead = centered(card, -66, 13, false, UI.theme.inkMuted)
    card.rows = {}
    for i = 1, LIST_ROWS do
        local row = CreateFrame("Frame", nil, card)
        row:SetPoint("TOPLEFT", 92, -100 - (i - 1) * 46)
        row:SetSize(480, 44)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
        rule:SetHeight(1)
        rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
        row.label = Panels.Text(row, 0, -10, 250, 17, true)
        GL.Safe(row.label.SetWordWrap, row.label, false)
        row.counts = Panels.Text(row, 250, -12, 230, 14)
        row.counts:SetJustifyH("RIGHT")
        card.rows[i] = row
    end
    card.empty = centered(card, -120, 14, false, UI.theme.inkMuted)
end
local function paintList(card, items, heading, lead)
    card.heading:SetText(heading)
    card.lead:SetText(lead)
    for i, row in ipairs(card.rows) do
        local item = items[i]
        if item then
            row.label:SetText(plain(item.label))
            row.counts:SetText(L("%d morts · %d victoires"):format(item.deaths, item.kills))
            if item.deaths > item.kills then row.label:SetTextColor(0.55, 0.12, 0.12) else row.label:SetTextColor(0.18, 0.37, 0.20) end
            row:Show()
        else
            row:Hide()
        end
    end
    card.empty:SetText(#items == 0 and L("Aucun combat sur cette période.") or "")
end
local function paintClasses(card, facts)
    paintList(card, facts.classes, L("Les classes qui vous tuent"), L("Vos morts et vos victoires par classe adverse."))
end
local function paintRaces(card, facts)
    paintList(card, facts.races, L("Les races qui vous tuent"), L("Vos morts et vos victoires par race adverse."))
end
local function buildInitiative(card)
    card.heading = centered(card, -36, 21, true)
    card.value = centered(card, -100, 46, true, { 0.45, 0.30, 0.10 })
    card.caption = centered(card, -160, 14, false, UI.theme.inkMuted)
    card.lines = centered(card, -220, 15, false, nil, 120)
end
local function paintInitiative(card, facts)
    local stats = facts.stats
    local opened, answered = stats.initiated or 0, stats.responded or 0
    card.heading:SetText(L("Qui frappe le premier"))
    card.value:SetText(opened + answered > 0 and L("%d sur %d"):format(opened, opened + answered) or "—")
    card.caption:SetText(L("combats où vous portez le premier coup"))
    card.lines:SetText(table.concat({
        L("Revanches : %d"):format(stats.revengeKills or 0),
        L("Victoires après avoir été attaqué : %d"):format(stats.responseKills or 0),
        L("Joueurs vaincus : %d · joueurs qui vous ont blessé : %d"):format(stats.victims or 0, stats.attackers or 0),
    }, "\n"))
end
local function buildHonor(card)
    card.heading = centered(card, -36, 21, true)
    card.value = centered(card, -100, 46, true, { 0.45, 0.30, 0.10 })
    card.caption = centered(card, -160, 14, false, UI.theme.inkMuted)
    card.lines = centered(card, -220, 15, false, nil, 90)
end
local function paintHonor(card, facts)
    local stats = facts.stats
    card.heading:SetText(L("Votre honneur"))
    card.value:SetText(tostring(stats.honor or 0))
    card.caption:SetText(L("points d’honneur gagnés en combat"))
    local lines = { L("%d gains · meilleur gain : %d"):format(stats.honorAwards or 0, stats.bestHonor or 0) }
    if (stats.unassignedHonor or 0) > 0 then
        lines[#lines + 1] = L("Dont %d sans adversaire identifié"):format(stats.unassignedHonor)
    end
    card.lines:SetText(table.concat(lines, "\n"))
end
local function buildGuild(card)
    card.heading = centered(card, -36, 21, true)
    card.share = centered(card, -100, 46, true, { 0.45, 0.30, 0.10 })
    card.shareCaption = centered(card, -160, 14, false, UI.theme.inkMuted)
    card.totals = centered(card, -220, 15, true)
    card.enemy = centered(card, -256, 15, false, { 0.55, 0.12, 0.12 })
    card.note = centered(card, -110, 15, false, nil, 80)
    card.open = UI.button(card, L("Ouvrir le Journal de guilde"), (SHEET_W - 260) / 2, -350, 260, function()
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
            or not guild and L("La vision de guilde est décochée : cochez-la dans l’onglet Guilde pour voir cette page.")
            or L("Aucun combat de la guilde sur cette période."))
        return
    end
    card.note:Hide()
    local share = guild.kills > 0 and math.floor(guild.mine * 100 / guild.kills + 0.5) or 0
    card.share:SetText(share .. " %")
    card.shareCaption:SetText(L("des victoires de la guilde sont les vôtres"))
    card.totals:SetText(L("La guilde : %s · %s · %s"):format(wins(guild.kills), deaths(guild.deaths),
        count(guild.members, "%d membre", "%d membres")))
    card.enemy:SetText(guild.enemy and L("Son pire ennemi : %s, %s"):format(plain(guild.enemy.name or L("un joueur inconnu")),
        deaths(guild.enemy.deaths)) or "")
end
local cards = {
    { build = buildWho, paint = paintWho }, { build = buildNumbers, paint = paintNumbers },
    { build = buildPeople, paint = paintPeople }, { build = buildTerritory, paint = paintTerritory },
    { build = buildList, paint = paintClasses }, { build = buildList, paint = paintRaces },
    { build = buildInitiative, paint = paintInitiative }, { build = buildHonor, paint = paintHonor },
    { build = buildGuild, paint = paintGuild },
}
local CARDS = #cards

-- The page, first entry of the Relations book (0.55.0). Above the card, the Journal's kind of
-- buttons: the period (a click shows the next one), the characters, the copy, the old tables.
-- Below, the arrows and one dot a card.
function R.BuildPage(host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints()
    page.period, page.scope, page.card = "month", "character", 1
    page.periodButton = UI.button(page, "", 26, -14, 170, function()
        for i, entry in ipairs(PERIODS) do
            if entry[1] == page.period then
                page.period = PERIODS[i % #PERIODS + 1][1]
                break
            end
        end
        GL.RelationsPages.Refresh()
    end)
    page.scopeButton = UI.button(page, "", 200, -14, 180, function()
        page.scope = page.scope == "character" and "all" or "character"
        GL.RelationsPages.Refresh()
    end)
    page.copy = UI.button(page, L("Copier"), 384, -14, 110, function()
        if page.copyBox:IsShown() then
            page.copyBox:Hide()
            return
        end
        page.copyBox:Show()
        page.copyBox:Raise()
        page.copyField:SetText(page.copyText or "")
        page.copyField:SetFocus()
        page.copyField:HighlightText()
    end)
    page.details = UI.button(page, L("Tableaux détaillés"), 498, -14, 140, function() GL.ShowJournal("summary") end)
    page.cards = {}
    for i, entry in ipairs(cards) do
        local card = CreateFrame("Frame", nil, page)
        card:SetPoint("TOPLEFT", 0, -30)
        card:SetSize(SHEET_W, SHEET_H - 80)
        entry.build(card)
        card:Hide()
        page.cards[i] = card
    end
    page.previous = UI.button(page, "‹", 26, -464, 48, function()
        page.card = (page.card - 2) % CARDS + 1
        GL.RelationsPages.Refresh()
    end, nil, true)
    page.next = UI.button(page, "›", SHEET_W - 74, -464, 48, function()
        page.card = page.card % CARDS + 1
        GL.RelationsPages.Refresh()
    end, nil, true)
    -- One dot a card, the current one in red: you see where you are in the story.
    page.dots = {}
    for i = 1, CARDS do
        local dot = CreateFrame("Button", nil, page)
        dot:SetPoint("TOPLEFT", SHEET_W / 2 - CARDS * 11 + (i - 1) * 22, -474)
        dot:SetSize(14, 14)
        dot.fill = dot:CreateTexture(nil, "ARTWORK")
        dot.fill:SetAllPoints()
        local index = i
        dot:SetScript("OnClick", function()
            page.card = index
            GL.RelationsPages.Refresh()
        end)
        page.dots[i] = dot
    end
    -- The copy box: the card as text, over the page, like the Journal's filter panel.
    page.copyBox = CreateFrame("Frame", nil, page)
    page.copyBox:SetPoint("TOPLEFT", 284, -44)
    page.copyBox:SetSize(354, 176)
    page.copyBox:SetFrameStrata("FULLSCREEN_DIALOG")
    GL.Safe(page.copyBox.SetFrameLevel, page.copyBox, (GL.Safe(page.GetFrameLevel, page) or 1) + 20)
    UI.surface(page.copyBox, UI.theme.gold)
    UI.surface(page.copyBox, UI.theme.panel, 1)
    page.copyField = CreateFrame("EditBox", nil, page.copyBox)
    page.copyField:SetPoint("TOPLEFT", 8, -8)
    page.copyField:SetSize(338, 136)
    page.copyField:SetMultiLine(true)
    page.copyField:SetAutoFocus(false)
    UI.styleInput(page.copyField, true)
    page.copyField:SetScript("OnEscapePressed", function() page.copyBox:Hide() end)
    page.copyHint = UI.label(page.copyBox, L("Ctrl+C pour copier."), nil, 10, -152, 330)
    page.copyHint:SetTextColor(unpack(UI.theme.muted))
    -- Hidden, the box keeps no text.
    page.copyBox:SetScript("OnHide", function()
        page.copyField:ClearFocus()
        page.copyField:SetText("")
    end)
    page.copyBox:Hide()
    page:SetScript("OnHide", function() page.copyBox:Hide() end)
    return page
end
function R.PaintPage(page)
    page.periodButton:SetText(labelOf(PERIODS, page.period))
    page.scopeButton:SetText(labelOf(SCOPES, page.scope))
    UI.selectButton(page.scopeButton, page.scope ~= "character")
    local facts = R.Facts(page.period, page.scope)
    for i, card in ipairs(page.cards) do
        if i == page.card then
            card:Show()
            cards[i].paint(card, facts, page.period, page.scope)
        else
            card:Hide()
        end
    end
    for i, dot in ipairs(page.dots) do
        if i == page.card then dot.fill:SetColorTexture(0.55, 0.12, 0.12, 1) else dot.fill:SetColorTexture(0.49, 0.32, 0.13, 0.45) end
    end
    local who = plain(page.scope == "character" and facts.stats.actorName or L("Tous vos personnages"))
    page.copyText = R.Text(facts, page.period, who)
    if page.copyBox:IsShown() then page.copyField:SetText(page.copyText) end
end
-- Opens the Bilan in the Relations book, on a card when one is asked for.
function R.Open(card)
    local f = GL.RelationsPages and GL.RelationsPages.Open("recap")
    local page = f and f.host.pages.recap
    if page and type(card) == "number" and card >= 1 and card <= CARDS then
        page.card = card
        GL.RelationsPages.Refresh()
    end
    return f
end
