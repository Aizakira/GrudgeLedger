-- Grudge Ledger: a single journal, explicit relations and optional notes.
local GL = GrudgeLedger
local ledger, noteWindow, settingsWindow, minimapButton, guildWindow
local correctionWindow, diagnosticWindow
local selectedKey, filter, offset = nil, "all", 0
local drafts = {}
local guildDrafts = {}
local relationNames = { friend = "Ami", warning = "Méfiance", enemy = "Ennemi", neutral = "Neutre" }
local colors = { friend = { 0.3, 0.95, 0.55 }, warning = { 1, 0.62, 0.12 }, enemy = { 1, 0.3, 0.3 }, neutral = { 0.75, 0.75, 0.75 } }
local pvpNames = { kill = "Victoire", death = "Mort", aggression = "Agression" }
local theme = { paper = { 0.91, 0.86, 0.74 }, muted = { 0.65, 0.59, 0.48 }, gold = { 0.48, 0.35, 0.18 },
    background = { 0.055, 0.043, 0.042 }, panel = { 0.09, 0.071, 0.065 }, red = { 0.22, 0.055, 0.065 } }

local function surface(parent, color, inset)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    texture:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    texture:SetColorTexture(color[1], color[2], color[3], 1)
    return texture
end

local function plain(text) return tostring(text or ""):gsub("|", "||") end
local function subdued(text) return "|cffa6967a" .. text .. "|r" end
local function stamp(t) return date("%d/%m/%Y %H:%M", t or GL.Now()) end
local function label(parent, text, size, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", size == "large" and "GameFontNormalLarge" or "GameFontHighlight")
    f:SetPoint("TOPLEFT", x, y)
    f:SetJustifyH("LEFT")
    GL.Safe(f.SetJustifyV, f, "TOP")
    f:SetTextColor(unpack(theme.paper))
    if width then f:SetWidth(width) end
    f:SetText(text or "")
    return f
end

local function button(parent, text, x, y, width, callback)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(width, 26)
    surface(b, theme.gold)
    local normal = surface(b, theme.panel, 1)
    b.normalSurface = normal
    b:SetNormalTexture(normal)
    local pushed = surface(b, theme.red, 1)
    b:SetPushedTexture(pushed)
    local disabled = surface(b, theme.background, 1)
    b:SetDisabledTexture(disabled)
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(0.57, 0.39, 0.18, 0.22)
    b:SetHighlightTexture(highlight)
    local caption = label(b, text, nil, 7, -6, width - 14)
    caption:SetJustifyH("CENTER")
    caption:SetHeight(16)
    GL.Safe(caption.SetWordWrap, caption, false)
    GL.Safe(caption.SetMaxLines, caption, 1)
    b:SetFontString(caption)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetText(text)
    b:SetScript("OnClick", callback)
    return b
end

local function styleInput(edit, multiline)
    local edge = surface(edit, theme.gold)
    surface(edit, theme.background, 1)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextColor(unpack(theme.paper))
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
    local shadow = f:CreateTexture(nil, "BACKGROUND")
    shadow:SetPoint("TOPLEFT", -4, 4)
    shadow:SetPoint("BOTTOMRIGHT", 4, -4)
    shadow:SetColorTexture(0, 0, 0, 0.65)
    surface(f, theme.gold)
    surface(f, theme.background, 1)
    local header = f:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(42)
    header:SetColorTexture(unpack(theme.red))
    local seal = f:CreateTexture(nil, "ARTWORK")
    seal:SetSize(34, 34)
    seal:SetPoint("TOPLEFT", 9, -5)
    seal:SetTexture(GL.icon or "Interface\\Icons\\INV_Misc_Book_09")
    f.title = label(f, title, "large", 53, -13, width - 107)
    f.title:SetTextColor(0.91, 0.77, 0.48)
    f.title:SetHeight(24)
    GL.Safe(f.title.SetWordWrap, f.title, false)
    button(f, "X", width - 37, -9, 26, function() f:Hide() end)
    f:SetScript("OnShow", function(self)
        self:Raise()
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        self:SetScale(math.min(1, (w - 24) / width, (h - 24) / height))
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    f:Hide()
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
        for i, choice in ipairs({ { "Amie", "friend" }, { "Méfiance", "warning" }, { "Ennemie", "enemy" }, { "Neutre", "neutral" } }) do
            local reaction = choice[2]
            button(f, choice[1], 288 + ((i - 1) % 2) * 178, -312 - math.floor((i - 1) / 2) * 32, 165, function() save(reaction) end)
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
            row.title:SetText(stamp(event.time) .. " — " .. pvpNames[event.kind] .. " (" .. (event.confidence == "confirmed" and "confirmé" or "probable") .. ")" .. (event.voided and " — annulé" or ""))
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

local function showDiagnostic()
    if not diagnosticWindow then
        local f = window("GrudgeLedgerDiagnostic", "Grudge Ledger — Diagnostic", 660, 500)
        diagnosticWindow = f
        label(f, "Texte sélectionné : Ctrl+C pour copier. Aucun nom, note ni détail d'erreur.", nil, 18, -54, 620)
        f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT", 22, -91)
        f.scroll:SetSize(590, 355)
        f.edit = CreateFrame("EditBox", nil, f.scroll)
        f.edit:SetMultiLine(true)
        f.edit:SetFontObject("ChatFontNormal")
        f.edit:SetSize(580, 355)
        f.edit:SetAutoFocus(false)
        styleInput(f.edit, true)
        f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() f:Hide() end)
        f.scroll:SetScrollChild(f.edit)
        button(f, "Tout sélectionner", 22, -461, 180, function() f.edit:SetFocus() f.edit:HighlightText() end)
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
    diagnosticWindow.edit:SetText(table.concat(lines, "\n"))
    local _, fontHeight = diagnosticWindow.edit:GetFont()
    diagnosticWindow.edit:SetHeight(math.max(355, diagnosticWindow.edit:GetNumLines() * (fontHeight + diagnosticWindow.edit:GetSpacing()) + 8))
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
    if not record then
        ledger.detailTitle:SetText("Choisis une personne dans le journal.")
        ledger.detailText:SetText("Tu peux aussi sélectionner un joueur, puis utiliser « Ajouter la cible ».\n\nLe clic droit sur son portrait ou son nom dans le chat donne accès à Ami, Méfiance, Ennemi, Neutre et aux avis +1 / -1.")
    else
        local relation = GL.Relation(record)
        local c = colors[relation]
        ledger.detailTitle:SetText(plain(record.fullName or record.name or record.key))
        ledger.detailTitle:SetTextColor(c[1], c[2], c[3])
        local pvp = record.pvp or {}
        local guildRule = GL.GetGuildRule(record)
        local lines = {
            relationNames[relation] .. " — " .. (({ manual = "choix personnel", pvp = "historique PvP", guild = "avis hérité de la guilde", neutral = "aucun avis" })[GL.RelationSource(record)] or "classement automatique"),
            "Réputation personnelle : " .. (record.reputation ~= nil and tostring(record.reputation) or "aucun avis"),
            "Guilde : " .. plain(record.guild or "aucune guilde connue"),
            guildRule and guildRule.note and guildRule.note ~= "" and "Note de guilde : " .. plain(guildRule.note) or "",
            subdued("Dernier lieu : " .. plain(record.lastZone or "inconnu")),
            subdued("Groupes partagés : " .. tostring(record.groupCount or 0)),
            "",
            "PvP confirmé : " .. tostring(pvp.kills or 0) .. " victoire(s), " .. tostring(pvp.deaths or 0) .. " mort(s)",
            "PvP probable : " .. tostring(pvp.probableKills or 0) .. " victoire(s), " .. tostring(pvp.probableDeaths or 0) .. " mort(s)",
            "Agressions : " .. tostring(pvp.aggressions or 0) .. " confirmée(s), " .. tostring(pvp.probableAggressions or 0) .. " probable(s)",
            subdued("Les événements probables sont des déductions, pas des confirmations."),
            "", "|cffd4b373NOTES PERSONNELLES|r",
        }
        if #(record.notes or {}) == 0 then lines[#lines + 1] = "Aucune note. Ajoute un souvenir avec le bouton ci-dessus." end
        for i = #(record.notes or {}), 1, -1 do
            local note = record.notes[i]
            lines[#lines + 1] = stamp(note.time) .. " — " .. plain(note.text)
        end
        lines[#lines + 1] = "\n|cffd4b373HISTORIQUE RÉCENT|r |cffa6967a(20 derniers événements)|r"
        local history = record.history or {}
        if #history == 0 then lines[#lines + 1] = "Aucun événement." end
        for i = #history, math.max(1, #history - 19), -1 do
            local e = history[i]
            local kind = ({ kill = "Victoire", death = "Mort", aggression = "Agression", reputation = "Avis", grouped = "Groupe partagé", group = "Groupe partagé", reaction = "Classement", note = "Note ajoutée" })[e.kind] or plain(e.kind)
            local confidence = e.confidence == "probable" and " (probable)" or e.confidence == "confirmed" and " (confirmé)" or ""
            local opinion = e.reaction and " : " .. (relationNames[e.reaction] or plain(e.reaction)) or ""
            local zone = e.zone and " — " .. plain(e.zone) or ""
            local delta = type(e.delta) == "number" and " (" .. (e.delta >= 0 and "+" or "") .. tostring(e.delta) .. ")" or ""
            lines[#lines + 1] = stamp(e.time) .. " — " .. kind .. confidence .. (e.voided and " — annulé" or "") .. delta .. opinion .. zone
            if e.evidence and e.evidence ~= "" then lines[#lines + 1] = "  " .. plain(e.evidence) end
        end
        ledger.detailText:SetText(table.concat(lines, "\n"))
    end
    ledger.detailBody:SetHeight(math.max(300, ledger.detailText:GetStringHeight() + 12))
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
        local f = window("GrudgeLedgerSettings", "Grudge Ledger — Réglages", 450, 530)
        settingsWindow = f
        f.checks = {}
        local options = {
            { "markers", "Icônes près des noms" }, { "nameColor", "Colorer aussi le nom (si compatible)" },
            { "friendAlerts", "Alerte quand un ami apparaît" }, { "enemyAlerts", "Alerte quand un ennemi apparaît" },
            { "sounds", "Sons des alertes" }, { "pvpTracking", "Historique PvP automatique" },
            { "groupTracking", "Historique des groupes" },
            { "socialTracking", "Avis via mes émotes" },
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
        label(f, "Les noms flottants seuls ne portent pas les marqueurs. Active le repérage pour afficher les barres, icônes et couleurs.", nil, 20, -325, 405)
        f.plateStatus = label(f, "", nil, 20, -365, 405)
        function f:UpdatePlateStatus()
            local function status(key)
                local value = GL.Clean(GL.Safe((C_CVar and C_CVar.GetCVar) or GetCVar, key), "string")
                return value == "1" and "activées" or value == "0" and "désactivées" or "inconnu"
            end
            self.plateStatus:SetText("Alliés : " .. status("nameplateShowFriendlyPlayers") .. " • Ennemis : " .. status("nameplateShowEnemies"))
        end
        button(f, "Activer le repérage (icônes + couleurs)", 20, -393, 405, enableRecognition)
        label(f, "Les alertes pour une même personne sont espacées de 3 minutes par défaut.", nil, 20, -434, 405)
        button(f, "Diagnostic", 20, -480, 405, showDiagnostic)
    end
    for key, check in pairs(settingsWindow.checks) do check:SetChecked(GL.Settings()[key]) end
    settingsWindow:UpdatePlateStatus()
    settingsWindow:Show()
    settingsWindow:Raise()
end

local function buildLedger()
    if ledger then return end
    local f = window("GrudgeLedgerWindow", "Grudge Ledger", 820, 590)
    ledger = f
    button(f, "Guildes", 540, -9, 105, function() GL.ShowGuilds() end)
    button(f, "Réglages", 654, -9, 110, showSettings)
    button(f, "Ajouter la cible", 16, -52, 150, function()
        local identity = GL.Identity("target")
        if not identity then GL.Print("Sélectionne un joueur pour ouvrir sa fiche.") return end
        local record = GL.Remember(identity)
        if record then GL.ShowLedger(record.key) end
    end)
    local listPanel = f:CreateTexture(nil, "BACKGROUND")
    listPanel:SetPoint("TOPLEFT", 10, -83)
    listPanel:SetSize(267, 469)
    listPanel:SetColorTexture(unpack(theme.panel))
    local divider = f:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPLEFT", 282, -52)
    divider:SetSize(1, 497)
    divider:SetColorTexture(theme.gold[1], theme.gold[2], theme.gold[3], 0.7)
    f.search = CreateFrame("EditBox", nil, f)
    f.search:SetPoint("TOPLEFT", 27, -89)
    f.search:SetSize(232, 25)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(100)
    styleInput(f.search)
    f.search:SetScript("OnTextChanged", function() offset = 0 refresh() end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    label(f, "Recherche facultative", nil, 16, -118, 250)
    f.filters = {}
    for i, option in ipairs({ { "Tous", "all" }, { "Amis", "friend" }, { "Méfiance", "warning" }, { "Ennemis", "enemy" } }) do
        local value = option[2]
        f.filters[value] = button(f, option[1], 16 + (i - 1) * 65, -140, 61, function() filter, offset = value, 0 refresh() end)
    end
    f.rows = {}
    for i = 1, 11 do
        local row = CreateFrame("Button", nil, f)
        row:SetPoint("TOPLEFT", 16, -174 - (i - 1) * 31)
        row:SetSize(254, 29)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(theme.red[1], theme.red[2], theme.red[3], 1)
        row.selection = row:CreateTexture(nil, "BORDER")
        row.selection:SetPoint("TOPLEFT")
        row.selection:SetPoint("BOTTOMLEFT")
        row.selection:SetWidth(3)
        row.selection:SetColorTexture(0.75, 0.57, 0.29, 1)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.57, 0.39, 0.18, 0.16)
        row:SetHighlightTexture(hover)
        row.name = label(row, "", nil, 8, -7, 237)
        row.name:SetHeight(18)
        GL.Safe(row.name.SetWordWrap, row.name, false)
        GL.Safe(row.name.SetMaxLines, row.name, 1)
        row:SetScript("OnClick", function(self) selectedKey = self.key f.detailScroll:SetVerticalScroll(0) refresh() end)
        f.rows[i] = row
    end
    button(f, "Précédent", 16, -522, 115, function() offset = math.max(0, offset - 11) refresh() end)
    f.next = button(f, "Suivant", 144, -522, 115, function() offset = offset + 11 refresh() end)
    f.total = label(f, "", nil, 16, -558, 270)
    f.total:SetTextColor(unpack(theme.muted))
    f.empty = label(f, "Aucune personne ici.\n\nAjoute un joueur avec « Ajouter la cible » ou utilise le clic droit sur son portrait.", nil, 27, -193, 232)
    f.empty:SetTextColor(unpack(theme.muted))
    f.detailTitle = label(f, "", "large", 294, -58, 506)
    f.detailTitle:SetHeight(25)
    GL.Safe(f.detailTitle.SetWordWrap, f.detailTitle, false)
    f.actions = {}
    for i, option in ipairs({ { "Ami", "friend" }, { "Méfiance", "warning" }, { "Ennemi", "enemy" }, { "Neutre", "neutral" } }) do
        local value = option[2]
        f.actions[#f.actions + 1] = button(f, option[1], 294 + (i - 1) * 87, -92, 80, function()
            local record = currentRecord()
            if record then GL.SetReaction(record, value) end
        end)
    end
    f.actions[#f.actions + 1] = button(f, "Ajouter une note", 647, -92, 150, function()
        local record = currentRecord()
        if record then GL.EditNote(record) end
    end)
    for i, option in ipairs({ { "Avis positif (+1)", 1 }, { "Avis négatif (-1)", -1 } }) do
        local delta = option[2]
        f.actions[#f.actions + 1] = button(f, option[1], 294 + (i - 1) * 161, -124, 150, function()
            local record = currentRecord()
            if record then GL.AdjustReputation(record, delta, "Avis personnel", "manual") end
        end)
    end
    f.guildButton = button(f, "Guilde", 624, -124, 173, function()
        local record = currentRecord()
        if record and record.guild then GL.ShowGuilds(record) end
    end)
    f.actions[#f.actions + 1] = button(f, "Corriger le PvP", 294, -156, 150, function() showCorrections(currentRecord()) end)
    f.detailScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.detailScroll:SetPoint("TOPLEFT", 294, -192)
    f.detailScroll:SetSize(480, 356)
    f.detailBody = CreateFrame("Frame", nil, f.detailScroll)
    f.detailBody:SetSize(475, 416)
    f.detailText = label(f.detailBody, "", nil, 0, 0, 465)
    f.detailText:SetSpacing(4)
    f.detailScroll:SetScrollChild(f.detailBody)
    label(f, "Ton choix personnel reste prioritaire sur les événements PvP.", nil, 294, -559, 500)
end

refresh = function()
    if not ledger or not ledger:IsShown() or not GL.db then return end
    local text = (ledger.search:GetText() or ""):lower()
    local records = {}
    for _, record in pairs(GL.db.players) do
        local name = (record.fullName or record.name or record.key):lower()
        if (filter == "all" or GL.Relation(record) == filter) and name:find(text, 1, true) then records[#records + 1] = record end
    end
    table.sort(records, function(a, b)
        if (a.lastSeen or 0) ~= (b.lastSeen or 0) then return (a.lastSeen or 0) > (b.lastSeen or 0) end
        return (a.fullName or a.name or a.key) < (b.fullName or b.name or b.key)
    end)
    offset = math.min(offset, math.max(0, math.floor((#records - 1) / 11) * 11))
    for i, row in ipairs(ledger.rows) do
        local record = records[offset + i]
        if record then
            row.key = record.key
            local relation = GL.Relation(record)
            local color = colors[relation]
            row.name:SetText((relation == "friend" and "+ " or relation == "warning" and "? " or relation == "enemy" and "! " or "  ") .. plain(record.fullName or record.name or record.key))
            row.name:SetTextColor(color[1], color[2], color[3])
            row.bg:SetAlpha(selectedKey == record.key and 1 or 0.35)
            if selectedKey == record.key then row.selection:Show() else row.selection:Hide() end
            row:Show()
        else row.key = nil row:Hide() end
    end
    ledger.total:SetText(tostring(#records) .. " personne(s) — " .. (relationNames[filter] or "Tous"))
    if #records == 0 then ledger.empty:Show() else ledger.empty:Hide() end
    for value, control in pairs(ledger.filters) do
        local c = value == filter and theme.red or theme.panel
        control.normalSurface:SetColorTexture(c[1], c[2], c[3], 1)
    end
    ledger.next:SetEnabled(offset + 11 < #records)
    renderDetail()
end

function GL.ShowLedger(key)
    if not GL.db then return end
    buildLedger()
    if key then
        local record = GL.Get(key)
        selectedKey = record and record.key or nil
        filter, offset = "all", 0
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
        styleInput(f.edit, true)
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
    elseif command == "settings" or command == "options" then showSettings()
    elseif command == "reperage" or command == "repérage" then enableRecognition()
    elseif command == "guilde" then
        if reason == "" then GL.ShowGuilds() return end
        local reaction = ({ ami = "friend", amie = "friend", ennemi = "enemy", ennemie = "enemy", neutre = "neutral", mefiance = "warning", ["méfiance"] = "warning" })[(reason:gsub("[A-Z]", string.lower))]
        if not reaction then GL.Print("/gl guilde ami|ennemi|mefiance|neutre — utilise la guilde de ta cible.") return end
        local identity = GL.Identity("target")
        if not identity or not identity.guild then GL.Print("Sélectionne un joueur dont la guilde est connue.") return end
        GL.SetGuildReaction(identity, reaction)
    elseif command == "+" or command == "-" or command == "ami" or command == "ennemi" or command == "neutre"
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
            GL.SetReaction(identity, ({ ami = "friend", ennemi = "enemy", neutre = "neutral", mefiance = "warning", ["méfiance"] = "warning" })[command])
        end
    elseif command == "" then
        if ledger and ledger:IsShown() then ledger:Hide() else GL.ShowLedger() end
    else GL.Print("Commandes : /gl, /gl + [raison], /gl - [raison], /gl ami|ennemi|neutre|mefiance, /gl note [texte], /gl guilde [ami|ennemi|mefiance|neutre], /gl reperage, /gl settings, /gl debug") end
end
