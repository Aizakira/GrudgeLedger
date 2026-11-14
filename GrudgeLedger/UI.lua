-- Grudge Ledger: a single journal, explicit relations and optional notes.
local GL = GrudgeLedger
local L = GL.L
local ledger, noteWindow, settingsWindow, minimapButton, guildWindow
local correctionWindow, diagnosticWindow
local statisticsWindow, journalWindow, guideWindow
local showSettings, inspectEvent
local selectedKey, filter, offset = nil, "all", 0
local factionFilter = "all"
local notesOnly = false
local listSort, listDetail = "recent", "identity"
local sortChoices = { { "recent", L("Dernière interaction") }, { "name", L("Nom") }, { "reputation", L("Réputation") }, { "kills", L("Victoires") }, { "deaths", L("Morts") }, { "encounters", L("Nb de rencontres") } }
local detailChoices = { { "identity", L("Identité") }, { "guild", L("Guilde") }, { "pvp", L("PvP") }, { "notes", L("Notes") } }
local drafts = {}
local guildDrafts = {}
local relationNames = { friend = L("Ami"), warning = L("Méfiance"), enemy = L("Ennemi"), neutral = L("Neutre") }
local factionNames = { Alliance = GL.Clean(FACTION_ALLIANCE, "string") or L("Alliance"),
    Horde = GL.Clean(FACTION_HORDE, "string") or L("Horde"), Neutral = L("Neutre") }
local colors = { friend = { 0.48, 0.86, 0.56 }, warning = { 0.97, 0.76, 0.39 }, enemy = { 0.98, 0.55, 0.50 }, neutral = { 0.79, 0.74, 0.65 } }
local inkColors = { friend = { 0.10, 0.34, 0.15 }, warning = { 0.50, 0.22, 0.03 }, enemy = { 0.57, 0.12, 0.11 }, neutral = { 0.34, 0.27, 0.20 } }
local relationIcons = { friend = "RelationFriend", warning = "RelationWarning", enemy = "RelationEnemy", neutral = "RelationNeutral" }
local media = "Interface\\AddOns\\GrudgeLedger\\Media\\"
local pvpNames = { kill = L("Victoire"), death = L("Mort"), aggression = L("Agression") }
local UI = GL.UITheme
local theme, journalFonts = UI.theme, UI.journalFonts
local surface, plain, label, button = UI.surface, UI.plain, UI.label, UI.button
local styleInput, window, bookWindow, journalFont = UI.styleInput, UI.window, UI.bookWindow, UI.journalFont
local function classLabel(token, fallback, sex)
    local female = sex == 3 and LOCALIZED_CLASS_NAMES_FEMALE
    return (female and GL.Clean(female[token], "string")) or
        (LOCALIZED_CLASS_NAMES_MALE and GL.Clean(LOCALIZED_CLASS_NAMES_MALE[token], "string")) or fallback or token or L("Classe inconnue")
end
-- Legacy records stored only the file token. Cache native names per race ID
-- and accept a lookup only when the client confirms the same token.
local baseRaceIDs = {Human=1, Orc=2, Dwarf=3, NightElf=4, Scourge=5, Tauren=6, Gnome=7, Troll=8,
    Goblin=9, BloodElf=10, Draenei=11, Worgen=22, Pandaren=24}
local nativeRaces = {}
local function raceLabel(token, fallback, id)
    id = id or baseRaceIDs[token]
    if token and type(id) == "number" and id > 0 and id < math.huge then
        local info = nativeRaces[id]
        if info == nil and C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
            local data = GL.Safe(C_CreatureInfo.GetRaceInfo, id)
            local name = type(data) == "table" and GL.Clean(data.raceName, "string")
            info = name and name ~= "" and {name = name, token = GL.Clean(data.clientFileString, "string")} or false
            nativeRaces[id] = info
        end
        if info and info.token == token then return info.name end
    end
    return fallback or token or L("Race inconnue")
end
local function identityLabels(record)
    return factionNames[record.faction] or L("Faction inconnue"), raceLabel(record.race, record.raceName, record.raceID),
        classLabel(record.class, record.className, record.sex)
end
GL.IdentityLabels = identityLabels
local function identityAtlas(texture, atlas)
    if atlas and GL.Safe(C_Texture and C_Texture.GetAtlasInfo, atlas) then
        return pcall(texture.SetAtlas, texture, atlas)
    end
    return false
end

local function classIcon(texture, record)
    local class = GL.Clean(record.class, "string")
    local atlas = class and GL.Safe(GetClassAtlas, (class:gsub("[A-Z]", string.lower)))
    if identityAtlas(texture, atlas) then return true end
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if type(coords) == "table" and #coords == 4 then
        texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        texture:SetTexCoord(unpack(coords))
        return true
    end
    return false
end

local portraitRows = {}
local portraitFrames = CreateFrame("Frame")
local factionPortrait = { Alliance = "Interface\\Icons\\INV_BannerPVP_02", Horde = "Interface\\Icons\\INV_BannerPVP_01" }
local portraitFallbackUnits = { "target", "mouseover", "focus" }
local function visibleGUID(unit, guid)
    return unit and GL.Safe(UnitGUID, unit) == guid and GL.Safe(UnitIsVisible, unit) == true
end
local function portraitUnit(record)
    local guid = GL.Clean(record.guid, "string")
    if not guid or not SetPortraitTexture then return end
    local unit = GL.Clean(GL.Safe(UnitTokenFromGUID, guid), "string")
    if visibleGUID(unit, guid) then return unit end
    for _, candidate in ipairs(portraitFallbackUnits) do
        if candidate ~= unit and visibleGUID(candidate, guid) then return candidate end
    end
end

-- ponytail: retain 64 spare native portraits plus the visible slots this session.
-- The Armory archive covers reloads and evicted faces.
local spareFaces = {}
local function usePortrait(row, guid)
    local current = row.raceIcon
    if guid == row.faceGUID then return current end
    local shown = current:IsShown()
    current:Hide()
    if row.faceGUID then
        spareFaces[#spareFaces + 1] = {guid = row.livePortraitGUID, face = current}
    else
        row.faceAnchor = current
    end
    local face = row.faceAnchor
    if guid then
        local slot
        for i = #spareFaces, 1, -1 do
            if spareFaces[i].guid == guid then slot = i break end
            if not spareFaces[i].guid then slot = i end
        end
        if slot or #spareFaces >= 64 then
            local saved = table.remove(spareFaces, slot or 1)
            face = saved.face
            face:SetParent(row)
            face:ClearAllPoints()
            row.livePortraitGUID = saved.guid == guid and guid or nil
        else
            face = row:CreateTexture(nil, "ARTWORK")
            row.livePortraitGUID = nil
        end
        face:SetAllPoints(row.faceAnchor)
    else
        row.livePortraitGUID = nil
    end
    row.raceIcon, row.faceGUID = face, guid
    if shown then face:Show() else face:Hide() end
    return face
end

local function paintPortrait(row, record, unit)
    local guid = GL.Clean(record.guid, "string")
    local known = guid and row.livePortraitGUID == guid
    if guid and not known and not unit then
        for _, saved in ipairs(spareFaces) do
            if saved.guid == guid then known = true break end
        end
    end
    local face = usePortrait(row, (unit or known) and guid or nil)
    row.portraitUnit, row.archivedPortrait = nil, nil
    face:SetTexCoord(0, 1, 0, 1)
    row.classIcon:SetTexCoord(0, 1, 0, 1)
    row.classIcon:SetTexture(nil)
    row.classIcon:SetAlpha(classIcon(row.classIcon, record) and 1 or 0)
    if unit and (not IsUnitModelReadyForUI or GL.Safe(IsUnitModelReadyForUI, unit)) and pcall(SetPortraitTexture, face, unit, true) then
        row.livePortraitGUID = record.guid
        row.portraitUnit = unit
        return
    end
    if guid and row.livePortraitGUID == guid then return end
    face = usePortrait(row, nil)
    if guid and type(GrudgeLedgerPortraitIndex) == "table" and GrudgeLedgerPortraitIndex[guid] == true
        and guid:match("^Player%-%d+%-%x+$") then
        face:SetTexture("Interface\\AddOns\\GrudgeLedgerPortraits\\" .. guid)
        row.livePortraitGUID = nil
        row.archivedPortrait = true
        return
    end
    face:SetTexture(nil)
    local race = GL.Clean(record.race, "string")
    local sex = record.sex == 2 and "male" or record.sex == 3 and "female"
    local suffix = race and sex and (race:lower() .. "-" .. sex)
    if suffix and (identityAtlas(face, "raceicon128-" .. suffix) or identityAtlas(face, "raceicon-" .. suffix)) then return end
    if classIcon(face, record) then row.classIcon:SetAlpha(0) return end
    face:SetTexture(factionPortrait[record.faction] or GL.icon)
end

local function identityIcons(row, record)
    row.classIcon:SetDrawLayer("OVERLAY")
    portraitRows[row] = record
    paintPortrait(row, record, portraitUnit(record))
end

-- ponytail: the client paints a live texture, not a serializable image. Refresh
-- only visible journal slots, once per event burst, regardless of contact count.
local redrawPortraits
local function refreshPortraits(frame)
    frame:SetScript("OnUpdate", nil)
    for row, record in pairs(portraitRows) do
        if row.raceIcon:IsVisible() then
            local unit = portraitUnit(record)
            if unit ~= row.portraitUnit or (unit and redrawPortraits) then paintPortrait(row, record, unit) end
        end
    end
    redrawPortraits = nil
end
portraitFrames:SetScript("OnEvent", function(self, event)
    if not ((ledger and ledger:IsShown()) or (statisticsWindow and statisticsWindow:IsShown())
        or (journalWindow and journalWindow:IsShown()) or (correctionWindow and correctionWindow:IsShown())) then return end
    if event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" or event == "PORTRAITS_UPDATED" then redrawPortraits = true end
    self:SetScript("OnUpdate", refreshPortraits)
end)
for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "PORTRAITS_UPDATED", "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "GROUP_ROSTER_UPDATE", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE", "PLAYER_ENTERING_WORLD" }) do
    GL.Safe(portraitFrames.RegisterEvent, portraitFrames, event)
end
local function subdued(text) return "|cff5c4029" .. text .. "|r" end
local function stamp(t) return date("%d/%m/%Y %H:%M", t or GL.Now()) end
local frenchNumbers = not GetLocale or GetLocale() == "frFR"
local function counted(n, singular, plural)
    local many = n > 1 or n == 0 and not frenchNumbers
    return n .. " " .. L(many and (plural or singular .. "s") or singular)
end
local function honorTotal(stats)
    return stats.honorAwards > 0 and L("Honneur reçu : %d"):format(stats.honor) or L("Aucun gain d’honneur enregistré")
end
local function honorDetail(stats)
    if stats.honorAwards == 0 then return "" end
    local text = counted(stats.honorAwards, "gain", "gains") .. " · " .. L("Gain maximal : %d"):format(stats.bestHonor)
    if (stats.unassignedHonor or 0) > 0 then
        text = text .. " · " .. L("Sans adversaire identifié : %d"):format(stats.unassignedHonor)
    end
    return text
end
local function eventEvidence(event)
    return GL.LocalizeEvidence and GL.LocalizeEvidence(event) or event.evidence
