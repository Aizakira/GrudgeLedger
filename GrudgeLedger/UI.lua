-- Grudge Ledger: a single journal, explicit relations and optional notes.
local GL = GrudgeLedger
local ledger, noteWindow, settingsWindow, minimapButton, guildWindow
local correctionWindow, diagnosticWindow
local statisticsWindow, journalWindow, guideWindow
local showSettings
local selectedKey, filter, offset = nil, "all", 0
local factionFilter = "all"
local notesOnly = false
local listSort, listDetail = "recent", "identity"
local sortChoices = { { "recent", "Rencontres" }, { "name", "Nom" }, { "reputation", "Réputation" }, { "kills", "Victoires" }, { "deaths", "Morts" }, { "encounters", "Croisements" } }
local detailChoices = { { "identity", "Identité" }, { "guild", "Guilde" }, { "pvp", "PvP confirmé" }, { "notes", "Notes" } }
local drafts = {}
local guildDrafts = {}
local relationNames = { friend = "Ami", warning = "Méfiance", enemy = "Ennemi", neutral = "Neutre" }
local factionNames = { Alliance = "Alliance", Horde = "Horde", Neutral = "Neutre" }
local colors = { friend = { 0.48, 0.86, 0.56 }, warning = { 0.97, 0.76, 0.39 }, enemy = { 0.98, 0.55, 0.50 }, neutral = { 0.79, 0.74, 0.65 } }
local inkColors = { friend = { 0.10, 0.34, 0.15 }, warning = { 0.50, 0.22, 0.03 }, enemy = { 0.57, 0.12, 0.11 }, neutral = { 0.34, 0.27, 0.20 } }
local relationIcons = { friend = "RelationFriend", warning = "RelationWarning", enemy = "RelationEnemy", neutral = "RelationNeutral" }
local media = "Interface\\AddOns\\GrudgeLedger\\Media\\"
local pvpNames = { kill = "Victoire", death = "Mort", aggression = "Agression" }
local UI = GL.UITheme
local theme, journalFonts = UI.theme, UI.journalFonts
local surface, plain, label, button = UI.surface, UI.plain, UI.label, UI.button
local styleInput, window, bookWindow, journalFont = UI.styleInput, UI.window, UI.bookWindow, UI.journalFont
local function identityLabels(record)
    local classes = record.sex == 3 and LOCALIZED_CLASS_NAMES_FEMALE or LOCALIZED_CLASS_NAMES_MALE
    return factionNames[record.faction] or "Faction inconnue", record.raceName or record.race or "Race inconnue",
        record.className or (classes and classes[record.class]) or record.class or "Classe inconnue"
end
local function identityAtlas(texture, atlas)
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(0, 1, 0, 1)
    GL.Safe(texture.SetVertexColor, texture, 1, 1, 1)
    if atlas and GL.Safe(C_Texture and C_Texture.GetAtlasInfo, atlas) then
        return pcall(texture.SetAtlas, texture, atlas)
    end
    return false
end

local function identityIcons(row, record)
    local class = GL.Clean(record.class, "string")
    local atlas = class and GL.Safe(GetClassAtlas, (class:gsub("[A-Z]", string.lower)))
    if not identityAtlas(row.classIcon, atlas) then
        local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if type(coords) == "table" and #coords == 4 then
            row.classIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            row.classIcon:SetTexCoord(unpack(coords))
        end
    end
    local race = GL.Clean(record.race, "string")
    local sex = record.sex == 2 and "male" or record.sex == 3 and "female"
    -- ponytail: race atlas names vary across clients; use only an atlas the client
    -- confirms, otherwise keep '?' and the race label. Add verified aliases if needed.
    local suffix = race and sex and (race:lower() .. "-" .. sex)
    if not identityAtlas(row.raceIcon, suffix and ("raceicon128-" .. suffix)) and suffix then
        identityAtlas(row.raceIcon, "raceicon-" .. suffix)
    end
end
local function subdued(text) return "|cff5c4029" .. text .. "|r" end
local function stamp(t) return date("%d/%m/%Y %H:%M", t or GL.Now()) end
local function counted(n, singular, plural)
    return n .. " " .. (n > 1 and (plural or singular .. "s") or singular)
end
local gestureNames = {
    KISS = "Bisou", WINK = "Clin d'œil", HUG = "Étreinte", WAVE = "Signe de la main", THANK = "Remerciement",
    BOW = "Révérence", SALUTE = "Salut", CHEER = "Encouragement", APPLAUD = "Applaudissement", SMILE = "Sourire",
    LOVE = "Déclaration d'amour", COMFORT = "Réconfort", PAT = "Tape amicale", SOOTHE = "Geste apaisant",
    RUDE = "Geste grossier", INSULT = "Insulte", TAUNT = "Provocation", MOCK = "Moquerie", SPIT = "Crachat",
    SLAP = "Gifle", GLARE = "Regard noir", ANGRY = "Colère", FROWN = "Froncement de sourcils", BOO = "Huée", SNUB = "Dédain",
}
local function eventTitle(event)
    local confirmed = event.confidence == "confirmed"
    if event.kind == "death" then return confirmed and "Vous a tué" or "Participation possible à votre mort" end
    if event.kind == "kill" then return confirmed and "Vous l'avez vaincu" or "Victoire probable contre ce joueur" end
    if event.kind == "aggression" then return confirmed and "Vous a infligé des dégâts" or "Agression suspectée" end
    if event.kind == "reputation" then
        if event.source == "emote" then
            local token = type(event.evidence) == "string" and event.evidence:match("/([A-Za-z]+)$")
            return "Geste demandé : " .. (token and gestureNames[token:upper()] or "émote")
        end
        return (event.delta or 0) > 0 and "Vous avez ajouté un avis positif"
            or (event.delta or 0) < 0 and "Vous avez ajouté un avis négatif" or "Votre avis est inchangé"
    end
    if event.kind == "reaction" then
        return event.source == "automatic" and "Classement automatique réactivé"
            or "Vous l'avez marqué : " .. (relationNames[event.reaction] or "avis personnel")
    end
    if event.kind == "grouped" or event.kind == "group" then return "Vous avez partagé un groupe" end
    return event.kind == "note" and "Vous avez ajouté une note" or "Événement enregistré"
end
local function showBook(frame)
    for _, page in pairs({ ledger, statisticsWindow, journalWindow, settingsWindow }) do
        if page ~= frame then page:Hide() end
    end
    if guideWindow then guideWindow:Hide() end
    frame:Show()
    frame:Raise()
end

local function bookNavigation(f, selected)
    f.navigation = {}
    for i, entry in ipairs({
        { "ledger", "Journal", function() GL.ShowLedger() end },
        { "players", "Classements", function() GL.ShowStatistics("players") end },
        { "guilds", "Guildes", function() GL.ShowStatistics("guilds") end },
        { "journal", "Bilan", function() GL.ShowJournal("summary") end },
    }) do
        local b = button(f, entry[2], 40 + (i - 1) * 221, -99, 216, entry[3], true)
        b:SetHeight(31)
        journalFont(b.caption, "GameFontHighlightSmall", 16)
        b.caption:ClearAllPoints()
        b.caption:SetPoint("CENTER")
        b.caption:SetHeight(24)
        f.navigation[entry[1]] = b
        UI.selectButton(b, entry[1] == selected)
    end
    f.settingsButton = UI.iconButton(f, "JournalSettings", "Réglages et aide", 869, -45, 32, showSettings)
    if selected == "settings" then f.settingsButton:LockHighlight() end
end

local function currentRecord() return selectedKey and GL.Get(selectedKey) end
local refresh

local function guildDraftKey(name, realm)
    name, realm = GL.Clean(name, "string"), GL.Clean(realm, "string")
    realm = realm and realm:match("^%s*(.-)%s*$")
    if not realm or realm == "" then realm = GL.Clean(GL.Safe(GetRealmName), "string") or "Forever" end
    if not name or #name > 160 or #realm > 160 or name:find("[|%c]") or realm:find("[|%c]") then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" then return realm:lower() .. ":" .. name:lower() end
end

