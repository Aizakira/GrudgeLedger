-- Grudge Ledger: a single journal, explicit relations and optional notes.
local GL = GrudgeLedger
local ledger, noteWindow, settingsWindow, minimapButton, guildWindow
local correctionWindow, diagnosticWindow
local selectedKey, filter, offset = nil, "all", 0
local factionFilter = "all"
local drafts = {}
local guildDrafts = {}
local relationNames = { friend = "Ami", warning = "Méfiance", enemy = "Ennemi", neutral = "Neutre" }
local factionNames = { Alliance = "Alliance", Horde = "Horde", Neutral = "Neutre" }
local colors = { friend = { 0.48, 0.86, 0.56 }, warning = { 0.97, 0.76, 0.39 }, enemy = { 0.98, 0.55, 0.50 }, neutral = { 0.79, 0.74, 0.65 } }
local inkColors = { friend = { 0.10, 0.34, 0.15 }, warning = { 0.50, 0.22, 0.03 }, enemy = { 0.57, 0.12, 0.11 }, neutral = { 0.34, 0.27, 0.20 } }
local relationIcons = { friend = "RelationFriend", warning = "RelationWarning", enemy = "RelationEnemy", neutral = "RelationNeutral" }
local media = "Interface\\AddOns\\GrudgeLedger\\Media\\"
local pvpNames = { kill = "Victoire", death = "Mort", aggression = "Agression" }
local theme = { paper = { 0.94, 0.87, 0.72 }, muted = { 0.73, 0.64, 0.51 }, gold = { 0.52, 0.38, 0.20 }, brass = { 0.91, 0.77, 0.48 },
    background = { 0.075, 0.045, 0.035 }, panel = { 0.115, 0.075, 0.055 }, red = { 0.30, 0.075, 0.075 },
    ink = { 0.20, 0.13, 0.08 }, inkMuted = { 0.36, 0.25, 0.16 }, selection = { 0.91, 0.80, 0.62 }, disabledInk = { 0.50, 0.44, 0.36 } }

local function surface(parent, color, inset, sublevel)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel or 0)
    texture:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    texture:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    texture:SetColorTexture(color[1], color[2], color[3], 1)
    return texture
end

local function plain(text) return tostring(text or ""):gsub("|", "||") end
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
    identityAtlas(row.raceIcon, race and sex and ("raceicon128-" .. (race:gsub("[A-Z]", string.lower)) .. "-" .. sex))
end
local function subdued(text) return "|cff5c4029" .. text .. "|r" end
local function stamp(t) return date("%d/%m/%Y %H:%M", t or GL.Now()) end
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
local journalFonts = {}
local function journalFont(region, decorative, size)
    journalFonts[region] = { decorative, size }
    local r, g, b, a = GL.Safe(region.GetTextColor, region)
    local spacing = GL.Safe(region.GetSpacing, region)
    region:SetFontObject(GL.Settings().readableFont and "ChatFontNormal" or decorative)
    if GL.Settings().readableFont then
        local path, _, flags = region:GetFont()
        if path then region:SetFont(path, size, flags) end
    end
    if r then region:SetTextColor(r, g, b, a) end
    if spacing then region:SetSpacing(spacing) end