end
local killOpeningLabels = {
    initiatedKillsNoGrudge = L("Initiative sans rancune"), initiatedKillsGrudge = L("Initiative avec rancune"),
    revengeKills = L("Revanche"), responseKills = L("Riposte"), unknownOpeningKills = L("Initiative inconnue"),
}
local function combatDetails(event, compact)
    local c = event.combat
    if type(c) ~= "table" then return end
    local parts = {}
    if c.pet then parts[#parts + 1] = L("Familier impliqué") end
    if type(c.opponents) == "number" and c.opponents > (compact and 1 or 0) then
        parts[#parts + 1] = counted(c.opponents, "adversaire observé", "adversaires observés")
    end
    if c.pve then parts[#parts + 1] = compact and L("Monstre engagé") or L("Monstre engagé pendant le combat") end
    if type(c.healthPct) == "number" then parts[#parts + 1] = (compact and L("Vie au premier signal : ") or L("Votre vie au premier signal JcJ : ")) .. c.healthPct .. " %" end
    if type(c.playerLevel) == "number" and type(c.opponentLevel) == "number" then
        local difference = c.opponentLevel - c.playerLevel
        local levels = L("Niveaux : vous ") .. c.playerLevel .. L(", adversaire ") .. c.opponentLevel
        parts[#parts + 1] = levels .. (difference ~= 0 and (" (%+d)"):format(difference) or "")
    elseif type(c.opponentLevel) == "number" then parts[#parts + 1] = L("Adversaire de niveau ") .. c.opponentLevel end
    if #parts > 0 then return table.concat(parts, compact and " · " or "\n", 1, compact and math.min(2, #parts) or #parts) end
end
local function realmLabel(realm)
    local region, shard, rules = (realm or ""):match("^CAMWOW%s*([%u]+%d*)%s*Realm%s*(%d+)%s*(%a*)$")
    if region then return region .. " · " .. shard .. (rules ~= "" and " " .. rules or "") end
    return plain(realm)
end
local gestureNames = {
    KISS = L("Bisou"), WINK = L("Clin d'œil"), HUG = L("Étreinte"), WAVE = L("Signe de la main"), THANK = L("Remerciement"),
    BOW = L("Révérence"), SALUTE = L("Salut"), CHEER = L("Encouragement"), APPLAUD = L("Applaudissement"), SMILE = L("Sourire"),
    LOVE = L("Déclaration d'amour"), COMFORT = L("Réconfort"), PAT = L("Tape amicale"), SOOTHE = L("Geste apaisant"),
    RUDE = L("Geste grossier"), INSULT = L("Insulte"), TAUNT = L("Provocation"), MOCK = L("Moquerie"), SPIT = L("Crachat"),
    SLAP = L("Gifle"), GLARE = L("Regard noir"), ANGRY = L("Colère"), FROWN = L("Froncement de sourcils"), BOO = L("Huée"), SNUB = L("Dédain"),
}
local function groupDurationText(seconds)
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then return "< 1 min" end
    if minutes < 60 then return minutes .. " min" end
    return ("%d h %02d"):format(math.floor(minutes / 60), minutes % 60)
end
local function eventTitle(event)
    if event.kind == "honor" then
        local points = GL.HonorPoints(event)
        return points and L("Honneur reçu : +%d"):format(points) or L("Honneur")
    end
    if event.kind == "opening" then
        return event.opener == "player" and L("Premier dégât observé : vous")
            or event.opener == "opponent" and L("Premier dégât observé : adversaire") or L("Initiative inconnue")
    end
    if event.kind == "grouped" and GL.GroupDuration then
        local seconds = GL.GroupDuration(event)
        if seconds > 0 then
            return L("En groupe · ") .. groupDurationText(seconds) .. L(" en ligne")
        end
    end
    if event.kind == "trade" then return L("Échange terminé") end
    if event.kind == "death" then return L("Vous a tué") end
    if event.kind == "kill" then return L("Vous l'avez vaincu") end
    if event.kind == "aggression" then return L("Vous a infligé des dégâts") end
    if event.kind == "reputation" then
        if event.source == "emote" then
            local token = type(event.evidence) == "string" and event.evidence:match("/([A-Za-z]+)$")
            return L("Geste demandé : ") .. (token and gestureNames[token:upper()] or L("émote"))
        end
        return (event.delta or 0) > 0 and L("Vous avez ajouté un avis positif")
            or (event.delta or 0) < 0 and L("Vous avez ajouté un avis négatif") or L("Votre avis est inchangé")
    end
    if event.kind == "reaction" then
        return event.source == "automatic" and L("Classement automatique réactivé")
            or L("Vous l'avez marqué : ") .. (relationNames[event.reaction] or L("avis personnel"))
    end
    if event.kind == "grouped" or event.kind == "group" then return L("Vous avez partagé un groupe") end
    return event.kind == "note" and L("Vous avez ajouté une note") or L("Événement enregistré")
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
        { "ledger", L("Journal"), function() GL.ShowLedger() end },
        { "players", L("Classements"), function() GL.ShowStatistics("players") end },
        { "guilds", L("Guildes"), function() GL.ShowStatistics("guilds") end },
        { "journal", L("Bilan"), function() GL.ShowJournal("summary") end },
    }) do
        local b = button(f, entry[2], 76 + (i - 1) * 204, -96, 196, entry[3], true)
        b:SetHeight(38)
        journalFont(b.caption, "GameFontNormalLarge", 19)
        b.caption:SetHeight(32)
        f.navigation[entry[1]] = b
        UI.selectButton(b, entry[1] == selected)
    end
    f.settingsButton = UI.iconButton(f, "JournalSettings", L("Réglages et aide"), 869, -45, 32, showSettings)
    if selected == "settings" then f.settingsButton:LockHighlight() end
end

local function currentRecord() return selectedKey and GL.Get(selectedKey) end
local refresh

local function guildDraftKey(name, realm)
    name, realm = GL.Clean(name, "string"), GL.Clean(realm, "string")
    realm = realm and realm:match("^%s*(.-)%s*$")
    if not realm or realm == "" then realm = GL.Clean(GL.Safe(GetRealmName), "string") or "Forever" end
    if not name or #name > 160 or #realm > 160 or GL.ContainsControlOrMarkup(name) or GL.ContainsControlOrMarkup(realm) then return nil end
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
        f.status:SetText(current and L("Avis actuel : ") .. relationNames[current.reaction] or L("Aucun avis sur cette guilde."))
    end
    for reaction, control in pairs(f.reactions) do
        local active = current and current.reaction == reaction
        UI.selectButton(control, active)
    end
end

function GL.ShowGuilds(identity)
    if not GL.db then return end
    if not guildWindow then
        local f = window("GrudgeLedgerGuilds", L("Grudge Ledger — Guildes"), 660, 480)
        guildWindow, f.offset = f, 0
        label(f, L("Les membres héritent de l'avis de leur guilde. Un choix personnel reste prioritaire."), nil, 18, -54, 620)
        f.rows = {}
        f.empty = label(f, L("Aucune guilde enregistrée.\n\nSaisis son nom exact à droite ou utilise la guilde de ta cible."), nil, 23, -119, 230)
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
        f.previous = button(f, L("Précédent"), 18, -375, 112, function() f.offset = math.max(0, f.offset - 9) refreshGuilds() end)
        f.next = button(f, L("Suivant"), 147, -375, 112, function() f.offset = f.offset + 9 refreshGuilds() end)
        f.total = label(f, "", nil, 18, -411, 245)
        for _, entry in ipairs({ { "name", L("Nom exact de la guilde"), 101, 160 }, { "realm", L("Serveur"), 160, 160 }, { "note", L("Note facultative"), 219, 2000 } }) do
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
                f.status:SetText(L("Avis enregistré : ") .. relationNames[rule.reaction])
                refreshGuilds()
            else f.status:SetText(L("Nom, serveur ou note invalide (2000 octets max.).")) end
        end
        f.reactions = {}
        for i, choice in ipairs({ { L("Amie"), "friend" }, { L("Méfiance"), "warning" }, { L("Ennemie"), "enemy" }, { L("Neutre"), "neutral" } }) do
            local reaction = choice[2]
            f.reactions[reaction] = button(f, choice[1], 288 + ((i - 1) % 2) * 178, -312 - math.floor((i - 1) / 2) * 32, 165, function() save(reaction) end, true)
        end
        button(f, L("Enregistrer la note"), 288, -382, 343, function()
            local rule = GL.GetGuildRule(f.name:GetText(), f.realm:GetText())
            save(rule and rule.reaction or "neutral")
        end)
        button(f, L("Guilde de la cible"), 288, -426, 343, function()
            local target = GL.Identity("target")
            if not target or not target.guild then f.status:SetText(L("Sélectionne un joueur dont la guilde est connue.")) return end
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

local rankingPageSize = 5
local function bookText(parent, x, y, w, h, size, text, color)
    local region = label(parent, text or "", nil, x, -y, w)
    journalFont(region, size >= 16 and "GameFontNormalLarge" or "GameFontHighlight", size)
    region:SetHeight(h)
    region:SetTextColor(unpack(color or theme.ink))
    GL.Safe(region.SetWordWrap, region, false)
    return region
end
local function bookIcon(parent, x, y, size, texture)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", x, -y) icon:SetSize(size, size)
    if texture then icon:SetTexture(texture) end
    return icon
end
local function parchmentPanel(frame)
    surface(frame, theme.gold):SetAlpha(0.48)
    local fill = surface(frame, theme.paper, 1, 1)
    local paper = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    paper:SetAllPoints(fill)
    paper:SetTexture(media .. "JournalPaper")
    paper:SetVertexColor(1, 0.97, 0.92)
end
local function moveTo(region, x, y)
    region:ClearAllPoints() region:SetPoint("TOPLEFT", x, -y)
end
local function showIf(region, visible)
    if visible then region:Show() else region:Hide() end
end
local encounterHelp = L("Une rencontre recommence après plus de 10 min sans observation. Le total inclut les rencontres avant le changement d'avis ; les anciens passages ne sont pas reconstitués.")
local recentHelp = L("Dernière observation enregistrée, tous tes personnages confondus. Une personne vue récemment n'est pas forcément encore à proximité.")
local confirmedHelp = L("Mon bilan PvP")
local statisticsChoices = {
    players = {
        { name = L("Menaces"), entries = {
            { "grudge", L("Rancunes les plus fortes"), L("Tes ennemis et les personnes à surveiller, selon leur solde négatif actuel."), "point", L("Solde actuel"), L("Les rancunes restent tenaces : une mort pèse dix victoires. Un avis manuel ou de guilde peut aussi signaler un danger sans solde négatif.") },
            { "enemiesSeen", L("Menaces les plus recroisées"), L("Celles que vous avez rencontrées le plus souvent."), "rencontre", L("Rencontres"), encounterHelp },
            { "enemiesRecent", L("Menaces vues récemment"), L("Tes ennemis et les personnes à surveiller, du plus récemment aperçu au plus ancien."), "date", L("Dernière observation"), recentHelp },
            { "aggressions", L("Le plus d'agressions"), L("Les joueurs avec le plus d'agressions confirmées enregistrées à ton encontre."), "agression", L("Agressions confirmées"), L("Nombre d'épisodes enregistrés, pas de coups reçus ni de fréquence horaire. Les suspicions sont exclues de ce classement.") },
        } },
        { name = L("Amis"), entries = {
            { "friendsSeen", L("Amis les plus recroisés"), L("Tes amis actuels que tu as rencontrés le plus souvent."), "rencontre", L("Rencontres"), encounterHelp },
            { "reputation", L("Affinités les plus fortes"), L("Tes amis classés selon leur solde positif actuel."), "point", L("Solde actuel"), L("Les avis, les gestes et les faits PvP alimentent le solde. Un ami désigné par un avis de guilde peut avoir un solde nul.") },
            { "friendsRecent", L("Amis vus récemment"), L("Tes amis actuels, du plus récemment aperçu au plus ancien."), "date", L("Dernière observation"), recentHelp },
            { "friendsGrouped", L("Compagnons de groupe"), L("Les amis actuels avec lesquels tu as partagé le plus de sessions de groupe."), "session", L("Sessions partagées"), L("Ouvrez la fiche pour lire la durée en ligne des sessions mesurées. Partager un groupe ne rend personne ami automatiquement.") },
            { "friendsOnline", L("Temps passé en groupe"), L("Les amis avec lesquels vous avez passé le plus de temps en groupe, tous deux en ligne."), "durée", L("Temps en groupe"), L("Les durées commencent lorsque le suivi observe les deux joueurs connectés. Les anciennes sessions et les champs de bataille sont exclus du calcul.") },
        } },
        { name = L("Combats"), entries = {
            { "deaths", L("Ceux qui m'ont le plus tué"), L("Les joueurs auxquels le plus de tes morts sont attribuées avec confirmation."), "mort", L("Morts confirmées"), confirmedHelp },
            { "kills", L("Adversaires les plus vaincus"), L("Les joueurs contre lesquels tu as le plus de victoires confirmées."), "victoire", L("Victoires confirmées"), confirmedHelp },
        } },
    },
    guilds = {
        { name = L("Relations"), entries = {
            { "grudges", L("Le plus de rancunes"), L("Guildes réunissant le plus de membres avec une rancune personnelle."), "rancune", L("Rancunes personnelles"), L("Dernière guilde connue des personnes de ton livre. Un avis global sur une guilde ne crée pas artificiellement des rancunes personnelles.") },
            { "friends", L("Le plus d'amis"), L("Guildes réunissant le plus de membres que tu apprécies personnellement."), "ami", L("Amis personnels"), L("Dernière guilde connue des personnes de ton livre. Les relations héritées d'un avis global sur la guilde ne gonflent pas ce total.") },
        } },
        { name = L("Combats"), entries = {
            { "deaths", L("Guildes qui m'ont le plus tué"), L("Morts confirmées, rattachées à la guilde connue au moment des faits."), "mort", L("Morts confirmées"), L("Une même mort n'est comptée qu'une fois par guilde impliquée. Les faits sans guilde connue restent non attribués.") },
            { "kills", L("Guildes les plus vaincues"), L("Victoires confirmées contre les membres de ces guildes."), "victoire", L("Victoires confirmées"), L("Guilde mémorisée au moment du combat.") },
            { "aggressions", L("Le plus d'agressions"), L("Agressions confirmées attribuées aux membres de ces guildes."), "agression", L("Agressions confirmées"), L("Guilde mémorisée lors des faits. Plusieurs membres peuvent participer à un même épisode ; les faits sans guilde restent non attribués.") },
        } },
        { name = L("Mes règles"), entries = {
            { "rules", L("Mes règles de guilde"), L("Les avis de guilde que vous avez enregistrés, par ordre alphabétique."), "avis", L("Avis de guilde"), L("Les avis individuels restent prioritaires. La fiche indique les exceptions à la règle choisie.") },
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
        if (guild and choice[1] == "rules" and not GL.GetGuildRule(rows[i].name, rows[i].realm))
            or (guild and choice[1] ~= "rules" and rows[i][choice[1]] <= 0)
            or (not guild and f.faction ~= "all" and (rows[i].record.faction or "unknown") ~= f.faction)
            or (not guild and f.category == 1 and f.relation and GL.Relation(rows[i].record) ~= f.relation) then
            table.remove(rows, i)
        end
    end
    if guild then
        table.sort(rows, function(a, b)
            if choice[1] ~= "rules" and a[choice[1]] ~= b[choice[1]] then return a[choice[1]] > b[choice[1]] end
            if choice[1] == "rules" and a.name ~= b.name then return a.name < b.name end
            return a.key < b.key
        end)
    end
    f.offset = math.min(f.offset, math.max(0, math.floor((#rows - 1) / rankingPageSize) * rankingPageSize))
    f.heading:SetText(guild and L("Les guildes de votre histoire") or choice[2])
    f.description:SetText(choice[3])
    f.columnName:SetText(guild and L("Guilde") or L("Joueur"))
    local guildColumns = { rules = L("Avis"), grudges = L("Personnes"), friends = L("Personnes"), deaths = L("Morts"), kills = L("Victoires"), aggressions = L("Agressions") }
    f.columnValue:SetText(guild and guildColumns[choice[1]] or choice[5])
    showIf(f.relationButton, not guild and f.category == 1)
    f.relationButton:SetText(f.relation and relationNames[f.relation] or L("Tous les avis"))
    local showOpinion = not guild and f.category == 1
    local showSessions = choice[1] == "friendsOnline"
    f.columnExtra:SetText(guild and "" or showOpinion and L("Avis") or showSessions and L("Groupes") or L("Guilde connue"))
    f.scope:SetText(guild and f.category ~= 2 and L("Compte · Relations actuelles") or choice[4] == "date" and L("Compte · Dernières observations") or choice[4] == "point" and L("Compte · Soldes actuels") or L("Compte · Toutes périodes"))
    for mode, tab in pairs(f.tabs) do UI.selectButton(tab, mode == f.mode) end
    if guild then f.factionButton:Hide() else f.factionButton:Show() end
    f.factionButton:SetText(f.faction == "all" and L("Toutes les factions") or factionNames[f.faction] or L("Faction inconnue"))
    f.manage:SetText(guild and L("Gérer les avis de guilde") or L("Mon bilan PvP"))
    local y = 157
    for i, control in ipairs(f.choices) do control:Hide() end
    for i, control in ipairs(f.groups) do
        local group = groups[i]
        showIf(control, group ~= nil)
        if group then
            moveTo(control, 36, y) control:SetText(group.name)
            UI.selectButton(control, i == f.category)
            y = y + 36
            if i == f.category then
                for j, entry in ipairs(choices) do
                    local b = f.choices[j]
                    moveTo(b, 54, y) b:SetText(entry[2]) b.metric = entry[1] b:Show()
                    UI.selectButton(b, j == f.choice)
                    y = y + 32
                end
            end
        end
    end
    f.columnBand:SetWidth(guild and 211 or 548)
    f.columnValue:SetWidth(guild and 87 or 145)
    moveTo(f.columnValue, guild and 478 or 608, 255)
    showIf(f.guildDetail, guild)
    local selected
    if guild then
        selected = rows[f.offset + 1]
        if f.selected then
            for i = f.offset + 1, math.min(f.offset + rankingPageSize, #rows) do
                if rows[i].key == f.selected.key then selected = rows[i] break end
            end
        end
        if not selected or not f.selected or selected.key ~= f.selected.key then
            f.guildDetail.offset, f.guildDetail.exceptionsOnly = 0, false
        end
    end
    f.selected = selected
    for i, row in ipairs(f.rows) do
        local item = rows[f.offset + i]
        row.item = item
        if item then
            local relation = not guild and GL.Relation(item.record)
            local value = (guild and item[choice[1]] or item.value) or 0
            row.rank:SetText(tostring(f.offset + i))
            row.name:SetText(plain(guild and item.name or item.record.fullName))
            row.name:SetTextColor(unpack(relation and inkColors[relation] or theme.ink))
            row.value:SetText(choice[4] == "date" and date("%d/%m/%y %H:%M", value)
                or choice[4] == "durée" and groupDurationText(value)
                or (choice[1] == "grudge" and "−" or choice[1] == "reputation" and "+" or "") .. value)
            row:SetWidth(guild and 211 or 548)
            row.name:SetWidth(guild and 188 or 208)
            moveTo(row.name, guild and 9 or 45, 3)
            moveTo(row.value, guild and 125 or 250, guild and 28 or 4)
            row.value:SetWidth(guild and 76 or 145)
            row.meta:SetWidth(guild and 111 or 211)
            moveTo(row.meta, guild and 9 or 45, 28)
            showIf(row.raceIcon, not guild) showIf(row.classIcon, not guild) showIf(row.extra, not guild)
            showIf(row.icon, showOpinion)
            if showOpinion then row.icon:SetTexture(media .. relationIcons[relation]) end
            if guild then
                row.meta:SetText(realmLabel(item.realm))
                row.value:SetText(choice[1] == "rules" and relationNames[GL.GetGuildRule(item.name, item.realm).reaction] or tostring(value))
            else
                local faction, _, class = identityLabels(item.record)
                identityIcons(row, item.record)
                row.meta:SetText(plain(faction) .. " · " .. plain(class))
                moveTo(row.extra, showOpinion and 435 or 418, 5)
                row.extra:SetWidth(showOpinion and 110 or 130)
                row.extra:SetText(showOpinion and relationNames[relation] or showSessions and tostring(item.record.groupCount or 0) or plain(item.record.guild or L("Inconnue")))
                row.extra:SetTextColor(unpack(showOpinion and inkColors[relation] or theme.ink))
            end
            showIf(row.rank, not guild)
            row.bg:SetAlpha(guild and f.selected and f.selected.key == item.key and 0.85 or (i % 2 == 1 and 0.18 or 0.04))
            row:Show()
        else row:Hide() end
    end
    if guild then
        local members = selected and GL.GuildMembers(selected.name, selected.realm) or {}
        local detail = f.guildDetail
        detail.name:SetText(selected and plain(selected.name) or L("Fiche de guilde"))
        detail.status:SetText(selected and realmLabel(selected.realm) .. " · " .. counted(#members, "membre connu", "membres connus") or L("Choisissez une guilde dans la liste."))
        local rule = selected and GL.GetGuildRule(selected.name, selected.realm)
        detail.rule:SetText(selected and (L("Avis de guilde · ") .. (rule and relationNames[rule.reaction] or L("Aucun"))) or "")
        detail.counts:SetText(selected and counted(selected.grudges, "rancune") .. " · " .. counted(selected.friends, "ami") or "")
        local exceptions = 0
        if rule then
            for i = #members, 1, -1 do
                if GL.Relation(members[i]) ~= rule.reaction then exceptions = exceptions + 1
                elseif detail.exceptionsOnly then table.remove(members, i) end
            end
        else detail.exceptionsOnly = false end
        showIf(detail.exceptionButton, rule and (detail.exceptionsOnly or exceptions > 0))
        detail.exceptionButton:SetText(detail.exceptionsOnly and L("Tous les membres") or counted(exceptions, "exception"))
        detail.exceptionButton:SetEnabled(detail.exceptionsOnly or exceptions > 0)
        detail.memberTitle:SetText(selected and (detail.exceptionsOnly and L("Exceptions") or L("Membres connus")) or "")
        detail.empty:SetText(selected and #members == 0 and (detail.exceptionsOnly and L("Aucune exception à la règle.") or L("Aucun membre actuel dans le registre.")) or "")
        local limit = #detail.rows
        detail.offset = math.min(detail.offset or 0, math.max(0, math.floor((#members - 1) / limit) * limit))
        for i, member in ipairs(detail.rows) do
            member.record = members[detail.offset + i]
            showIf(member, member.record ~= nil)
            if member.record then
                local relation, source = GL.Relation(member.record), GL.RelationSource(member.record)
                member.name:SetText(plain(member.record.fullName))
                member.status:SetText(relationNames[relation] .. " · " .. (({ guild = L("avis de guilde"), manual = L("choix personnel"), emote = L("geste personnel"), pvp = L("faits PvP") })[source] or L("automatique")))
                member.icon:SetTexture(media .. relationIcons[relation])
            end
        end
        for _, b in ipairs({detail.previous, detail.next}) do showIf(b, #members > limit) end
        detail.previous:SetEnabled(detail.offset > 0) detail.next:SetEnabled(detail.offset + limit < #members)
    end
    local emptyHelp = choice[1] == "rules" and L("Vous pouvez ajouter une guilde depuis « Gérer les avis de guilde ».")
        or guild and L("Seules les guildes avec une valeur positive figurent ici.")
        or choice[4] == "date" and L("Il faut au moins une observation enregistrée d'une personne de cette catégorie.")
        or choice[4] == "rencontre" and L("Ce classement commence à la deuxième rencontre observée sur le compte.")
        or choice[4] == "session" and L("Il faut une session de groupe enregistrée avec un ami.")
        or L("Seules les personnes avec des données pour ce critère figurent ici.")
    f.empty:SetText(#rows == 0 and (L("Aucun résultat dans cette sélection.\n\n") .. emptyHelp .. (not guild and f.faction ~= "all" and L("\nEssaie aussi Toutes les factions.") or "")) or "")
    f.empty:SetWidth(guild and 196 or 525)
    local total = #rows == 0 and L("Aucune entrée") or counted(#rows, guild and "guilde" or "personne")
    if #rows > rankingPageSize then total = total .. " · " .. (f.offset + 1) .. "–" .. math.min(f.offset + rankingPageSize, #rows) end
    f.total:SetText(total)
    f.next:SetEnabled(f.offset + rankingPageSize < #rows)
    f.previous:SetEnabled(f.offset > 0)
    showIf(f.next, #rows > rankingPageSize) showIf(f.previous, #rows > rankingPageSize)
    for _, b in ipairs(f.guildActions) do
        if guild then b:Show() else b:Hide() end
        b:SetEnabled(f.selected ~= nil)
    end
    local rule = f.selected and GL.GetGuildRule(f.selected.name, f.selected.realm)
    for _, b in ipairs(f.guildActions) do
        if b.reaction then UI.selectButton(b, rule and b.reaction == rule.reaction) end
    end
    f.selection:SetText(#rows == 0 and "" or guild and (f.selected and L("Définir l’avis de guilde") or L("Sélectionnez une guilde pour définir un avis."))
        or L("Clique sur une personne pour lire son histoire."))
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
        for i = 1, 3 do
            f.groups[i] = button(f, "", 36, -157, 256, function()
                f.category, f.choice, f.offset, f.selected = i, 1, 0, nil refreshStatistics()
            end, true)
            journalFont(f.groups[i].caption, "GameFontNormalLarge", 14)
        end
        for i = 1, 5 do
            f.choices[i] = button(f, "", 54, -195 - (i - 1) * 32, 237, function()
                f.choice, f.offset, f.selected = i, 0, nil refreshStatistics()
            end, true)
            f.choices[i].caption:SetJustifyH("LEFT")
        end
        bookText(f, 36, 433, 256, 21, 13, L("Comment lire ce classement"), theme.paper)
        f.footnote = label(f, "", nil, 36, -462, 256)
        f.footnote:SetTextColor(unpack(theme.muted))
        f.manage = button(f, "", 36, -620, 256, function()
            if f.mode == "guilds" then GL.ShowGuilds() else GL.ShowJournal("summary") end
        end)
        f.heading = label(f, "", "large", 372, -165, 532)
        journalFont(f.heading, "GameFontNormalLarge", 21)
        f.heading:SetTextColor(unpack(theme.ink))
        f.description = label(f, "", nil, 372, -194, 532)
        f.description:SetHeight(32)
        f.description:SetTextColor(unpack(theme.inkMuted))
        f.factionButton = button(f, "", 356, -225, 155, function()
            local nextFaction = { all = "Alliance", Alliance = "Horde", Horde = "unknown", unknown = "all" }
            f.faction, f.offset, f.selected = nextFaction[f.faction], 0, nil refreshStatistics()
        end, nil, true)
        f.relationButton = button(f, L("Tous les avis"), 515, -225, 126, function()
            if not f.relation then f.relation = "enemy" elseif f.relation == "enemy" then f.relation = "warning" else f.relation = nil end
            f.offset = 0 refreshStatistics()
        end, nil, true)
        f.scope = label(f, "", nil, 642, -232, 262)
        f.scope:SetJustifyH("RIGHT") f.scope:SetTextColor(unpack(theme.inkMuted))
        f.columnBand = f:CreateTexture(nil, "BORDER")
        f.columnBand:SetPoint("TOPLEFT", 356, -251) f.columnBand:SetHeight(25)
        f.columnBand:SetColorTexture(0.44, 0.28, 0.13, 0.18)
        f.columnName = label(f, "", nil, 365, -255, 135) f.columnName:SetTextColor(unpack(theme.ink))
        f.columnValue = label(f, "", nil, 608, -255, 145)
        f.columnValue:SetJustifyH("RIGHT") f.columnValue:SetTextColor(unpack(theme.inkMuted))
        f.columnExtra = bookText(f, 774, 255, 130, 21, 12, "")
        for i = 1, rankingPageSize do
            local row = CreateFrame("Button", nil, f)
            row:SetPoint("TOPLEFT", 356, -279 - (i - 1) * 59) row:SetSize(548, 56)
            row.bg = surface(row, theme.selection)
            local line = row:CreateTexture(nil, "BORDER")
            line:SetPoint("BOTTOMLEFT") line:SetPoint("BOTTOMRIGHT") line:SetHeight(1)
            line:SetColorTexture(0.49, 0.32, 0.13, 0.32)
            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints() hover:SetColorTexture(0.57, 0.39, 0.18, 0.15) row:SetHighlightTexture(hover)
            row.rank = bookText(row, 12, 37, 20, 17, 10, "", theme.inkMuted)
            row.icon = bookIcon(row, 413, 8, 18)
            row.raceIcon = bookIcon(row, 4, 3, 32) row.classIcon = bookIcon(row, 25, 23, 14)
            row.extra = bookText(row, 435, 5, 110, 23, 13, "")
            row.name = bookText(row, 45, 3, 208, 24, 15, "")
            row.value = label(row, "", nil, 383, -5, 163)
            row.value:SetHeight(24) GL.Safe(row.value.SetWordWrap, row.value, false)
            row.value:SetJustifyH("RIGHT") row.value:SetTextColor(unpack(theme.ink))
            row.meta = label(row, "", nil, 50, -24, 496)
            journalFont(row.meta, "GameFontHighlightSmall", 12) row.meta:SetHeight(16)
            GL.Safe(row.meta.SetWordWrap, row.meta, false)
            row.meta:SetTextColor(unpack(theme.inkMuted))
            row:SetScript("OnClick", function(self)
                if not self.item then return end
                if f.mode == "guilds" then f.selected, f.guildDetail.offset, f.guildDetail.exceptionsOnly = self.item, 0, false refreshStatistics()
                else f:Hide() GL.ShowLedger(self.item.record.key) end
            end)
            f.rows[i] = row
        end
        f.empty = label(f, "", nil, 364, -307, 525) f.empty:SetTextColor(unpack(theme.inkMuted))
        local detail = CreateFrame("Frame", nil, f)
        detail:SetPoint("TOPLEFT", 577, -253) detail:SetSize(327, 331)
        f.guildDetail = detail
        parchmentPanel(detail)
        detail.name = bookText(detail, 11, 7, 305, 28, 17)
        detail.status = bookText(detail, 11, 41, 305, 21, 12)
        detail.counts = bookText(detail, 11, 63, 305, 21, 12)
        detail.rule = bookText(detail, 11, 88, 305, 24, 15)
        detail.memberTitle = bookText(detail, 11, 124, 151, 24, 15)
        detail.exceptionButton = button(detail, L("Exceptions"), 164, -119, 151, function()
            detail.exceptionsOnly, detail.offset = not detail.exceptionsOnly, 0 refreshStatistics()
        end, nil, true)
        detail.empty = bookText(detail, 11, 158, 305, 45, 12)
        detail.rows = {}
        for i = 1, 3 do
            local member = CreateFrame("Button", nil, detail)
            member:SetPoint("TOPLEFT", 10, -154 - (i - 1) * 45) member:SetSize(307, 43)
            member.icon = bookIcon(member, 5, 7, 24)
            member.name = bookText(member, 35, 0, 269, 22, 13)
            member.status = bookText(member, 35, 21, 269, 19, 11, "", theme.inkMuted)
            member:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            member:SetScript("OnClick", function(self) if self.record then GL.ShowLedger(self.record.key) end end)
            detail.rows[i] = member
        end
        detail.previous = button(detail, L("Précédents"), 11, -300, 145, function() detail.offset = math.max(0, detail.offset - #detail.rows) refreshStatistics() end, nil, true)
        detail.next = button(detail, L("Suivants"), 169, -300, 145, function() detail.offset = detail.offset + #detail.rows refreshStatistics() end, nil, true)
        f.previous = button(f, L("Précédent"), 356, -589, 110, function() f.offset = math.max(0, f.offset - rankingPageSize) refreshStatistics() end, nil, true)
        f.total = label(f, "", nil, 481, -596, 279) f.total:SetTextColor(unpack(theme.inkMuted))
        f.next = button(f, L("Suivant"), 794, -589, 110, function() f.offset = f.offset + rankingPageSize refreshStatistics() end, nil, true)
        f.selection = label(f, "", nil, 356, -619, 548) f.selection:SetTextColor(unpack(theme.inkMuted))
        f.selection:SetHeight(17) GL.Safe(f.selection.SetWordWrap, f.selection, false)
        for i, action in ipairs({ { L("À surveiller"), "warning" }, { L("Amie"), "friend" }, { L("Ennemie"), "enemy" }, { L("Neutre"), "neutral" }, { L("Avis et note…") } }) do
            local reaction = action[2]
            f.guildActions[i] = button(f, action[1], 356 + (i - 1) * 110, -637, 108, function()
                local selected = f.selected
                if not selected then return end
                if reaction then GL.SetGuildReaction(selected.name, reaction, nil, selected.realm)
                else GL.ShowGuilds({ guild = selected.name, realm = selected.realm }) end
            end, nil, true)
            f.guildActions[i].reaction = reaction
        end
    end
    local f = statisticsWindow
    if f.mode ~= mode then f.mode, f.category, f.choice, f.offset, f.selected = mode, 1, mode == "players" and 2 or 1, 0, nil end
    f.faction = f.faction or "all"
    showBook(f)
    refreshStatistics()
end
GL.On("CHANGED", refreshStatistics)


local journalPeriods = { { "all", L("Toutes périodes") }, { "week", L("7 derniers jours") }, { "month", L("30 derniers jours") }, { "year", L("Année") } }
local journalScopes = { { "character", L("Ce personnage") }, { "all", L("Tout le compte") }, { "legacy", L("Auteur inconnu") } }
local journalKinds = { { "all", L("Tous les événements") }, { "pvp", L("Rencontres PvP") }, { "honor", L("Gains d’honneur") }, { "social", L("Avis et groupes") }, { "notes", L("Notes personnelles") }, { "trade", L("Échanges") } }
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
    local history, annual = f.mode == "history", f.mode == "year"
    f.year = tonumber(f.year) or GL.JournalYears()[1] or tonumber(date("%Y"))
    local options = { period = annual and "year" or f.period, year = f.year, scope = f.scope, kind = f.kind, query = f.query or "" }
    local period = choiceLabel(journalPeriods, options.period) .. (options.period == "year" and f.year and (" " .. f.year) or "")
    local scope = choiceLabel(journalScopes, f.scope)
    f.scopeButton:SetText(scope) f.kindButton:SetText(choiceLabel(journalKinds, f.kind))
    f.yearButton:SetText(f.year and (L("Année : ") .. f.year) or L("Année inconnue"))
    f.yearButton:SetEnabled(options.period == "year" and f.year ~= nil)
    moveTo(f.yearButton, 36, annual and 341 or 416)
    for _, control in ipairs({ f.kindButton, f.search, f.searchButton, f.searchLabel, f.reset }) do
        if history then control:Show() else control:Hide() end
    end
    for key, control in pairs(f.tabs) do UI.selectButton(control, key == f.mode) end
    for key, control in pairs(f.periodButtons) do UI.selectButton(control, key == options.period) showIf(control, not annual) end
    for key, page in pairs({ summary = f.summary, history = f.history, story = f.story, year = f.annual }) do
        if key == f.mode then page:Show() else page:Hide() end
    end
    f.heading:SetText(({ summary = L("Votre tableau d’honneur"), history = L("La chronique de vos rencontres"), story = L("Votre récit de campagne"), year = L("Une année de rencontres") })[f.mode])
    f.subtitle:SetText(scope .. " · " .. period)
    showIf(f.copyAnnual, annual)
    if not annual then f.cardCopy:Hide() end
    local stats
    if not history then
        options.query, options.kind = "", "pvp"
        stats = GL.PersonalStatistics(options)
    end
    if f.mode == "summary" then
        f.cardName:SetText(f.scope == "character" and plain(stats.actorName or L("Votre personnage"))
            or f.scope == "legacy" and L("Archives sans auteur") or L("Les personnages de ce compte"))
        f.honor:SetText(honorTotal(stats))
        f.honor:SetEnabled(stats.honorAwards > 0)
        for key, metric in pairs(f.metrics) do
            local value = stats[key] or 0
            metric.value:SetText(tostring(value))
        end
        for key, control in pairs(f.recaps) do
            local item = stats[key]
            control.record = item and item.record
            local deaths = key == "mostDeaths"
            control.name:SetText(item and plain(item.record.fullName)
                or (deaths and L("Aucune mort confirmée") or L("Aucune victoire confirmée")))
            moveTo(control.name, item and 54 or 10, item and 27 or 36)
            control.name:SetWidth(item and 207 or 250)
            control.detail:SetText(item and counted(item.value, deaths and "mort confirmée" or "victoire confirmée",
                deaths and "morts confirmées" or "victoires confirmées") or "")
            if item then identityIcons(control, item.record) else portraitRows[control] = nil end
            showIf(control.raceIcon, item ~= nil) showIf(control.classIcon, item ~= nil)
            control:SetEnabled(item ~= nil)
        end
        local unknown = stats.unknownActorEvents or 0
        local coverage = counted(stats.events or 0, "fait de combat", "faits de combat")
        if unknown > 0 then
            coverage = coverage .. " · " .. unknown .. L(" sans auteur connu") .. (f.scope == "character" and L(" (hors bilan)") or "")
        end
        f.coverage:SetText(coverage)
        local podium = f.dimension == "opponents"
        local initiative = f.dimension == "initiative"
        local geographic = f.dimension == "zone"
        local zoom = geographic and f.zoneKey
        options.zone = zoom
        local breakdown = not podium and not initiative and GL.PvPBreakdown(options, zoom and "subzone" or f.dimension) or {}
        local exposure, partial = {}
        if geographic and not zoom and GL.ZoneTimes then exposure, partial = GL.ZoneTimes(options) end
        if geographic and not zoom then
            local known, peaceful = {}, {}
            for _, item in ipairs(breakdown) do known[item.key] = true end
            for place, seconds in pairs(exposure) do
                if not known[place] then peaceful[#peaceful + 1] = {key = place, label = place, kills = 0,
                    deaths = 0, correctedKills = 0, correctedDeaths = 0, seconds = seconds} end
            end
            table.sort(peaceful, function(a, b) return a.seconds > b.seconds or a.seconds == b.seconds and a.key < b.key end)
            for _, item in ipairs(peaceful) do breakdown[#breakdown + 1] = item end
        end
        local showTime = geographic and not zoom and (GL.Settings().zoneTime or next(exposure) ~= nil)
        showIf(f.zoneBack, zoom) showIf(f.breakdownTime, showTime)
        showIf(f.zoneTracking, geographic and GL.ZoneTimes ~= nil)
        f.zoneTracking:SetText(GL.Settings().zoneTime and L("Suspendre le suivi du temps") or L("Mesurer le temps par zone"))
        f.zoneBack:SetText(L("‹ Toutes les zones"))
        f.breakdownLabel:SetText(zoom and plain(f.zoneLabel) or geographic and L("Zone · ouvrir les lieux") or L("Combats"))
        moveTo(f.breakdownLabel, zoom and 484 or 356, 451)
        f.breakdownLabel:SetWidth(zoom and 150 or showTime and 176 or 270)
        showIf(f.podium, podium) showIf(f.initiative, initiative) showIf(f.breakdown, not podium and not initiative)
        if initiative then
            local ratio = "—"
            if stats.attackers > 0 then
                local decimal = DECIMAL_SEPERATOR or (frenchNumbers and "," or ".")
                ratio = ("%.2f"):format(stats.victims / stats.attackers):gsub("%.", decimal)
            end
            for key, value in pairs(f.initiative.values) do
                value:SetText(key == "ratio" and ratio or tostring(stats[key]))
            end
            local openings = stats.initiated + stats.responded
            if openings > 0 then
                local share = math.floor(100 * stats.initiated / openings + 0.5)
                f.initiative.values.initiated:SetText(L("%d · %d %%"):format(stats.initiated, share))
                f.initiative.values.responded:SetText(L("%d · %d %%"):format(stats.responded, 100 - share))
            end
        end
        if podium then
            for i, control in ipairs(f.podium.rows) do
                local item = stats.topDeaths[i]
                control.record = item and item.record
                showIf(control, item ~= nil)
                if item then
                    control.name:SetText(i .. ". " .. plain(item.record.fullName))
                    control.bar:SetWidth(160 * item.value / stats.topDeaths[1].value)
                    control.count:SetText(tostring(item.value))
                    identityIcons(control, item.record)
                end
            end
            f.podium.empty:SetText(#stats.topDeaths == 0 and L("Aucun adversaire confirmé sur cette période.") or "")
        end
        f.breakdownOffset = math.min(f.breakdownOffset, math.max(0, math.floor((#breakdown - 1) / #f.breakdownRows) * #f.breakdownRows))
        local corrected = 0
        for _, item in ipairs(breakdown) do corrected = corrected + item.correctedKills + item.correctedDeaths end
        for i, row in ipairs(f.breakdownRows) do
            local item = breakdown[f.breakdownOffset + i]
            if item then
                row.zone = geographic and not zoom and item.key ~= "mixed" and item.key ~= "unknown" and item or nil
                row:EnableMouse(row.zone ~= nil)
                local text = item.label
                if item.key == "unknown" or item.key == "mixed" then text = L(text)
                elseif f.dimension == "race" then text = raceLabel(item.key, text, item.raceID)
                elseif f.dimension == "class" then text = classLabel(item.key, text) end
                row.name:SetText(plain(text))
                row.name:SetWidth(showTime and 177 or 270)
                local seconds = exposure[item.key]
                showIf(row.time, showTime)
                if showTime then
                    row.time:SetText(seconds and groupDurationText(seconds) or "—")
                end
                row.kills:SetText(tostring(item.kills))
                row.deaths:SetText(tostring(item.deaths))
                row:Show()
            else row:Hide() end
        end
        for key, control in pairs(f.dimensionButtons) do
            UI.selectButton(control, key == f.dimension)
        end
        f.breakdownEmpty:SetText(#breakdown == 0 and (zoom and L("Aucun combat enregistré dans cette zone pour cette sélection.") or L("Aucune victoire ni mort enregistrée pour cette sélection.")) or "")
        local notices = {}
        if corrected > 0 then notices[#notices + 1] = counted(corrected, "rapport annulé", "rapports annulés") .. L(", hors totaux") end
        if showTime and partial then notices[#notices + 1] = L("Durées minimales · archives de présence partielles") end
        f.breakdownInfo:SetText(table.concat(notices, "\n"))
        f.breakdownPrevious:SetEnabled(f.breakdownOffset > 0)
        f.breakdownNext:SetEnabled(f.breakdownOffset + #f.breakdownRows < #breakdown)
    elseif annual then
        local card = f.annual
        card.name:SetText(f.scope == "character" and plain(stats.actorName or L("Votre personnage")) or f.scope == "legacy" and L("Archives sans auteur") or L("Votre compte"))
        card.period:SetText(f.year and (L("Votre campagne de ") .. f.year) or L("Année inconnue"))
        for key, metric in pairs(card.metrics) do metric:SetText(tostring(stats[key])) end
        for key, recap in pairs(card.recaps) do
            local item = stats[key]
            recap.record = item and item.record
            recap.name:SetText(item and plain(item.record.fullName) or L("Aucun adversaire confirmé"))
            recap.score:SetText(item and counted(item.value, key == "mostDeaths" and "mort" or "victoire") or "—")
            if item then identityIcons(recap, item.record) end
            showIf(recap.raceIcon, item ~= nil) showIf(recap.classIcon, item ~= nil) recap:SetEnabled(item ~= nil)
        end
        card.honor:SetText(honorTotal(stats))
        card.coverage:SetText((stats.events > 0 or stats.honorAwards > 0) and counted(stats.events, "fait de combat", "faits de combat") .. L(" · Hors champs de bataille et arènes.") or L("Aucun fait PvP conservé pour cette année et cette sélection."))
        local text = table.concat({ "Grudge Ledger · " .. period .. " · " .. scope,
            L("Confirmés : ") .. counted(stats.kills, "victoire") .. ", " .. counted(stats.deaths, "mort") .. ", " .. counted(stats.aggressions, "agression") .. ".",
            honorTotal(stats) }, "\n")
        if text ~= f.annualText then f.cardCopy:Hide() end
        f.annualText = text
    elseif f.mode == "story" then
        local story = {
            L("Vous avez remporté ") .. counted(stats.kills, "victoire confirmée", "victoires confirmées") .. L(" et subi ") .. counted(stats.deaths, "mort confirmée", "morts confirmées") .. ".", "" }
        if stats.aggressions > 0 then story[#story + 1] = L("Le registre compte aussi ") .. counted(stats.aggressions, "agression confirmée", "agressions confirmées") .. ".\n" end
        if stats.mostDeaths then story[#story + 1] = L("Votre némésis sur cette période : ") .. plain(stats.mostDeaths.record.fullName) .. " (" .. counted(stats.mostDeaths.value, "mort confirmée", "morts confirmées") .. ").\n" end
        if stats.mostKilled then story[#story + 1] = L("Votre adversaire le plus vaincu : ") .. plain(stats.mostKilled.record.fullName) .. " (" .. counted(stats.mostKilled.value, "victoire confirmée", "victoires confirmées") .. ").\n" end
        if (stats.events or 0) == 0 then
            story = stats.honorAwards > 0 and {} or { L("Le récit de cette période reste à écrire."), "", L("Aucun fait PvP comptabilisé dans cette sélection. Essayez une période plus large ou un autre personnage.") }
        end
        story[#story + 1] = honorTotal(stats)
        if stats.honorAwards > 0 then story[#story + 1] = honorDetail(stats) end
        story[#story + 1] = ""
        story[#story + 1] = subdued(L("Ce récit résume vos archives, pas l'ensemble de votre carrière. Champs de bataille et rapports annulés sont exclus."))
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
                if event.kind == "note" then title = event.text or L("Note personnelle") end
                if event.voided then title = title .. L(" — exclu des compteurs") end
                local place = event.subzone or event.zone
                local author = not event.actorGUID and L(" · auteur inconnu") or f.scope == "all" and (" · " .. plain(event.actorName or L("Autre personnage"))) or ""
                if record then identityIcons(row, record) else portraitRows[row] = nil end
                showIf(row.raceIcon, record ~= nil) showIf(row.classIcon, record ~= nil)
                local hasTime = type(event.time) == "number" and event.time > 0
                row.name:SetText((hasTime and date("%H:%M", event.time) .. "  ·  " or "") .. (record and plain(record.fullName) or L("Adversaire non identifié")))
                row.action:SetText(plain(title):gsub("[\r\n]+", " "))
                row.meta:SetText((hasTime and date("%d/%m/%Y", event.time) or L("Date inconnue")) .. (place and (" · " .. plain(place)) or "") .. author)
                row.context:SetText(event.kind == "trade" and plain((eventEvidence(event) or ""):gsub("\n", " · ")) or combatDetails(event, true) or event.questTitle and L("Quête suivie · ") .. plain(event.questTitle)
                    or event.guild and L("Guilde lors du combat · ") .. plain(event.guild) or "")
                row.stripe:SetColorTexture(unpack(inkColors[GL.Relation(record)] or inkColors.neutral)) row:Show()
            else row:Hide() end
        end
        f.empty:SetText(#events == 0 and L("Aucune rencontre dans cette sélection.\nÉlargissez la période ou les filtres.") or "")
        f.total:SetText(#events == 0 and L("Aucun événement") or (f.offset + 1) .. "–" .. math.min(f.offset + #f.rows, #events) .. " / " .. #events)
        f.previous:SetEnabled(f.offset > 0) f.next:SetEnabled(f.offset + #f.rows < #events)
    end
    f.help:ClearAllPoints() f.help:SetPoint("TOPLEFT", 36, history and -608 or annual and -396 or -465) f.help:SetHeight(history and 46 or annual and 60 or 180)
    local help = history and L("Ouvrez les détails d’un événement. Validez la recherche avec Entrée ou OK.")
        or annual and L("Cette carte résume les faits PvP conservés pour l’année et les personnages choisis.")
        or f.mode == "story" and L("Choisissez une période et les personnages dont vous souhaitez relire les combats.")
        or f.dimension == "opponents" and L("Seules les morts confirmées figurent au podium. Cliquez sur un adversaire pour ouvrir sa fiche.")
        or f.dimension == "initiative" and L("La rancune est celle du journal avant le combat. Une revanche est une victoire que vous engagez après une mort confirmée contre ce joueur avec le même personnage.")
        or f.dimension == "zone" and L("Cliquez sur une zone pour lire ses sous-zones. Le temps mesure la présence en monde ouvert depuis l’activation, hors absences et instances.")
        or L("La race et la classe sont celles relevées au combat. « Inconnue » signifie que l'information manque.")
    if f.mode == "summary" and stats.honorAwards > 0 then help = honorDetail(stats) .. "\n\n" .. help end
    f.help:SetText(help)
end

function GL.ShowJournal(mode)
    if not GL.db then return end
    if not journalWindow then
        local f = bookWindow("GrudgeLedgerJournal", "Grudge Ledger") journalWindow = f
        f.mode, f.period, f.scope, f.kind, f.offset, f.dimension, f.breakdownOffset = "summary", "all", "character", "all", 0, "opponents", 0
        f.year = GL.JournalYears()[1] or tonumber(date("%Y"))
        bookNavigation(f, "journal")
        f.tabs = {}
        for i, entry in ipairs({ { "summary", L("Vue d’ensemble") }, { "history", L("Chronique") }, { "year", L("Mon année") }, { "story", L("Récit") } }) do
            local key = entry[1]
            f.tabs[key] = button(f, entry[2], 36 + ((i - 1) % 2) * 131, -157 - math.floor((i - 1) / 2) * 33, 125, function() GL.ShowJournal(key) end, true)
        end
        label(f, L("Personnages"), nil, 36, -245, 256):SetTextColor(unpack(theme.muted))
        f.scopeButton = button(f, "", 36, -267, 256, function() f.scope, f.offset, f.breakdownOffset = nextChoice(journalScopes, f.scope), 0, 0 refreshJournal() end)
        label(f, L("Période"), nil, 36, -315, 256):SetTextColor(unpack(theme.muted))
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
        f.searchLabel = label(f, L("Rechercher dans la chronique"), nil, 36, -510, 256) f.searchLabel:SetTextColor(unpack(theme.muted))
        f.search = CreateFrame("EditBox", nil, f) f.search:SetPoint("TOPLEFT", 36, -534) f.search:SetSize(195, 26)
        f.search:SetAutoFocus(false) f.search:SetMaxLetters(200) styleInput(f.search, false, false)
        local function searchJournal() f.query, f.offset = f.search:GetText(), 0 f.search:ClearFocus() refreshJournal() end
        f.search:SetScript("OnEnterPressed", searchJournal) f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.searchButton = button(f, "OK", 241, -534, 51, searchJournal)
        f.reset = button(f, L("Effacer les filtres"), 36, -572, 256, function()
            f.query, f.kind, f.period, f.scope, f.offset = "", "all", "all", "character", 0 f.search:SetText("") refreshJournal()
        end)
        f.help = label(f, "", nil, 36, -608, 256) f.help:SetTextColor(unpack(theme.muted)) f.help:SetHeight(46) journalFont(f.help, "GameFontHighlightSmall", 12)
        f.heading = label(f, "", "large", 372, -165, 532) f.heading:SetTextColor(unpack(theme.ink))
        journalFont(f.heading, "GameFontNormalLarge", 21)
        f.subtitle = label(f, "", nil, 372, -194, 532) f.subtitle:SetTextColor(unpack(theme.inkMuted))
        f.summary = CreateFrame("Frame", nil, f) f.summary:SetAllPoints(f)
        f.history = CreateFrame("Frame", nil, f) f.history:SetAllPoints(f)
        f.story = CreateFrame("Frame", nil, f) f.story:SetAllPoints(f)
        f.cardName = label(f.summary, "", "large", 356, -216, 300) f.cardName:SetTextColor(unpack(theme.ink))
        f.cardName:SetHeight(26) GL.Safe(f.cardName.SetWordWrap, f.cardName, false)
        f.honor = button(f.summary, "", 661, -211, 243, function()
            f.kind, f.query, f.offset = "honor", "", 0
            f.search:SetText("") GL.ShowJournal("history")
        end, nil, true)
        f.metrics = {}
        for i, entry in ipairs({ { "kills", L("Victoires confirmées") }, { "deaths", L("Morts confirmées") }, { "aggressions", L("Agressions confirmées") } }) do
            local card = CreateFrame("Frame", nil, f.summary) card:SetPoint("TOPLEFT", 356 + (i - 1) * 185, -245) card:SetSize(176, 80)
            parchmentPanel(card)
            local icons = { "Interface\\Icons\\Ability_DualWield", "Interface\\Icons\\Ability_Rogue_FeignDeath", "Interface\\Icons\\Ability_Warrior_Challange" }
            bookIcon(card, 9, 10, 25, icons[i])
            local value = bookText(card, 42, 0, 128, 34, 23, "0")
            local caption = label(card, entry[2], nil, 8, -34, 160) caption:SetTextColor(unpack(theme.inkMuted))
            journalFont(caption, "GameFontHighlightSmall", 11) caption:SetHeight(30)
            f.metrics[entry[1]] = { value = value, caption = caption }
        end
        f.recaps = {}
        for i, entry in ipairs({ { "mostDeaths", L("Votre pire antagoniste") }, { "mostKilled", L("Votre adversaire le plus vaincu") } }) do
            local row = CreateFrame("Button", nil, f.summary)
            row:SetPoint("TOPLEFT", 356 + (i - 1) * 277, -331) row:SetSize(270, 76)
            parchmentPanel(row)
            local title = bookText(row, 10, 5, 250, 21, 14, entry[2], theme.inkMuted)
            journalFont(title, "QuestFont_Large", 14, true)
            row.raceIcon = bookIcon(row, 10, 30, 36) row.classIcon = bookIcon(row, 34, 54, 15)
            row.name = bookText(row, 54, 27, 207, 23, 16)
            row.detail = bookText(row, 54, 52, 207, 20, 12, "", theme.inkMuted)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", function(self) if self.record then GL.ShowLedger(self.record.key) end end)
            f.recaps[entry[1]] = row
        end
        f.dimensionButtons = {}
        for i, entry in ipairs({ { "opponents", L("Adversaires") }, { "race", L("Par race") }, { "class", L("Par classe") }, { "zone", L("Par zone") }, { "initiative", L("Initiative") } }) do
            local key = entry[1]
            f.dimensionButtons[key] = button(f.summary, entry[2], 356 + (i - 1) * 111, -413, 104, function() f.dimension, f.breakdownOffset, f.zoneKey = key, 0, nil refreshJournal() end, true, true)
        end
        f.initiative = CreateFrame("Frame", nil, f.summary) f.initiative:SetAllPoints(f)
        f.initiative.values = {}
        for _, group in ipairs({
            { x = 356, y = 449, title = L("Joueurs distincts"), {"victims", L("Vaincus")}, {"attackers", L("Vous ayant blessé")}, {"ratio", L("Vaincus / attaquants")} },
            { x = 356, y = 556, title = L("Premier dégât observé"), {"initiated", L("Porté par vous")}, {"responded", L("Porté par l’adversaire")} },
            { x = 633, y = 449, title = L("Victoires confirmées"), {"initiatedKillsNoGrudge"}, {"initiatedKillsGrudge"},
                {"revengeKills"}, {"responseKills"}, {"unknownOpeningKills"} },
        }) do
            bookText(f.initiative, group.x, group.y, 271, 25, 16, group.title)
            for i, entry in ipairs(group) do
                local y = group.y + 26 + (i - 1) * 24
                local share = entry[1] == "initiated" or entry[1] == "responded"
                bookText(f.initiative, group.x, y, share and 153 or 198, 23, 13, entry[2] or killOpeningLabels[entry[1]], theme.inkMuted)
                local value = bookText(f.initiative, group.x + (share and 157 or 201), y, share and 97 or 53, 23, 14)
                value:SetJustifyH("RIGHT") f.initiative.values[entry[1]] = value
            end
        end
        f.podium = CreateFrame("Frame", nil, f.summary) f.podium:SetAllPoints(f)
        bookText(f.podium, 356, 449, 548, 25, 16, L("Vos morts par adversaire"))
        f.podium.empty = bookText(f.podium, 356, 485, 548, 29, 13, "", theme.inkMuted)
        f.podium.rows = {}
        for i = 1, 3 do
            local row = CreateFrame("Button", nil, f.podium)
            row:SetPoint("TOPLEFT", 356, -480 - (i - 1) * 41) row:SetSize(548, 39)
            row.raceIcon = bookIcon(row, 2, 2, 30) row.classIcon = bookIcon(row, 23, 21, 13)
            row.name = bookText(row, 43, 5, 242, 26, 15)
            local track = row:CreateTexture(nil, "BACKGROUND")
            track:SetPoint("TOPLEFT", 305, -12) track:SetSize(162, 12) track:SetColorTexture(0.46, 0.32, 0.16, 0.32)
            row.bar = row:CreateTexture(nil, "ARTWORK") row.bar:SetPoint("TOPLEFT", 306, -13) row.bar:SetHeight(10) row.bar:SetColorTexture(0.50, 0.12, 0.10, 1)
            row.count = bookText(row, 475, 5, 65, 27, 16) row.count:SetJustifyH("RIGHT")
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", function(self) if self.record then GL.ShowLedger(self.record.key) end end)
            f.podium.rows[i] = row
        end
        f.breakdown = CreateFrame("Frame", nil, f.summary) f.breakdown:SetAllPoints(f)
        f.breakdownLabel = bookText(f.breakdown, 356, 451, 270, 23, 12, "", theme.inkMuted)
        f.breakdownTime = bookText(f.breakdown, 539, 451, 96, 23, 12, L("Présence"), theme.inkMuted)
        f.zoneBack = button(f.breakdown, L("‹ Toutes les zones"), 356, -447, 125, function()
            f.zoneKey, f.breakdownOffset = nil, 0 refreshJournal()
        end, nil, true)
        f.zoneTracking = button(f.summary, "", 36, -620, 256, function()
            GL.SetSetting("zoneTime", not GL.Settings().zoneTime) refreshJournal()
        end)
        label(f.breakdown, L("Victoires"), nil, 642, -451, 125):SetTextColor(unpack(theme.inkMuted))
        label(f.breakdown, L("Morts"), nil, 787, -451, 117):SetTextColor(unpack(theme.inkMuted))
        f.breakdownRows = {}
        for i = 1, 5 do
            local row = CreateFrame("Button", nil, f.breakdown) row:SetPoint("TOPLEFT", 356, -476 - (i - 1) * 24) row:SetSize(548, 22)
            surface(row, theme.selection):SetAlpha(i % 2 == 0 and 0.35 or 0)
            row.name = label(row, "", nil, 5, -2, 270) row.name:SetTextColor(unpack(theme.ink))
            row.time = bookText(row, 183, 2, 96, 20, 12, "", theme.inkMuted)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", function(self)
                if self.zone then f.zoneKey, f.zoneLabel, f.breakdownOffset = self.zone.key, self.zone.label, 0 refreshJournal() end
            end)
            row.kills = label(row, "", nil, 286, -2, 125) row.kills:SetTextColor(unpack(theme.ink))
            row.deaths = label(row, "", nil, 431, -2, 117) row.deaths:SetTextColor(unpack(theme.ink))
            for _, text in ipairs({ row.name, row.kills, row.deaths }) do text:SetHeight(20) GL.Safe(text.SetWordWrap, text, false) end
            f.breakdownRows[i] = row
        end
        f.breakdownEmpty = label(f.breakdown, "", nil, 356, -497, 548) f.breakdownEmpty:SetTextColor(unpack(theme.inkMuted))
        f.breakdownInfo = label(f.breakdown, "", nil, 356, -604, 410) f.breakdownInfo:SetTextColor(unpack(theme.inkMuted)) journalFont(f.breakdownInfo, "GameFontHighlightSmall", 12)
        f.breakdownPrevious = button(f.breakdown, "<", 808, -598, 42, function() f.breakdownOffset = math.max(0, f.breakdownOffset - #f.breakdownRows) refreshJournal() end, nil, true)
        f.breakdownNext = button(f.breakdown, ">", 862, -598, 42, function() f.breakdownOffset = f.breakdownOffset + #f.breakdownRows refreshJournal() end, nil, true)
        f.coverage = label(f.summary, "", nil, 356, -645, 548) f.coverage:SetTextColor(unpack(theme.inkMuted)) journalFont(f.coverage, "GameFontHighlightSmall", 12) f.coverage:SetHeight(17)
        f.storyScroll = CreateFrame("ScrollFrame", nil, f.story, "UIPanelScrollFrameTemplate") f.storyScroll:SetPoint("TOPLEFT", 356, -221) f.storyScroll:SetSize(536, 405)
        f.storyBody = CreateFrame("Frame", nil, f.storyScroll) f.storyBody:SetSize(531, 405)
        f.storyText = label(f.storyBody, "", nil, 0, 0, 521) journalFont(f.storyText, "QuestFont_Large", 15) f.storyText:SetTextColor(unpack(theme.ink)) f.storyText:SetSpacing(5)
        f.storyScroll:SetScrollChild(f.storyBody)
        local annual = CreateFrame("Frame", nil, f)
        annual:SetPoint("TOPLEFT", 356, -213) annual:SetSize(548, 435)
        f.annual, annual.metrics, annual.recaps = annual, {}, {}
        surface(annual, theme.gold):SetAlpha(0.72)
        local annualPaper = annual:CreateTexture(nil, "BACKGROUND", nil, 1)
        annualPaper:SetPoint("TOPLEFT", 2, -2) annualPaper:SetPoint("BOTTOMRIGHT", -2, 2)
        annualPaper:SetTexture(media .. "JournalPaper")
        for _, entry in ipairs({ { "TOPLEFT", 1, -1, 0 }, { "TOPRIGHT", -1, -1, 1 }, { "BOTTOMLEFT", 1, 1, 2 }, { "BOTTOMRIGHT", -1, 1, 3 } }) do
            local corner = annual:CreateTexture(nil, "BORDER")
            corner:SetPoint(entry[1], entry[2], entry[3]) corner:SetSize(18, 18)
            corner:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
            local u, v = entry[4] % 2 * 0.65, math.floor(entry[4] / 2) * 0.65
            corner:SetTexCoord(u, u + 0.35, v, v + 0.35)
        end
        annual.name = bookText(annual, 14, 14, 520, 40, 25) annual.name:SetJustifyH("CENTER")
        annual.period = bookText(annual, 14, 55, 520, 28, 16, "", theme.inkMuted) annual.period:SetJustifyH("CENTER")
        for i, entry in ipairs({ { "kills", L("Victoires") }, { "deaths", L("Morts PvP") }, { "aggressions", L("Agressions") } }) do
            local x = 12 + (i - 1) * 176
            annual.metrics[entry[1]] = bookText(annual, x, 89, 172, 49, 30)
            annual.metrics[entry[1]]:SetJustifyH("CENTER")
            bookText(annual, x, 142, 172, 25, 15, entry[2]):SetJustifyH("CENTER")
        end
        bookText(annual, 14, 173, 520, 21, 12, L("Faits PvP confirmés"), theme.inkMuted):SetJustifyH("CENTER")
        for i, entry in ipairs({ { "mostDeaths", L("Votre pire antagoniste") }, { "mostKilled", L("Votre adversaire le plus vaincu") } }) do
            local row = CreateFrame("Button", nil, annual)
            row:SetPoint("TOPLEFT", 16, -207 - (i - 1) * 58) row:SetSize(516, 54)
            surface(row, theme.gold):SetAlpha(0.14)
            row.raceIcon = bookIcon(row, 7, 6, 37) row.classIcon = bookIcon(row, 32, 32, 15)
            row.name = bookText(row, 54, 3, 326, 24, 15)
            bookText(row, 54, 29, 326, 21, 12, entry[2], theme.inkMuted)
            row.score = bookText(row, 390, 11, 117, 27, 15) row.score:SetJustifyH("RIGHT")
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", function(self) if self.record then GL.ShowLedger(self.record.key) end end)
            annual.recaps[entry[1]] = row
        end
        annual.honor = bookText(annual, 16, 345, 516, 22, 14)
        annual.coverage = bookText(annual, 16, 369, 516, 26, 12)
        GL.Safe(annual.coverage.SetWordWrap, annual.coverage, true)
        annual.events = button(annual, L("Voir les événements de l’année"), 95, -397, 358, function()
            f.period, f.kind, f.query, f.offset = "year", "pvp", "", 0
            f.search:SetText("") GL.ShowJournal("history")
        end, nil, true)
        f.cardCopy = CreateFrame("Frame", nil, f)
        f.cardCopy:SetPoint("TOPLEFT", 36, -502) f.cardCopy:SetSize(256, 145)
        local copyField = CreateFrame("EditBox", nil, f.cardCopy)
        copyField:SetPoint("TOPLEFT") copyField:SetSize(256, 115) copyField:SetMultiLine(true)
        copyField:SetAutoFocus(false) styleInput(copyField, true)
        copyField:SetScript("OnEscapePressed", function() f.cardCopy:Hide() end)
        f.cardCopy:SetScript("OnHide", function() copyField:ClearFocus() end)
        label(f.cardCopy, L("Ctrl+C pour copier."), nil, 0, -119, 256):SetTextColor(unpack(theme.muted))
        f.cardCopy:Hide()
        f.copyAnnual = button(f, L("Copier le bilan annuel"), 36, -464, 256, function()
            f.cardCopy:Show() copyField:SetText(f.annualText) copyField:SetFocus() copyField:HighlightText()
        end, true)
        f.rows = {}
        for i = 1, 5 do
            local row = CreateFrame("Button", nil, f.history) row:SetPoint("TOPLEFT", 356, -216 - (i - 1) * 80) row:SetSize(548, 76)
            surface(row, theme.selection):SetAlpha(i % 2 == 0 and 0.25 or 0.08)
            row.stripe = row:CreateTexture(nil, "ARTWORK") row.stripe:SetPoint("TOPLEFT") row.stripe:SetPoint("BOTTOMLEFT") row.stripe:SetWidth(2)
            row.raceIcon = bookIcon(row, 8, 10, 37) row.classIcon = bookIcon(row, 32, 36, 15)
            row.name = bookText(row, 54, 3, 305, 24, 15)
            row.action = bookText(row, 54, 29, 480, 22, 13)
            row.meta = bookText(row, 366, 5, 174, 36, 10, "", theme.inkMuted) GL.Safe(row.meta.SetWordWrap, row.meta, true)
            row.context = bookText(row, 54, 53, 367, 21, 11, "", theme.inkMuted)
            row.details = button(row, L("Détails"), 432, -47, 108, function()
                local item = row.item
                if not item then return end
                if item.event.note then GL.EditNote(item.record, item.event.note)
                else inspectEvent(item.record, item.event) end
            end, nil, true)
            for _, text in ipairs({ row.name, row.action, row.meta }) do GL.Safe(text.SetWordWrap, text, false) end
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:SetScript("OnClick", function(self)
                if not self.item then return end
                if self.item.record then GL.ShowLedger(self.item.record.key) else inspectEvent(nil, self.item.event) end
            end)
            f.rows[i] = row
        end
        f.empty = label(f.history, "", nil, 365, -238, 520) f.empty:SetTextColor(unpack(theme.inkMuted))
        f.previous = button(f.history, L("Précédent"), 356, -628, 120, function() f.offset = math.max(0, f.offset - #f.rows) refreshJournal() end, nil, true)
        f.total = label(f.history, "", nil, 486, -635, 284) f.total:SetJustifyH("CENTER") f.total:SetTextColor(unpack(theme.inkMuted))
        f.next = button(f.history, L("Suivant"), 784, -628, 120, function() f.offset = f.offset + #f.rows refreshJournal() end, nil, true)
    end
    journalWindow.mode = (mode == "history" or mode == "story" or mode == "year") and mode or "summary"
    showBook(journalWindow) refreshJournal()
end
GL.On("CHANGED", refreshJournal)

local function eventDate(event)
    local t = GL.Clean(event.time, "number")
    return t and t > 0 and t < math.huge and GL.Safe(date, "%d/%m/%Y %H:%M", t) or L("Date inconnue")
end

local function eventPlace(e)
    local zone = e.zone ~= "?" and e.zone or ""
    if e.subzone and e.subzone ~= "" and e.subzone ~= zone then return e.subzone .. (zone ~= "" and " · " .. zone or "") end
    return zone ~= "" and zone or L("Lieu non renseigné")
end

local function eventCertainty(e)
    if e.kind == "trade" then return L("Échange confirmé") end
    if e.voidReason == "battleground" then return L("Champ de bataille · exclu") end
    if e.voided then return L("Annulé · exclu") end
    if e.kind == "honor" then return L("Honneur") end
    if e.kind == "opening" then return L("Initiative") end
    if e.playerConfirmedAt then return L("Témoignage") end
    if pvpNames[e.kind] then return e.confidence == "confirmed" and L("Confirmé") or L("Certitude inconnue") end
    return e.source == "emote" and L("Geste") or e.kind == "grouped" and L("Groupe") or L("Journal")
end

local function honorRecipient(e)
    return L("Reçu par %s"):format(plain(e.actorName or L("Auteur inconnu")))
end

local function eventAction(e)
    if pvpNames[e.kind] and e.confidence ~= "confirmed" then return pvpNames[e.kind] .. L(" consignée") end
    local delta = type(e.delta) == "number" and e.delta ~= 0 and (L(" — avis ") .. (e.delta > 0 and "+" or "") .. e.delta) or ""
    return eventTitle(e) .. delta
end

local function eventReason(e)
    if e.kind == "honor" then
        return honorRecipient(e) .. "\n" .. L("Le jeu annonce votre gain d’honneur. Plusieurs joueurs peuvent recevoir de l’honneur pour le même combat.")
    end
    if e.voidReason == "other-killer" then return L("Le jeu a attribué le coup fatal à un autre joueur.") end
    if e.playerConfirmedAt then return L("Coup fatal confirmé manuellement le %s."):format(stamp(e.playerConfirmedAt)) end
end

local function refreshCorrections()
    local f = correctionWindow
    if not f or not f:IsShown() or not f.event then return end
    local e = f.event
    f.certainty:SetText(eventCertainty(e))
    f.effect:SetText(e.voided and L("Ce fait reste dans l’histoire. Il est exclu des statistiques et du solde automatique.")
        or e.kind == "honor" and L("Honneur adverse inconnu")
        or pvpNames[e.kind] and L("Annuler retire ce fait des statistiques et du solde automatique. Il reste lisible dans l’histoire.")
        or L("Cet événement reste dans votre journal personnel."))
    if pvpNames[e.kind] then f.confirm:Show() else f.confirm:Hide() end
    f.confirm:SetEnabled(not e.voided and e.confidence == "confirmed")
    f.keep:SetText(pvpNames[e.kind] and not e.voided and L("Conserver") or L("Fermer"))
end

inspectEvent = function(record, e)
    if not e or not record and e.kind ~= "honor" then return end
    if not correctionWindow then
        local f = window("GrudgeLedgerCorrections", L("Vérifier cet événement"), 586, 447)
        correctionWindow = f
        local backing = surface(f, theme.paper, 12, 1)
        backing:ClearAllPoints() backing:SetPoint("TOPLEFT", 12, -48) backing:SetPoint("BOTTOMRIGHT", -12, 12)
        local paper = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        paper:SetAllPoints(backing) paper:SetTexture(media .. "JournalPaper")
        local function field(x, y, w, h, size)
            local region = label(f, "", nil, x, y, w)
            journalFont(region, size >= 16 and "GameFontNormalLarge" or "GameFontHighlight", size)
            region:SetTextColor(unpack(theme.ink)) region:SetHeight(h)
            return region
        end
        f.action = field(26, -65, 397, 53, 20)
        f.certainty = field(422, -70, 137, 40, 14) f.certainty:SetJustifyH("RIGHT")
        f.raceIcon = f:CreateTexture(nil, "ARTWORK") f.raceIcon:SetPoint("TOPLEFT", 26, -125) f.raceIcon:SetSize(56, 56)
        f.classIcon = f:CreateTexture(nil, "ARTWORK") f.classIcon:SetPoint("TOPLEFT", 70, -171) f.classIcon:SetSize(17, 17)
        f.who = field(98, -122, 463, 28, 16)
        f.where = field(98, -156, 463, 45, 13)
        field(26, -209, 515, 26, 17):SetText(L("Pourquoi cet événement ?"))
        f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT", 26, -242) f.scroll:SetSize(510, 77)
        local body = CreateFrame("Frame", nil, f.scroll) body:SetSize(500, 77)
        f.proof = label(body, "", nil, 0, 0, 498) f.proof:SetTextColor(unpack(theme.ink))
        f.scroll:SetScrollChild(body) f.body = body
        f.effect = field(26, -334, 532, 49, 13)
        f.keep = button(f, L("Fermer"), 24, -396, 105, function() f:Hide() end, true, true)
        UI.selectButton(f.keep, true)
        f.confirm = button(f, L("Annuler cet événement"), 351, -396, 211, nil, nil, true)
    end
    local f = correctionWindow
    f.identity, f.event = record and { key=record.key, guid=record.guid, alias=record.alias }, e
    f.title:SetText(pvpNames[e.kind] and L("Vérifier cet événement") or L("Détails de la rencontre"))
    f.action:SetText(eventAction(e))
    if record then identityIcons(f, record) else portraitRows[f] = nil end
    showIf(f.raceIcon, record ~= nil) showIf(f.classIcon, record ~= nil)
    f.who:SetText(record and plain(record.fullName or record.name or record.key) or L("Adversaire non identifié"))
    f.where:SetText(eventDate(e) .. "   ·   " .. plain(eventPlace(e)))
    local evidence = {}
    local category = GL.KillOpeningCategory(record, e)
    if category then evidence[#evidence + 1] = killOpeningLabels[category] end
    local reason = eventReason(e)
    if reason then evidence[#evidence+1] = reason end
    if e.evidence and e.evidence ~= "" then evidence[#evidence+1] = plain(eventEvidence(e)) end
    local combat = combatDetails(e)
    if combat then evidence[#evidence+1] = combat end
    if e.questTitle then evidence[#evidence+1] = L("Quête suivie : ") .. plain(e.questTitle) end
    if e.guildSource and e.guild then evidence[#evidence+1] = L("Guilde mémorisée : ") .. plain(e.guild) .. (e.guildRealm and " (" .. plain(e.guildRealm) .. ")" or "") .. (e.guildSource == "last-known" and L(" — observée auparavant") or "") end
    f.proof:SetText(#evidence > 0 and table.concat(evidence, "\n") or L("Aucune précision enregistrée."))
    f.body:SetHeight(math.max(77, f.proof:GetStringHeight() + 8)) f.scroll:SetVerticalScroll(0)
    local identity = f.identity
    f.confirm:SetScript("OnClick", function()
        if f.event ~= e or not f:IsShown() then return end
        local ok, err = GL.VoidPvP(identity, e)
        if ok then f:Hide() else refreshCorrections() f.effect:SetText(plain(err)) end
    end)
    f:Show() f:Raise() refreshCorrections()
end

local function showDiagnostic(private)
    if not diagnosticWindow then
        local f = window("GrudgeLedgerDiagnostic", L("Grudge Ledger — Diagnostic"), 660, 500)
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
        f.radarStatus = label(f, L("Réapplique l'apparence native ; rotation conservée."), nil, 234, -424, 395)
        f.radarStatus:SetHeight(30)
        button(f, L("Préparer la minimap"), 22, -421, 200, function()
            local _, message = GL.PrepareDruidRadar()
            f.radarStatus:SetText(message)
            f.edit:ClearFocus()
        end)
        button(f, L("Tout sélectionner"), 22, -461, 150, function() f.edit:SetFocus() f.edit:HighlightText() end)
        button(f, L("Données du registre"), 186, -461, 150, function()
            f:Hide() showSettings() settingsWindow:SelectCategory("data")
        end)
        button(f, L("Actualiser"), 350, -461, 120, function() showDiagnostic(f.private) end)
        button(f, L("Validation druide"), 484, -461, 145, function()
            if SlashCmdList.GRUDGELEDGERDRUIDRADAR and C_Timer and type(C_Timer.After) == "function" then
                f:Hide()
                GL.Print(L("Essai dans 3 secondes : place la souris sur le monde, hors fenêtres, puis reste immobile."))
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
        return L("indisponible")
    end
    local client, build, _, interface = GL.Safe(GetBuildInfo)
    local loading, loaded = GL.Safe((C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded, "TidyPlates_ThreatPlates")
    loaded = loaded == true or (loaded == nil and loading == true)
    local lines = { "Grudge Ledger " .. version(GL.version), L("Client : ") .. version(client), L("Build : ") .. version(build),
        L("Interface : ") .. version(interface), L("Intégration détectée : ") .. (loaded and "Threat Plates" or L("aucune")),
        L("Erreurs conservées : ") .. #(GL.errors or {}), "", L("API disponibles :") }
    for _, api in ipairs({
        { "Menu.ModifyMenu", Menu and Menu.ModifyMenu }, { "C_NamePlate.GetNamePlateForUnit", C_NamePlate and C_NamePlate.GetNamePlateForUnit },
        { "GetGuildInfo", GetGuildInfo }, { "CombatLogGetCurrentEventInfo", CombatLogGetCurrentEventInfo },
        { "C_ChatInfo.PerformEmote", C_ChatInfo and C_ChatInfo.PerformEmote }, { "DoEmote", DoEmote },
    }) do lines[#lines + 1] = api[1] .. " : " .. (type(api[2]) == "function" and L("oui") or L("non")) end
    lines[#lines + 1] = L("Coup fatal · événement PARTY_KILL : ") .. (GL.Tracker and GL.Tracker.nativeKillEvent and L("oui") or L("non"))
    lines[#lines + 1] = L("\nRéglages :")
    for _, key in ipairs({ "markers", "nameColor", "friendAlerts", "enemyAlerts", "sounds", "pvpTracking", "groupTracking", "socialTracking", "tradeTracking" }) do
        lines[#lines + 1] = key .. " : " .. (GL.Clean(GL.Settings()[key], "boolean") == true and L("oui") or L("non"))
    end
    lines[#lines + 1] = L("\nAffichage des noms :")
    for _, key in ipairs({ "nameplateShowFriendlyPlayers", "nameplateShowEnemies", "nameplateShowAll", "nameplateShowOnlyNameForFriendlyPlayerUnits" }) do
        local value = GL.Safe((C_CVar and C_CVar.GetCVar) or GetCVar, key)
        lines[#lines + 1] = key .. " : " .. ((value == "0" or value == "1") and value or L("indisponible"))
    end
    diagnosticWindow.private = private == true
    diagnosticWindow.privacy:SetText(private == true and L("Journal local : contient les noms de ton livre. Ne le publie pas tel quel.")
        or L("Rapport anonyme : Ctrl+C pour copier. Aucun nom ni note personnelle."))
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

local noteEditor, selectNote
local historyKinds = { {"all", L("Tous les événements")}, {"pvp", L("Combats PvP")}, {"matchup", L("Mes face-à-face")}, {"honor", L("Gains d’honneur")}, {"social", L("Avis et gestes")}, {"group", L("Groupes")}, {"trade", L("Échanges")}, {"voided", L("Événements annulés")} }
local function includeHistory(e, kind)
    return kind == "all" or (kind == "pvp" or kind == "honor") and GL.HonorPoints(e) or kind == "pvp" and (pvpNames[e.kind] or e.kind == "opening")
        or kind == "social" and (e.kind == "reaction" or e.kind == "reputation")
        or kind == "group" and (e.kind == "grouped" or e.kind == "group") or kind == "trade" and e.kind == "trade" or kind == "voided" and e.voided
end

local function renderHistory(p, record)
    if p.owner ~= record.key then p.owner, p.offset = record.key, 0 end
    local history = record.history or {}
    local cache = p.cache
    -- ponytail: index positions only for this open profile. Corrections preserve
    -- array length, so the CHANGED listener explicitly drops this index.
    if not cache or cache.history ~= history or cache.count ~= #history or cache.kind ~= p.kind then
        cache = { history = history, count = #history, kind = p.kind, indices = {} }
        if p.kind == "matchup" then cache.indices = GL.ContactMatchup(record, true).indices
        else
            for i = #history, 1, -1 do
                if type(history[i]) == "table" and includeHistory(history[i], p.kind) then cache.indices[#cache.indices + 1] = i end
            end
        end
        p.cache = cache
    end
    local count, size = #cache.indices, #p.rows
    p.offset = math.max(0, math.min(p.offset, math.floor(math.max(0, count-1) / size) * size))
    p.heading:SetText(L("Votre histoire avec ") .. plain(record.name or record.fullName))
    for _, entry in ipairs(historyKinds) do
        if entry[1] == p.kind then p.filter:SetText(entry[2]) end
        UI.selectButton(p.options[entry[1]], entry[1] == p.kind)
    end
    for i, row in ipairs(p.rows) do
        local e = history[cache.indices[p.offset + i]]
        row.record, row.event = e and record, e
        if e then
            row.date:SetText(eventDate(e) .. "   ·   " .. plain(eventPlace(e)))
            row.title:SetText(eventAction(e))
            row.badge:SetText(eventCertainty(e))
            row.badge:SetTextColor(unpack(e.voided and theme.inkMuted or theme.ink))
            local hint = e.kind == "honor" and honorRecipient(e) or combatDetails(e, true)
                or e.questTitle and (L("Quête suivie : ") .. plain(e.questTitle)) or eventReason(e)
            if not hint and e.source ~= "emote" and not pvpNames[e.kind] and e.evidence ~= "Avis personnel" then hint = plain(eventEvidence(e)) end
            if e.kind == "trade" then hint = plain((eventEvidence(e) or ""):gsub("\n", " · ")) end
            row.hint:SetText(hint or "")
            local icon = ({death="Ability_Rogue_FeignDeath", kill="Ability_DualWield", aggression="Ability_Warrior_Charge"})[e.kind]
            row.icon:SetTexture(icon and ("Interface\\Icons\\" .. icon) or GL.icon)
            row.details:SetText(L("Détails"))
            row:Show()
        else row:Hide() end
    end
    p.empty:SetText(count == 0 and L("Aucun événement dans cette sélection.") or "")
    p.total:SetText(count == 0 and L("0 événement") or (p.offset+1) .. "–" .. math.min(count,p.offset+size) .. L(" sur ") .. count)
    p.prev:SetEnabled(p.offset > 0) p.next:SetEnabled(p.offset + size < count)
end

local function renderDetail()
    local record = currentRecord()
    local tab = ledger.detailTab or "summary"
    if record then ledger.emptyPage:Hide() else ledger.emptyPage:Show() end
    for key, control in pairs(ledger.detailTabs) do
        if record then control:Show() else control:Hide() end
        UI.selectButton(control, tab == key)
    end
    for _, b in ipairs(ledger.actions) do b:SetEnabled(record ~= nil) end
    ledger.guildButton:SetEnabled(record ~= nil and record.guild ~= nil)
    ledger.tools:SetEnabled(record ~= nil)
    if not record then ledger.toolsMenu:Hide() end
    for reaction, control in pairs(ledger.reactions) do
        UI.selectButton(control, record and GL.Relation(record) == reaction)
    end
    local showHistory, showNotes = record and tab == "history", record and tab == "notes"
    local summary, matchup = tab == "summary" and record ~= nil, tab == "matchup" and record ~= nil
    if showHistory then ledger.historyPage:Show() else ledger.historyPage:Hide() end
    if not showNotes and noteWindow then noteWindow:Hide() end
    if showHistory or showNotes or not record then ledger.detailScroll:Hide() else ledger.detailScroll:Show() end
    for i = 1, 5 do
        local control = ledger.actions[i]
        showIf(control, summary)
    end
    if not summary then ledger.hint:Hide() ledger.tools:Hide() ledger.toolsMenu:Hide()
    else ledger.hint:Show() ledger.tools:Show() end
    showIf(ledger.counters, summary or matchup)
    showIf(ledger.balancePanel, summary)
    showIf(ledger.matchupHistory, matchup)
    ledger.detailScroll:ClearAllPoints()
    ledger.detailScroll:SetPoint("TOPLEFT", 356, summary and -450 or matchup and -380 or -283)
    ledger.detailScroll:SetHeight(summary and 126 or matchup and 220 or 293)
    ledger.detailTitle:SetTextColor(unpack(theme.ink))
    local lines = {}
    if not record then
        ledger.detailTitle:SetText("")
        ledger.detailIcon:Hide()
        ledger.detailStatus:SetText("")
        ledger.detailStatus:SetTextColor(unpack(theme.inkMuted))
        ledger.detailIdentity:SetText("")
        ledger.detailSource:SetText("") ledger.detailGuild:SetText("")
        ledger.raceIcon:Hide() ledger.classIcon:Hide() ledger.detailFaction:Hide()
    else
        ledger.detailIcon:Show()
        local relation, pvp = GL.Relation(record), record.pvp or {}
        ledger.detailTitle:SetText(plain(record.fullName or record.name or record.key))
        ledger.detailIcon:SetTexture(media .. relationIcons[relation])
        local source = GL.RelationSource(record)
        ledger.detailStatus:SetText(relationNames[relation])
        ledger.detailSource:SetText(({ manual = L("Avis personnel"), emote = L("Avis issu de vos gestes"), pvp = L("Avis issu du PvP"), guild = L("Avis hérité de la guilde"), automatic = L("Avis automatique"), neutral = L("Aucun avis") })[source] or L("Avis automatique"))
        ledger.detailStatus:SetTextColor(unpack(inkColors[relation]))
        local faction, race, class = identityLabels(record)
        local banner = factionPortrait[record.faction]
        if banner then ledger.detailFaction:SetTexture(banner) end
        showIf(ledger.detailFaction, banner)
        ledger.detailIdentity:SetText(plain(faction .. " · " .. race .. " · " .. class))
        ledger.detailGuild:SetText(record.guild and plain(record.guild) or L("Guilde non renseignée"))
        ledger.raceIcon:Show() ledger.classIcon:Show() identityIcons(ledger, record)
        local duels = matchup and GL.ContactMatchup(record)
        if summary or matchup then
            local counts = duels or pvp
            for _, field in ipairs({ "kills", "deaths" }) do
                local card = ledger.metrics[field]
                local n = counts[field] or 0
                local kills = field == "kills"
                card.caption:SetText(matchup and (kills and L("Victoires confirmées") or L("Morts confirmées"))
                    or (kills and L("Vous l’avez vaincu") or L("Vous a tué")))
                card.value:SetText(matchup and tostring(n) or (n == 1 and L("1 fois") or L("%d fois"):format(n)))
            end
        end
        if summary then
            local score, raw, gestures = GL.AutomaticBalance(record)
            ledger.balance:SetText(tostring(score))
            ledger.balance:SetTextColor(unpack(score < 0 and inkColors.enemy or score > 0 and inkColors.friend or theme.ink))
            local deaths = (pvp.deaths or 0)
            local wins = (pvp.kills or 0)
            local hits = (pvp.aggressions or 0)
            local formula = counted(deaths, "mort") .. " × −10  +  " .. counted(wins, "victoire")
            if hits > 0 then formula = formula .. "  −  " .. counted(hits, "agression") end
            if gestures ~= 0 then
                formula = (L("Combats %+.0f   ·   Gestes %+.0f")):format(raw, gestures)
            else
                formula = formula .. "  =  " .. raw
            end
            ledger.formula:SetText(formula)
            local context = source == "manual" and L("Avis personnel prioritaire · %s"):format(relationNames[relation]) or ""
            if score ~= raw + gestures then
                local reason = math.abs(score) == 100 and L("Solde plafonné à 100 en valeur absolue.")
                    or raw < 0 and L("Un geste amical n’efface pas une dette PvP.") or L("Une victoire seule ne crée pas d’amitié.")
                context = context ~= "" and context .. " · " .. reason or reason
            end
            ledger.scoreContext:SetText(context)
            local guildRule = GL.GetGuildRule(record)
            lines = {
                "|cff653c20" .. L("Dernière rencontre") .. "|r",
                record.lastEncounterAt and (stamp(record.lastEncounterAt) .. (record.lastEncounterZone and "  ·  " .. plain(record.lastEncounterSubzone or record.lastEncounterZone) or "")) or L("Date non enregistrée"),
            }
            local note = record.notes and record.notes[#record.notes]
            if note then
                -- ponytail: a short UTF-8-safe preview keeps the summary compact; Notes retains the full text.
                local count = 0
                local preview = note.text:gsub("[ \t\r\n\f\v]+", " "):gsub("[%z\1-\127\194-\244][\128-\191]*", function(character)
                    count = count + 1
                    return count <= 80 and character or ""
                end)
                lines[#lines + 1] = "\n|cff653c20" .. L("Dernière note") .. "|r"
                lines[#lines + 1] = plain(preview) .. (count > 80 and L("… (suite dans Notes)") or "")
            else lines[#lines + 1] = "\n" .. L("Aucune note personnelle.") end
            lines[#lines + 1] = "\n" .. L("Rencontres mémorisées : %d"):format(record.encounters and record.encounters.count or 0)
            lines[#lines + 1] = counted(pvp.aggressions or 0, "agression")
            local awards = GL.ContactMatchup(record)
            lines[#lines + 1] = honorTotal(awards)
            lines[#lines + 1] = L("Honneur adverse inconnu")
            if guildRule and guildRule.note and guildRule.note ~= "" then lines[#lines + 1] = L("Note de guilde : %s"):format(plain(guildRule.note)) end
            if (record.groupCount or 0) > 0 then lines[#lines + 1] = subdued(L("Sessions de groupe : %d"):format(record.groupCount)) end
        elseif matchup then
            local confirmed = duels.kills + duels.deaths
            ledger.matchupHistory:SetEnabled(confirmed + duels.honorAwards > 0)
            lines = { subdued(L("Ce personnage · Monde ouvert")), honorTotal(duels) }
            if duels.honorAwards > 0 then lines[#lines + 1] = honorDetail(duels) end
            lines[#lines + 1] = subdued(L("Honneur adverse inconnu"))
            if duels.run > 1 then
                lines[#lines + 1] = L("Série en cours : %s de suite."):format(counted(duels.run, duels.lastKind == "kill" and "victoire" or "défaite"))
            end
            if duels.comeback then lines[#lines + 1] = L("Dernière victoire après une défaite : %s"):format(eventDate(duels.comeback)) end
            if duels.closeDeaths then lines[#lines + 1] = L("Deux défaites à trois minutes d’intervalle ou moins le %s."):format(eventDate(duels.closeDeaths)) end
            if #duels.recent > 0 then
                lines[#lines + 1] = "\n|cff653c20" .. L("Derniers résultats datés") .. "|r"
                for _, event in ipairs(duels.recent) do
                    lines[#lines + 1] = eventDate(event) .. "   ·   " .. (event.kind == "kill" and L("Victoire") or L("Défaite")) .. "   ·   " .. plain(eventPlace(event))
                end
            elseif confirmed > 0 then lines[#lines + 1] = "\n" .. L("Aucun combat confirmé et daté pour ce personnage.")
            else lines[#lines + 1] = "\n" .. L("Aucune victoire ni défaite enregistrée avec ce joueur pour ce personnage.") end
        elseif tab == "history" then
            renderHistory(ledger.historyPage, record)
        elseif tab == "notes" then
            local editor = noteEditor()
            if editor.identity ~= record then
                editor.identity, editor.noteOffset = record, 0
                selectNote(editor, record.notes[#record.notes])
            else editor:RefreshList() end
            editor:Show()
        end
    end
    ledger.detailText:SetText(table.concat(lines, "\n"))
    ledger.detailText:SetSpacing(GL.Settings().compactMode and 2 or 4)
    ledger.detailBody:SetHeight(math.max(ledger.detailScroll:GetHeight(), ledger.detailText:GetStringHeight() + 12))
    ledger.detailScroll:SetVerticalScroll(math.min(ledger.detailScroll:GetVerticalScroll(), math.max(0, ledger.detailBody:GetHeight() - ledger.detailScroll:GetHeight())))
end

local function enableRecognition()
    if GL.Safe(InCombatLockdown) then GL.Print(L("Active le repérage hors combat.")) return end
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
    GL.Print(ready and L("Repérage activé : barres de noms, icônes et couleurs. Ennemi = rouge, méfiance = orange.")
        or L("Icônes et couleurs activées, mais le jeu n'a pas confirmé toutes les barres de noms. Vérifie les réglages d'affichage."))
end

local function settingText(page, text, x, y, width, size, color)
    local region = label(page, text, size and size >= 16 and "large" or nil, x, -y, width)
    if size then journalFont(region, size >= 16 and "GameFontNormalLarge" or "GameFontHighlight", size) end
    region:SetTextColor(unpack(color or theme.ink))
    return region
end

local function delayText(seconds)
    local minutes, tail = math.floor(seconds / 60), math.floor(seconds % 60)
    if minutes == 0 then return tail .. " s" end
    return minutes .. " min" .. (tail ~= 0 and (" " .. tail .. " s") or "")
end

showSettings = function()
    if not settingsWindow then
        local f = bookWindow("GrudgeLedgerSettings", "Grudge Ledger")
        settingsWindow = f
        bookNavigation(f, "settings")
        settingText(f, L("Réglages"), 40, 163, 255, 24, theme.paper)
        f.tabs, f.pages, f.checks, f.sliders, f.previewRows = {}, {}, {}, {}, {}
        local categories = {
            {"appearance", L("Apparence"), L("Apparence et lisibilité")},
            {"alerts", L("Alertes"), L("Alertes de proximité")},
            {"relations", L("Relations et PvP"), L("Ce que votre livre retient")},
            {"shortcuts", L("Raccourcis"), L("Vos gestes à portée de main")},
            {"data", L("Données et diagnostic"), L("Votre livre personnel")},
        }
        function f:SelectCategory(key)
            self.category = self.pages[key] and key or "appearance"
            if self.clearAction then self.clearAction.armed = false self.clearAction:SetText(L("Effacer les traces…")) end
            for name, page in pairs(self.pages) do
                showIf(page, name == self.category)
                UI.selectButton(self.tabs[name], name == self.category)
            end
        end
        for i, entry in ipairs(categories) do
            local key = entry[1]
            local tab = button(f, entry[2], 36, -221 - (i - 1) * 62, 263, function() f:SelectCategory(key) end, true)
            tab:SetHeight(41) tab.caption:ClearAllPoints() tab.caption:SetPoint("CENTER") tab.caption:SetHeight(29)
            journalFont(tab.caption, "GameFontNormalLarge", 16)
            f.tabs[key] = tab
            local page = CreateFrame("Frame", nil, f)
            page:SetAllPoints(f) f.pages[key] = page
            settingText(page, entry[3], 356, 160, 554, 24)
        end
        local function check(category, key, text, y, width, x)
            local control = CreateFrame("CheckButton", nil, f.pages[category], "UICheckButtonTemplate")
            control:SetPoint("TOPLEFT", (x or 356) - 3, -y) control:SetSize(26, 26)
            control:SetHitRectInsets(0, -(width or 522) + 28, 0, 0)
            settingText(control, text, 32, 4, (width or 522) - 33, 14)
            control:SetScript("OnClick", function(self) GL.SetSetting(key, self:GetChecked() and true or false) end)
            f.checks[key] = control
            return control
        end
        local function range(page, key, title, x, y, width, low, high, step, format)
            local slider = CreateFrame("Slider", nil, page)
            slider:SetPoint("TOPLEFT", x + 32, -(y + 24))
            slider:SetSize(width - 64, 26)
            slider:SetMinMaxValues(low, high) slider:SetValueStep(step)
            GL.Safe(slider.SetOrientation, slider, "HORIZONTAL")
            GL.Safe(slider.SetObeyStepOnDrag, slider, true)
            local track = surface(slider, theme.gold)
            track:ClearAllPoints() track:SetPoint("LEFT") track:SetPoint("RIGHT") track:SetHeight(4)
            local thumb = slider:CreateTexture(nil, "OVERLAY")
            thumb:SetSize(9, 17) thumb:SetColorTexture(unpack(theme.red))
            if slider.SetThumbTexture then slider:SetThumbTexture(thumb) end
            local valueText = settingText(page, "", x, y, width, 14)
            local function draw(value)
                if not slider.SetThumbTexture then
                    thumb:ClearAllPoints()
                    thumb:SetPoint("CENTER", slider, "LEFT", 4.5 + (slider:GetWidth() - 9) * (value-low)/(high-low), 0)
                end
                valueText:SetText(title .. "  " .. format(value))
            end
            local function commit(value)
                value = math.max(low, math.min(high, value))
                if GL.Settings()[key] ~= value then GL.SetSetting(key, value) end
            end
            slider:SetScript("OnValueChanged", function(_, value)
                draw(value)
                if key == "iconSize" then f:DrawMarkers(value) end
            end)
            slider:SetScript("OnMouseUp", function(self) commit(self:GetValue()) end)
            local minus = button(page, "−", x, -y - 24, 27, function() commit(GL.Settings()[key] - step) end, nil, true)
            local plus = button(page, "+", x + width - 27, -y - 24, 27, function() commit(GL.Settings()[key] + step) end, nil, true)
            function slider:Sync(value)
                self:SetValue(value) draw(value)
                minus:SetEnabled(value > low) plus:SetEnabled(value < high)
            end
            f.sliders[key] = slider
        end
        local p = f.pages.appearance
        settingText(p, L("Police de lecture"), 356, 209, 266, 16)
        f.grimoire = button(p, L("Grimoire · PT Serif"), 356, -243, 145, function() GL.SetSetting("readableFont", false) end, true, true)
        f.classic = button(p, L("Classique"), 509, -243, 127, function() GL.SetSetting("readableFont", true) end, true, true)
        check("appearance", "compactMode", L("Espacement compact"), 282, 266)
        f.readingLabel = settingText(p, "", 356, 326, 142, 13)
        button(p, "−", 500, -317, 29, function() GL.SetSetting("readingScale", (GL.Settings().readingScale or 1) - 0.05) end, nil, true)
        button(p, "+", 535, -317, 29, function() GL.SetSetting("readingScale", (GL.Settings().readingScale or 1) + 0.05) end, nil, true)
        button(p, "100 %", 569, -317, 68, function() GL.SetSetting("readingScale", 1) end, nil, true)
        check("appearance", "markers", L("Icônes près des noms"), 368, 272)
        check("appearance", "nameColor", L("Colorer aussi le nom"), 402, 272)
        check("appearance", "chatBadges", L("Marquer les contacts dans le chat"), 482, 272, 640)
        range(p, "iconSize", L("Taille des icônes"), 356, 457, 258, 12, 40, 1, function(n) return math.floor(n + .5) .. " px" end)
        settingText(p, L("Aperçu des marqueurs"), 640, 213, 261, 17)
        for i, data in ipairs({{"friend", L("Oriane · Ami")}, {"warning", L("Hélène · Méfiance")}, {"enemy", L("Bastian · Ennemi")}, {"neutral", L("Neutre")}}) do
            local y = 256 + (i-1)*52
            local icon = bookIcon(p, 644, y, 20, media .. relationIcons[data[1]])
            local name = settingText(p, data[2], 697, y+4, 205, 15)
            f.previewRows[data[1]] = {icon=icon, name=name}
        end
        function f:DrawMarkers(size)
            for key, row in pairs(self.previewRows) do
                row.icon:SetSize(size, size)
                showIf(row.icon, GL.Settings().markers)
                row.name:SetTextColor(unpack(GL.Settings().markers and GL.Settings().nameColor and key ~= "neutral" and inkColors[key] or theme.ink))
            end
        end
        f.plateStatus = settingText(p, "", 356, 548, 549, 14)
        function f:UpdatePlateStatus()
            local function status(key)
                local value = GL.Clean(GL.Safe((C_CVar and C_CVar.GetCVar) or GetCVar, key), "string")
                return value == "1" and L("activées") or value == "0" and L("désactivées") or L("inconnues")
            end
            self.plateStatus:SetText(L("Barres alliées : %s · Ennemies : %s"):format(status("nameplateShowFriendlyPlayers"), status("nameplateShowEnemies")))
        end
        button(p, L("Activer le repérage"), 356, -586, 222, enableRecognition, nil, true)
        settingText(p, L("Le repérage utilise les barres de nom compatibles."), 590, 586, 315, 13, theme.inkMuted)
        check("appearance", "compactTooltips", L("Infobulle compacte (Maj pour les détails)"), 626)
        p = f.pages.alerts
        check("alerts", "friendAlerts", L("Signaler un ami"), 217, 268)
        check("alerts", "enemyAlerts", L("Signaler une menace"), 251, 268)
        check("alerts", "sounds", L("Jouer un son"), 285, 268)
        check("alerts", "indirectAlerts", L("Signaux indirects de menace"), 318, 268)
        range(p, "alertCooldown", L("Délai des menaces"), 356, 350, 261, 15, 3600, 15, delayText)
        settingText(p, L("Tester au-dessus du chat"), 638, 213, 275, 17)
        for i, entry in ipairs({{"enemy", L("Aperçu d’une menace")}, {"friend", L("Aperçu d’un ami")}}) do
            local relation, y = entry[1], 254 + (i-1)*67
            bookIcon(p, 641, y, 34, media .. relationIcons[relation])
            local b = button(p, entry[2], 688, -y-3, 219, function()
                if not GL.Display or not GL.Display.PreviewAlert then
                    f.testStatus:SetText(L("L’aperçu est indisponible."))
                elseif not GL.Display.PreviewAlert(relation) then
                    f.testStatus:SetText(L("Une alerte réelle est déjà affichée."))
                else f.testStatus:SetText("") end
            end, nil, true)
            if relation == "enemy" then f.testEnemy = b else f.testFriend = b end
        end
        f.testStatus = settingText(p, "", 638, 396, 269, 13, theme.inkMuted)
        settingText(p, L("Un signal indirect indique une voix entendue ou la cible d’un équipier proche. Les amis du groupe restent silencieux ; les autres amis sont signalés après 10 min d’absence."), 356, 439, 547, 13)
        check("alerts", "partyWarnings", L("Prévenir mon groupe d’un ancien agresseur"), 534)
        settingText(p, L("Petit groupe en monde ouvert ou donjon. Un message au plus par minute et par personne toutes les 30 minutes."), 356, 582, 547, 13, theme.inkMuted)
        p = f.pages.relations
        check("relations", "pvpTracking", L("Enregistrer le PvP en monde ouvert"), 217)
        check("relations", "socialTracking", L("Noter mes gestes envers les joueurs"), 257)
        check("relations", "groupTracking", L("Compter les groupes avec mes contacts"), 297)
        check("relations", "tradeTracking", L("Consigner les échanges réussis avec mes contacts"), 337)
        settingText(p, L("Comment évolue une rancune ?"), 356, 388, 544, 18)
        for i, rule in ipairs({{L("Il vous tue"),"−10"}, {L("Il vous agresse"),"−1"}, {L("Vous le vainquez"),"+1"}}) do
            local x = 358+(i-1)*183
            settingText(p, rule[1], x, 432, 178, 15)
            settingText(p, rule[2], x, 460, 170, 19)
        end
        settingText(p, L("Les victoires compensent la dette de PvP. Seul un avis positif peut créer une amitié."), 356, 507, 548, 14)
        settingText(p, L("Champs de bataille et arènes"), 356, 563, 548, 17)
        settingText(p, L("Enregistrement et alertes en pause. Vos notes et vos choix manuels restent accessibles et prioritaires."), 356, 604, 548, 13, theme.inkMuted)
        p = f.pages.shortcuts
        check("shortcuts", "quickGestures", L("Afficher les boutons bisou et crachat"), 219)
        for i, entry in ipairs({{media.."GestureKiss", L("Envoyer un baiser · +1")}, {"Interface\\Icons\\Spell_Nature_CorrosiveBreath", L("Cracher · −1")}}) do
            local x = 358 + (i-1)*280
            bookIcon(p, x+6, 284, 64, entry[1])
            settingText(p, entry[2], x, 362, 260, 16)
        end
        settingText(p, L("Sélectionnez d’abord un joueur. Les deux gestes utilisent votre cible actuelle."), 356, 419, 547, 15)
        button(p, L("Replacer les boutons"), 356, -494, 245, function() if GL.ResetGesturePosition then GL.ResetGesturePosition() end end, nil, true)
        settingText(p, L("Ctrl + glisser pour les déplacer. Par défaut, ils se trouvent au-dessus du chat."), 616, 487, 288, 13)
        settingText(p, L("Glissez le livre autour de la minimap. Clic gauche : Journal. Clic droit : Réglages."), 356, 564, 544, 14)
        settingText(p, L("Commandes : /gl · /gl note · /gl + · /gl -"), 356, 632, 546, 13, theme.inkMuted)
        p = f.pages.data
        settingText(p, L("Vos rencontres et vos notes sont enregistrées localement, dans les données de votre compte."), 356, 213, 548, 14)
        check("data", "detectionLog", L("Conserver les traces de détection (200 lignes)"), 279)
        settingText(p, L("Rapport technique anonyme"), 356, 344, 258, 16)
        settingText(p, L("Version, API disponibles et réglages."), 356, 389, 258, 13, theme.inkMuted)
        settingText(p, L("Journal des détections"), 644, 344, 264, 16)
        settingText(p, L("Les traces privées peuvent contenir des noms."), 644, 389, 264, 13, theme.inkMuted)
        f.report = button(p, L("Afficher le rapport"), 356, -437, 253, function() showDiagnostic(false) end, nil, true)
        f.traces = button(p, L("Consulter les traces"), 644, -437, 260, function() showDiagnostic(true) end, nil, true)
        settingText(p, L("Version de l’addon : %s"):format(tostring(GL.version)), 356, 491, 548, 13)
        f.guide = button(p, L("Revoir les premiers pas"), 356, -530, 253, function() GL.ShowGuide() end, nil, true)
        f.clearAction = button(p, L("Effacer les traces…"), 644, -530, 260, function(self)
            if self.armed then
                GL.ClearDetectionLog() self.armed = false self:SetText(L("Effacer les traces…"))
            else self.armed = true self:SetText(L("Confirmer l’effacement")) end
        end, nil, true)
        f.experimental = button(p, L("Outils expérimentaux"), 356, -596, 253, function()
            showIf(f.experimentalText, not f.experimentalText:IsShown())
        end, nil, true)
        f.experimentalText = settingText(p, L("Radar druide en recherche. L’essai manuel reste accessible dans le diagnostic."), 644, 591, 262, 13, theme.inkMuted)
        f.experimentalText:Hide()
        function f:SyncControls()
            local settings = GL.Settings()
            for key, c in pairs(self.checks) do c:SetChecked(settings[key]) end
            self.readingLabel:SetText(L("Lecture : %d %%"):format(math.floor(settings.readingScale*100 + .5)))
            for key, slider in pairs(self.sliders) do slider:Sync(settings[key]) end
            self:DrawMarkers(settings.iconSize)
            UI.selectButton(self.classic, settings.readableFont)
            UI.selectButton(self.grimoire, not settings.readableFont)
            self:UpdatePlateStatus()
        end
    end
    settingsWindow:SyncControls()
    showBook(settingsWindow)
    settingsWindow:SelectCategory(settingsWindow.category)
end

function GL.ShowGuide()
    if not GL.db then return end
    if not guideWindow then
        local f = bookWindow("GrudgeLedgerGuide", "Grudge Ledger")
        guideWindow = f
        bookNavigation(f, "ledger")
        -- Reuse the book's parchment panel, including its painted edge, across both columns.
        local sheet = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        sheet:SetPoint("TOPLEFT", 21, -145) sheet:SetSize(917, 525)
        sheet:SetTexture(media .. "JournalBookSurface")
        sheet:SetTexCoord(345/960, 938/960, 145/700, 670/700)
        bookIcon(f, 114, 313, 154, GL.icon)
        local heading = settingText(f, L("Votre livre commence ici"), 44, 178, 872, 28)
        heading:SetJustifyH("CENTER")
        settingText(f, L("1. Sélectionnez un joueur"), 344, 260, 540, 20)
        settingText(f, L("Cliquez sur son personnage ou sur son portrait."), 344, 299, 535, 15)
        settingText(f, L("2. Donnez votre avis"), 344, 355, 540, 20)
        bookIcon(f, 345, 395, 44, media .. "GestureKiss")
        settingText(f, L("Bisou  +1"), 402, 408, 159, 17)
        bookIcon(f, 584, 395, 44, "Interface\\Icons\\Spell_Nature_CorrosiveBreath")
        settingText(f, L("Crachat  −1"), 642, 408, 226, 17)
        settingText(f, L("Le clic droit sur le portrait permet aussi de choisir un statut."), 344, 453, 535, 14)
        settingText(f, L("3. Retrouvez vos rencontres"), 344, 502, 541, 20)
        settingText(f, L("Le Journal rassemble vos avis, vos notes et votre histoire. Partager un groupe ne crée pas d’amitié."), 344, 544, 535, 14)
        f.openJournal = button(f, L("Ouvrir le Journal"), 306, -602, 348, function() GL.ShowLedger() end, nil, true)
        UI.selectButton(f.openJournal, true)
        local revisit = settingText(f, L("Retrouvez ce guide dans les réglages, sous Données et diagnostic."), 62, 643, 836, 12, theme.inkMuted)
        revisit:SetJustifyH("CENTER")
    end
    if not GL.Settings().guideSeen then GL.SetSetting("guideSeen", true) end
    -- Keep the calling page underneath so closing this guide returns to it.
    guideWindow:Show() guideWindow:Raise()
end

local function buildLedger()
    if ledger then return end
    local f = bookWindow("GrudgeLedgerWindow", "Grudge Ledger")
    ledger = f
    bookNavigation(f, "ledger")
    f.detailTab, f.query = "summary", ""
    f.addTarget = button(f, L("Ajouter la cible"), 195, -155, 112, function()
        local identity = GL.Identity("target")
        if not identity then GL.Print(L("Sélectionne un joueur pour ouvrir sa fiche.")) return end
        local record = GL.Remember(identity)
        if record then
            if GL.Safe(UnitIsVisible, "target") == true then GL.RecordSeen(identity, true) end
            GL.ShowLedger(record.key)
        end
    end, nil, false)
    f.search = CreateFrame("EditBox", nil, f)
    f.search:SetPoint("TOPLEFT", 36, -155)
    f.search:SetSize(154, 26)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(100)
    styleInput(f.search, false, false)
    f.search:SetTextInsets(28, 6, 3, 3)
    local function applySearch() f.query = f.search:GetText():match("^%s*(.-)%s*$") offset = 0 f.search:ClearFocus() refresh() end
    f.search:SetScript("OnEnterPressed", applySearch)
    f.searchButton = CreateFrame("Button", nil, f.search)
    f.searchButton:SetPoint("LEFT", 3, 0) f.searchButton:SetSize(23, 23)
    f.searchButton:SetNormalTexture("Interface\\Common\\UI-Searchbox-Icon")
    f.searchButton:SetScript("OnClick", applySearch)
    f.searchButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("Nom, guilde, note…")) GameTooltip:Show()
    end)
    f.searchButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.searchHint = label(f.search, L("Rechercher…"), nil, 28, -4, 120)
    f.searchHint:SetHeight(19)
    GL.Safe(f.searchHint.SetJustifyV, f.searchHint, "MIDDLE")
    GL.Safe(f.searchHint.SetWordWrap, f.searchHint, false)
    f.searchHint:SetTextColor(unpack(theme.muted))
    f.search:SetScript("OnTextChanged", function(self)
        if self:GetText():find("%S") then f.searchHint:Hide() else
            f.searchHint:Show()
            if f.query and f.query ~= "" then f.query, offset = "", 0 refresh() end
        end
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
    f.relationFilter, f.filters = filterMenu(36, { { L("Tous les avis"), "all" }, { L("Amis"), "friend" }, { L("Méfiance"), "warning" },
        { L("Ennemis"), "enemy" }, { L("Neutres"), "neutral" } }, function(value) filter = value end)
    f.factionFilter, f.factions = filterMenu(173, { { L("Toutes factions"), "all" }, { L("Alliance"), "Alliance" },
        { L("Horde"), "Horde" }, { L("Inconnue"), "unknown" } }, function(value) factionFilter = value end)
    f.rows = {}
    f.sort = button(f, L("Dernière interaction"), 149, -229, 158, function()
        if not f.query or f.query == "" then return end
        for i, choice in ipairs(sortChoices) do
            if choice[1] == listSort then listSort = sortChoices[i % #sortChoices + 1][1] break end
        end
        offset = 0
        GL.SetSetting("listSort", listSort)
        refresh()
    end, nil, false)
    f.notesOnly = button(f, L("Avec notes"), 36, -229, 107, function() notesOnly, offset = not notesOnly, 0 refresh() end, true, false)
    f.detail = button(f, L("Détail : Identité"), 36, -262, 177, function()
        for i, choice in ipairs(detailChoices) do
            if choice[1] == listDetail then listDetail = detailChoices[i % #detailChoices + 1][1] break end
        end
        GL.SetSetting("listDetail", listDetail)
        refresh()
    end, nil, false)
    f.reset = button(f, L("Effacer"), 218, -262, 89, function()
        filter, factionFilter, notesOnly, offset, f.query = "all", "all", false, 0, ""
        f.search:SetText("") refresh()
    end)
    for i = 1, 9 do
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
            GameTooltip:AddLine(self.portraitUnit and L("Portrait actuel du joueur") or self.archivedPortrait
                and L("Portrait enregistré de l’Armurerie") or L("Icône générique"), 0.82, 0.78, 0.69)
            if record.guild then GameTooltip:AddLine(plain(record.guild)) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = row
    end
    f.previous = button(f, "‹", 36, -634, 32, function() offset = math.max(0, offset - f.pageSize) refresh() end, nil, false)
    f.next = button(f, "›", 275, -634, 32, function() offset = offset + f.pageSize refresh() end, nil, false)
    f.total = label(f, "", nil, 72, -640, 199)
    f.total:SetHeight(20) f.total:SetJustifyH("CENTER")
    journalFont(f.total, "GameFontHighlightSmall", 12)
    GL.Safe(f.total.SetWordWrap, f.total, false)
    f.total:SetTextColor(unpack(theme.muted))
    f.empty = label(f, "", nil, 45, -321, 249)
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
    f.classIcon:SetPoint("TOPLEFT", 402, -200) f.classIcon:SetSize(17, 17)
    f.detailFaction = bookIcon(f, 426, 193, 16)
    f.detailIdentity = label(f, "", nil, 447, -192, 300)
    journalFont(f.detailIdentity, "GameFontHighlightSmall", 13)
    f.detailIdentity:SetTextColor(unpack(theme.inkMuted))
    f.detailIdentity:SetHeight(20)
    GL.Safe(f.detailIdentity.SetWordWrap, f.detailIdentity, false)
    f.detailGuild = label(f, "", nil, 426, -215, 318)
    f.detailGuild:SetTextColor(unpack(theme.ink)) f.detailGuild:SetHeight(22)
    GL.Safe(f.detailGuild.SetWordWrap, f.detailGuild, false)
    f.detailSource = label(f, "", nil, 753, -196, 166)
    journalFont(f.detailSource, "GameFontHighlight", 13, true)
    f.detailSource:SetJustifyH("RIGHT") f.detailSource:SetHeight(39) f.detailSource:SetTextColor(unpack(theme.inkMuted))
    f.actions, f.reactions = {}, {}
    for _, option in ipairs({ { L("Ami"), "friend", 356, 74 }, { L("Méfiance"), "warning", 434, 100 }, { L("Ennemi"), "enemy", 538, 89 }, { L("Automatique"), "neutral", 631, 123 } }) do
        local value = option[2]
        local control = button(f, option[1], option[3], -592, option[4], function()
            local record = currentRecord()
            if record then GL.SetReaction(record, value) end
        end, true, true)
        if value ~= "neutral" then
            local icon = control:CreateTexture(nil, "OVERLAY")
            icon:SetTexture(media .. relationIcons[value]) icon:SetSize(16, 16) icon:SetPoint("LEFT", 7, 0)
            control.caption:ClearAllPoints() control.caption:SetPoint("TOPLEFT", 25, -5) control.caption:SetWidth(option[4] - 29)
        end
        f.actions[#f.actions + 1], f.reactions[value] = control, control
    end
    f.actions[#f.actions + 1] = button(f, L("Ajouter une note"), 758, -592, 156, function()
        local record = currentRecord()
        if record then GL.EditNote(record) end
    end, nil, true)
    f.toolsMenu = CreateFrame("Frame", nil, f)
    f.toolsMenu:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 734, -624) f.toolsMenu:SetSize(180, 148)
    f.toolsMenu:SetFrameStrata("FULLSCREEN_DIALOG") f.toolsMenu:SetToplevel(true) f.toolsMenu:EnableMouse(true)
    surface(f.toolsMenu, theme.gold) surface(f.toolsMenu, theme.panel, 1)
    f.tools = button(f, L("Autres actions"), 734, -634, 180, function() toggleMenu(f.toolsMenu) end, nil, true)
    for i, option in ipairs({ { L("Avis positif (+1)"), 1 }, { L("Avis négatif (-1)"), -1 } }) do
        local delta = option[2]
        f.actions[#f.actions + 1] = button(f.toolsMenu, option[1], 3, -3 - (i - 1) * 29, 174, function()
            local record = currentRecord()
            if record then GL.AdjustReputation(record, delta, "Avis personnel", "manual") end
            f.toolsMenu:Hide()
        end)
    end
    f.guildButton = button(f.toolsMenu, L("Guilde"), 3, -61, 174, function()
        local record = currentRecord()
        f.toolsMenu:Hide()
        if record and record.guild then GL.ShowGuilds(record) end
    end)
    f.actions[#f.actions + 1] = button(f.toolsMenu, L("Corriger le PvP"), 3, -90, 174, function()
        f.toolsMenu:Hide()
        f.detailTab, f.historyPage.kind, f.historyPage.offset = "history", "pvp", 0
        renderDetail()
    end)
    local deleteDialog = "GRUDGE_LEDGER_DELETE_PROFILE"
    StaticPopupDialogs[deleteDialog] = {
        text = L("Supprimer définitivement la fiche de %s ? Ses notes et son historique seront effacés et ses événements retirés des statistiques du compte."),
        button1 = L("Supprimer"), button2 = L("Annuler"), timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, record)
            if currentRecord() ~= record or not GL.DeleteProfile(record) then
                GL.Print(L("La fiche a changé. Rouvrez-la pour la supprimer."))
            end
        end,
    }
    f:HookScript("OnHide", function() StaticPopup_Hide(deleteDialog) end)
    f.actions[#f.actions + 1] = button(f.toolsMenu, L("Supprimer la fiche…"), 3, -119, 174, function()
        closeMenu()
        local record = currentRecord()
        if record then StaticPopup_Show(deleteDialog, plain(record.fullName or record.key), nil, record) end
    end)
    f.toolsMenu:Hide()
    f.detailTabs = {}
    for i, entry in ipairs({ { "summary", L("Synthèse") }, { "history", L("Histoire") }, { "notes", L("Notes") }, { "matchup", L("Face-à-face") } }) do
        local key = entry[1]
        f.detailTabs[key] = button(f, entry[2], 356 + (i - 1) * 115, -242, 110, function()
            f.detailTab = key f.detailScroll:SetVerticalScroll(0) renderDetail()
        end, true, true)
    end
    f.counters = CreateFrame("Frame", nil, f)
    f.counters:SetPoint("TOPLEFT", 356, -279) f.counters:SetSize(558, 160)
    f.metrics = {}
    for i, entry in ipairs({ { "deaths", L("Vous a tué") }, { "kills", L("Vous l’avez vaincu") } }) do
        local card = CreateFrame("Frame", nil, f.counters)
        card:SetPoint("TOPLEFT", (i - 1) * 281, 0) card:SetSize(274, 85)
        parchmentPanel(card)
        card.caption = label(card, entry[2], nil, 6, -6, 262)
        journalFont(card.caption, "GameFontNormalLarge", 16)
        card.caption:SetTextColor(unpack(theme.ink)) card.caption:SetHeight(23) card.caption:SetJustifyH("CENTER")
        card.value = label(card, "0", "large", 6, -29, 262)
        journalFont(card.value, "GameFontNormalLarge", 28)
        card.value:SetTextColor(unpack(theme.ink)) card.value:SetHeight(34) card.value:SetJustifyH("CENTER")
        f.metrics[entry[1]] = card
    end
    f.balancePanel = CreateFrame("Frame", nil, f.counters) f.balancePanel:SetAllPoints()
    local balanceCaption = label(f.balancePanel, L("Solde automatique"), nil, 32, -98, 238)
    journalFont(balanceCaption, "GameFontNormalLarge", 20) balanceCaption:SetTextColor(unpack(theme.ink)) balanceCaption:SetJustifyH("RIGHT")
    f.balance = label(f.balancePanel, "", nil, 286, -89, 160)
    journalFont(f.balance, "GameFontNormalLarge", 31) f.balance:SetTextColor(unpack(inkColors.enemy)) f.balance:SetHeight(44)
    f.formula = label(f.balancePanel, "", nil, 6, -128, 546)
    f.formula:SetTextColor(unpack(theme.ink)) f.formula:SetJustifyH("CENTER") f.formula:SetHeight(22)
    f.scoreContext = label(f.balancePanel, "", nil, 6, -151, 546)
    journalFont(f.scoreContext, "GameFontHighlightSmall", 11, true) f.scoreContext:SetTextColor(unpack(theme.inkMuted)) f.scoreContext:SetJustifyH("CENTER") f.scoreContext:SetHeight(17)
    f.detailScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.detailScroll:SetPoint("TOPLEFT", 356, -379)
    f.detailScroll:SetSize(544, 190)
    f.matchupHistory = button(f, L("Voir les combats dans l’histoire"), 356, -619, 293, function()
        f.detailTab, f.historyPage.kind, f.historyPage.offset = "history", "matchup", 0
        renderDetail()
    end, nil, true)
    local p = CreateFrame("Frame", nil, f)
    f.historyPage = p
    p:SetPoint("TOPLEFT", 353, -278) p:SetSize(561, 382)
    p.heading = label(p, "", "large", 2, -4, 325) p.heading:SetTextColor(unpack(theme.ink))
    p.heading:SetHeight(32) GL.Safe(p.heading.SetWordWrap, p.heading, false)
    p.kind, p.offset, p.rows, p.options = "all", 0, {}, {}
    p.menu = CreateFrame("Frame", nil, p)
    p.menu:SetPoint("TOPLEFT", 348, -30) p.menu:SetSize(208, #historyKinds * 28 + 5)
    p.menu:SetFrameStrata("FULLSCREEN_DIALOG") p.menu:EnableMouse(true) p.menu:SetToplevel(true)
    surface(p.menu, theme.gold) surface(p.menu, theme.panel, 1) p.menu:Hide()
    p.filter = button(p, L("Tous les événements"), 348, -1, 208, function() toggleMenu(p.menu) end, nil, true)
    for i, entry in ipairs(historyKinds) do
        local key = entry[1]
        p.options[key] = button(p.menu, entry[2], 2, -2 - (i-1)*28, 204, function()
            closeMenu() p.kind, p.offset = key, 0 renderDetail()
        end, true)
    end
    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, p)
        row:SetPoint("TOPLEFT", 2, -44 - (i-1)*94) row:SetSize(552, 88)
        surface(row, {0.53,0.37,0.19,0.42}) surface(row, theme.paper, 1, 1):SetAlpha(0.85)
        row.icon = row:CreateTexture(nil, "ARTWORK") row.icon:SetPoint("TOPLEFT", 6, -18) row.icon:SetSize(40, 40)
        row.date = label(row, "", nil, 55, -5, 483) row.date:SetHeight(22) row.date:SetTextColor(unpack(theme.inkMuted))
        row.title = label(row, "", nil, 55, -29, 350) journalFont(row.title, "GameFontNormalLarge", 15)
        row.title:SetHeight(24) row.title:SetTextColor(unpack(theme.ink))
        row.hint = label(row, "", nil, 55, -57, 359) row.hint:SetHeight(25) row.hint:SetTextColor(unpack(theme.inkMuted))
        row.badge = label(row, "", nil, 411, -29, 133) row.badge:SetJustifyH("RIGHT") row.badge:SetHeight(25)
        for _, field in ipairs({row.date, row.title, row.hint,row.badge}) do GL.Safe(field.SetWordWrap, field, false) end
        row.details = button(row, L("Détails"), 433, -56, 111, function() inspectEvent(row.record, row.event) end, nil, true)
        p.rows[i] = row
    end
    p.empty = label(p, "", nil, 14, -104, 512) p.empty:SetTextColor(unpack(theme.inkMuted))
    p.total = label(p, "", nil, 212, -343, 134) p.total:SetJustifyH("CENTER") p.total:SetTextColor(unpack(theme.ink))
    p.prev = button(p, L("Précédent"), 61, -337, 124, function() p.offset = math.max(0, p.offset - #p.rows) renderDetail() end, nil, true)
    p.next = button(p, L("Suivant"), 373, -337, 124, function() p.offset = p.offset + #p.rows renderDetail() end, nil, true)
    p:HookScript("OnHide", function() p.menu:Hide() end)
    f.detailBody = CreateFrame("Frame", nil, f.detailScroll)
    f.detailBody:SetSize(539, 210)
    f.detailText = label(f.detailBody, "", nil, 0, 0, 529)
    journalFont(f.detailText, "QuestFont_Large", 15)
    f.detailText:SetTextColor(unpack(theme.ink))
    f.detailText:SetSpacing(4)
    f.detailScroll:SetScrollChild(f.detailBody)
    local hint = label(f, L("Votre choix personnel reste prioritaire."), nil, 356, -640, 360)
    f.hint = hint
    journalFont(hint, "GameFontHighlightSmall", 12, true)
    hint:SetHeight(20)
    hint:SetTextColor(unpack(theme.inkMuted))
    local first = CreateFrame("Frame", nil, f)
    f.emptyPage = first
    first:SetPoint("TOPLEFT", 357, -151)
    first:SetSize(555, 480)
    local badge = first:CreateTexture(nil, "ARTWORK")
    badge:SetSize(82, 82) badge:SetPoint("TOP", 0, -69) badge:SetTexture(GL.icon)
    first.title = label(first, "", "large", 12, -176, 531)
    first.title:SetTextColor(unpack(theme.ink)) first.title:SetJustifyH("CENTER")
    journalFont(first.title, "GameFontNormalLarge", 23)
    first.body = label(first, "", nil, 65, -235, 425)
    first.body:SetJustifyH("CENTER") first.body:SetTextColor(unpack(theme.inkMuted))
    first.action = button(first, "", 176, -329, 202, function()
        local source = f.filtersActive and f.reset or f.addTarget
        source:GetScript("OnClick")(source)
    end, nil, true)
end

local function layoutIndex(f, compact)
    local pageSize = compact and 9 or 6
    if f.pageSize == pageSize then return end
    f.pageSize, offset = pageSize, 0
    for i, row in ipairs(f.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 32, -301 - (i - 1) * (compact and 36 or 53))
        row:SetHeight(compact and 34 or 51)
        row.name:ClearAllPoints() row.name:SetPoint("TOPLEFT", compact and 34 or 52, compact and -7 or -4)
        row.name:SetWidth(compact and 168 or 145)
        row.identity:SetWidth(198)
        row.relation:ClearAllPoints() row.relation:SetPoint("TOPLEFT", 215, compact and -8 or -6)
        row.relation:SetWidth(58)
        row.relationIcon:ClearAllPoints() row.relationIcon:SetPoint("TOPLEFT", compact and 6 or 200, -6)
        row.relationIcon:SetSize(compact and 22 or 16, compact and 22 or 16)
        for _, detail in ipairs({ row.raceIcon, row.classIcon, row.identity }) do
            if compact then detail:Hide() else detail:Show() end
        end
    end
end

refresh = function(focusSelected)
    if not ledger or not ledger:IsShown() or not GL.db then return end
    layoutIndex(ledger, GL.Settings().compactMode)
    local selected = currentRecord()
    selectedKey = selected and selected.key
    local searched = ledger.query ~= nil and ledger.query ~= ""
    listSort = searched and GL.Settings().listSort or "recent"
    listDetail = GL.Settings().listDetail or listDetail
    local records = GL.SearchPlayers({ query = ledger.query or "", relation = filter, faction = factionFilter,
        notesOnly = notesOnly, sort = listSort, selectedKey = selectedKey })
    local selectionIndex
    for index, record in ipairs(records) do
        if selectedKey == record.key then
            selectionIndex = index
            break
        end
    end
    offset = math.min(offset, math.max(0, math.floor((#records - 1) / ledger.pageSize) * ledger.pageSize))
    if focusSelected and selectionIndex then
        offset = math.floor((selectionIndex - 1) / ledger.pageSize) * ledger.pageSize
    elseif not selectionIndex or selectionIndex <= offset or selectionIndex > offset + ledger.pageSize then
        selectedKey = records[offset + 1] and records[offset + 1].key
        ledger.detailTab = "summary"
        ledger.detailScroll:SetVerticalScroll(0)
        ledger.toolsMenu:Hide()
    end
    for i, row in ipairs(ledger.rows) do
        local record = i <= ledger.pageSize and records[offset + i]
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
            if listDetail == "guild" then detail = record.guild or L("Guilde inconnue")
            elseif listDetail == "pvp" then
                local pvp = record.pvp or {}
                detail = counted(pvp.kills or 0, "victoire") .. " · " .. counted(pvp.deaths or 0, "mort")
            elseif listDetail == "notes" then
                local note = record.notes and record.notes[#record.notes]
                detail = note and note.text or L("Aucune note")
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
    ledger.filtersActive = (ledger.query or "") ~= "" or filter ~= "all" or factionFilter ~= "all" or notesOnly
    if #records == 0 then
        ledger.empty:SetText(ledger.filtersActive and L("Aucun résultat.") or L("Aucune fiche enregistrée."))
        ledger.empty:Show()
    else ledger.empty:Hide() end
    local blank = ledger.emptyPage
    if #records == 0 and ledger.filtersActive then
        blank.title:SetText(L("Aucun contact ne correspond"))
        blank.body:SetText(L("Élargissez votre recherche ou effacez les filtres pour retrouver toutes vos fiches."))
    else
        blank.title:SetText(L("Votre livre commence ici"))
        blank.body:SetText(L("Ciblez un joueur pour ouvrir sa première fiche. Vous pourrez y inscrire votre avis ou une note personnelle."))
    end
    blank.action:SetText(ledger.filtersActive and L("Effacer les filtres") or L("Ajouter la cible"))
    for value, control in pairs(ledger.filters) do
        UI.selectButton(control, value == filter)
    end
    for value, control in pairs(ledger.factions) do
        UI.selectButton(control, value == factionFilter)
    end
    ledger.relationFilter:SetText(filter == "all" and L("Tous les avis") or relationNames[filter])
    ledger.factionFilter:SetText(factionNames[factionFilter] or (factionFilter == "unknown" and L("Inconnue") or L("Toutes factions")))
    ledger.previous:SetEnabled(offset > 0)
    ledger.next:SetEnabled(offset + ledger.pageSize < #records)
    ledger.sort:SetEnabled(searched)
    for _, choice in ipairs(sortChoices) do if choice[1] == listSort then ledger.sort:SetText(choice[2]) end end
    for _, choice in ipairs(detailChoices) do if choice[1] == listDetail then ledger.detail:SetText(L("Détail : %s"):format(choice[2])) end end
    UI.selectButton(ledger.notesOnly, notesOnly)
    renderDetail()
end

function GL.ShowLedger(key)
    if not GL.db then return end
    local record = key and GL.Get(key)
    if key and not record then return end
    buildLedger()
    ledger.closeMenu()
    if statisticsWindow then statisticsWindow:Hide() end
    if journalWindow then journalWindow:Hide() end
    if key then
        selectedKey = record.key
        filter, factionFilter, offset, notesOnly = "all", "all", 0, false
        ledger.query, ledger.detailTab = "", "summary"
        ledger.historyPage.kind, ledger.historyPage.offset = "all", 0
        ledger.search:SetText("")
        ledger.detailScroll:SetVerticalScroll(0)
    end
    showBook(ledger)
    refresh(true)
    if not key and not GL.Settings().guideSeen then GL.ShowGuide() end
end

selectNote = function(f, note)
    local record = GL.Get(f.identity)
    if note then
        local index
        for i, item in ipairs(record and record.notes or {}) do if item == note then index = i break end end
        if not index then f.error:SetText(L("Cette note n’appartient plus à cette fiche.")) return end
        f.noteOffset = math.floor((#record.notes - index) / #f.rows) * #f.rows
    end
    f.selectedNote, f.confirmDelete = note, nil
    f.remove:SetText(L("Supprimer la note…")) f.remove:SetEnabled(note ~= nil)
    f.noteInfo:SetText(note and (L("Note du %s"):format(eventDate(note))) or L("Nouvelle note"))
    f.error:SetText("")
    f.loading = true
    f.edit:SetText(drafts[note or f.identity] or (note and note.text) or "")
    f.loading = false
    f.scroll:SetVerticalScroll(0)

    f:RefreshList()
end

noteEditor = function()
    if noteWindow then return noteWindow end
    local f = CreateFrame("Frame", "GrudgeLedgerNote", ledger)
    noteWindow, f.rows, f.noteOffset = f, {}, 0
    f:SetPoint("TOPLEFT", 353, -278) f:SetSize(560, 382)
    f.heading = label(f, L("Notes personnelles"), "large", 2, -4, 545) f.heading:SetTextColor(unpack(theme.ink))
    local privacy = label(f, L("Ces notes restent dans votre livre."), nil, 2, -32, 545) privacy:SetTextColor(unpack(theme.inkMuted))
    f.new = button(f, L("+ Nouvelle note"), 2, -68, 157, function() selectNote(f) f.edit:SetFocus() end, nil, true)
    for i=1,5 do
        local row = button(f, "", 2, -107 - (i-1)*35, 157, nil, true, true)
        row:SetScript("OnClick", function() if row.note then selectNote(f, row.note) end end)
        row:SetScript("OnEnter", function()
            if not row.note or not GameTooltip then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(eventDate(row.note))
            GameTooltip:AddLine(plain(row.note.text), 1, 0.92, 0.78, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = row
    end
    f.previous = button(f, "‹", 2, -287, 39, function() f.noteOffset = math.max(0,f.noteOffset-#f.rows) f:RefreshList() end, nil, true)
    f.next = button(f, "›", 120, -287, 39, function() f.noteOffset = f.noteOffset+#f.rows f:RefreshList() end, nil, true)
    f.total = label(f, "", nil, 42, -293, 76) f.total:SetTextColor(unpack(theme.ink)) f.total:SetJustifyH("CENTER")
    f.noteInfo = label(f, "", nil, 176, -70, 376)
    journalFont(f.noteInfo, "GameFontNormalLarge", 16) f.noteInfo:SetTextColor(unpack(theme.ink))
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll = scroll
    scroll:SetPoint("TOPLEFT", 176, -105) scroll:SetSize(354, 148)
    f.edit = CreateFrame("EditBox", nil, scroll)
    f.edit:SetMultiLine(true) f.edit:SetWidth(348) f.edit:SetHeight(148)
    f.edit:SetAutoFocus(false) f.edit:SetMaxLetters(2000)
    styleInput(f.edit, true, true)
    f.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    function f:Measure()
        local _, fontHeight = self.edit:GetFont()
        local height = math.max(scroll:GetHeight(), self.edit:GetNumLines() * (fontHeight+self.edit:GetSpacing())+8)
        self.edit:SetHeight(height)
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(),math.max(0,height-scroll:GetHeight())))
    end
    f.edit:SetScript("OnTextChanged", function(self)
        if f.identity and not f.loading then
            local original = f.selectedNote and f.selectedNote.text or ""
            drafts[f.selectedNote or f.identity] = self:GetText() ~= original and self:GetText() or nil
            f.confirmDelete = nil
            f.remove:SetText(L("Supprimer la note…"))
            f.error:SetText("")
            f.draft:SetText(drafts[f.selectedNote or f.identity] and L("Brouillon non enregistré") or "")
        end
        f:Measure()
    end)
    -- Cursor-follow scrolling follows Worth Remembering's multiline editor (Kyle, GPL-3.0).
    f.edit:SetScript("OnCursorChanged", function(self, _, y, _, height)
        y, height = GL.Clean(y,"number"), GL.Clean(height,"number")
        if not y or not height then return end
        local top = math.max(0,-y)
        local bottom = top + height
        if self:GetHeight() < bottom+4 then self:SetHeight(bottom+4) end
        local offset = scroll:GetVerticalScroll()
        if top < offset then scroll:SetVerticalScroll(top)
        elseif bottom > offset+scroll:GetHeight() then scroll:SetVerticalScroll(bottom-scroll:GetHeight()) end
    end)
    scroll:SetScrollChild(f.edit)
    f.draft = label(f, "", nil, 176, -267, 374) f.draft:SetTextColor(unpack(theme.inkMuted))
    f.save = button(f, L("Enregistrer"), 176, -291, 204, function()
        local id, note = f.identity, f.selectedNote
        local ok, err
        if note then ok, err = GL.UpdateNote(id, note, f.edit:GetText()) else ok, err = GL.AddNote(id, f.edit:GetText()) end
        if not ok then f.error:SetText(plain(L(err or "La note n’a pas pu être enregistrée."))) return end
        drafts[note or id] = nil
        local record = GL.Get(id)
        selectNote(f, note or record.notes[#record.notes])
        f.edit:ClearFocus() f.draft:SetText(L("Note enregistrée"))
    end, true, true)
    UI.selectButton(f.save, true)
    f.cancel = button(f, L("Annuler"), 390, -291, 160, function()
        drafts[f.selectedNote or f.identity] = nil
        selectNote(f,f.selectedNote) f.edit:ClearFocus()
    end, nil, true)
    f.remove = button(f, L("Supprimer la note…"), 2, -335, 157, function()
        local note = f.selectedNote
        if not note then return end
        if f.confirmDelete ~= note then
            f.confirmDelete = note f.remove:SetText(L("Confirmer ?"))
            f.error:SetText(L("Supprimer cette note définitivement ? Cliquez de nouveau pour confirmer."))
            return
        end
        local ok, err = GL.DeleteNote(f.identity, note)
        if not ok then f.error:SetText(plain(L(err))) return end
        drafts[note] = nil selectNote(f)
    end, nil, true)
    f.error = label(f,"",nil,176,-327,374) f.error:SetTextColor(unpack(inkColors.enemy)) f.error:SetHeight(50)
    function f:RefreshList()
        local record = GL.Get(self.identity)
        local notes = record and record.notes or {}
        local size, count = #self.rows, #notes
        self.noteOffset = math.max(0, math.min(self.noteOffset, math.floor(math.max(0,count-1)/size)*size))
        for i,row in ipairs(self.rows) do
            row.note = notes[count-self.noteOffset-i+1]
            if row.note then
                row:SetText((count-self.noteOffset-i+1) .. " · " .. (row.note.time and GL.Safe(date, "%d/%m %H:%M", row.note.time) or L("Date inconnue")))
                UI.selectButton(row,row.note == self.selectedNote)
                row:Show()
            else row:Hide() end
        end
        self.total:SetText(count == 0 and L("0 note") or (math.floor(self.noteOffset/size)+1).." / "..math.ceil(count/size))
        self.previous:SetEnabled(self.noteOffset>0) self.next:SetEnabled(self.noteOffset+size<count)
        self.draft:SetText(drafts[self.selectedNote or self.identity] and L("Brouillon non enregistré") or "")
    end
    f:HookScript("OnHide",function() f.edit:ClearFocus() f.confirmDelete = nil f.remove:SetText(L("Supprimer la note…")) end)
    f:Hide()
    return f
end

function GL.EditNote(identity, selectedNote)
    if not identity or not identity.key then return end
    local record = GL.Get(identity) or GL.Remember(identity)
    if not record then return end
    GL.ShowLedger(record.key)
    ledger.detailTab = "notes"
    renderDetail()
    selectNote(noteWindow, selectedNote)
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
        GameTooltip:AddLine(L("Clic : journal • Clic droit : réglages"), 1, 1, 1)
        GameTooltip:AddLine(L("Glisser : déplacer le bouton"), 0.7, 0.7, 0.7)
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

GL.On("CHANGED", function(record, reason)
    if reason == "deleted" then
        drafts[record] = nil
        for _, note in ipairs(record.notes) do drafts[note] = nil end
        if correctionWindow and correctionWindow.identity and correctionWindow.identity.key == record.key then correctionWindow:Hide() end
    end
    if ledger then ledger.historyPage.cache = nil end
    refresh(true)
end)
local sightingRefreshPending
GL.On("CONTACT_SEEN", function()
    if not ledger or not ledger:IsShown() or listSort ~= "recent" or sightingRefreshPending then return end
    if C_Timer and C_Timer.After then
        sightingRefreshPending = true
        C_Timer.After(0.2, function() sightingRefreshPending = nil refresh(true) end)
    else refresh(true) end
end)
GL.On("CHANGED", refreshGuilds)
GL.On("CHANGED", refreshCorrections)
GL.On("SETTINGS", function()
    for region, fonts in pairs(journalFonts) do journalFont(region, fonts[1], fonts[2], fonts[3]) end
    refresh(true)
    if ledger then renderDetail() end
    if settingsWindow then settingsWindow:SyncControls() end
    refreshStatistics() refreshJournal()
    if noteWindow then noteWindow:Measure() end
    if minimapButton and not minimapButton.dragging then positionMinimap() end
end)
-- Aliases are stable across locales so existing macros survive a language change.
local commandAliases = {
    summary = "bilan", resumen = "bilan", history = "chronique", historial = "chronique",
    guilds = "guildes", hermandades = "guildes", guild = "guilde", hermandad = "guilde",
    logs = "traces", registros = "traces", ajustes = "settings", opciones = "options",
    markers = "reperage", marcadores = "reperage", diagnostico = "debug", ["diagnóstico"] = "debug",
    estadisticas = "stats", ["estadísticas"] = "stats", nota = "note", guia = "guide", ["guía"] = "guide",
    friend = "ami", amigo = "ami", amiga = "ami", amie = "ami", enemy = "ennemi",
    enemigo = "ennemi", enemiga = "ennemi", ennemie = "ennemi", watch = "mefiance",
    vigilar = "mefiance", ["méfiance"] = "mefiance", neutral = "neutre", auto = "neutre",
    automatique = "neutre", automatic = "neutre", automatico = "neutre", ["automático"] = "neutre",
}
local reactionCommands = { ami = "friend", ennemi = "enemy", mefiance = "warning", neutre = "neutral" }
SLASH_GRUDGELEDGER1 = "/gl"
SLASH_GRUDGELEDGER2 = "/grudges"
SlashCmdList.GRUDGELEDGER = function(message)
    local command, reason = (GL.Clean(message, "string") or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):gsub("[A-Z]", string.lower)
    command = commandAliases[command] or command
    reason = reason or ""
    if command == "version" then GL.Print(L("Version chargée : %s"):format(GL.version))
    elseif command == "debug" then
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
        local relation = reason:gsub("[A-Z]", string.lower)
        local reaction = reactionCommands[commandAliases[relation] or relation]
        if not reaction then GL.Print(L("/gl guilde ami|ennemi|mefiance|neutre — utilise la guilde de ta cible.")) return end
        local identity = GL.Identity("target")
        if not identity or not identity.guild then GL.Print(L("Sélectionne un joueur dont la guilde est connue.")) return end
        GL.SetGuildReaction(identity, reaction)
    elseif command == "+" or command == "-" or reactionCommands[command] or command == "note" then
        local identity = GL.Identity("target")
        if not identity then GL.Print(L("Sélectionne un joueur pour cette action.")) return end
        if command == "+" or command == "-" then
            GL.AdjustReputation(identity, command == "+" and 1 or -1, reason ~= "" and reason or "Avis personnel", "manual")
        elseif command == "note" then
            if reason == "" then GL.EditNote(identity)
            else
                local ok, err = GL.AddNote(identity, reason)
                if not ok then GL.Print(L(err or "Impossible d'ajouter cette note.")) end
            end
        else
            GL.SetReaction(identity, reactionCommands[command])
        end
    elseif command == "" then
        if ledger and ledger:IsShown() then ledger:Hide() else GL.ShowLedger() end
    else GL.Print(L("Commandes : /gl, /gl bilan, /gl chronique, /gl stats, /gl guildes, /gl traces, /gl + [raison], /gl - [raison], /gl ami|ennemi|auto|mefiance, /gl note [texte], /gl guilde [ami|ennemi|mefiance|neutre], /gl reperage, /gl settings, /gl debug")) end
end