local function refreshGuilds()
    if not guildWindow or not guildWindow:IsShown() or guildWindow.changingIdentity then return end
    local f, rules = guildWindow, {}
    for _, rule in pairs(GL.db.guilds) do rules[#rules + 1] = rule end
    table.sort(rules, function(a, b) return a.name:lower() .. a.realm < b.name:lower() .. b.realm end)
    f.offset = math.min(f.offset, math.max(0, math.floor((#rules - 1) / 9) * 9))
    for i, row in ipairs(f.rows) do
        local rule = rules[f.offset + i]
        if rule then
            row.rule = rule
            local c = colors[rule.reaction]
            row.name:SetText(plain(rule.name))
            row.name:SetTextColor(c[1], c[2], c[3])
            row.bg:SetAlpha(f.name:GetText() == rule.name and f.realm:GetText() == rule.realm and 1 or 0.2)
            row:Show()
        else row.rule = nil row:Hide() end
    end
    f.total:SetText(counted(#rules, "guilde enregistrée", "guildes enregistrées"))
    if #rules == 0 then f.empty:Show() else f.empty:Hide() end
    f.previous:SetEnabled(f.offset > 0)
    f.next:SetEnabled(f.offset + 9 < #rules)
    local current = GL.GetGuildRule(f.name:GetText(), f.realm:GetText())
    local key = guildDraftKey(f.name:GetText(), f.realm:GetText())
    local saved = current and current.note or ""
    if key ~= f.draftKey then
        if f.draftKey then
            local text = f.note:GetText()
            guildDrafts[f.draftKey] = text ~= f.loadedNote and text or nil
        end
        f.draftKey, f.loadedNote = key, saved
        f.note:SetText(guildDrafts[key] or saved)
    elseif saved ~= f.loadedNote then
        if f.note:GetText() == (f.loadedNote or "") then f.note:SetText(saved) end
        f.loadedNote = saved
    end
    local statusKey = (key or "") .. "\n" .. (current and current.reaction or "")
    if f.statusKey ~= statusKey then
        f.statusKey = statusKey
        f.status:SetText(current and "Avis actuel : " .. relationNames[current.reaction] or "Aucun avis sur cette guilde.")
    end
    for reaction, control in pairs(f.reactions) do
        local active = current and current.reaction == reaction
        UI.selectButton(control, active)
    end
end

function GL.ShowGuilds(identity)
    if not GL.db then return end
    if not guildWindow then
        local f = window("GrudgeLedgerGuilds", "Grudge Ledger — Guildes", 660, 480)
        guildWindow, f.offset = f, 0
        label(f, "Les membres héritent de l'avis de leur guilde. Un choix personnel reste prioritaire.", nil, 18, -54, 620)
        f.rows = {}
        f.empty = label(f, "Aucune guilde enregistrée.\n\nSaisis son nom exact à droite ou utilise la guilde de ta cible.", nil, 23, -119, 230)
        f.empty:SetTextColor(unpack(theme.muted))
        for i = 1, 9 do
            local row = CreateFrame("Button", nil, f)
            row:SetPoint("TOPLEFT", 18, -102 - (i - 1) * 29)
            row:SetSize(245, 27)
            row.bg = surface(row, theme.red)
            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(0.57, 0.39, 0.18, 0.16)
            row:SetHighlightTexture(hover)
            row.name = label(row, "", nil, 4, -6, 235)
            row.name:SetHeight(17)
            GL.Safe(row.name.SetWordWrap, row.name, false)
            GL.Safe(row.name.SetMaxLines, row.name, 1)
            row:SetScript("OnClick", function(self) GL.ShowGuilds({ guild = self.rule.name, realm = self.rule.realm }) end)
            f.rows[i] = row
        end
        f.previous = button(f, "Précédent", 18, -375, 112, function() f.offset = math.max(0, f.offset - 9) refreshGuilds() end)
        f.next = button(f, "Suivant", 147, -375, 112, function() f.offset = f.offset + 9 refreshGuilds() end)
        f.total = label(f, "", nil, 18, -411, 245)
        for _, entry in ipairs({ { "name", "Nom exact de la guilde", 101, 160 }, { "realm", "Serveur", 160, 160 }, { "note", "Note facultative", 219, 2000 } }) do
            label(f, entry[2], nil, 288, -entry[3], 345)
            local edit = CreateFrame("EditBox", nil, f)
            edit:SetPoint("TOPLEFT", 297, -entry[3] - 22)
            edit:SetSize(332, 25)
            edit:SetAutoFocus(false)
            edit:SetMaxLetters(entry[4])
            styleInput(edit)
            edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            if entry[1] ~= "note" then edit:SetScript("OnTextChanged", refreshGuilds) end
            f[entry[1]] = edit
        end
        f.status = label(f, "", nil, 288, -278, 345)
        local function save(reaction)
            local rule = GL.SetGuildReaction(f.name:GetText(), reaction, f.note:GetText(), f.realm:GetText())
            if rule then
                guildDrafts[guildDraftKey(rule.name, rule.realm)] = nil
                f.status:SetText("Avis enregistré : " .. relationNames[rule.reaction])
                refreshGuilds()
            else f.status:SetText("Nom, serveur ou note invalide (2000 octets max.).") end
        end
        f.reactions = {}
        for i, choice in ipairs({ { "Amie", "friend" }, { "Méfiance", "warning" }, { "Ennemie", "enemy" }, { "Neutre", "neutral" } }) do
            local reaction = choice[2]
            f.reactions[reaction] = button(f, choice[1], 288 + ((i - 1) % 2) * 178, -312 - math.floor((i - 1) / 2) * 32, 165, function() save(reaction) end, true)
        end
        button(f, "Enregistrer la note", 288, -382, 343, function()
            local rule = GL.GetGuildRule(f.name:GetText(), f.realm:GetText())
            save(rule and rule.reaction or "neutral")
        end)
        button(f, "Guilde de la cible", 288, -426, 343, function()
            local target = GL.Identity("target")
            if not target or not target.guild then f.status:SetText("Sélectionne un joueur dont la guilde est connue.") return end
            GL.ShowGuilds(target)
        end)
        f.realm:SetText(GL.Clean(GL.Safe(GetRealmName), "string") or "")
    end
    if identity and identity.guild then
        guildWindow.changingIdentity = true
        guildWindow.name:SetText(identity.guild)
        guildWindow.realm:SetText(identity.realm or GL.Clean(GL.Safe(GetRealmName), "string") or "")
        guildWindow.changingIdentity = nil
    end
    guildWindow:Show()
    guildWindow:Raise()
    refreshGuilds()
end

local rankingPageSize = 7
local encounterHelp = "Une rencontre recommence après plus de 10 min sans observation. Le total inclut les rencontres avant le changement d'avis ; les anciens passages ne sont pas reconstitués."
local recentHelp = "Dernière observation enregistrée, tous tes personnages confondus. Une personne vue récemment n'est pas forcément encore à proximité."
local confirmedHelp = "Faits confirmés uniquement. Les attributions probables ont leur propre classement. Pour choisir un personnage ou une période, ouvre Mon bilan PvP."
local probableHelp = "Attributions déduites des indices disponibles, pas des coups fatals confirmés. Ouvre une fiche pour vérifier ou corriger les événements."
local statisticsChoices = {
    players = {
        { name = "Menaces", entries = {
            { "grudge", "Rancunes les plus fortes", "Tes ennemis et les personnes à surveiller, selon leur solde négatif actuel.", "point", "Solde actuel", "Les rancunes restent tenaces : une mort pèse dix victoires. Un avis manuel ou de guilde peut aussi signaler un danger sans solde négatif." },
            { "enemiesSeen", "Menaces les plus recroisées", "Les personnes actuellement surveillées que tu as rencontrées le plus souvent.", "rencontre", "Rencontres", encounterHelp },
            { "enemiesRecent", "Menaces vues récemment", "Tes ennemis et les personnes à surveiller, du plus récemment aperçu au plus ancien.", "date", "Dernière observation", recentHelp },
            { "aggressions", "Le plus d'agressions", "Les joueurs avec le plus d'agressions confirmées enregistrées à ton encontre.", "agression", "Agressions confirmées", "Nombre d'épisodes enregistrés, pas de coups reçus ni de fréquence horaire. Les suspicions sont exclues de ce classement." },
        } },
        { name = "Amis", entries = {
            { "friendsSeen", "Amis les plus recroisés", "Tes amis actuels que tu as rencontrés le plus souvent.", "rencontre", "Rencontres", encounterHelp },
            { "reputation", "Affinités les plus fortes", "Tes amis classés selon leur solde positif actuel.", "point", "Solde actuel", "Les avis, les gestes et les faits PvP alimentent le solde. Un ami désigné par un avis de guilde peut avoir un solde nul." },
            { "friendsRecent", "Amis vus récemment", "Tes amis actuels, du plus récemment aperçu au plus ancien.", "date", "Dernière observation", recentHelp },
            { "friendsGrouped", "Compagnons de groupe", "Les amis actuels avec lesquels tu as partagé le plus de sessions de groupe.", "session", "Sessions partagées", "Sessions enregistrées, y compris avant l'amitié ; ni durée ni donjons terminés. Partager un groupe ne rend personne ami automatiquement." },
        } },
        { name = "Combats", entries = {
            { "deaths", "Ceux qui m'ont le plus tué", "Les joueurs auxquels le plus de tes morts sont attribuées avec confirmation.", "mort", "Morts confirmées", confirmedHelp },
            { "kills", "Adversaires les plus vaincus", "Les joueurs contre lesquels tu as le plus de victoires confirmées.", "victoire", "Victoires confirmées", confirmedHelp },
            { "probableDeaths", "Morts probables", "Participations possibles à ta mort : un classement séparé, à vérifier.", "mort", "Morts probables", probableHelp },
            { "probableKills", "Victoires probables", "Victoires déduites des observations : un classement séparé, à vérifier.", "victoire", "Victoires probables", probableHelp },
        } },
    },
    guilds = {
        { name = "Relations", entries = {
            { "grudges", "Le plus de rancunes", "Guildes réunissant le plus de membres avec une rancune personnelle.", "rancune", "Rancunes personnelles", "Dernière guilde connue des personnes de ton livre. Un avis global sur une guilde ne crée pas artificiellement des rancunes personnelles." },
            { "friends", "Le plus d'amis", "Guildes réunissant le plus de membres que tu apprécies personnellement.", "ami", "Amis personnels", "Dernière guilde connue des personnes de ton livre. Les relations héritées d'un avis global sur la guilde ne gonflent pas ce total." },
        } },
        { name = "Combats", entries = {
            { "deaths", "Guildes qui m'ont le plus tué", "Morts confirmées, rattachées à la guilde connue au moment des faits.", "mort", "Morts confirmées", "Une même mort n'est comptée qu'une fois par guilde impliquée. Les faits sans guilde connue restent non attribués." },
            { "kills", "Guildes les plus vaincues", "Victoires confirmées contre les membres de ces guildes.", "victoire", "Victoires confirmées", "Guilde mémorisée au moment du combat. Les victoires probables et les faits sans guilde connue sont exclus." },
            { "aggressions", "Le plus d'agressions", "Agressions confirmées attribuées aux membres de ces guildes.", "agression", "Agressions confirmées", "Guilde mémorisée lors des faits. Plusieurs membres peuvent participer à un même épisode ; les faits sans guilde restent non attribués." },
            { "probableDeaths", "Morts probables", "Participations possibles à ta mort, séparées des morts confirmées.", "mort", "Morts probables", probableHelp },
        } },
    },
}
local function refreshStatistics()
    local f = statisticsWindow
    if not f or not f:IsShown() then return end
    local guild = f.mode == "guilds"
    local groups = statisticsChoices[f.mode]
    local choices = groups[f.category].entries
    local choice = choices[f.choice]
    local rows = guild and GL.GuildStatistics() or GL.PlayerStatistics(choice[1])
    -- ponytail: filter the existing result on demand; no extra cache or background scan.
    for i = #rows, 1, -1 do
        if (guild and rows[i][choice[1]] <= 0)
            or (not guild and f.faction ~= "all" and (rows[i].record.faction or "unknown") ~= f.faction) then
            table.remove(rows, i)
        end
    end
    if guild then
        table.sort(rows, function(a, b)
            if a[choice[1]] ~= b[choice[1]] then return a[choice[1]] > b[choice[1]] end
            return a.key < b.key
        end)
    end
    f.offset = math.min(f.offset, math.max(0, math.floor((#rows - 1) / rankingPageSize) * rankingPageSize))
    f.heading:SetText(choice[2]) f.description:SetText(choice[3])
    f.columnName:SetText(guild and "Guilde" or "Personne")
    f.columnValue:SetText(choice[5])
    f.scope:SetText(guild and f.category == 1 and "Compte · Relations actuelles" or choice[4] == "date" and "Compte · Dernières observations" or choice[4] == "point" and "Compte · Soldes actuels" or "Compte · Toutes périodes")
    for mode, tab in pairs(f.tabs) do UI.selectButton(tab, mode == f.mode) end
    if guild then f.factionButton:Hide() else f.factionButton:Show() end
    f.factionButton:SetText(f.faction == "all" and "Toutes les factions" or factionNames[f.faction] or "Faction inconnue")
    f.manage:SetText(guild and "Gérer les avis de guilde" or "Mon bilan PvP")
    for _, controls in ipairs({ f.groups, f.choices }) do
        local entries = controls == f.groups and groups or choices
        for i, control in ipairs(controls) do
            local entry = entries[i]
            if entry then
                local selected = i == (controls == f.groups and f.category or f.choice)
                control:SetText(controls == f.groups and entry.name or entry[2]) control:Show()
                control.metric = controls == f.choices and entry[1] or nil
                UI.selectButton(control, selected)
            else control:Hide() end
        end
    end
    local selected
    for i, row in ipairs(f.rows) do
        local item = rows[f.offset + i]
        row.item = item
        if item then
            local relation = not guild and GL.Relation(item.record)
            local value = guild and item[choice[1]] or item.value
            local suffix = choice[4] .. (value > 1 and "s" or "")
            row.rank:SetText(tostring(f.offset + i))
            row.name:SetText(plain(guild and item.name or item.record.fullName))
            row.name:SetTextColor(unpack(relation and inkColors[relation] or theme.ink))
            row.value:SetText(choice[4] == "date" and date("%d/%m/%y %H:%M", value)
                or (choice[1] == "grudge" and "−" or choice[1] == "reputation" and "+" or "") .. value .. " " .. suffix)
            if guild then row.icon:Hide() else row.icon:Show() end
            if relation then row.icon:SetTexture(media .. relationIcons[relation]) end
            if guild then
                row.meta:SetText(plain(item.realm) .. " · " .. counted(item.members, "membre connu", "membres connus") .. " · " .. counted(item.grudges, "rancune") .. " · " .. counted(item.friends, "ami"))
                if f.selected and f.selected.key == item.key then selected = item end
            else
                local faction, _, class = identityLabels(item.record)
                row.meta:SetText(relationNames[relation] .. " · " .. plain(faction) .. " · " .. plain(class) .. " · " .. plain(item.record.guild or "Guilde inconnue"))
            end
            row.bg:SetAlpha(guild and f.selected and f.selected.key == item.key and 0.8 or (i % 2 == 1 and 0.30 or 0.08))
            row:Show()
        else row:Hide() end
    end
    f.selected = selected
    local emptyHelp = guild and "Seules les guildes avec une valeur positive figurent ici."
        or choice[4] == "date" and "Il faut au moins une observation enregistrée d'une personne de cette catégorie."
        or choice[4] == "rencontre" and "Les passages anciens ne sont pas reconstitués."
        or choice[4] == "session" and "Il faut une session de groupe enregistrée avec un ami."
        or "Seules les personnes avec des données pour ce critère figurent ici."
    f.empty:SetText(#rows == 0 and ("Aucun résultat dans cette sélection.\n\n" .. emptyHelp .. (not guild and f.faction ~= "all" and "\nEssaie aussi Toutes les factions." or "")) or "")
    local total = #rows == 0 and "Aucune entrée" or counted(#rows, guild and "guilde" or "personne")
    if #rows > rankingPageSize then total = total .. " · " .. (f.offset + 1) .. "–" .. math.min(f.offset + rankingPageSize, #rows) end
    f.total:SetText(total)
    f.next:SetEnabled(f.offset + rankingPageSize < #rows)
    f.previous:SetEnabled(f.offset > 0)
    for _, b in ipairs(f.guildActions) do
        if guild then b:Show() else b:Hide() end
        b:SetEnabled(f.selected ~= nil)
    end
    local rule = f.selected and GL.GetGuildRule(f.selected.name, f.selected.realm)
    f.selection:SetText(#rows == 0 and "" or guild and (f.selected and plain(f.selected.name) .. " · Avis global : " .. (rule and relationNames[rule.reaction] or "aucun") or "Sélectionne une guilde pour définir un avis global.")
        or "Clique sur une personne pour lire son histoire.")
    f.footnote:SetText(choice[6])
end
function GL.ShowStatistics(mode)
    if not GL.db then return end
    mode = mode == "guilds" and "guilds" or "players"
    if not statisticsWindow then
        local f = bookWindow("GrudgeLedgerStatistics", "Grudge Ledger")
        statisticsWindow = f
        f.rows, f.groups, f.choices, f.guildActions = {}, {}, {}, {}
        bookNavigation(f, "players")
        f.tabs = { players = f.navigation.players, guilds = f.navigation.guilds }
        label(f, "Choisir un thème", "large", 36, -154, 256):SetTextColor(unpack(theme.paper))
        for i = 1, 3 do
            f.groups[i] = button(f, "", 36 + (i - 1) * 87, -215, 82, function()
                f.category, f.choice, f.offset, f.selected = i, 1, 0, nil refreshStatistics()
            end, true)
        end
        for i = 1, 4 do
            f.choices[i] = button(f, "", 36, -255 - (i - 1) * 43, 256, function()
                f.choice, f.offset, f.selected = i, 0, nil refreshStatistics()
            end, true)
            f.choices[i].caption:SetJustifyH("LEFT")
        end
        label(f, "Comment lire ce classement", nil, 36, -442, 256):SetTextColor(unpack(theme.paper))
        f.footnote = label(f, "", nil, 36, -468, 256)
        f.footnote:SetTextColor(unpack(theme.muted))
        f.manage = button(f, "", 36, -620, 256, function()
            if f.mode == "guilds" then GL.ShowGuilds() else GL.ShowJournal("summary") end
        end)
        f.heading = label(f, "", "large", 356, -154, 548)
        f.heading:SetTextColor(unpack(theme.ink))
        f.description = label(f, "", nil, 356, -183, 548)
        f.description:SetHeight(32)
        f.description:SetTextColor(unpack(theme.inkMuted))
        f.factionButton = button(f, "", 356, -225, 155, function()
            local nextFaction = { all = "Alliance", Alliance = "Horde", Horde = "unknown", unknown = "all" }
            f.faction, f.offset, f.selected = nextFaction[f.faction], 0, nil refreshStatistics()
        end, nil, true)
        f.scope = label(f, "", nil, 516, -232, 388)
        f.scope:SetJustifyH("RIGHT") f.scope:SetTextColor(unpack(theme.inkMuted))
        label(f, "#", nil, 364, -255, 24):SetTextColor(unpack(theme.inkMuted))
        f.columnName = label(f, "", nil, 406, -255, 320) f.columnName:SetTextColor(unpack(theme.inkMuted))
        f.columnValue = label(f, "", nil, 741, -255, 163)
        f.columnValue:SetJustifyH("RIGHT") f.columnValue:SetTextColor(unpack(theme.inkMuted))
        for i = 1, rankingPageSize do
            local row = CreateFrame("Button", nil, f)
            row:SetPoint("TOPLEFT", 356, -277 - (i - 1) * 43) row:SetSize(548, 41)
            row.bg = surface(row, theme.selection)
            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints() hover:SetColorTexture(0.57, 0.39, 0.18, 0.15) row:SetHighlightTexture(hover)
            row.rank = label(row, "", nil, 8, -6, 22) row.rank:SetTextColor(unpack(theme.inkMuted))
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("TOPLEFT", 30, -6) row.icon:SetSize(14, 14)
            row.name = label(row, "", nil, 50, -5, 326)
            row.name:SetHeight(18) GL.Safe(row.name.SetWordWrap, row.name, false)
            row.value = label(row, "", nil, 383, -5, 163)
            row.value:SetHeight(18) GL.Safe(row.value.SetWordWrap, row.value, false)
            row.value:SetJustifyH("RIGHT") row.value:SetTextColor(unpack(theme.ink))
            row.meta = label(row, "", nil, 50, -24, 496)
            row.meta:SetFontObject("GameFontHighlightSmall") row.meta:SetHeight(16)
            GL.Safe(row.meta.SetWordWrap, row.meta, false)
            row.meta:SetTextColor(unpack(theme.inkMuted))
            row:SetScript("OnClick", function(self)
                if not self.item then return end
                if f.mode == "guilds" then f.selected = self.item refreshStatistics()
                else f:Hide() GL.ShowLedger(self.item.record.key) end
            end)
            f.rows[i] = row
        end
        f.empty = label(f, "", nil, 406, -310, 470) f.empty:SetTextColor(unpack(theme.inkMuted))
        f.previous = button(f, "Précédent", 356, -589, 110, function() f.offset = math.max(0, f.offset - rankingPageSize) refreshStatistics() end, nil, true)
        f.total = label(f, "", nil, 481, -596, 279) f.total:SetTextColor(unpack(theme.inkMuted))
        f.next = button(f, "Suivant", 794, -589, 110, function() f.offset = f.offset + rankingPageSize refreshStatistics() end, nil, true)
        f.selection = label(f, "", nil, 356, -619, 548) f.selection:SetTextColor(unpack(theme.inkMuted))
        f.selection:SetHeight(17) GL.Safe(f.selection.SetWordWrap, f.selection, false)
        for i, action in ipairs({ { "Guilde à surveiller", "warning" }, { "Guilde amie", "friend" }, { "Avis et note…" } }) do
            local reaction = action[2]
            f.guildActions[i] = button(f, action[1], 356 + (i - 1) * 185, -637, 178, function()
                local selected = f.selected
                if not selected then return end
                if reaction then GL.SetGuildReaction(selected.name, reaction, nil, selected.realm)
                else GL.ShowGuilds({ guild = selected.name, realm = selected.realm }) end
            end, nil, true)
        end
    end
    local f = statisticsWindow
    if f.mode ~= mode then f.mode, f.category, f.choice, f.offset, f.selected = mode, 1, 1, 0, nil end
    f.faction = f.faction or "all"
    showBook(f)
    refreshStatistics()
end
GL.On("CHANGED", refreshStatistics)


local journalPeriods = { { "all", "Tout le récit" }, { "week", "7 derniers jours" }, { "month", "30 derniers jours" }, { "year", "Année" } }
local journalScopes = { { "character", "Ce personnage" }, { "all", "Tout le compte" }, { "legacy", "Auteur inconnu" } }
local journalKinds = { { "all", "Tous les événements" }, { "pvp", "Rencontres PvP" }, { "social", "Avis et gestes" }, { "notes", "Notes personnelles" } }
local function choiceLabel(choices, key)
    for _, entry in ipairs(choices) do if entry[1] == key then return entry[2] end end
    return key
end
local function nextChoice(choices, key)
    for i, entry in ipairs(choices) do if entry[1] == key then return choices[i % #choices + 1][1] end end
    return choices[1][1]
end
local function refreshJournal()
    local f = journalWindow
    if not f or not f:IsShown() then return end
    local history = f.mode == "history"
    f.year = tonumber(f.year) or GL.JournalYears()[1] or tonumber(date("%Y"))
    local options = { period = f.period, year = f.year, scope = f.scope, kind = f.kind, query = f.query or "" }
    local period = choiceLabel(journalPeriods, f.period) .. (f.period == "year" and (" " .. tostring(f.year)) or "")
    local scope = choiceLabel(journalScopes, f.scope)
    f.scopeButton:SetText(scope) f.kindButton:SetText(choiceLabel(journalKinds, f.kind))
    f.yearButton:SetText("Année : " .. tostring(f.year)) f.yearButton:SetEnabled(f.period == "year")
    for _, control in ipairs({ f.kindButton, f.search, f.searchButton, f.searchLabel, f.reset }) do
        if history then control:Show() else control:Hide() end
    end
    for key, control in pairs(f.tabs) do UI.selectButton(control, key == f.mode) end
    for key, control in pairs(f.periodButtons) do UI.selectButton(control, key == f.period) end
    for key, page in pairs({ summary = f.summary, history = f.history, story = f.story }) do
        if key == f.mode then page:Show() else page:Hide() end
    end
    f.heading:SetText(({ summary = "Tableau d'honneur", history = "Chronique des rencontres", story = "Votre récit de campagne" })[f.mode])
    f.subtitle:SetText(scope .. " · " .. period)
    local stats
    if not history then
        options.query, options.kind = "", "pvp"
        stats = GL.PersonalStatistics(options)
    end
    if f.mode == "summary" then
        f.cardName:SetText(f.scope == "character" and plain(stats.actorName or "Votre personnage")
            or f.scope == "legacy" and "Archives sans auteur" or "Les personnages de ce compte")
        for key, metric in pairs(f.metrics) do
            local value = stats[key] or 0
            metric.value:SetText(tostring(value))
            if metric.qualifier then metric.qualifier:SetText(value > 1 and "probables" or "probable") end
        end
        for _, entry in ipairs({ { "mostDeaths", "Némésis", "mort confirmée", "morts confirmées" }, { "mostKilled", "Le plus vaincu", "victoire confirmée", "victoires confirmées" } }) do
            local item, control = stats[entry[1]], f.recaps[entry[1]]
            control.record = item and item.record
            control.name:SetText(item and plain(item.record.fullName) or "Aucun fait confirmé")
            control.detail:SetText(entry[2] .. (item and (" · " .. counted(item.value, entry[3], entry[4])) or ""))
            control:SetEnabled(item ~= nil)
        end
        local unknown = stats.unknownActorEvents or 0
        local coverage = counted(stats.events or 0, "fait retenu", "faits retenus")
        if unknown > 0 then
            coverage = coverage .. " · " .. unknown .. " sans auteur connu" .. (f.scope == "character" and " (hors bilan)" or "")
        end
        f.coverage:SetText(coverage .. " · archives partielles")
        local breakdown = GL.PvPBreakdown(options, f.dimension)
        f.breakdownOffset = math.min(f.breakdownOffset, math.max(0, math.floor((#breakdown - 1) / #f.breakdownRows) * #f.breakdownRows))
        local corrected = 0
        for _, item in ipairs(breakdown) do corrected = corrected + item.correctedKills + item.correctedDeaths end
        for i, row in ipairs(f.breakdownRows) do
            local item = breakdown[f.breakdownOffset + i]
            if item then
                row.name:SetText(plain(item.label))
                row.kills:SetText(item.kills .. " / " .. item.probableKills)
                row.deaths:SetText(item.deaths .. " / " .. item.probableDeaths)
                row:Show()
            else row:Hide() end
        end
        for key, control in pairs(f.dimensionButtons) do
            UI.selectButton(control, key == f.dimension)
        end
        f.breakdownEmpty:SetText(#breakdown == 0 and "Aucune victoire ni mort enregistrée pour cette sélection." or "")
        f.breakdownInfo:SetText(corrected > 0 and counted(corrected, "rapport annulé", "rapports annulés") .. ", hors totaux" or "")
        f.breakdownPrevious:SetEnabled(f.breakdownOffset > 0)
        f.breakdownNext:SetEnabled(f.breakdownOffset + #f.breakdownRows < #breakdown)
    elseif f.mode == "story" then
        local story = {
            "Vous avez remporté " .. counted(stats.kills, "victoire confirmée", "victoires confirmées") .. " et subi " .. counted(stats.deaths, "mort confirmée", "morts confirmées") .. ".", "" }
        if stats.aggressions > 0 then story[#story + 1] = "Le registre compte aussi " .. counted(stats.aggressions, "agression confirmée", "agressions confirmées") .. ".\n" end
        if stats.probableKills + stats.probableDeaths + stats.probableAggressions > 0 then
            story[#story + 1] = "Faits probables : " .. counted(stats.probableKills, "victoire") .. ", " .. counted(stats.probableDeaths, "mort") .. " et " .. counted(stats.probableAggressions, "agression") .. ".\n"
        end
        if stats.mostDeaths then story[#story + 1] = "Votre némésis sur cette période : " .. plain(stats.mostDeaths.record.fullName) .. " (" .. counted(stats.mostDeaths.value, "mort confirmée", "morts confirmées") .. ").\n" end
        if stats.mostKilled then story[#story + 1] = "Votre adversaire le plus vaincu : " .. plain(stats.mostKilled.record.fullName) .. " (" .. counted(stats.mostKilled.value, "victoire confirmée", "victoires confirmées") .. ").\n" end
        if (stats.events or 0) == 0 then story = { "Le récit de cette période reste à écrire.", "", "Aucun fait PvP comptabilisé dans cette sélection. Essayez une période plus large ou un autre personnage." } end
        story[#story + 1] = subdued("Ce récit résume vos archives, pas l'ensemble de votre carrière. Champs de bataille et rapports annulés sont exclus.")
        f.storyText:SetText(table.concat(story, "\n"))
        f.storyBody:SetHeight(math.max(405, f.storyText:GetStringHeight() + 12))
        f.storyScroll:SetVerticalScroll(math.min(f.storyScroll:GetVerticalScroll() or 0, math.max(0, f.storyBody:GetHeight() - f.storyScroll:GetHeight())))
    else
        local events = GL.JournalEvents(options)
        f.offset = math.min(f.offset, math.max(0, math.floor((#events - 1) / #f.rows) * #f.rows))
        for i, row in ipairs(f.rows) do
            local item = events[f.offset + i] row.item = item
            if item then
                local event, record = item.event, item.record
                local title = pvpNames[event.kind] or eventTitle(event)
                if event.kind == "note" then title = event.text or "Note personnelle" end
                if pvpNames[event.kind] then title = title .. (event.confidence == "confirmed" and " confirmée" or " probable") end
                if event.voided then title = title .. " — exclu des compteurs" end
                local place = event.subzone or event.zone
                local author = not event.actorGUID and " · auteur inconnu" or f.scope == "all" and (" · " .. plain(event.actorName or "Autre personnage")) or ""
                row.name:SetText(plain(record.fullName)) row.action:SetText(plain(title):gsub("[\r\n]+", " "))
                row.meta:SetText(stamp(event.time) .. (place and (" · " .. plain(place)) or "") .. author)
                row.stripe:SetColorTexture(unpack(inkColors[GL.Relation(record)] or inkColors.neutral)) row:Show()
            else row:Hide() end
        end
        f.empty:SetText(#events == 0 and "Aucune rencontre dans cette sélection.\nÉlargissez la période ou les filtres." or "")
        f.total:SetText(#events == 0 and "Aucun événement" or (f.offset + 1) .. "–" .. math.min(f.offset + #f.rows, #events) .. " / " .. #events)
        f.previous:SetEnabled(f.offset > 0) f.next:SetEnabled(f.offset + #f.rows < #events)
    end
    f.help:ClearAllPoints() f.help:SetPoint("TOPLEFT", 36, history and -608 or -465) f.help:SetHeight(history and 46 or 180)
    f.help:SetText(history and "Cliquez sur un événement pour ouvrir sa fiche. Validez la recherche avec Entrée ou OK."
        or f.mode == "story" and "Choisissez une période et les personnages dont vous souhaitez relire les combats."
        or "Les colonnes distinguent les faits confirmés et probables.\n\nLa race et la classe sont celles relevées au combat. « Inconnue » signifie que l'information manque.")
end

function GL.ShowJournal(mode)
    if not GL.db then return end
    if not journalWindow then
        local f = bookWindow("GrudgeLedgerJournal", "Grudge Ledger") journalWindow = f
        f.mode, f.period, f.scope, f.kind, f.offset, f.dimension, f.breakdownOffset = "summary", "all", "character", "all", 0, "race", 0
        f.year = GL.JournalYears()[1] or tonumber(date("%Y"))
        bookNavigation(f, "journal")
        label(f, "Votre carnet de route", "large", 36, -154, 256):SetTextColor(unpack(theme.paper))
        f.tabs = {}
        for i, entry in ipairs({ { "summary", "Bilan" }, { "history", "Chronique" }, { "story", "Récit" } }) do
            local key = entry[1]
            f.tabs[key] = button(f, entry[2], 36 + (i - 1) * 87, -192, 82, function() GL.ShowJournal(key) end, true)
        end
        label(f, "Personnages", nil, 36, -245, 256):SetTextColor(unpack(theme.muted))
        f.scopeButton = button(f, "", 36, -267, 256, function() f.scope, f.offset, f.breakdownOffset = nextChoice(journalScopes, f.scope), 0, 0 refreshJournal() end)
        label(f, "Période", nil, 36, -315, 256):SetTextColor(unpack(theme.muted))
        f.periodButtons = {}
        for i, entry in ipairs(journalPeriods) do
            local key = entry[1]
            f.periodButtons[key] = button(f, entry[2], 36 + ((i - 1) % 2) * 133, -341 - math.floor((i - 1) / 2) * 32, 123, function()
                f.period, f.offset, f.breakdownOffset = key, 0, 0 refreshJournal()
            end, true)
        end
        f.yearButton = button(f, "", 36, -416, 256, function()
            local years = GL.JournalYears()
            for i, year in ipairs(years) do if year == f.year then f.year = years[i % #years + 1] break end end
            f.offset, f.breakdownOffset = 0, 0 refreshJournal()
        end)
        f.kindButton = button(f, "", 36, -465, 256, function() f.kind, f.offset = nextChoice(journalKinds, f.kind), 0 refreshJournal() end)
        f.searchLabel = label(f, "Rechercher dans la chronique", nil, 36, -510, 256) f.searchLabel:SetTextColor(unpack(theme.muted))
        f.search = CreateFrame("EditBox", nil, f) f.search:SetPoint("TOPLEFT", 36, -534) f.search:SetSize(195, 26)
        f.search:SetAutoFocus(false) f.search:SetMaxLetters(200) styleInput(f.search, false, false)
        local function searchJournal() f.query, f.offset = f.search:GetText(), 0 f.search:ClearFocus() refreshJournal() end
        f.search:SetScript("OnEnterPressed", searchJournal) f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.searchButton = button(f, "OK", 241, -534, 51, searchJournal)
        f.reset = button(f, "Effacer les filtres", 36, -572, 256, function()
            f.query, f.kind, f.period, f.scope, f.offset = "", "all", "all", "character", 0 f.search:SetText("") refreshJournal()
        end)
        f.help = label(f, "", nil, 36, -608, 256) f.help:SetTextColor(unpack(theme.muted)) f.help:SetHeight(46) f.help:SetFontObject("GameFontHighlightSmall")
        f.heading = label(f, "", "large", 356, -154, 548) f.heading:SetTextColor(unpack(theme.ink))
        f.subtitle = label(f, "", nil, 356, -183, 548) f.subtitle:SetTextColor(unpack(theme.inkMuted))
        f.summary = CreateFrame("Frame", nil, f) f.summary:SetAllPoints(f)
        f.history = CreateFrame("Frame", nil, f) f.history:SetAllPoints(f)
        f.story = CreateFrame("Frame", nil, f) f.story:SetAllPoints(f)
        f.cardName = label(f.summary, "", "large", 356, -216, 548) f.cardName:SetTextColor(unpack(theme.ink))
        f.cardName:SetHeight(26) GL.Safe(f.cardName.SetWordWrap, f.cardName, false)
        f.metrics = {}
        for i, entry in ipairs({ { "kills", "Victoires", "probableKills" }, { "deaths", "Morts", "probableDeaths" }, { "aggressions", "Agressions", "probableAggressions" } }) do
            local card = CreateFrame("Frame", nil, f.summary) card:SetPoint("TOPLEFT", 356 + (i - 1) * 185, -245) card:SetSize(176, 80)
            surface(card, theme.selection):SetAlpha(0.30)
            local value = label(card, "0", "large", 10, -4, 156) value:SetTextColor(unpack(theme.ink))
            local caption = label(card, entry[2] .. "\nconfirmées", nil, 10, -27, 156) caption:SetTextColor(unpack(theme.inkMuted))
            journalFont(caption, "GameFontHighlightSmall", 11) caption:SetHeight(30)
            local probable = label(card, "0", nil, 10, -60, 36) probable:SetTextColor(unpack(theme.inkMuted))
            local qualifier = label(card, "", nil, 43, -60, 120) qualifier:SetTextColor(unpack(theme.inkMuted))
            f.metrics[entry[1]], f.metrics[entry[3]] = { value = value, caption = caption }, { value = probable, qualifier = qualifier }
        end
        f.dimensionButtons = {}
        for i, entry in ipairs({ { "race", "Par race" }, { "class", "Par classe" } }) do
            local key = entry[1]
            f.dimensionButtons[key] = button(f.summary, entry[2], 356 + (i - 1) * 132, -331, 122, function() f.dimension, f.breakdownOffset = key, 0 refreshJournal() end, true, true)
        end
        label(f.summary, "Confirmées / probables", nil, 356, -369, 270):SetTextColor(unpack(theme.inkMuted))
        label(f.summary, "Victoires", nil, 642, -369, 125):SetTextColor(unpack(theme.inkMuted))
        label(f.summary, "Morts", nil, 787, -369, 117):SetTextColor(unpack(theme.inkMuted))
        f.breakdownRows = {}
        for i = 1, 5 do
            local row = CreateFrame("Frame", nil, f.summary) row:SetPoint("TOPLEFT", 356, -394 - (i - 1) * 24) row:SetSize(548, 22)
            surface(row, theme.selection):SetAlpha(i % 2 == 0 and 0.35 or 0)
            row.name = label(row, "", nil, 5, -2, 270) row.name:SetTextColor(unpack(theme.ink))
            row.kills = label(row, "", nil, 286, -2, 125) row.kills:SetTextColor(unpack(theme.ink))
            row.deaths = label(row, "", nil, 431, -2, 117) row.deaths:SetTextColor(unpack(theme.ink))
            for _, text in ipairs({ row.name, row.kills, row.deaths }) do text:SetHeight(20) GL.Safe(text.SetWordWrap, text, false) end
            f.breakdownRows[i] = row
        end
        f.breakdownEmpty = label(f.summary, "", nil, 356, -415, 548) f.breakdownEmpty:SetTextColor(unpack(theme.inkMuted))
        f.breakdownInfo = label(f.summary, "", nil, 356, -522, 410) f.breakdownInfo:SetTextColor(unpack(theme.inkMuted)) f.breakdownInfo:SetFontObject("GameFontHighlightSmall")
        f.breakdownPrevious = button(f.summary, "<", 808, -516, 42, function() f.breakdownOffset = math.max(0, f.breakdownOffset - #f.breakdownRows) refreshJournal() end, nil, true)
        f.breakdownNext = button(f.summary, ">", 862, -516, 42, function() f.breakdownOffset = f.breakdownOffset + #f.breakdownRows refreshJournal() end, nil, true)
        f.recaps = {}
        for i, key in ipairs({ "mostDeaths", "mostKilled" }) do
            local row = CreateFrame("Button", nil, f.summary) row:SetPoint("TOPLEFT", 356, -552 - (i - 1) * 43) row:SetSize(548, 42)
            surface(row, theme.selection):SetAlpha(0.25)
            row.name = label(row, "", nil, 8, -2, 532) row.name:SetTextColor(unpack(theme.ink)) row.name:SetHeight(18)
            row.detail = label(row, "", nil, 8, -22, 532) row.detail:SetTextColor(unpack(theme.inkMuted)) row.detail:SetFontObject("GameFontHighlightSmall") row.detail:SetHeight(20)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", function(self) if self.record then GL.ShowLedger(self.record.key) end end)
            f.recaps[key] = row
        end
        f.coverage = label(f.summary, "", nil, 356, -645, 548) f.coverage:SetTextColor(unpack(theme.inkMuted)) f.coverage:SetFontObject("GameFontHighlightSmall") f.coverage:SetHeight(17)
        f.storyScroll = CreateFrame("ScrollFrame", nil, f.story, "UIPanelScrollFrameTemplate") f.storyScroll:SetPoint("TOPLEFT", 356, -221) f.storyScroll:SetSize(536, 405)
        f.storyBody = CreateFrame("Frame", nil, f.storyScroll) f.storyBody:SetSize(531, 405)
        f.storyText = label(f.storyBody, "", nil, 0, 0, 521) journalFont(f.storyText, "QuestFont_Large", 15) f.storyText:SetTextColor(unpack(theme.ink)) f.storyText:SetSpacing(5)
        f.storyScroll:SetScrollChild(f.storyBody)
        f.rows = {}
        for i = 1, 6 do
            local row = CreateFrame("Button", nil, f.history) row:SetPoint("TOPLEFT", 356, -216 - (i - 1) * 66) row:SetSize(548, 62)
            surface(row, theme.selection):SetAlpha(i % 2 == 0 and 0.25 or 0.08)
            row.stripe = row:CreateTexture(nil, "ARTWORK") row.stripe:SetPoint("TOPLEFT") row.stripe:SetPoint("BOTTOMLEFT") row.stripe:SetWidth(2)
            row.name = label(row, "", nil, 10, -3, 528) row.name:SetTextColor(unpack(theme.ink)) row.name:SetHeight(18)
            row.action = label(row, "", nil, 10, -24, 528) row.action:SetTextColor(unpack(theme.ink)) row.action:SetHeight(18)
            row.meta = label(row, "", nil, 10, -45, 528) row.meta:SetTextColor(unpack(theme.inkMuted)) row.meta:SetFontObject("GameFontHighlightSmall") row.meta:SetHeight(16)
            for _, text in ipairs({ row.name, row.action, row.meta }) do GL.Safe(text.SetWordWrap, text, false) end
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", function(self) if self.item then GL.ShowLedger(self.item.record.key) end end)
            f.rows[i] = row
        end
        f.empty = label(f.history, "", nil, 365, -238, 520) f.empty:SetTextColor(unpack(theme.inkMuted))
        f.previous = button(f.history, "Précédent", 356, -628, 120, function() f.offset = math.max(0, f.offset - #f.rows) refreshJournal() end, nil, true)
        f.total = label(f.history, "", nil, 486, -635, 284) f.total:SetJustifyH("CENTER") f.total:SetTextColor(unpack(theme.inkMuted))
        f.next = button(f.history, "Suivant", 784, -628, 120, function() f.offset = f.offset + #f.rows refreshJournal() end, nil, true)
    end
    journalWindow.mode = (mode == "history" or mode == "story") and mode or "summary"
    showBook(journalWindow) refreshJournal()
end
GL.On("CHANGED", refreshJournal)

local function refreshCorrections()
    if not correctionWindow or not correctionWindow:IsShown() then return end
    local f, events = correctionWindow, {}
    local record = GL.Get(f.identity)
    for i = #(record and record.history or {}), 1, -1 do
        local event = record.history[i]
        if pvpNames[event.kind] then events[#events + 1] = event end
    end
    f.offset = math.min(f.offset, math.max(0, math.floor((#events - 1) / 6) * 6))
    for i, row in ipairs(f.rows) do
        local event = events[f.offset + i]
        if event then
            row.title:SetText(stamp(event.time) .. " — " .. pvpNames[event.kind] .. " (" .. (event.confidence == "confirmed" and "confirmé" or "probable") .. ")" .. (event.voidReason == "battleground" and " — champ de bataille, exclu" or event.voided and " — annulé" or ""))
            row.evidence:SetText(plain(event.evidence or "Aucune précision enregistrée."))
            row.undo:SetText(event.voided and "Annulé" or "Annuler")
            row.undo:SetEnabled(not event.voided)
            -- Keep the record and actual history table, never a mutable row index or current target.
            local originalIdentity = f.identity
            row.undo:SetScript("OnClick", function()
                local ok, err = GL.VoidPvP(originalIdentity, event)
                f.status:SetText(ok and "Événement annulé ; il reste visible dans l'historique." or plain(err or "Correction impossible."))
                refreshCorrections()
            end)
            row:Show()
        else row.undo:SetScript("OnClick", nil) row:Hide() end
    end
    f.total:SetText(#events == 0 and "Aucun événement PvP." or #events .. " événement(s) — page " .. (math.floor(f.offset / 6) + 1))
    f.next:SetEnabled(f.offset + 6 < #events)
end

local function showCorrections(record)
    if not record then return end
    if not correctionWindow then
        local f = window("GrudgeLedgerCorrections", "Grudge Ledger — Corriger le PvP", 740, 590)
        correctionWindow = f
        f.target = label(f, "", "large", 18, -54, 700)
        label(f, "Annuler retire l'événement des compteurs ; son historique est conservé.", nil, 18, -81, 700)
        f.rows = {}
        for i = 1, 6 do
            local row = CreateFrame("Frame", nil, f)
            row:SetPoint("TOPLEFT", 18, -113 - (i - 1) * 65)
            row:SetSize(704, 60)
            surface(row, i % 2 == 0 and theme.panel or theme.background)
            row.title = label(row, "", nil, 0, -1, 585)
            row.title:SetTextColor(0.83, 0.7, 0.45)
            row.evidence = label(row, "", nil, 0, -22, 585)
            row.evidence:SetHeight(32)
            row.evidence:SetTextColor(unpack(theme.muted))
            row.undo = button(row, "Annuler", 603, -10, 99, nil)
            f.rows[i] = row
        end
        button(f, "Précédent", 18, -515, 115, function() f.offset = math.max(0, f.offset - 6) refreshCorrections() end)
        f.next = button(f, "Suivant", 143, -515, 115, function() f.offset = f.offset + 6 refreshCorrections() end)
        f.total = label(f, "", nil, 280, -521, 440)
        f.status = label(f, "", nil, 18, -555, 704)
    end
    local identity = {}
    for _, field in ipairs({ "key", "guid", "name", "surname", "alias" }) do identity[field] = record[field] end
    correctionWindow.identity, correctionWindow.offset = identity, 0
    correctionWindow.target:SetText(plain(record.fullName or record.name))
    correctionWindow.status:SetText("")
    correctionWindow:Show()
    correctionWindow:Raise()
    refreshCorrections()
end

local function showDiagnostic(private)
    if not diagnosticWindow then
        local f = window("GrudgeLedgerDiagnostic", "Grudge Ledger — Diagnostic", 660, 500)
        diagnosticWindow = f
        f.privacy = label(f, "", nil, 18, -54, 620)
        f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT", 22, -91)
        f.scroll:SetSize(590, 315)
        f.edit = CreateFrame("EditBox", nil, f.scroll)
        f.edit:SetMultiLine(true)
        f.edit:SetFontObject("ChatFontNormal")
        f.edit:SetSize(580, 315)
        f.edit:SetAutoFocus(false)
        styleInput(f.edit, true)
        f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() f:Hide() end)
        f.scroll:SetScrollChild(f.edit)
        f.radarStatus = label(f, "Réapplique l'apparence native ; rotation conservée.", nil, 234, -424, 395)
        f.radarStatus:SetHeight(30)
        button(f, "Préparer la minimap", 22, -421, 200, function()
            local _, message = GL.PrepareDruidRadar()
            f.radarStatus:SetText(message)
            f.edit:ClearFocus()
        end)
        button(f, "Tout sélectionner", 22, -461, 150, function() f.edit:SetFocus() f.edit:HighlightText() end)
        button(f, "Effacer les traces", 186, -461, 150, function() GL.ClearDetectionLog() showDiagnostic(f.private) end)
        button(f, "Actualiser", 350, -461, 120, function() showDiagnostic(f.private) end)
        button(f, "Validation druide", 484, -461, 145, function()
            if SlashCmdList.GRUDGELEDGERDRUIDRADAR and C_Timer and type(C_Timer.After) == "function" then
                f:Hide()
                GL.Print("Essai dans 3 secondes : place la souris sur le monde, hors fenêtres, puis reste immobile.")
                C_Timer.After(3, function() SlashCmdList.GRUDGELEDGERDRUIDRADAR("validation") end)
            end
        end)
    end
    local function version(value)
        value = GL.Clean(value)
        if type(value) == "string" or type(value) == "number" then
            value = tostring(value)
            if #value <= 32 and value:match("^%d[%d%.]*$") then return value end
        end
        return "indisponible"
    end
    local client, build, _, interface = GL.Safe(GetBuildInfo)
    local loading, loaded = GL.Safe((C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded, "TidyPlates_ThreatPlates")
    loaded = loaded == true or (loaded == nil and loading == true)
    local lines = { "Grudge Ledger " .. version(GL.version), "Client : " .. version(client), "Build : " .. version(build),
        "Interface : " .. version(interface), "Intégration détectée : " .. (loaded and "Threat Plates" or "aucune"),
        "Erreurs conservées : " .. #(GL.errors or {}), "", "API disponibles :" }
    for _, api in ipairs({
        { "Menu.ModifyMenu", Menu and Menu.ModifyMenu }, { "C_NamePlate.GetNamePlateForUnit", C_NamePlate and C_NamePlate.GetNamePlateForUnit },
        { "GetGuildInfo", GetGuildInfo }, { "CombatLogGetCurrentEventInfo", CombatLogGetCurrentEventInfo },
        { "C_ChatInfo.PerformEmote", C_ChatInfo and C_ChatInfo.PerformEmote }, { "DoEmote", DoEmote },
    }) do lines[#lines + 1] = api[1] .. " : " .. (type(api[2]) == "function" and "oui" or "non") end
    lines[#lines + 1] = "\nRéglages :"
    for _, key in ipairs({ "markers", "nameColor", "friendAlerts", "enemyAlerts", "sounds", "pvpTracking", "groupTracking", "socialTracking" }) do
        lines[#lines + 1] = key .. " : " .. (GL.Clean(GL.Settings()[key], "boolean") == true and "oui" or "non")
    end
    lines[#lines + 1] = "\nAffichage des noms :"
    for _, key in ipairs({ "nameplateShowFriendlyPlayers", "nameplateShowEnemies", "nameplateShowAll", "nameplateShowOnlyNameForFriendlyPlayerUnits" }) do
        local value = GL.Safe((C_CVar and C_CVar.GetCVar) or GetCVar, key)
        lines[#lines + 1] = key .. " : " .. ((value == "0" or value == "1") and value or "indisponible")
    end
    diagnosticWindow.private = private == true
    diagnosticWindow.privacy:SetText(private == true and "Journal local : contient les noms de ton livre. Ne le publie pas tel quel."
        or "Rapport anonyme : Ctrl+C pour copier. Aucun nom ni note personnelle.")
    lines[#lines + 1] = GL.DetectionReport(private == true)
    diagnosticWindow.edit:SetText(table.concat(lines, "\n"))
    local _, fontHeight = diagnosticWindow.edit:GetFont()
    diagnosticWindow.edit:SetHeight(math.max(315, diagnosticWindow.edit:GetNumLines() * (fontHeight + diagnosticWindow.edit:GetSpacing()) + 8))
    diagnosticWindow.scroll:SetVerticalScroll(0)
    diagnosticWindow:Show()
    diagnosticWindow:Raise()
    diagnosticWindow.edit:SetFocus()
    diagnosticWindow.edit:HighlightText()
end

local function counted(value, noun)
    return tostring(value) .. " " .. noun .. (value > 1 and "s" or "")
end

local function renderDetail()
    local record = currentRecord()
    local tab = ledger.detailTab or "summary"
    for key, control in pairs(ledger.detailTabs) do
        UI.selectButton(control, tab == key)
    end
    for _, b in ipairs(ledger.actions) do b:SetEnabled(record ~= nil) end
    ledger.guildButton:SetEnabled(record ~= nil and record.guild ~= nil)
    ledger.tools:SetEnabled(record ~= nil)
    if not record then ledger.toolsMenu:Hide() end
    for reaction, control in pairs(ledger.reactions) do
        UI.selectButton(control, record and GL.Relation(record) == reaction)
    end
    local summary = tab == "summary" and record ~= nil
    if summary then ledger.counters:Show() else ledger.counters:Hide() end
    ledger.detailScroll:ClearAllPoints()
    ledger.detailScroll:SetPoint("TOPLEFT", 356, summary and -450 or -283)
    ledger.detailScroll:SetHeight(summary and 126 or 293)
    ledger.detailTitle:SetTextColor(unpack(theme.ink))
    local lines = {}
    if not record then
        ledger.detailTitle:SetText("Une histoire à retrouver")
        ledger.detailIcon:SetTexture(GL.icon)
        ledger.detailStatus:SetText("")
        ledger.detailStatus:SetTextColor(unpack(theme.inkMuted))
        ledger.detailIdentity:SetText("Sélectionne une personne dans l’index.")
        ledger.detailSource:SetText("") ledger.detailGuild:SetText("")
        ledger.raceIcon:Hide() ledger.classIcon:Hide()
        lines = { "Pour créer une fiche, cible un joueur puis clique sur « Ajouter la cible ». Tu peux aussi ouvrir le menu Grudge Ledger depuis son portrait." }
    else
        local relation, pvp = GL.Relation(record), record.pvp or {}
        ledger.detailTitle:SetText(plain(record.fullName or record.name or record.key))
        ledger.detailIcon:SetTexture(media .. relationIcons[relation])
        local source = GL.RelationSource(record)
        ledger.detailStatus:SetText(relationNames[relation])
        ledger.detailSource:SetText(({ manual = "Avis personnel", emote = "Avis issu de vos gestes", pvp = "Avis issu du PvP", guild = "Avis hérité de la guilde", automatic = "Avis automatique", neutral = "Aucun avis" })[source] or "Avis automatique")
        ledger.detailStatus:SetTextColor(unpack(inkColors[relation]))
        local faction, race, class = identityLabels(record)
        ledger.detailIdentity:SetText(plain(faction .. " · " .. race .. " · " .. class))
        ledger.detailGuild:SetText(record.guild and plain(record.guild) or "Guilde non renseignée")
        ledger.raceIcon:Show() ledger.classIcon:Show() identityIcons(ledger, record)
        if summary then
            for _, entry in ipairs({ { "kills", "probableKills" }, { "deaths", "probableDeaths" } }) do
                local card = ledger.metrics[entry[1]]
                local probable = pvp[entry[2]] or 0
                card.value:SetText((pvp[entry[1]] or 0) .. " fois")
                card.probable:SetText(counted(probable, "probable"))
            end
            local score, raw = GL.AutomaticBalance(record)
            ledger.balance:SetText(tostring(score))
            ledger.balance:SetTextColor(unpack(score < 0 and inkColors.enemy or score > 0 and inkColors.friend or theme.ink))
            local deaths = (pvp.deaths or 0) + (pvp.probableDeaths or 0)
            local wins = (pvp.kills or 0) + (pvp.probableKills or 0)
            local hits = (pvp.aggressions or 0) + (pvp.probableAggressions or 0)
            local formula = counted(deaths, "mort") .. " × −10  +  " .. counted(wins, "victoire")
            if hits > 0 then formula = formula .. "  −  " .. counted(hits, "agression") end
            ledger.formula:SetText(formula .. "  =  " .. raw .. " PvP")
            ledger.scoreContext:SetText(source == "manual" and ("Avis personnel prioritaire  ·  " .. tostring(record.reputation or 0))
                or "Les faits probables et les gestes comptent dans le solde.")
            local guildRule = GL.GetGuildRule(record)
            lines = {
                "|cff653c20Dernière rencontre|r",
                record.lastEncounterAt and (stamp(record.lastEncounterAt) .. "  ·  " .. plain(record.lastEncounterSubzone or record.lastEncounterZone or "Lieu non renseigné")) or "Date non enregistrée",
            }
            local note = record.notes and record.notes[#record.notes]
            if note then
                -- ponytail: a short UTF-8-safe preview keeps the summary compact; Notes retains the full text.
                local count = 0
                local preview = note.text:gsub("[ \t\r\n\f\v]+", " "):gsub("[%z\1-\127\194-\244][\128-\191]*", function(character)
                    count = count + 1
                    return count <= 80 and character or ""
                end)
                lines[#lines + 1] = "\n|cff653c20Dernière note|r"
                lines[#lines + 1] = plain(preview) .. (count > 80 and "… (suite dans Notes)" or "")
            else lines[#lines + 1] = "\nAucune note personnelle." end
            lines[#lines + 1] = "\nRencontres mémorisées : " .. (record.encounters and record.encounters.count or 0)
            lines[#lines + 1] = "Agressions : " .. counted(pvp.aggressions or 0, "confirmée") .. ", " .. counted(pvp.probableAggressions or 0, "probable") .. "."
            if guildRule and guildRule.note and guildRule.note ~= "" then lines[#lines + 1] = "Note de guilde : " .. plain(guildRule.note) end
            if (record.groupCount or 0) > 0 then lines[#lines + 1] = subdued(tostring(record.groupCount) .. " session(s) de groupe mémorisée(s).") end
        elseif tab == "notes" then
            lines = { "|cff653c20NOTES PERSONNELLES|r", "" }
            if #(record.notes or {}) == 0 then lines[#lines + 1] = "Aucun souvenir noté. Utilise « Ajouter une note » pour garder le contexte." end
            for i = #(record.notes or {}), 1, -1 do
                local note = record.notes[i]
                lines[#lines + 1] = subdued(stamp(note.time))
                lines[#lines + 1] = plain(note.text) .. "\n"
            end
            lines[#lines + 1] = subdued("L'éditeur permet aussi de modifier ou supprimer tes notes.")
        else
            lines = { "|cff653c20HISTOIRE RÉCENTE|r " .. subdued("(20 derniers événements)") }
            local history = record.history or {}
            if #history == 0 then lines[#lines + 1] = "Aucun événement." end
            for i = #history, math.max(1, #history - 19), -1 do
                local e = history[i]
                lines[#lines + 1] = "\n" .. subdued(stamp(e.time)) .. (e.voidReason == "battleground" and " — champ de bataille, non comptabilisé" or e.voided and " — annulé, non comptabilisé" or "")
                local delta = type(e.delta) == "number" and e.delta ~= 0 and (" — avis " .. (e.delta > 0 and "+" or "") .. e.delta) or ""
                lines[#lines + 1] = eventTitle(e) .. delta
                local place = e.zone and e.zone ~= "?" and e.zone or ""
                if e.subzone and e.subzone ~= "" and e.subzone ~= place then place = e.subzone .. (place ~= "" and " · " .. place or "") end
                if place ~= "" then lines[#lines + 1] = subdued(plain(place)) end
                if e.questTitle then lines[#lines + 1] = "Quête suivie : " .. plain(e.questTitle) end
                if e.kind == "death" and e.confidence ~= "confirmed" then lines[#lines + 1] = "Indices de participation à l'attaque ; coup fatal non identifié."
                elseif e.kind == "kill" and e.confidence ~= "confirmed" then lines[#lines + 1] = "Mort observée après un combat ; victoire à confirmer."
                elseif e.kind == "aggression" and e.confidence ~= "confirmed" then lines[#lines + 1] = "Attaque soupçonnée ; source des dégâts non confirmée." end
                if e.source ~= "emote" and not pvpNames[e.kind] and e.evidence and e.evidence ~= "" and e.evidence ~= "Avis personnel" then
                    lines[#lines + 1] = plain(e.evidence)
                end
                if e.guildSource and e.guild then
                    lines[#lines + 1] = subdued("Guilde mémorisée : " .. plain(e.guild) .. (e.guildRealm and " (" .. plain(e.guildRealm) .. ")" or "")
                        .. (e.guildSource == "last-known" and " — observée auparavant" or ""))
                end
            end
        end
    end
    ledger.detailText:SetText(table.concat(lines, "\n"))
    ledger.detailText:SetSpacing(GL.Settings().compactMode and 2 or 4)
    ledger.detailBody:SetHeight(math.max(ledger.detailScroll:GetHeight(), ledger.detailText:GetStringHeight() + 12))
    ledger.detailScroll:SetVerticalScroll(math.min(ledger.detailScroll:GetVerticalScroll(), math.max(0, ledger.detailBody:GetHeight() - ledger.detailScroll:GetHeight())))
end

local function enableRecognition()
    if GL.Safe(InCombatLockdown) then GL.Print("Active le repérage hors combat.") return end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ready = true
    -- Forever uses the per-player filter, not the old nameplateShowFriends CVar.
    for _, key in ipairs({ "nameplateShowFriendlyPlayers", "nameplateShowEnemies", "nameplateShowAll" }) do
        GL.Safe(set, key, 1)
        if GL.Safe(get, key) ~= "1" then ready = false end
    end
    GL.SetSetting("markers", true)
    GL.SetSetting("nameColor", true)
    if settingsWindow then settingsWindow:UpdatePlateStatus() end
    GL.Print(ready and "Repérage activé : barres de noms, icônes et couleurs. Ennemi = rouge, méfiance = orange."
        or "Icônes et couleurs activées, mais le jeu n'a pas confirmé toutes les barres de noms. Vérifie les réglages d'affichage.")
end

showSettings = function()
    if not settingsWindow then
        local f = bookWindow("GrudgeLedgerSettings", "Grudge Ledger")
        settingsWindow = f
        bookNavigation(f, "settings")
        label(f, "Réglages du registre", "large", 36, -154, 256):SetTextColor(unpack(theme.paper))
        f.tabs, f.pages, f.checks, f.category = {}, {}, {}, "appearance"
        local categories = { { "appearance", "Apparence", "Police, taille et marqueurs" }, { "alerts", "Alertes", "Sons et messages de groupe" },
            { "relations", "Relations", "PvP, groupes et émotes" }, { "shortcuts", "Raccourcis", "Gestes et commandes" }, { "data", "Données et aide", "Diagnostic et premiers pas" } }
        function f:SelectCategory(key)
            self.category = self.pages[key] and key or "appearance"
            for name, page in pairs(self.pages) do
                if name == self.category then page:Show() else page:Hide() end
                UI.selectButton(self.tabs[name], name == self.category)
            end
        end
        for i, entry in ipairs(categories) do
            local key = entry[1]
            f.tabs[key] = button(f, entry[2], 36, -229 - (i - 1) * 65, 256, function() f:SelectCategory(key) end, true)
            label(f, entry[3], nil, 44, -260 - (i - 1) * 65, 240):SetTextColor(unpack(theme.muted))
            local page = CreateFrame("Frame", nil, f) page:SetAllPoints(f) f.pages[key] = page
            label(page, entry[2], "large", 356, -154, 548):SetTextColor(unpack(theme.ink))
        end
        local function copy(page, text, y, height)
            local textLabel = label(page, text, nil, 356, y, 548)
            textLabel:SetTextColor(unpack(theme.inkMuted))
            if height then textLabel:SetHeight(height) end
            return textLabel
        end
        local function check(category, key, text, y)
            local control = CreateFrame("CheckButton", nil, f.pages[category], "UICheckButtonTemplate")
            control:SetPoint("TOPLEFT", 352, y) control:SetSize(26, 26)
            control:SetHitRectInsets(0, -516, 0, 0)
            local caption = label(control, text, nil, 33, -5, 510) caption:SetTextColor(unpack(theme.ink))
            control:SetScript("OnClick", function(self) GL.SetSetting(key, self:GetChecked() and true or false) end)
            f.checks[key] = control
        end
        local p = f.pages.appearance
        check("appearance", "readableFont", "Police classique (plus lisible)", -235)
        check("appearance", "compactMode", "Espacement compact dans les fiches", -274)
        f.readingLabel = copy(p, "", -326, 20)
        button(p, "−", 745, -319, 45, function() GL.SetSetting("readingScale", math.max(0.85, (GL.Settings().readingScale or 1) - 0.05)) end, nil, true)
        button(p, "+", 798, -319, 45, function() GL.SetSetting("readingScale", math.min(1.25, (GL.Settings().readingScale or 1) + 0.05)) end, nil, true)
        button(p, "100 %", 851, -319, 53, function() GL.SetSetting("readingScale", 1) end, nil, true)
        check("appearance", "markers", "Icônes près des noms", -375)
        check("appearance", "nameColor", "Colorer aussi le nom (si compatible)", -414)
        copy(p, "Les marqueurs s'accrochent aux barres de noms. Les noms flottants seuls ne peuvent pas les porter.", -463, 48)
        f.plateStatus = copy(p, "", -523, 35)
        function f:UpdatePlateStatus()
            local function status(key)
                local value = GL.Clean(GL.Safe((C_CVar and C_CVar.GetCVar) or GetCVar, key), "string")
                return value == "1" and "activées" or value == "0" and "désactivées" or "inconnu"
            end
            self.plateStatus:SetText("Alliés : " .. status("nameplateShowFriendlyPlayers") .. " · Ennemis : " .. status("nameplateShowEnemies"))
        end
        button(p, "Activer le repérage (icônes + couleurs)", 356, -573, 548, enableRecognition, nil, true)
        p = f.pages.alerts
        check("alerts", "friendAlerts", "Alerte quand un ami apparaît", -239)
        check("alerts", "enemyAlerts", "Alerte quand un ennemi apparaît", -281)
        check("alerts", "sounds", "Sons des alertes", -323)
        copy(p, "Les amis du groupe restent identifiés, sans alerte répétée. Une nouvelle rencontre amicale est annoncée après plus de 10 minutes d'absence.", -373, 78)
        check("alerts", "partyWarnings", "Prévenir le groupe d'un ancien agresseur", -470)
        copy(p, "Option désactivée par défaut. Hors raid, champ de bataille et arène : une alerte par rencontre, 30 min par personne et 60 s entre messages.", -519, 90)
        p = f.pages.relations
        copy(p, "Votre avis personnel garde la priorité. Une rencontre en groupe ne crée pas une amitié à elle seule.", -190, 54)
        check("relations", "pvpTracking", "Historique PvP automatique", -266)
        check("relations", "groupTracking", "Historique des groupes", -308)
        check("relations", "socialTracking", "Avis via mes émotes", -350)
        copy(p, "Le solde reste tenace : une mort vaut −10, une agression −1 et une victoire +1. Les faits probables restent signalés comme tels.\n\nChamps de bataille et arènes sont exclus du registre des rancunes. Les notes et choix manuels restent à vous.", -407, 170)
        p = f.pages.shortcuts
        copy(p, "Sélectionnez un joueur, puis envoyez un geste ou ouvrez son menu de portrait.", -190, 48)
        check("shortcuts", "quickGestures", "Boutons bisou / crachat", -251)
        for i, entry in ipairs({ { media .. "GestureKiss", "Bisou", "Un avis positif envers la cible." }, { "Interface\\Icons\\Spell_Nature_CorrosiveBreath", "Crachat", "Un avis négatif envers la cible." } }) do
            local x = 356 + (i - 1) * 280
            local icon = p:CreateTexture(nil, "ARTWORK") icon:SetPoint("TOPLEFT", x, -303) icon:SetSize(48, 48) icon:SetTexture(entry[1])
            label(p, entry[2], "large", x + 58, -310, 210):SetTextColor(unpack(theme.ink))
            local note = label(p, entry[3], nil, x, -363, 260) note:SetTextColor(unpack(theme.inkMuted))
        end
        button(p, "Replacer les boutons", 356, -425, 548, function() if GL.ResetGesturePosition then GL.ResetGesturePosition() end end, nil, true)
        copy(p, "Maintenez Ctrl pour déplacer les boutons.\n\nCommandes utiles : /gl · /gl note · /gl + · /gl -\nLe clic droit sur un portrait donne accès aux avis et à la fiche.", -477, 130)
        p = f.pages.data
        copy(p, "Votre carnet est personnel. Distribuer le dossier de l'addon ne distribue pas vos notes ni vos rencontres : elles sont conservées dans les données sauvegardées du jeu.", -190, 85)
        check("data", "detectionLog", "Conserver le diagnostic des détections (200 lignes)", -294)
        button(p, "Diagnostic", 356, -348, 264, function() showDiagnostic(false) end, nil, true)
        button(p, "Journal des détections", 640, -348, 264, function() showDiagnostic(true) end, nil, true)
        copy(p, "Le diagnostic permet de comprendre une détection manquée. Relisez les informations avant de les transmettre.\n\nUne erreur dans le PvP ? Ouvrez la fiche de la personne puis « Corriger le PvP ». Les événements annulés restent consultables.", -400, 144)
        button(p, "Revoir les premiers pas", 356, -573, 548, function() GL.ShowGuide() end, nil, true)
    end
    for key, check in pairs(settingsWindow.checks) do check:SetChecked(GL.Settings()[key]) end
    settingsWindow.readingLabel:SetText("Taille de lecture : " .. math.floor((GL.Settings().readingScale or 1) * 100 + 0.5) .. " %")
    settingsWindow:UpdatePlateStatus()
    showBook(settingsWindow)
    settingsWindow:SelectCategory(settingsWindow.category)
end

function GL.ShowGuide()
    if not GL.db then return end
    if not guideWindow then
        local f = window("GrudgeLedgerGuide", "Bienvenue dans votre registre", 560, 438)
        guideWindow = f
        label(f, "Marquer un joueur", "large", 25, -59, 510)
        label(f, "Sélectionnez un joueur puis cliquez sur l'un des deux gestes près du chat.", nil, 25, -96, 510)
        for i, entry in ipairs({ { media .. "GestureKiss", "Un bisou pour un avis positif." }, { "Interface\\Icons\\Spell_Nature_CorrosiveBreath", "Un crachat pour un avis négatif." } }) do
            local y = -155 - (i - 1) * 66
            local icon = f:CreateTexture(nil, "ARTWORK") icon:SetPoint("TOPLEFT", 25, y) icon:SetSize(46, 46) icon:SetTexture(entry[1])
            label(f, entry[2], nil, 87, y - 9, 448)
        end
        label(f, "Un clic droit sur son portrait permet aussi de choisir un avis ou d’ajouter une note privée.\n\nRetrouvez cette aide dans Réglages → Données et aide.", nil, 25, -290, 510)
        button(f, "Ouvrir mon registre", 25, -388, 510, function() f:Hide() GL.ShowLedger() end)
    end
    GL.SetSetting("guideSeen", true)
    guideWindow:Show() guideWindow:Raise()
end

local function buildLedger()
    if ledger then return end
    local f = bookWindow("GrudgeLedgerWindow", "Grudge Ledger")
    ledger = f
    bookNavigation(f, "ledger")
    f.detailTab, f.query = "summary", ""
    button(f, "Ajouter la cible", 189, -155, 118, function()
        local identity = GL.Identity("target")
        if not identity then GL.Print("Sélectionne un joueur pour ouvrir sa fiche.") return end
        local record = GL.Remember(identity)
        if record then GL.ShowLedger(record.key) end
    end, nil, false)
    f.search = CreateFrame("EditBox", nil, f)
    f.search:SetPoint("TOPLEFT", 36, -155)
    f.search:SetSize(121, 26)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(100)
    styleInput(f.search, false, false)
    local function applySearch() f.query = f.search:GetText() offset = 0 f.search:ClearFocus() refresh() end
    f.search:SetScript("OnEnterPressed", applySearch)
    f.searchButton = button(f, "OK", 159, -155, 28, applySearch)
    f.searchButton.caption:SetWidth(26) f.searchButton.caption:ClearAllPoints() f.searchButton.caption:SetPoint("CENTER")
    f.searchHint = label(f.search, "Rechercher…", nil, 8, -6, 107)
    f.searchHint:SetTextColor(unpack(theme.muted))
    f.search:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then f.searchHint:Show() else f.searchHint:Hide() end
    end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local openMenu
    local function closeMenu()
        if openMenu then openMenu:Hide() openMenu = nil end
    end
    f.closeMenu = closeMenu
    local function toggleMenu(menu)
        local opening = not menu:IsShown()
        closeMenu()
        if opening then openMenu = menu menu:Show() menu:Raise() end
    end
    f:HookScript("OnHide", closeMenu)
    local function filterMenu(x, options, select)
        local menu = CreateFrame("Frame", nil, f)
        menu:SetPoint("TOPLEFT", x, -222) menu:SetSize(134, #options * 28 + 4)
        menu:EnableMouse(true) menu:SetFrameStrata("FULLSCREEN_DIALOG") menu:SetToplevel(true)
        surface(menu, theme.gold) surface(menu, theme.panel, 1)
        local choices = {}
        for i, entry in ipairs(options) do
            local value = entry[2]
            choices[value] = button(menu, entry[1], 2, -2 - (i - 1) * 28, 130, function()
                menu:Hide() select(value) offset = 0 refresh()
            end, true)
        end
        menu:Hide()
        local opener = button(f, "", x, -193, 134, function() toggleMenu(menu) end)
        opener.caption:ClearAllPoints() opener.caption:SetPoint("TOPLEFT", 3, -5) opener.caption:SetWidth(112)
        local arrow = opener:CreateTexture(nil, "ARTWORK")
        arrow:SetPoint("RIGHT", -3, 0) arrow:SetSize(16, 16)
        arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        return opener, choices
    end
    f.relationFilter, f.filters = filterMenu(36, { { "Tous les avis", "all" }, { "Amis", "friend" }, { "Méfiance", "warning" },
        { "Ennemis", "enemy" }, { "Neutres", "neutral" } }, function(value) filter = value end)
    f.factionFilter, f.factions = filterMenu(173, { { "Toutes factions", "all" }, { "Alliance", "Alliance" },
        { "Horde", "Horde" }, { "Inconnue", "unknown" } }, function(value) factionFilter = value end)
    f.rows = {}
    f.sort = button(f, "Tri : Rencontres", 149, -229, 158, function()
        for i, choice in ipairs(sortChoices) do
            if choice[1] == listSort then listSort = sortChoices[i % #sortChoices + 1][1] break end
        end
        offset = 0
        GL.SetSetting("listSort", listSort)
        refresh()
    end, nil, false)
    f.notesOnly = button(f, "Avec notes", 36, -229, 107, function() notesOnly, offset = not notesOnly, 0 refresh() end, true, false)
    f.detail = button(f, "Détail : Identité", 36, -262, 177, function()
        for i, choice in ipairs(detailChoices) do
            if choice[1] == listDetail then listDetail = detailChoices[i % #detailChoices + 1][1] break end
        end
        GL.SetSetting("listDetail", listDetail)
        refresh()
    end, nil, false)
    f.reset = button(f, "Effacer", 218, -262, 89, function()
        filter, factionFilter, notesOnly, offset, f.query = "all", "all", false, 0, ""
        f.search:SetText("") refresh()
    end)
    for i = 1, 6 do
        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT", 32, -301 - (i - 1) * 53)
        row:SetSize(277, 51)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(theme.red[1], theme.red[2], theme.red[3], 1)
        row.selection = row:CreateTexture(nil, "BORDER")
        row.selection:SetAllPoints()
        row.selection:SetTexture(media .. "JournalButtons")
        row.selection:SetTexCoord(36 / 1254, 1218 / 1254, 514 / 1254, 768 / 1254)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT") rule:SetPoint("BOTTOMRIGHT") rule:SetHeight(1)
        rule:SetColorTexture(theme.gold[1], theme.gold[2], theme.gold[3], 0.62)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.57, 0.39, 0.18, 0.16)
        row:SetHighlightTexture(hover)
        row.relationIcon = row:CreateTexture(nil, "ARTWORK")
        row.relationIcon:SetPoint("TOPLEFT", 193, -28)
        row.relationIcon:SetSize(16, 16)
        row.name = label(row, "", nil, 52, -4, 218)
        journalFont(row.name, "Fancy16Font", 16)
        row.name:SetHeight(23)
        GL.Safe(row.name.SetWordWrap, row.name, false)
        GL.Safe(row.name.SetMaxLines, row.name, 1)
        row.raceIcon = row:CreateTexture(nil, "ARTWORK")
        row.raceIcon:SetPoint("TOPLEFT", 6, -4)
        row.raceIcon:SetSize(42, 42)
        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetPoint("TOPLEFT", 51, -29)
        row.classIcon:SetSize(15, 15)
        row.identity = label(row, "", nil, 70, -29, 119)
        journalFont(row.identity, "GameFontHighlightSmall", 12)
        row.identity:SetTextColor(unpack(theme.muted))
        row.identity:SetHeight(18)
        GL.Safe(row.identity.SetWordWrap, row.identity, false)
        GL.Safe(row.identity.SetMaxLines, row.identity, 1)
        row.relation = label(row, "", nil, 210, -29, 63)
        journalFont(row.relation, "GameFontHighlightSmall", 12)
        row.relation:SetJustifyH("RIGHT")
        row.relation:SetHeight(18)
        GL.Safe(row.relation.SetWordWrap, row.relation, false)
        GL.Safe(row.relation.SetMaxLines, row.relation, 1)
        row:SetScript("OnClick", function(self) closeMenu() selectedKey = self.key f.detailScroll:SetVerticalScroll(0) refresh() end)
        row:SetScript("OnEnter", function(self)
            local record = self.key and GL.Get(self.key)
            if not record or not GameTooltip then return end
            local faction, race, class = identityLabels(record)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(plain(record.fullName or record.name))
            GameTooltip:AddLine(plain(faction .. " · " .. race .. " · " .. class))
            if record.guild then GameTooltip:AddLine(plain(record.guild)) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = row
    end
    f.previous = button(f, "‹", 36, -634, 32, function() offset = math.max(0, offset - #f.rows) refresh() end, nil, false)
    f.next = button(f, "›", 275, -634, 32, function() offset = offset + #f.rows refresh() end, nil, false)
    f.total = label(f, "", nil, 72, -640, 199)
    f.total:SetHeight(20) f.total:SetJustifyH("CENTER")
    f.total:SetFontObject("GameFontHighlightSmall")
    GL.Safe(f.total.SetWordWrap, f.total, false)
    f.total:SetTextColor(unpack(theme.muted))
    f.empty = label(f, "Aucune personne ici.\n\nChange les filtres ou ajoute un joueur avec « Ajouter la cible » ou le clic droit sur son portrait.", nil, 45, -321, 249)
    f.empty:SetTextColor(unpack(theme.muted))
    f.raceIcon = f:CreateTexture(nil, "ARTWORK")
    f.raceIcon:SetPoint("TOPLEFT", 356, -155) f.raceIcon:SetSize(60, 60)
    f.detailTitle = label(f, "", "large", 426, -151, 321)
    f.detailTitle:SetHeight(37)
    GL.Safe(f.detailTitle.SetWordWrap, f.detailTitle, false)
    journalFont(f.detailTitle, "Fancy24Font", 24)
    f.detailIcon = f:CreateTexture(nil, "ARTWORK")
    f.detailIcon:SetPoint("TOPLEFT", 772, -153)
    f.detailIcon:SetSize(32, 32)
    f.detailStatus = label(f, "", nil, 807, -157, 112)
    journalFont(f.detailStatus, "GameFontNormalLarge", 18) f.detailStatus:SetHeight(29)
    GL.Safe(f.detailStatus.SetWordWrap, f.detailStatus, false)
    f.classIcon = f:CreateTexture(nil, "ARTWORK")
    f.classIcon:SetPoint("TOPLEFT", 426, -193) f.classIcon:SetSize(17, 17)
    f.detailIdentity = label(f, "", nil, 447, -192, 300)
    journalFont(f.detailIdentity, "GameFontHighlightSmall", 13)
    f.detailIdentity:SetTextColor(unpack(theme.inkMuted))
    f.detailIdentity:SetHeight(20)
    GL.Safe(f.detailIdentity.SetWordWrap, f.detailIdentity, false)
    f.detailGuild = label(f, "", nil, 426, -215, 318)
    f.detailGuild:SetTextColor(unpack(theme.ink)) f.detailGuild:SetHeight(22)
    GL.Safe(f.detailGuild.SetWordWrap, f.detailGuild, false)
    f.detailSource = label(f, "", nil, 753, -196, 166)
    f.detailSource:SetJustifyH("RIGHT") f.detailSource:SetHeight(39) f.detailSource:SetTextColor(unpack(theme.inkMuted))
    f.actions, f.reactions = {}, {}
    for _, option in ipairs({ { "Ami", "friend", 356, 74 }, { "Méfiance", "warning", 434, 100 }, { "Ennemi", "enemy", 538, 89 }, { "Automatique", "neutral", 631, 123 } }) do
        local value = option[2]
        local control = button(f, option[1], option[3], -592, option[4], function()
            local record = currentRecord()
            if record then GL.SetReaction(record, value) end
        end, true, true)
        if value ~= "neutral" then
            local icon = control:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(media .. relationIcons[value]) icon:SetSize(16, 16) icon:SetPoint("LEFT", 7, 0)
            control.caption:ClearAllPoints() control.caption:SetPoint("TOPLEFT", 25, -5) control.caption:SetWidth(option[4] - 29)
        end
        f.actions[#f.actions + 1], f.reactions[value] = control, control
    end
    f.actions[#f.actions + 1] = button(f, "Ajouter une note", 758, -592, 156, function()
        local record = currentRecord()
        if record then GL.EditNote(record) end
    end, nil, true)
    f.toolsMenu = CreateFrame("Frame", nil, f)
    f.toolsMenu:SetPoint("TOPLEFT", 734, -505) f.toolsMenu:SetSize(180, 119)
    f.toolsMenu:SetFrameStrata("FULLSCREEN_DIALOG") f.toolsMenu:SetToplevel(true) f.toolsMenu:EnableMouse(true)
    surface(f.toolsMenu, theme.gold) surface(f.toolsMenu, theme.panel, 1)
    f.tools = button(f, "Autres actions", 734, -634, 180, function() toggleMenu(f.toolsMenu) end, nil, true)
    for i, option in ipairs({ { "Avis positif (+1)", 1 }, { "Avis négatif (-1)", -1 } }) do
        local delta = option[2]
        f.actions[#f.actions + 1] = button(f.toolsMenu, option[1], 3, -3 - (i - 1) * 29, 174, function()
            local record = currentRecord()
            if record then GL.AdjustReputation(record, delta, "Avis personnel", "manual") end
            f.toolsMenu:Hide()
        end)
    end
    f.guildButton = button(f.toolsMenu, "Guilde", 3, -61, 174, function()
        local record = currentRecord()
        f.toolsMenu:Hide()
        if record and record.guild then GL.ShowGuilds(record) end
    end)
    f.actions[#f.actions + 1] = button(f.toolsMenu, "Corriger le PvP", 3, -90, 174, function() f.toolsMenu:Hide() showCorrections(currentRecord()) end)
    f.toolsMenu:Hide()
    f.detailTabs = {}
    for i, entry in ipairs({ { "summary", "Synthèse" }, { "history", "Histoire" }, { "notes", "Notes" } }) do
        local key = entry[1]
        f.detailTabs[key] = button(f, entry[2], 356 + (i - 1) * 115, -242, 110, function()
            f.detailTab = key f.detailScroll:SetVerticalScroll(0) renderDetail()
        end, true, true)
    end
    f.counters = CreateFrame("Frame", nil, f)
    f.counters:SetPoint("TOPLEFT", 356, -279) f.counters:SetSize(558, 160)
    f.metrics = {}
    for i, entry in ipairs({ { "deaths", "Vous a tué" }, { "kills", "Vous l’avez vaincu" } }) do
        local card = CreateFrame("Frame", nil, f.counters)
        card:SetPoint("TOPLEFT", (i - 1) * 281, 0) card:SetSize(274, 85)
        surface(card, theme.gold):SetAlpha(0.28) surface(card, theme.selection, 1, 1):SetAlpha(0.68)
        card.caption = label(card, entry[2], nil, 6, -6, 262)
        journalFont(card.caption, "GameFontNormalLarge", 16)
        card.caption:SetTextColor(unpack(theme.ink)) card.caption:SetHeight(23) card.caption:SetJustifyH("CENTER")
        card.value = label(card, "0", "large", 6, -29, 262)
        journalFont(card.value, "GameFontNormalLarge", 28)
        card.value:SetTextColor(unpack(theme.ink)) card.value:SetHeight(34) card.value:SetJustifyH("CENTER")
        local confirmed = label(card, "Confirmé", nil, 9, -65, 116)
        confirmed:SetJustifyH("RIGHT") confirmed:SetTextColor(unpack(theme.inkMuted)) journalFont(confirmed, "GameFontHighlightSmall", 11)
        card.probable = label(card, "", nil, 137, -65, 126)
        journalFont(card.probable, "GameFontHighlightSmall", 11) card.probable:SetTextColor(unpack(theme.inkMuted))
        f.metrics[entry[1]] = card
    end
    local balanceCaption = label(f.counters, "Solde automatique", nil, 32, -98, 238)
    journalFont(balanceCaption, "GameFontNormalLarge", 20) balanceCaption:SetTextColor(unpack(theme.ink)) balanceCaption:SetJustifyH("RIGHT")
    f.balance = label(f.counters, "", nil, 286, -89, 160)
    journalFont(f.balance, "GameFontNormalLarge", 31) f.balance:SetTextColor(unpack(inkColors.enemy)) f.balance:SetHeight(44)
    f.formula = label(f.counters, "", nil, 6, -128, 546)
    f.formula:SetTextColor(unpack(theme.ink)) f.formula:SetJustifyH("CENTER") f.formula:SetHeight(22)
    f.scoreContext = label(f.counters, "", nil, 6, -151, 546)
    journalFont(f.scoreContext, "GameFontHighlightSmall", 11) f.scoreContext:SetTextColor(unpack(theme.inkMuted)) f.scoreContext:SetJustifyH("CENTER") f.scoreContext:SetHeight(17)
    f.detailScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.detailScroll:SetPoint("TOPLEFT", 356, -379)
    f.detailScroll:SetSize(544, 190)
    f.detailBody = CreateFrame("Frame", nil, f.detailScroll)
    f.detailBody:SetSize(539, 210)
    f.detailText = label(f.detailBody, "", nil, 0, 0, 529)
    journalFont(f.detailText, "QuestFont_Large", 15)
    f.detailText:SetTextColor(unpack(theme.ink))
    f.detailText:SetSpacing(4)
    f.detailScroll:SetScrollChild(f.detailBody)
    local hint = label(f, "Votre choix personnel reste prioritaire.", nil, 356, -640, 360)
    hint:SetFontObject("GameFontHighlightSmall")
    hint:SetHeight(20)
    hint:SetTextColor(unpack(theme.inkMuted))
end

refresh = function(focusSelected)
    if not ledger or not ledger:IsShown() or not GL.db then return end
    local selected = currentRecord()
    selectedKey = selected and selected.key
    listSort = GL.Settings().listSort or listSort
    listDetail = GL.Settings().listDetail or listDetail
    local records = GL.SearchPlayers({ query = ledger.query or "", relation = filter, faction = factionFilter,
        notesOnly = notesOnly, sort = listSort, selectedKey = selectedKey })
    local selectionVisible = false
    for index, record in ipairs(records) do
        if selectedKey == record.key then
            selectionVisible = true
            if focusSelected == true then offset = math.floor((index - 1) / #ledger.rows) * #ledger.rows end
        end
    end
    if not selectionVisible then selectedKey = nil end
    offset = math.min(offset, math.max(0, math.floor((#records - 1) / #ledger.rows) * #ledger.rows))
    for i, row in ipairs(ledger.rows) do
        local record = records[offset + i]
        if record then
            row.key = record.key
            local relation = GL.Relation(record)
            local color = colors[relation]
            row.name:SetText(plain(record.fullName or record.name or record.key))
            row.name:SetTextColor(color[1], color[2], color[3])
            row.relation:SetText(relationNames[relation])
            row.relation:SetTextColor(color[1], color[2], color[3])
            if relationIcons[relation] then
                row.relationIcon:SetTexture(media .. relationIcons[relation])
                row.relationIcon:Show()
            else
                row.relationIcon:SetTexture(nil)
                row.relationIcon:Hide()
            end
            local faction, race, class = identityLabels(record)
            local detail = faction .. " · " .. race .. " · " .. class
            if listDetail == "guild" then detail = record.guild or "Guilde inconnue"
            elseif listDetail == "pvp" then
                local pvp = record.pvp or {}
                detail = tostring(pvp.kills or 0) .. " victoire(s) · " .. tostring(pvp.deaths or 0) .. " mort(s)"
            elseif listDetail == "notes" then
                local note = record.notes and record.notes[#record.notes]
                detail = note and note.text or "Aucune note"
            end
            row.identity:SetText(plain(detail):gsub("[\r\n]", " "))
            identityIcons(row, record)
            local background = selectedKey == record.key and theme.red or theme.panel
            row.bg:SetColorTexture(unpack(background))
            row.bg:SetAlpha(selectedKey == record.key and 0.9 or 0)
            if selectedKey == record.key then row.selection:Show() else row.selection:Hide() end
            row:Show()
        else row.key = nil row:Hide() end
    end
    ledger.total:SetText(counted(#records, "personne"))
    if #records == 0 then ledger.empty:Show() else ledger.empty:Hide() end
    for value, control in pairs(ledger.filters) do
        UI.selectButton(control, value == filter)
    end
    for value, control in pairs(ledger.factions) do
        UI.selectButton(control, value == factionFilter)
    end
    ledger.relationFilter:SetText(filter == "all" and "Tous les avis" or relationNames[filter])
    ledger.factionFilter:SetText(factionNames[factionFilter] or (factionFilter == "unknown" and "Inconnue" or "Toutes factions"))
    ledger.previous:SetEnabled(offset > 0)
    ledger.next:SetEnabled(offset + #ledger.rows < #records)
    for _, choice in ipairs(sortChoices) do if choice[1] == listSort then ledger.sort:SetText("Tri : " .. choice[2]) end end
    for _, choice in ipairs(detailChoices) do if choice[1] == listDetail then ledger.detail:SetText("Détail : " .. choice[2]) end end
    UI.selectButton(ledger.notesOnly, notesOnly)
    renderDetail()
end

function GL.ShowLedger(key)
    if not GL.db then return end
    buildLedger()
    ledger.closeMenu()
    if statisticsWindow then statisticsWindow:Hide() end
    if journalWindow then journalWindow:Hide() end
    if key then
        local record = GL.Get(key)
        selectedKey = record and record.key or nil
        filter, factionFilter, offset, notesOnly = "all", "all", 0, false
        ledger.query, ledger.detailTab = "", "summary"
        ledger.search:SetText("")
        ledger.detailScroll:SetVerticalScroll(0)
    end
    showBook(ledger)
    refresh(key ~= nil)
    if not key and not GL.Settings().guideSeen then GL.ShowGuide() end
end

local function selectNote(f, note)
    local record = GL.Get(f.identity)
    local index
    for i, item in ipairs(record and record.notes or {}) do if item == note then index = i break end end
    f.selectedNote, f.confirmDelete = index and note or nil, nil
    f.remove:SetText("Supprimer") f.remove:SetEnabled(index ~= nil)
    f.previous:SetEnabled(record and #record.notes > 0 and (not index or index > 1))
    f.next:SetEnabled(index ~= nil)
    f.noteInfo:SetText(index and ("Note " .. index .. " / " .. #record.notes .. " · " .. stamp(note.time)) or "Nouvelle note · brouillon conservé à la fermeture")
    f.error:SetText("")
    f.loading = true
    f.edit:SetText(drafts[f.selectedNote or f.identity.key] or (f.selectedNote and f.selectedNote.text) or "")
    f.loading = false
    f.scroll:SetVerticalScroll(0)
end

function GL.EditNote(identity, selectedNote)
    if not identity or not identity.key then return end
    if not noteWindow then
        local f = window("GrudgeLedgerNote", "Notes personnelles", 480, 386)
        noteWindow = f
        f.target = label(f, "", nil, 18, -52, 440)
        f.previous = button(f, "Note précédente", 18, -82, 140, function()
            local record = GL.Get(f.identity)
            local index = #(record and record.notes or {}) + 1
            for i, note in ipairs(record and record.notes or {}) do if note == f.selectedNote then index = i break end end
            if record then selectNote(f, record.notes[index - 1]) end
        end)
        f.next = button(f, "Note suivante", 168, -82, 140, function()
            local record = GL.Get(f.identity)
            for i, note in ipairs(record and record.notes or {}) do
                if note == f.selectedNote then selectNote(f, record.notes[i + 1]) return end
            end
            selectNote(f)
        end)
        f.new = button(f, "Nouvelle note", 318, -82, 142, function() selectNote(f) end)
        f.noteInfo = label(f, "", nil, 18, -120, 440)
        f.noteInfo:SetFontObject("GameFontHighlightSmall") f.noteInfo:SetTextColor(unpack(theme.muted))
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll = scroll
        scroll:SetPoint("TOPLEFT", 22, -145)
        scroll:SetSize(410, 140)
        f.edit = CreateFrame("EditBox", nil, scroll)
        f.edit:SetMultiLine(true)
        f.edit:SetFontObject("ChatFontNormal")
        f.edit:SetWidth(400)
        f.edit:SetHeight(140)
        f.edit:SetAutoFocus(false)
        f.edit:SetMaxLetters(2000)
        f.edit:SetTextInsets(4, 4, 4, 4)
        styleInput(f.edit, true, true)
        f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() f:Hide() end)
        f.edit:SetScript("OnTextChanged", function(self)
            if f.identity and not f.loading then
                drafts[f.selectedNote or f.identity.key] = self:GetText()
                f.confirmDelete = nil
                if f.remove then f.remove:SetText("Supprimer") end
            end
            local _, fontHeight = self:GetFont()
            local height = math.max(scroll:GetHeight(), self:GetNumLines() * (fontHeight + self:GetSpacing()) + 8)
            self:SetHeight(height)
            scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, height - scroll:GetHeight())))
        end)
        -- Cursor-follow scrolling follows Worth Remembering's multiline editor
        -- (Kyle, GPL-3.0); grow the child from the actual font and wrapped lines.
        f.edit:SetScript("OnCursorChanged", function(self, _, y, _, height)
            y, height = GL.Clean(y, "number"), GL.Clean(height, "number")
            if not y or not height then return end
            local top = math.max(0, -y)
            local bottom = top + height
            if self:GetHeight() < bottom + 4 then self:SetHeight(bottom + 4) end
            local offset = scroll:GetVerticalScroll()
            if top < offset then scroll:SetVerticalScroll(top)
            elseif bottom > offset + scroll:GetHeight() then scroll:SetVerticalScroll(bottom - scroll:GetHeight()) end
        end)
        scroll:SetScrollChild(f.edit)
        f.error = label(f, "", nil, 18, -300, 440)
        f.error:SetTextColor(1, 0.4, 0.4)
        f.save = button(f, "Enregistrer", 18, -346, 125, function()
            if not f.identity then return end
            local ok, err
            if f.selectedNote then ok, err = GL.UpdateNote(f.identity, f.selectedNote, f.edit:GetText())
            else ok, err = GL.AddNote(f.identity, f.edit:GetText()) end
            if not ok then f.error:SetText(plain(err or "La note doit contenir du texte (2000 octets maximum).")) return end
            drafts[f.selectedNote or f.identity.key] = nil
            f:Hide()
        end)
        f.remove = button(f, "Supprimer", 160, -346, 150, function()
            if not f.selectedNote then return end
            if f.confirmDelete ~= f.selectedNote then
                f.confirmDelete = f.selectedNote
                f.remove:SetText("Confirmer ?")
                f.error:SetText("Cette note sera supprimée définitivement. Cliquez à nouveau pour confirmer.")
                return
            end
            local ok, err = GL.DeleteNote(f.identity, f.selectedNote)
            if not ok then f.error:SetText(plain(err or "Suppression impossible.")) return end
            drafts[f.selectedNote] = nil selectNote(f)
        end)
        button(f, "Fermer", 335, -346, 125, function() f:Hide() end)
    end
    local captured = {}
    for k, v in pairs(identity) do if type(v) ~= "table" then captured[k] = v end end
    noteWindow.identity = captured
    noteWindow.target:SetText(plain(identity.fullName or identity.name or identity.key))
    selectNote(noteWindow, selectedNote)
    noteWindow:Show()
    noteWindow:Raise()
    noteWindow.edit:SetFocus()
end

-- GetMinimapShape quadrant conventions follow LibDBIcon; no library is required.
local roundQuadrants = {
    ROUND = { true, true, true, true }, SQUARE = {},
    ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}
local dragAngle
local function positive(value, fallback)
    value = GL.Clean(value, "number")
    return value and value > 0 and value < math.huge and value or fallback
end
local function positionMinimap()
    if not minimapButton then return end
    local angle = dragAngle or GL.Clean(GL.Settings().minimapAngle, "number") or 225
    if angle ~= angle or math.abs(angle) == math.huge then angle = 225 end
    angle = math.rad(angle)
    local x, y = math.cos(angle), math.sin(angle)
    local quadrant = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)
    local shape = GL.Clean(GL.Safe(GetMinimapShape), "string") or "ROUND"
    local halfWidth = positive(GL.Safe(Minimap.GetWidth, Minimap), 140) / 2
    local halfHeight = positive(GL.Safe(Minimap.GetHeight, Minimap), 140) / 2
    local padding = 18 -- Keep the native 31px button outside the map's rim.
    local radius
    if roundQuadrants[shape] and roundQuadrants[shape][quadrant] then
        local ellipse = (x / halfWidth)^2 + (y / halfHeight)^2
        local normalDot = ellipse / math.sqrt((x / halfWidth^2)^2 + (y / halfHeight^2)^2)
        radius = 1 / math.sqrt(ellipse) + padding / normalDot
    else
        radius = math.min((halfWidth + padding) / math.max(math.abs(x), 0.0001), (halfHeight + padding) / math.max(math.abs(y), 0.0001))
    end
    local mapScale = positive(GL.Safe(Minimap.GetEffectiveScale, Minimap), 1)
    local rootScale = positive(GL.Safe(UIParent.GetEffectiveScale, UIParent), 1)
    minimapButton:SetScale(mapScale / rootScale)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
    if GL.Safe(Minimap.IsVisible, Minimap) == false or GL.Safe(Minimap.IsShown, Minimap) == false then minimapButton:Hide()
    else minimapButton:Show() end
end

GL.On("READY", function()
    if not Minimap or minimapButton then return end
    -- UIParent prevents a minimap addon clipping the outer medallion to the map.
    minimapButton = CreateFrame("Button", "GrudgeLedgerMinimapButton", UIParent)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetClampedToScreen(true)
    GL.Safe(minimapButton.SetFrameLevel, minimapButton, (GL.Safe(Minimap.GetFrameLevel, Minimap) or 0) + 10)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    -- Same native textures, sizes and anchors as LibDBIcon's standard buttons.
    -- Only the book artwork is ours; the gold ring belongs to the client UI.
    local modern = AddonCompartmentFrame
    local background = minimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(modern and 24 or 20, modern and 24 or 20)
    if modern then background:SetPoint("CENTER") else background:SetPoint("TOPLEFT", 7, -5) end
    minimapButton.background = background
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(modern and 50 or 53, modern and 50 or 53)
    border:SetPoint("TOPLEFT", 0, 0)
    minimapButton.border = border
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    minimapButton.icon = icon
    icon:SetSize(20, 20)
    if modern then icon:SetPoint("CENTER") else icon:SetPoint("TOPLEFT", 6, -5) end
    icon:SetTexture(GL.minimapIcon or "Interface\\Icons\\INV_Misc_Book_09")
    if minimapButton.CreateMaskTexture and icon.AddMaskTexture then
        local mask = minimapButton:CreateMaskTexture(nil, "ARTWORK")
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        icon:AddMaskTexture(mask)
    end
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    minimapButton:SetScript("OnClick", function(_, which)
        if which == "RightButton" then showSettings()
        elseif ledger and ledger:IsShown() then ledger:Hide() else GL.ShowLedger() end
    end)
    minimapButton:SetScript("OnEnter", function(self)
        if self.dragging or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Grudge Ledger")
        GameTooltip:AddLine("Clic : journal • Clic droit : réglages", 1, 1, 1)
        GameTooltip:AddLine("Glisser : déplacer le bouton", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    minimapButton:SetScript("OnDragStart", function(self)
        self.dragging = true
        if GameTooltip then GameTooltip:Hide() end
    end)
    local function stopDrag(self)
        self.dragging = nil
        if dragAngle then local angle = dragAngle dragAngle = nil GL.SetSetting("minimapAngle", angle) end
    end
    minimapButton:SetScript("OnDragStop", stopDrag)
    minimapButton:SetScript("OnHide", stopDrag)
    local elapsed = 0
    minimapButton:SetScript("OnUpdate", function(self, delta)
        if self.dragging then
            local x, y = GL.Safe(GetCursorPosition)
            local cx, cy = GL.Safe(Minimap.GetCenter, Minimap)
            local scale = positive(GL.Safe(Minimap.GetEffectiveScale, Minimap), 1)
            x, y, cx, cy = GL.Clean(x, "number"), GL.Clean(y, "number"), GL.Clean(cx, "number"), GL.Clean(cy, "number")
            if x and y and cx and cy and (x / scale ~= cx or y / scale ~= cy) then
                dragAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
                positionMinimap()
            end
        else
            elapsed = elapsed + delta
            if elapsed >= 1 then elapsed = 0 positionMinimap() end
        end
    end)
    GL.Safe(Minimap.HookScript, Minimap, "OnSizeChanged", positionMinimap)
    GL.Safe(Minimap.HookScript, Minimap, "OnShow", positionMinimap)
    GL.Safe(Minimap.HookScript, Minimap, "OnHide", function() minimapButton:Hide() end)
    positionMinimap()
end)

GL.On("CHANGED", refresh)
GL.On("CHANGED", refreshGuilds)
GL.On("CHANGED", refreshCorrections)
GL.On("SETTINGS", function()
    for region, fonts in pairs(journalFonts) do journalFont(region, fonts[1], fonts[2]) end
    refresh()
    if ledger then renderDetail() end
    if settingsWindow then settingsWindow.readingLabel:SetText("Taille de lecture : " .. math.floor((GL.Settings().readingScale or 1) * 100 + 0.5) .. " %") end
    refreshStatistics() refreshJournal()
    if noteWindow then noteWindow.edit:GetScript("OnTextChanged")(noteWindow.edit) end
    if minimapButton and not minimapButton.dragging then positionMinimap() end
    if settingsWindow then for key, check in pairs(settingsWindow.checks) do check:SetChecked(GL.Settings()[key]) end end
end)
SLASH_GRUDGELEDGER1 = "/gl"
SLASH_GRUDGELEDGER2 = "/grudges"
SlashCmdList.GRUDGELEDGER = function(message)
    local command, reason = (GL.Clean(message, "string") or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):gsub("[A-Z]", string.lower) -- Preserve UTF-8 bytes in French commands.
    reason = reason or ""
    if command == "debug" then
        showDiagnostic()
    elseif command == "traces" then showDiagnostic(true)
    elseif command == "stats" then GL.ShowStatistics("players")
    elseif command == "bilan" then GL.ShowJournal("summary")
    elseif command == "chronique" then GL.ShowJournal("history")
    elseif command == "guildes" then GL.ShowStatistics("guilds")
    elseif command == "guide" then GL.ShowGuide()
    elseif command == "settings" or command == "options" then showSettings()
    elseif command == "reperage" or command == "repérage" then enableRecognition()
    elseif command == "guilde" then
        if reason == "" then GL.ShowGuilds() return end
        local reaction = ({ ami = "friend", amie = "friend", ennemi = "enemy", ennemie = "enemy", neutre = "neutral", mefiance = "warning", ["méfiance"] = "warning" })[(reason:gsub("[A-Z]", string.lower))]
        if not reaction then GL.Print("/gl guilde ami|ennemi|mefiance|neutre — utilise la guilde de ta cible.") return end
        local identity = GL.Identity("target")
        if not identity or not identity.guild then GL.Print("Sélectionne un joueur dont la guilde est connue.") return end
        GL.SetGuildReaction(identity, reaction)
    elseif command == "+" or command == "-" or command == "ami" or command == "ennemi" or command == "neutre" or command == "auto" or command == "automatique"
        or command == "mefiance" or command == "méfiance" or command == "note" then
        local identity = GL.Identity("target")
        if not identity then GL.Print("Sélectionne un joueur pour cette action.") return end
        if command == "+" or command == "-" then
            GL.AdjustReputation(identity, command == "+" and 1 or -1, reason ~= "" and reason or "Avis personnel", "manual")
        elseif command == "note" then
            if reason == "" then GL.EditNote(identity)
            else
                local ok, err = GL.AddNote(identity, reason)
                if not ok then GL.Print(err or "Impossible d'ajouter cette note.") end
            end
        else
            GL.SetReaction(identity, ({ ami = "friend", ennemi = "enemy", neutre = "neutral", auto = "neutral", automatique = "neutral", mefiance = "warning", ["méfiance"] = "warning" })[command])
        end
    elseif command == "" then
        if ledger and ledger:IsShown() then ledger:Hide() else GL.ShowLedger() end
    else GL.Print("Commandes : /gl, /gl bilan, /gl chronique, /gl stats, /gl guildes, /gl traces, /gl + [raison], /gl - [raison], /gl ami|ennemi|auto|mefiance, /gl note [texte], /gl guilde [ami|ennemi|mefiance|neutre], /gl reperage, /gl settings, /gl debug") end
end