end
local function label(parent, text, size, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", size == "large" and "Fancy18Font" or "GameFontHighlight")
    if size == "large" then journalFont(f, "Fancy18Font", 18) end
    f:SetPoint("TOPLEFT", x, y)
    f:SetJustifyH("LEFT")
    GL.Safe(f.SetJustifyV, f, "TOP")
    f:SetTextColor(unpack(theme.paper))
    if width then f:SetWidth(width) end
    f:SetText(text or "")
    return f
end

local function button(parent, text, x, y, width, callback, selectable, paper)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(width, 26)
    local edge = surface(b, theme.gold, 0, -1)
    b.edge = edge
    edge:ClearAllPoints()
    edge:SetPoint("BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetHeight(1)
    edge:SetAlpha(0.65)
    local normal = surface(b, paper and theme.paper or theme.panel, 1)
    normal:SetAlpha(paper and 0.15 or 0)
    b.normalSurface = normal
    b:SetNormalTexture(normal)
    local pushed = surface(b, paper and theme.selection or theme.brass, 1)
    pushed:SetAlpha(paper and 0.65 or 0.18)
    b:SetPushedTexture(pushed)
    local disabled = surface(b, paper and theme.paper or theme.background, 1)
    disabled:SetAlpha(paper and 0.08 or 0)
    b:SetDisabledTexture(disabled)
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(0.57, 0.39, 0.18, 0.22)
    b:SetHighlightTexture(highlight)
    local caption = label(b, text, nil, 7, -6, width - 14)
    b.caption = caption
    caption:SetJustifyH("CENTER")
    caption:SetHeight(16)
    GL.Safe(caption.SetWordWrap, caption, false)
    GL.Safe(caption.SetMaxLines, caption, 1)
    b:SetFontString(caption)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetText(text)
    caption:SetTextColor(unpack(paper and theme.ink or theme.brass))
    b:SetScript("OnEnable", function()
        caption:SetTextColor(unpack(paper and theme.ink or theme.brass))
        edge:SetColorTexture(unpack(theme.gold))
    end)
    b:SetScript("OnDisable", function()
        if paper then caption:SetTextColor(unpack(theme.disabledInk)) else caption:SetTextColor(0.52, 0.50, 0.46) end
        edge:SetColorTexture(0.28, 0.24, 0.19, 1)
    end)
    if selectable then
        b.selection = b:CreateTexture(nil, "OVERLAY")
        b.selection:SetPoint("BOTTOMLEFT", 8, 2)
        b.selection:SetPoint("BOTTOMRIGHT", -8, 2)
        b.selection:SetHeight(2)
        b.selection:SetColorTexture(0.91, 0.77, 0.48, 1)
        b.selection:Hide()
    end
    b:SetScript("OnClick", callback)
    return b
end

local function styleInput(edit, multiline, paper)
    local edge = surface(edit, theme.gold, 0, -1)
    local fill = surface(edit, paper and theme.paper or theme.background, 1)
    if paper then
        local texture = edit:CreateTexture(nil, "BACKGROUND", nil, 1)
        texture:SetAllPoints(fill)
        texture:SetTexture(media .. "JournalPaper")
    end
    if paper and multiline then journalFont(edit, "QuestFont_Large", 15)
    else edit:SetFontObject("ChatFontNormal") end
    edit:SetTextColor(unpack(paper and theme.ink or theme.paper))
    GL.Safe(edit.SetJustifyV, edit, multiline and "TOP" or "MIDDLE")
    edit:SetTextInsets(8, 8, 5, 5)
    edit:SetScript("OnEditFocusGained", function() edge:SetColorTexture(0.75, 0.57, 0.29, 1) end)
    edit:SetScript("OnEditFocusLost", function() edge:SetColorTexture(unpack(theme.gold)) end)
end

local function window(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseDown", function(self) self:Raise() end)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local shadow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.shadow = shadow
    shadow:SetPoint("TOPLEFT", -4, 4)
    shadow:SetPoint("BOTTOMRIGHT", 4, -4)
    shadow:SetColorTexture(0, 0, 0, 0.65)
    -- ponytail: explicit native sublevels, never creation order; keep solid fills
    -- below decorative images so a missing texture cannot erase readable backing.
    f.outerBorder = surface(f, theme.gold, 0, -7)
    f.cover = surface(f, theme.red, 1, -6)
    f.innerBorder = surface(f, theme.gold, 6, -5)
    local lining = surface(f, theme.background, 7, -4)
    f.lining = lining
    local grain = f:CreateTexture(nil, "BACKGROUND", nil, -3)
    f.grain = grain
    grain:SetAllPoints(lining)
    grain:SetTexture(media .. "JournalPaper")
    GL.Safe(grain.SetVertexColor, grain, 0.13, 0.085, 0.065)
    local header = f:CreateTexture(nil, "BORDER", nil, 0)
    f.header = header
    header:SetPoint("TOPLEFT", 7, -7)
    header:SetPoint("TOPRIGHT", -7, -7)
    header:SetHeight(35)
    header:SetTexture(media .. "JournalPaper")
    GL.Safe(header.SetVertexColor, header, 0.32, 0.075, 0.065)
    local headerFill = f:CreateTexture(nil, "BORDER", nil, -1)
    f.headerFill = headerFill
    headerFill:SetAllPoints(header)
    headerFill:SetColorTexture(unpack(theme.red))
    f.headerLine = f:CreateTexture(nil, "BORDER", nil, 1)
    f.headerLine:SetPoint("TOPLEFT", 8, -42)
    f.headerLine:SetPoint("TOPRIGHT", -8, -42)
    f.headerLine:SetHeight(1)
    f.headerLine:SetColorTexture(theme.gold[1], theme.gold[2], theme.gold[3], 0.7)
    local seal = f:CreateTexture(nil, "ARTWORK")
    f.seal = seal
    seal:SetSize(34, 34)
    seal:SetPoint("TOPLEFT", 9, -5)
    seal:SetTexture(GL.icon or "Interface\\Icons\\INV_Misc_Book_09")
    f.title = label(f, title, "large", 53, -13, width - 107)
    f.title:SetTextColor(0.91, 0.77, 0.48)
    f.title:SetHeight(24)
    GL.Safe(f.title.SetWordWrap, f.title, false)
    f.closeButton = button(f, "×", width - 37, -9, 26, function() f:Hide() end)
    f.closeButton.edge:Hide()
    f.closeButton:SetNormalFontObject("GameFontNormalLarge")
    f.closeButton:SetHighlightFontObject("GameFontNormalLarge")
    f.closeButton.caption:ClearAllPoints()
    f.closeButton.caption:SetPoint("TOPLEFT", 3, -3)
    f.closeButton.caption:SetSize(20, 20)
    f:SetScript("OnShow", function(self)
        self:Raise()
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        self:SetScale(math.min(1, (w - 24) / width, (h - 24) / height))
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

local function bookWindow(name, title)
    local f = window(name, title, 960, 700)
    for _, region in ipairs({ f.shadow, f.outerBorder, f.cover, f.innerBorder, f.grain, f.header, f.headerFill, f.headerLine }) do region:Hide() end
    f.lining:ClearAllPoints()
    f.lining:SetPoint("TOPLEFT", 20, -20)
    f.lining:SetPoint("BOTTOMRIGHT", -20, 20)
    f.closeButton:ClearAllPoints()
    f.closeButton:SetPoint("TOPLEFT", 923, -29)
    f.seal:ClearAllPoints()
    f.seal:SetPoint("TOPLEFT", 22, -18)
    f.seal:SetSize(44, 44)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", 78, -19)
    f.title:SetSize(500, 30)
    journalFont(f.title, "Fancy24Font", 24)
    f.indexPaper = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.indexPaper:SetPoint("TOPLEFT", 18, -96)
    f.indexPaper:SetSize(294, 572)
    f.indexPaper:SetColorTexture(unpack(theme.paper))
    f.paper = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.paper:SetPoint("TOPLEFT", 329, -99)
    f.paper:SetSize(610, 562)
    f.paper:SetColorTexture(unpack(theme.paper))
    f.bookSurface = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.bookSurface:SetAllPoints()
    f.bookSurface:SetTexture(media .. "JournalBookSurface")
    return f
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
    if not guildWindow or not guildWindow:IsShown() then return end
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
    f.total:SetText(#rules .. " guilde(s) enregistrée(s)")
    if #rules == 0 then f.empty:Show() else f.empty:Hide() end
    f.next:SetEnabled(f.offset + 9 < #rules)
    local current = GL.GetGuildRule(f.name:GetText(), f.realm:GetText())
    local statusKey = (guildDraftKey(f.name:GetText(), f.realm:GetText()) or "") .. "\n" .. (current and current.reaction or "")
    if f.statusKey ~= statusKey then
        f.statusKey = statusKey
        f.status:SetText(current and "Avis actuel : " .. relationNames[current.reaction] or "Aucun avis sur cette guilde.")
    end
    for reaction, control in pairs(f.reactions) do
        local active = current and current.reaction == reaction
        local color = active and theme.red or theme.panel
        control.normalSurface:SetColorTexture(unpack(color))
        control.normalSurface:SetAlpha(active and 1 or 0)
        if active then control.selection:Show() else control.selection:Hide() end
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
        button(f, "Précédent", 18, -375, 112, function() f.offset = math.max(0, f.offset - 9) refreshGuilds() end)
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
        local previousKey = guildDraftKey(guildWindow.name:GetText(), guildWindow.realm:GetText())
        if previousKey then
            local previousRule = GL.GetGuildRule(guildWindow.name:GetText(), guildWindow.realm:GetText())
            local text = guildWindow.note:GetText()
            guildDrafts[previousKey] = text ~= (previousRule and previousRule.note or "") and text or nil
        end
        local rule = GL.GetGuildRule(identity)
        local key = guildDraftKey(identity.guild, identity.realm)
        guildWindow.name:SetText(identity.guild)
        guildWindow.realm:SetText(identity.realm or GL.Clean(GL.Safe(GetRealmName), "string") or "")
        guildWindow.note:SetText((key and guildDrafts[key]) or (rule and rule.note) or "")
        guildWindow.status:SetText(rule and "Avis actuel : " .. relationNames[rule.reaction] or "Aucun avis sur cette guilde.")
    end
    guildWindow:Show()
    guildWindow:Raise()
    refreshGuilds()
end

local statisticsWindow
local statisticsChoices = {
    players = {
        { "deaths", "Mes plus grands bourreaux", "Morts confirmées causées par ce joueur" },
        { "kills", "Mes victoires", "Victoires confirmées contre ce joueur" },
        { "grudge", "Mes pires antagonistes", "Ampleur du solde négatif actuel" },
        { "enemiesSeen", "Les menaces recroisées", "Rencontres distinctes avec les joueurs surveillés" },
        { "reputation", "Mes meilleurs amis", "Solde positif actuel : gestes et avis personnels" },
        { "friendsSeen", "Les amis recroisés", "Rencontres distinctes avec les amis actuels" },
        { "probableDeaths", "Morts probables", "Attributions déduites, à confirmer" },
        { "probableKills", "Victoires probables", "Attributions déduites, à confirmer" },
    },
    guilds = {
        { "grudges", "Le plus de rancunes", "Membres connus avec une rancune personnelle" },
        { "friends", "Le plus d'amis", "Membres connus avec un avis personnel positif" },
        { "deaths", "Guildes qui m'ont tué", "Morts confirmées, guilde mémorisée lors des faits" },
        { "probableDeaths", "Morts probables", "Morts déduites, guilde mémorisée lors des faits" },
        { "aggressions", "Agressions confirmées", "Agressions confirmées lors des rencontres" },
    },
}
local function refreshStatistics()
    local f = statisticsWindow
    if not f or not f:IsShown() then return end
    local choice = statisticsChoices[f.mode][f.choice]
    local rows = f.mode == "guilds" and GL.GuildStatistics() or GL.PlayerStatistics(choice[1])
    if f.mode == "guilds" then
        table.sort(rows, function(a, b)
            if a[choice[1]] ~= b[choice[1]] then return a[choice[1]] > b[choice[1]] end
            return a.key < b.key
        end)
    end
    f.offset = math.min(f.offset, math.max(0, math.floor((#rows - 1) / 8) * 8))
    f.heading:SetText(choice[2]) f.description:SetText(choice[3])
    for i, control in ipairs(f.choices) do
        local entry = statisticsChoices[f.mode][i]
        if entry then
            control:SetText(entry[2]) control:Show()
            control.caption:SetTextColor(unpack(i == f.choice and theme.paper or theme.ink))
            control.normalSurface:SetColorTexture(unpack(i == f.choice and theme.red or theme.paper))
            control.normalSurface:SetAlpha(i == f.choice and 1 or 0.15)
        else control:Hide() end
    end
    for i, row in ipairs(f.rows) do
        local item = rows[f.offset + i]
        row.item = item
        if item then
            local guild = f.mode == "guilds"
            row.name:SetText((f.offset + i) .. ". " .. plain(guild and item.name or item.record.fullName))
            row.value:SetText(tostring(guild and item[choice[1]] or item.value))
            row.meta:SetText(guild and (plain(item.realm) .. " · " .. item.grudges .. " rancune(s) · " .. item.friends .. " ami(s) · " .. item.members .. " connu(s)")
                or (relationNames[GL.Relation(item.record)] .. " · " .. plain(item.record.guild or "Guilde inconnue")))
            row.bg:SetAlpha(guild and f.selected and f.selected.key == item.key and 0.8 or 0.15)
            row:Show()
        else row:Hide() end
    end
    f.empty:SetText(#rows == 0 and "Aucune donnée pour ce classement.\nLes nouvelles rencontres enrichiront ton livre." or "")
    f.total:SetText(#rows .. (f.mode == "guilds" and " guilde(s)" or " personne(s)") .. " · " .. (f.offset + 1) .. "–" .. math.min(f.offset + 8, #rows))
    if #rows == 0 then f.total:SetText("Aucune entrée") end
    f.next:SetEnabled(f.offset + 8 < #rows)
    f.previous:SetEnabled(f.offset > 0)
    for _, b in ipairs(f.guildActions) do
        if f.mode == "guilds" then b:Show() b:SetEnabled(f.selected ~= nil) else b:Hide() end
    end
    local rule = f.selected and GL.GetGuildRule(f.selected.name, f.selected.realm)
    f.selection:SetText(f.mode == "guilds" and (f.selected and plain(f.selected.name) .. " · Avis global : " .. (rule and relationNames[rule.reaction] or "aucun") or "Clique sur une guilde pour définir un avis global.")
        or "Clique sur une personne pour ouvrir sa fiche.")
    f.footnote:SetText(f.mode == "guilds" and "Dernière guilde connue. Les avis personnels restent prioritaires. Les avis hérités ne gonflent pas le classement ; les faits sans guilde restent non attribués."
        or "Rencontres comptées depuis cette mise à jour, après plus de 10 min sans observation. Données de ce compte ; les anciens passages ne sont pas reconstitués.")
end
function GL.ShowStatistics(mode)
    if not GL.db then return end
    mode = mode == "guilds" and "guilds" or "players"
    if not statisticsWindow then
        local f = bookWindow("GrudgeLedgerStatistics", "Grudge Ledger")
        statisticsWindow = f
        f.rows, f.choices, f.guildActions = {}, {}, {}
        label(f, "Les chroniques de ton livre", nil, 79, -51, 330):SetTextColor(unpack(theme.muted))
        button(f, "Personnes", 582, -29, 110, function() GL.ShowStatistics("players") end)
        button(f, "Guildes", 702, -29, 91, function() GL.ShowStatistics("guilds") end)
        button(f, "Retour au livre", 805, -29, 108, function() f:Hide() GL.ShowLedger() end)
        label(f, "Classements", "large", 36, -115, 256):SetTextColor(unpack(theme.ink))
        for i = 1, 8 do
            f.choices[i] = button(f, "", 36, -157 - (i - 1) * 44, 256, function()
                f.choice, f.offset, f.selected = i, 0, nil refreshStatistics()
            end, nil, true)
        end
        button(f, "Gérer une guilde", 36, -548, 256, function() GL.ShowGuilds() end, nil, true)
        f.footnote = label(f, "", nil, 36, -589, 256)
        f.footnote:SetTextColor(unpack(theme.inkMuted))
        f.heading = label(f, "", "large", 350, -115, 554)
        f.heading:SetTextColor(unpack(theme.ink))
        f.description = label(f, "", nil, 350, -143, 554)
        f.description:SetTextColor(unpack(theme.inkMuted))
        for i = 1, 8 do
            local row = CreateFrame("Button", nil, f)
            row:SetPoint("TOPLEFT", 350, -177 - (i - 1) * 47) row:SetSize(554, 43)
            row.bg = surface(row, theme.selection)
            row.name = label(row, "", nil, 8, -5, 458)
            row.name:SetHeight(18) GL.Safe(row.name.SetWordWrap, row.name, false)
            row.name:SetTextColor(unpack(theme.ink))
            row.value = label(row, "", "large", 478, -5, 65)
            row.value:SetJustifyH("RIGHT") row.value:SetTextColor(unpack(theme.ink))
            row.meta = label(row, "", nil, 8, -25, 536)
            row.meta:SetFontObject("GameFontHighlightSmall") row.meta:SetHeight(16)
            GL.Safe(row.meta.SetWordWrap, row.meta, false)
            row.meta:SetTextColor(unpack(theme.inkMuted))
            row:SetScript("OnClick", function(self)
                if f.mode == "guilds" then f.selected = self.item refreshStatistics()
                else f:Hide() GL.ShowLedger(self.item.record.key) end
            end)
            f.rows[i] = row
        end
        f.empty = label(f, "", nil, 365, -220, 515) f.empty:SetTextColor(unpack(theme.inkMuted))
        f.previous = button(f, "Précédent", 350, -561, 110, function() f.offset = math.max(0, f.offset - 8) refreshStatistics() end, nil, true)
        f.total = label(f, "", nil, 475, -568, 285) f.total:SetTextColor(unpack(theme.inkMuted))
        f.next = button(f, "Suivant", 794, -561, 110, function() f.offset = f.offset + 8 refreshStatistics() end, nil, true)
        f.selection = label(f, "", nil, 350, -600, 554) f.selection:SetTextColor(unpack(theme.inkMuted))
        f.selection:SetHeight(20) GL.Safe(f.selection.SetWordWrap, f.selection, false)
        for i, action in ipairs({ { "Guilde à surveiller", "warning" }, { "Guilde amie", "friend" }, { "Avis et note…" } }) do
            local reaction = action[2]
            f.guildActions[i] = button(f, action[1], 350 + (i - 1) * 188, -628, 178, function()
                local selected = f.selected
                if not selected then return end
                if reaction then GL.SetGuildReaction(selected.name, reaction, nil, selected.realm)
                else GL.ShowGuilds({ guild = selected.name, realm = selected.realm }) end
            end, nil, true)
        end
    end
    local f = statisticsWindow
    if f.mode ~= mode then f.mode, f.choice, f.offset, f.selected = mode, 1, 0, nil end
    if ledger then ledger:Hide() end
    f:Show() refreshStatistics()
end
GL.On("CHANGED", refreshStatistics)

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

local function renderDetail()
    local record = currentRecord()
    for _, b in ipairs(ledger.actions) do b:SetEnabled(record ~= nil) end
    ledger.guildButton:SetEnabled(record ~= nil and record.guild ~= nil)
    for reaction, control in pairs(ledger.reactions) do
        local active = record and (record.reactionSource == "automatic" and reaction == "neutral"
            or record.reactionSource ~= "automatic" and GL.Relation(record) == reaction)
        local color = active and theme.red or theme.paper
        control.normalSurface:SetColorTexture(unpack(color))
        control.normalSurface:SetAlpha(active and 1 or 0.15)
        control.caption:SetTextColor(unpack(record and (active and theme.paper or theme.ink) or theme.disabledInk))
        if active then control.selection:Show() else control.selection:Hide() end
    end
    ledger.detailTitle:SetTextColor(unpack(theme.ink))
    if not record then
        ledger.detailTitle:SetText("Une histoire à retrouver")
        ledger.detailIcon:SetTexture(GL.icon)
        ledger.detailStatus:SetText("Sélectionne une personne dans l'index.")
        ledger.detailStatus:SetTextColor(unpack(theme.inkMuted))
        ledger.detailIdentity:SetText("Rencontres, alliances et vieilles rancunes.")
        ledger.detailText:SetText("Tu peux aussi sélectionner un joueur, puis utiliser « Ajouter la cible ».\n\nLe clic droit sur son portrait ou son nom dans le chat donne accès à Ami, Méfiance, Ennemi, Automatique et aux avis +1 / -1.")
    else
        local relation = GL.Relation(record)
        local c = inkColors[relation]
        ledger.detailTitle:SetText(plain(record.fullName or record.name or record.key))
        ledger.detailIcon:SetTexture(relationIcons[relation] and media .. relationIcons[relation] or GL.icon)
        ledger.detailStatus:SetText(relationNames[relation] .. " — " .. (({ manual = "choix personnel", emote = "gestes envoyés", pvp = "historique PvP", guild = "avis hérité de la guilde", automatic = "solde automatique", neutral = "aucun avis" })[GL.RelationSource(record)] or "classement automatique"))
        ledger.detailStatus:SetTextColor(c[1], c[2], c[3])
        local pvp = record.pvp or {}
        local guildRule = GL.GetGuildRule(record)
        local faction, race, class = identityLabels(record)
        ledger.detailIdentity:SetText(plain(faction .. " · " .. race .. " · " .. class))
        local lines = {
            "|cff653c20NOTES PERSONNELLES|r",
        }
        if #(record.notes or {}) == 0 then lines[#lines + 1] = "Aucun souvenir noté. Ajoute une note pour garder le contexte." end
        for i = #(record.notes or {}), 1, -1 do
            local note = record.notes[i]
            lines[#lines + 1] = subdued(stamp(note.time)) .. " — " .. plain(note.text)
        end
        local details = {
            "", "|cff653c20REPÈRES|r",
            "Réputation personnelle : " .. (record.reputation ~= nil and tostring(record.reputation) or "aucun avis"),
            subdued("Solde automatique : vous tuer −10 · vous blesser −1 · le vaincre +1."),
            record.guild and "Dernière guilde connue : " .. plain(record.guild) or "",
            guildRule and guildRule.note and guildRule.note ~= "" and "Note de guilde : " .. plain(guildRule.note) or "",
            subdued("Dernier lieu : " .. plain(record.lastZone or "inconnu")),
            (record.groupCount or 0) > 0 and subdued("Groupes partagés : " .. tostring(record.groupCount)) or "",
            "", "|cff653c20RENCONTRES PVP|r",
        }
        for _, line in ipairs(details) do lines[#lines + 1] = line end
        local encounters = 0
        for _, stat in ipairs({
            { "deaths", "Vous a tué" }, { "kills", "Vous l'avez vaincu" }, { "aggressions", "Vous a infligé des dégâts" },
            { "probableDeaths", "Participation possible à votre mort" }, { "probableKills", "Victoire probable contre ce joueur" },
            { "probableAggressions", "Agression suspectée" },
        }) do
            local count = pvp[stat[1]] or 0
            if count > 0 then lines[#lines + 1] = stat[2] .. " : " .. count .. " fois" encounters = encounters + count end
        end
        if encounters == 0 then lines[#lines + 1] = "Aucun affrontement enregistré." end
        lines[#lines + 1] = subdued("Les faits supposés restent à confirmer. Détails et corrections : « Corriger le PvP ».")
        lines[#lines + 1] = "\n|cff653c20HISTORIQUE RÉCENT|r " .. subdued("(20 derniers événements)")
        local history = record.history or {}
        if #history == 0 then lines[#lines + 1] = "Aucun événement." end
        for i = #history, math.max(1, #history - 19), -1 do
            local e = history[i]
            lines[#lines + 1] = "\n" .. subdued(stamp(e.time)) .. (e.voidReason == "battleground" and " — champ de bataille, non comptabilisé" or e.voided and " — annulé, non comptabilisé" or "")
            local delta = type(e.delta) == "number" and e.delta ~= 0
                and (" — avis " .. (e.delta > 0 and "+" or "") .. e.delta) or ""
            lines[#lines + 1] = eventTitle(e) .. delta
            local place = e.zone and e.zone ~= "?" and e.zone or ""
            if e.subzone and e.subzone ~= "" and e.subzone ~= place then
                place = e.subzone .. (place ~= "" and " · " .. place or "")
            end
            if place ~= "" then lines[#lines + 1] = subdued(plain(place)) end
            if e.questTitle then lines[#lines + 1] = "Quête suivie : " .. plain(e.questTitle) end
            if e.kind == "death" and e.confidence ~= "confirmed" then
                lines[#lines + 1] = "Indices de participation à l'attaque ; coup fatal non identifié."
            elseif e.kind == "kill" and e.confidence ~= "confirmed" then
                lines[#lines + 1] = "Mort observée après un combat ; victoire à confirmer."
            elseif e.kind == "aggression" and e.confidence ~= "confirmed" then
                lines[#lines + 1] = "Attaque soupçonnée ; source des dégâts non confirmée."
            end
            if e.source ~= "emote" and not pvpNames[e.kind] and e.evidence and e.evidence ~= "" and e.evidence ~= "Avis personnel" then
                lines[#lines + 1] = plain(e.evidence) -- Preserve personal reasons; raw PvP evidence stays in Corrections.
            end
            if e.guildSource and e.guild then
                lines[#lines + 1] = subdued("Guilde mémorisée : " .. plain(e.guild)
                    .. (e.guild and e.guildRealm and " (" .. plain(e.guildRealm) .. ")" or "")
                    .. (e.guildSource == "last-known" and " — observée auparavant" or ""))
            end
        end
        ledger.detailText:SetText(table.concat(lines, "\n"))
    end
    ledger.detailBody:SetHeight(math.max(300, ledger.detailText:GetStringHeight() + 12))
    ledger.detailScroll:SetVerticalScroll(math.min(ledger.detailScroll:GetVerticalScroll(),
        math.max(0, ledger.detailBody:GetHeight() - ledger.detailScroll:GetHeight())))
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

local function showSettings()
    if not settingsWindow then
        local f = window("GrudgeLedgerSettings", "Grudge Ledger — Réglages", 450, 685)
        settingsWindow = f
        f.checks = {}
        local options = {
            { "markers", "Icônes près des noms" }, { "nameColor", "Colorer aussi le nom (si compatible)" },
            { "friendAlerts", "Alerte quand un ami apparaît" }, { "enemyAlerts", "Alerte quand un ennemi apparaît" },
            { "sounds", "Sons des alertes" }, { "pvpTracking", "Historique PvP automatique" },
            { "groupTracking", "Historique des groupes" },
            { "socialTracking", "Avis via mes émotes" },
            { "readableFont", "Police classique (plus lisible)" },
        }
        for i, option in ipairs(options) do
            local key = option[1]
            local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", 16, -45 - (i - 1) * 33)
            check:SetSize(26, 26)
            label(check, option[2], nil, 31, -6, 360)
            check:SetScript("OnClick", function(self) GL.SetSetting(key, self:GetChecked() and true or false) end)
            f.checks[key] = check
        end
        label(f, "Les noms flottants seuls ne portent pas les marqueurs. Active le repérage pour afficher les barres, icônes et couleurs.", nil, 20, -358, 405)
        f.plateStatus = label(f, "", nil, 20, -398, 405)
        function f:UpdatePlateStatus()
            local function status(key)
                local value = GL.Clean(GL.Safe((C_CVar and C_CVar.GetCVar) or GetCVar, key), "string")
                return value == "1" and "activées" or value == "0" and "désactivées" or "inconnu"
            end
            self.plateStatus:SetText("Alliés : " .. status("nameplateShowFriendlyPlayers") .. " • Ennemis : " .. status("nameplateShowEnemies"))
        end
        button(f, "Activer le repérage (icônes + couleurs)", 20, -426, 405, enableRecognition)
        label(f, "Alertes amicales : plus de 10 min d'absence, hors groupe. Les icônes restent affichées en groupe.", nil, 20, -467, 405)
        button(f, "Diagnostic", 20, -513, 405, function() showDiagnostic(false) end)
        for i, entry in ipairs({ { "quickGestures", "Boutons bisou / crachat" }, { "detectionLog", "Conserver le diagnostic des détections (200 lignes)" } }) do
            local key = entry[1]
            local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", 16, -550 - (i - 1) * 33) check:SetSize(26, 26)
            label(check, entry[2], nil, 31, -6, 360)
            check:SetScript("OnClick", function(self) GL.SetSetting(key, self:GetChecked() and true or false) end)
            f.checks[key] = check
        end
        button(f, "Replacer les boutons", 20, -628, 195, function() if GL.ResetGesturePosition then GL.ResetGesturePosition() end end)
        button(f, "Journal des détections", 230, -628, 195, function() showDiagnostic(true) end)
    end
    for key, check in pairs(settingsWindow.checks) do check:SetChecked(GL.Settings()[key]) end
    settingsWindow:UpdatePlateStatus()
    settingsWindow:Show()
    settingsWindow:Raise()
end

local function buildLedger()
    if ledger then return end
    local f = bookWindow("GrudgeLedgerWindow", "Grudge Ledger")
    ledger = f
    label(f, "Journal des rencontres et des rancunes", nil, 79, -51, 330):SetTextColor(unpack(theme.muted))
    f.guildsButton = button(f, "Guildes", 702, -29, 91, function() GL.ShowStatistics("guilds") end)
    f.statsButton = button(f, "Statistiques", 582, -29, 110, function() GL.ShowStatistics("players") end)
    f.settingsButton = button(f, "Réglages", 805, -29, 108, showSettings)
    button(f, "Ajouter la cible", 36, -138, 256, function()
        local identity = GL.Identity("target")
        if not identity then GL.Print("Sélectionne un joueur pour ouvrir sa fiche.") return end
        local record = GL.Remember(identity)
        if record then GL.ShowLedger(record.key) end
    end, nil, true)
    label(f, "Index des rencontres", "large", 36, -115, 256):SetTextColor(unpack(theme.ink))
    f.search = CreateFrame("EditBox", nil, f)
    f.search:SetPoint("TOPLEFT", 36, -193)
    f.search:SetSize(256, 25)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(100)
    styleInput(f.search, false, true)
    f.search:SetScript("OnTextChanged", function() offset = 0 refresh() end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    label(f, "Rechercher un nom", nil, 36, -174, 256):SetTextColor(unpack(theme.inkMuted))
    f.filters = {}
    for i, option in ipairs({ { "Tous", "all" }, { "Amis", "friend" }, { "Méfiance", "warning" }, { "Ennemis", "enemy" } }) do
        local value = option[2]
        f.filters[value] = button(f, option[1], 36 + (i - 1) * 65, -228, 61, function() filter, offset = value, 0 refresh() end, nil, true)
    end
    f.factions = {}
    for i, option in ipairs({ { "Toutes", "all" }, { "Alliance", "Alliance" }, { "Horde", "Horde" }, { "Inconnue", "unknown" } }) do
        local value = option[2]
        f.factions[value] = button(f, option[1], 36 + (i - 1) * 65, -260, 61, function() factionFilter, offset = value, 0 refresh() end, nil, true)
    end
    f.rows = {}
    for i = 1, 8 do
        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT", 36, -294 - (i - 1) * 41)
        row:SetSize(256, 39)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(theme.red[1], theme.red[2], theme.red[3], 1)
        row.selection = row:CreateTexture(nil, "BORDER")
        row.selection:SetPoint("TOPLEFT")
        row.selection:SetPoint("BOTTOMLEFT")
        row.selection:SetWidth(2)
        row.selection:SetColorTexture(unpack(theme.red))
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.57, 0.39, 0.18, 0.16)
        row:SetHighlightTexture(hover)
        row.relationIcon = row:CreateTexture(nil, "ARTWORK")
        row.relationIcon:SetPoint("TOPLEFT", 8, -2)
        row.relationIcon:SetSize(19, 19)
        row.name = label(row, "", nil, 31, -3, 216)
        journalFont(row.name, "Fancy16Font", 16)
        row.name:SetHeight(18)
        GL.Safe(row.name.SetWordWrap, row.name, false)
        GL.Safe(row.name.SetMaxLines, row.name, 1)
        row.raceIcon = row:CreateTexture(nil, "ARTWORK")
        row.raceIcon:SetPoint("TOPLEFT", 8, -21)
        row.raceIcon:SetSize(15, 15)
        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetPoint("TOPLEFT", 26, -21)
        row.classIcon:SetSize(15, 15)
        row.identity = label(row, "", nil, 46, -22, 137)
        row.identity:SetFontObject("GameFontHighlightSmall")
        row.identity:SetTextColor(unpack(theme.inkMuted))
        row.identity:SetHeight(14)
        GL.Safe(row.identity.SetWordWrap, row.identity, false)
        GL.Safe(row.identity.SetMaxLines, row.identity, 1)
        row.relation = label(row, "", nil, 188, -22, 59)
        row.relation:SetFontObject("GameFontHighlightSmall")
        row.relation:SetJustifyH("RIGHT")
        row.relation:SetHeight(14)
        GL.Safe(row.relation.SetWordWrap, row.relation, false)
        GL.Safe(row.relation.SetMaxLines, row.relation, 1)
        row:SetScript("OnClick", function(self) selectedKey = self.key f.detailScroll:SetVerticalScroll(0) refresh() end)
        f.rows[i] = row
    end
    button(f, "Précédent", 36, -627, 122, function() offset = math.max(0, offset - #f.rows) refresh() end, nil, true)
    f.next = button(f, "Suivant", 170, -627, 122, function() offset = offset + #f.rows refresh() end, nil, true)
    f.total = label(f, "", nil, 450, -51, 235)
    f.total:SetHeight(17)
    f.total:SetFontObject("GameFontHighlightSmall")
    GL.Safe(f.total.SetWordWrap, f.total, false)
    f.total:SetTextColor(unpack(theme.muted))
    f.empty = label(f, "Aucune personne ici.\n\nChange les filtres ou ajoute un joueur avec « Ajouter la cible » ou le clic droit sur son portrait.", nil, 45, -310, 240)
    f.empty:SetTextColor(unpack(theme.inkMuted))
    f.detailTitle = label(f, "", "large", 350, -116, 554)
    f.detailTitle:SetHeight(27)
    GL.Safe(f.detailTitle.SetWordWrap, f.detailTitle, false)
    journalFont(f.detailTitle, "Fancy24Font", 24)
    f.detailIcon = f:CreateTexture(nil, "ARTWORK")
    f.detailIcon:SetPoint("TOPLEFT", 350, -151)
    f.detailIcon:SetSize(32, 32)
    f.detailStatus = label(f, "", nil, 392, -150, 512)
    f.detailStatus:SetHeight(19)
    GL.Safe(f.detailStatus.SetWordWrap, f.detailStatus, false)
    f.detailIdentity = label(f, "", nil, 392, -173, 512)
    f.detailIdentity:SetFontObject("GameFontHighlightSmall")
    f.detailIdentity:SetTextColor(unpack(theme.inkMuted))
    f.detailIdentity:SetHeight(17)
    GL.Safe(f.detailIdentity.SetWordWrap, f.detailIdentity, false)
    f.actions, f.reactions = {}, {}
    for i, option in ipairs({ { "Ami", "friend" }, { "Méfiance", "warning" }, { "Ennemi", "enemy" }, { "Automatique", "neutral" } }) do
        local value = option[2]
        local control = button(f, option[1], 350 + (i - 1) * 92, -203, 86, function()
            local record = currentRecord()
            if record then GL.SetReaction(record, value) end
        end, true, true)
        f.actions[#f.actions + 1], f.reactions[value] = control, control
    end
    f.actions[#f.actions + 1] = button(f, "Ajouter une note", 744, -203, 160, function()
        local record = currentRecord()
        if record then GL.EditNote(record) end
    end, nil, true)
    for i, option in ipairs({ { "Avis positif (+1)", 1 }, { "Avis négatif (-1)", -1 } }) do
        local delta = option[2]
        f.actions[#f.actions + 1] = button(f, option[1], 350 + (i - 1) * 148, -625, 138, function()
            local record = currentRecord()
            if record then GL.AdjustReputation(record, delta, "Avis personnel", "manual") end
        end, nil, true)
    end
    f.guildButton = button(f, "Guilde", 646, -625, 120, function()
        local record = currentRecord()
        if record and record.guild then GL.ShowGuilds(record) end
    end, nil, true)
    f.actions[#f.actions + 1] = button(f, "Corriger le PvP", 778, -625, 126, function() showCorrections(currentRecord()) end, nil, true)
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 350, -243)
    rule:SetSize(554, 1)
    rule:SetColorTexture(0.36, 0.25, 0.16, 0.35)
    f.detailScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.detailScroll:SetPoint("TOPLEFT", 350, -259)
    f.detailScroll:SetSize(544, 337)
    f.detailBody = CreateFrame("Frame", nil, f.detailScroll)
    f.detailBody:SetSize(539, 337)
    f.detailText = label(f.detailBody, "", nil, 0, 0, 529)
    journalFont(f.detailText, "QuestFont_Large", 15)
    f.detailText:SetTextColor(unpack(theme.ink))
    f.detailText:SetSpacing(4)
    f.detailScroll:SetScrollChild(f.detailBody)
    local hint = label(f, "Automatique suit le solde ; les autres choix restent prioritaires.", nil, 350, -605, 554)
    hint:SetFontObject("GameFontHighlightSmall")
    hint:SetHeight(15)
    hint:SetTextColor(unpack(theme.inkMuted))
end

refresh = function()
    if not ledger or not ledger:IsShown() or not GL.db then return end
    local text = (ledger.search:GetText() or ""):lower()
    local selected = currentRecord()
    selectedKey = selected and selected.key
    local records = {}
    local selectionVisible = false
    for _, record in pairs(GL.db.players) do
        local name = (record.fullName or record.name or record.key):lower()
        local matchesFaction = factionFilter == "all" or record.faction == factionFilter
            or (factionFilter == "unknown" and not factionNames[record.faction])
        if (record.key == selectedKey or not GL.IsGroupOnly(record)) and matchesFaction
            and (filter == "all" or GL.Relation(record) == filter) and name:find(text, 1, true) then
            records[#records + 1] = record
            if selectedKey == record.key then selectionVisible = true end
        end
    end
    if not selectionVisible then selectedKey = nil end
    table.sort(records, function(a, b)
        if (a.lastSeen or 0) ~= (b.lastSeen or 0) then return (a.lastSeen or 0) > (b.lastSeen or 0) end
        return (a.fullName or a.name or a.key) < (b.fullName or b.name or b.key)
    end)
    offset = math.min(offset, math.max(0, math.floor((#records - 1) / #ledger.rows) * #ledger.rows))
    for i, row in ipairs(ledger.rows) do
        local record = records[offset + i]
        if record then
            row.key = record.key
            local relation = GL.Relation(record)
            local color = inkColors[relation]
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
            row.identity:SetText(plain(faction .. " · " .. race .. " · " .. class))
            identityIcons(row, record)
            local background = selectedKey == record.key and theme.selection or theme.paper
            row.bg:SetColorTexture(unpack(background))
            row.bg:SetAlpha(selectedKey == record.key and 0.9 or 0)
            if selectedKey == record.key then row.selection:Show() else row.selection:Hide() end
            row:Show()
        else row.key = nil row:Hide() end
    end
    ledger.total:SetText(tostring(#records) .. " personne(s) · " .. (relationNames[filter] or "Tous") .. " · " .. (factionNames[factionFilter] or (factionFilter == "unknown" and "Inconnue" or "Toutes")))
    if #records == 0 then ledger.empty:Show() else ledger.empty:Hide() end
    for value, control in pairs(ledger.filters) do
        local c = value == filter and theme.red or theme.paper
        control.normalSurface:SetColorTexture(c[1], c[2], c[3], 1)
        control.normalSurface:SetAlpha(value == filter and 1 or 0.15)
        control.caption:SetTextColor(unpack(value == filter and theme.paper or theme.ink))
    end
    for value, control in pairs(ledger.factions) do
        local c = value == factionFilter and theme.red or theme.paper
        control.normalSurface:SetColorTexture(c[1], c[2], c[3], 1)
        control.normalSurface:SetAlpha(value == factionFilter and 1 or 0.15)
        control.caption:SetTextColor(unpack(value == factionFilter and theme.paper or theme.ink))
    end
    ledger.next:SetEnabled(offset + #ledger.rows < #records)
    renderDetail()
end

function GL.ShowLedger(key)
    if not GL.db then return end
    buildLedger()
    if key then
        local record = GL.Get(key)
        selectedKey = record and record.key or nil
        filter, factionFilter, offset = "all", "all", 0
        ledger.search:SetText("")
        ledger.detailScroll:SetVerticalScroll(0)
    end
    ledger:Show()
    ledger:Raise()
    refresh()
end

function GL.EditNote(identity)
    if not identity or not identity.key then return end
    if not noteWindow then
        local f = window("GrudgeLedgerNote", "Ajouter une note", 480, 300)
        noteWindow = f
        f.target = label(f, "", nil, 18, -52, 440)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll = scroll
        scroll:SetPoint("TOPLEFT", 22, -82)
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
            if f.identity then drafts[f.identity.key] = self:GetText() end
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
        f.error = label(f, "", nil, 18, -231, 440)
        f.error:SetTextColor(1, 0.4, 0.4)
        button(f, "Enregistrer", 18, -264, 125, function()
            if not f.identity then return end
            local ok, err = GL.AddNote(f.identity, f.edit:GetText())
            if not ok then f.error:SetText(plain(err or "La note doit contenir du texte (2000 octets maximum).")) return end
            drafts[f.identity.key] = nil
            f:Hide()
        end)
        button(f, "Fermer", 335, -264, 125, function() f:Hide() end)
    end
    local captured = {}
    for k, v in pairs(identity) do if type(v) ~= "table" then captured[k] = v end end
    noteWindow.identity = captured
    noteWindow.target:SetText(plain(identity.fullName or identity.name or identity.key))
    noteWindow.error:SetText("")
    noteWindow.edit:SetText(drafts[identity.key] or "")
    noteWindow.scroll:SetVerticalScroll(0)
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
    icon:SetSize(modern and 18 or 17, modern and 18 or 17)
    if modern then icon:SetPoint("CENTER") else icon:SetPoint("TOPLEFT", 7, -6) end
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
    elseif command == "guildes" then GL.ShowStatistics("guilds")
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
    else GL.Print("Commandes : /gl, /gl stats, /gl guildes, /gl traces, /gl + [raison], /gl - [raison], /gl ami|ennemi|auto|mefiance, /gl note [texte], /gl guilde [ami|ennemi|mefiance|neutre], /gl reperage, /gl settings, /gl debug") end
end
