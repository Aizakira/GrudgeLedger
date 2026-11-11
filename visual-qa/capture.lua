-- OFFLINE ONLY. Execute real addon UI code; capture its actual native region tree.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local qaClock = 1794400000
time = function() return qaClock end
local methods = getmetatable(UIParent).__index
local oldFrame, oldTexture, oldFont = CreateFrame, methods.CreateTexture, methods.CreateFontString
local function tag(region, kind, template, layer)
    region.qaKind, region.qaTemplate, region.qaLayer = kind, template, layer
    region.qaAnchors = {}
    return region
end
UIParent.qaKind, UIParent.qaRoot = "Frame", true
Minimap.qaKind = "Minimap"
function CreateFrame(kind, name, parent, template) return tag(oldFrame(kind, name, parent), kind, template) end
function methods:CreateTexture(name, layer, template, sublevel)
    local r = tag(oldTexture(self), "Texture", template, layer or "ARTWORK")
    r.qaSublevel = sublevel or 0
    return r
end
function methods:CreateMaskTexture(name, layer) return tag(oldTexture(self), "Mask", nil, layer) end
function methods:CreateFontString(name, layer, template)
    local r = tag(oldFont(self), "FontString", template, layer or "OVERLAY")
    r.qaFontObject = template
    return r
end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relativePoint, relative = relative, relativePoint, point, self.parent or UIParent
    elseif relative == nil then relative, relativePoint, x, y = self.parent or UIParent, point, 0, 0
    elseif type(relative) == "string" then relative = _G[relative] end
    if type(relativePoint) == "number" then x, y, relativePoint = relativePoint, x, point end
    relativePoint = relativePoint or point
    self.qaAnchors = self.qaAnchors or {}
    self.qaAnchors[point] = { point = point, relative = relative, relativePoint = relativePoint, x = x or 0, y = y or 0 }
end
function methods:ClearAllPoints() self.qaAnchors = {} end
function methods:SetAllPoints(relative)
    self:ClearAllPoints()
    relative = relative or self.parent
    self:SetPoint("TOPLEFT", relative, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", relative, "BOTTOMRIGHT", 0, 0)
end
function methods:SetFontObject(value) self.qaFontObject = value end
function methods:SetFont(path, size, flags) self.qaFont, self.qaFontSize, self.qaFontFlags = path, size, flags return true end
function methods:GetFont() return self.qaFont or "Fonts\\FRIZQT__.TTF", self.qaFontSize or QA_FontSize(self.qaFontObject), self.qaFontFlags or "" end
function methods:SetJustifyH(value) self.qaJustifyH = value end
function methods:SetJustifyV(value) self.qaJustifyV = value end
function methods:SetWordWrap(value) self.qaWordWrap = value end
function methods:SetNonSpaceWrap(value) self.qaNonSpaceWrap = value end
function methods:SetMaxLines(value) self.qaMaxLines = value end
function methods:SetSpacing(value) self.qaSpacing = value end
function methods:GetSpacing() return self.qaSpacing or 0 end
function methods:SetTextInsets(...) self.qaInsets = { ... } end
function methods:GetStringHeight() return QA_TextHeight(self:GetText(), self.width or 400, self.qaFontSize or QA_FontSize(self.qaFontObject), self.qaSpacing or 0) end
function methods:GetStringWidth() return QA_TextWidth(self:GetText(), self.qaFontSize or QA_FontSize(self.qaFontObject)) end
function methods:GetNumLines() return QA_TextLines(self:GetText(), self.width or 400, self.qaFontSize or QA_FontSize(self.qaFontObject)) end
function methods:SetColorTexture(...) self.qaFill = { ... } end
function methods:SetTexture(value) self.texture = value end
function methods:SetVertexColor(...) self.qaTint = { ... } end
function methods:SetTextColor(...) self.qaTextColor = { ... } end
function methods:GetTextColor() return unpack(self.qaTextColor or { 1, 1, 1, 1 }) end
function methods:SetAlpha(value) self.qaAlpha = value end
function methods:GetAlpha() return self.qaAlpha or 1 end
function methods:SetFrameStrata(value) self.qaStrata = value end
function methods:SetFrameLevel(value) self.qaLevel = value end
function methods:GetFrameLevel() return self.qaLevel or (self.parent and self.parent:GetFrameLevel() + 1) or 0 end
function methods:SetIgnoreParentAlpha(value) self.qaIgnoreAlpha = value end
function methods:SetIgnoreParentScale(value) self.qaIgnoreScale = value end
function methods:IsProtected() return false end
function methods:CanChangeProtectedState() return true end
function methods:SetDrawLayer(value, sublevel) self.qaLayer, self.qaSublevel = value, sublevel or 0 end
function methods:SetScrollChild(child)
    self.scrollChild = child
    child:ClearAllPoints()
    child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
end
function methods:SetNormalTexture(value)
    if type(value) == "string" then
        self.normalTexture = self.normalTexture or self:CreateTexture(nil, "ARTWORK")
        self.normalTexture:SetAllPoints() self.normalTexture:SetTexture(value)
    else self.normalTexture = value end
end
function methods:GetNormalTexture() return self.normalTexture end
function methods:SetHighlightTexture(value) self.qaHighlight = value end
function methods:SetPushedTexture(value) self.pushedTexture = value if type(value) == "table" then value.qaButtonState = "pushed" end end
function methods:SetDisabledTexture(value) self.disabledTexture = value if type(value) == "table" then value.qaButtonState = "disabled" end end
function methods:SetNormalFontObject(value) self.normalFont = value if self.fontString then self.fontString.qaFontObject = value end end
function methods:SetDisabledFontObject(value) self.disabledFont = value end
function methods:SetOwner() end
function methods:AddLine(value) self.qaLines = self.qaLines or {} self.qaLines[#self.qaLines + 1] = value end
function methods:HighlightText() end
function methods:SetShadowColor(...) self.qaShadow = { ... } end
function methods:SetShadowOffset(...) self.qaShadowOffset = { ... } end
function methods:GetPoint(index)
    for _, a in pairs(self.qaAnchors or {}) do return a.point, a.relative, a.relativePoint, a.x, a.y end
end
function methods:GetCenter() return self == Minimap and 1760 or 960, self == Minimap and 950 or 540 end
function methods:SetScale(value) self.scale = value end
function methods:GetEffectiveScale() return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1) end

Minimap:SetSize(160, 160)
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -30)
GameTooltip = CreateFrame("Frame", "GameTooltip", UIParent)
GameTooltip:Hide()
GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end
GetTimePreciseSec = function() return 123.456 end
UnitIsDeadOrGhost = function() return false end
UnitAffectingCombat = function() return false end
UnitIsPVP = function() return true end
UnitHealth = function() return 100 end
UnitHealthMax = function() return 100 end
UnitCanAttack = function() return false end
SOUNDKIT = { RAID_WARNING = 1, IG_QUEST_LOG_OPEN = 2 }
PlaySound = function() end
hooksecurefunc = function() end
C_ChatInfo.PerformEmote = function() end
DoEmote = function() end
StartDuel = function() end
C_NamePlate = { GetNamePlates = function() return {} end }
SetCVar("nameplateShowFriends", 1) SetCVar("nameplateShowEnemies", 1)
local toc = assert(io.open(TEST_ROOT .. "/GrudgeLedger.toc", "r"))
for line in toc:lines() do
    line = line:gsub("\r", "")
    if line:match("%.lua$") then assert(loadfile(TEST_ROOT .. "/" .. line))("GrudgeLedger") end
end
toc:close()
mock.Fire("ADDON_LOADED", "GrudgeLedger")
local GL = GrudgeLedger
-- Synthetic fixture data only; never installed or written to SavedVariables.
local examples = {
    { "Aveline", "Clairval", "friend", "Les Veilleurs de l'Aube" },
    { "Bastian", "Griseforge", "warning", "Les Corbeaux de la Dernière Nuit" },
    { "Célestine", "Longuebrise", "enemy", "Les Corbeaux de la Dernière Nuit" },
    { "Dorian", "Sombreval", "friend", "La Compagnie du Lys" },
    { "Éléonore", "Valombre", "neutral" },
    { "Félix", "Boisargent", "friend", "Les Veilleurs de l'Aube" },
    { "Gaspard", "Rougelune", "enemy" },
    { "Hélène", "Brisedargent", "warning" },
    { "Isolde", "Chant-de-l'Aube", "friend" },
    { "Jules", "Clairbois", "neutral" },
    { "Léandre", "Longnom-de-la-Vallée", "friend" },
    { "Mélisande", "Bruneterre", "enemy" },
}
local records = {}
for i, v in ipairs(examples) do
    local id = GL.IdentityFromName(v[1], v[2], "Player-1-qa" .. i)
    id.guild, id.realm, id.guildKnown = v[4], "Forever", true
    records[i] = GL.SetReaction(id, v[3])
end
GL.SetGuildReaction("Les Veilleurs de l'Aube", "friend", "Bons compagnons, fiables et patients.")
GL.SetGuildReaction("Les Corbeaux de la Dernière Nuit", "enemy", "Plusieurs mauvaises rencontres. À surveiller à proximité.")
GL.SetGuildReaction("La Compagnie du Lys", "warning", "Avis partagé : vérifier la personne avant de juger.")
GL.SetGuildReaction("Les Voyageurs", "neutral", "Aucun avis pour le moment.")
local record = records[2]
record.reaction = nil
GL.AddNote(record, "Très bon tank au monastère. A pris le temps d'expliquer les mécaniques et de partager le butin.")
GL.AddNote(record, "Rencontre suivante plus tendue : à recontacter pour éclaircir le malentendu.")
GL.RecordGroup(record, "qa-group-1", "Monastère écarlate")
for i = 1, 7 do
    GL.RecordPvP(record, "death", i % 2 == 0 and "confirmed" or "probable", "Un seul adversaire hostile vous ciblait avant la mort. Attribution déduite ; aucune confirmation du coup fatal.", "qa-event-" .. i)
end
GL.RecordAggression(record, "probable", "Baisse de santé observée pendant qu'un seul adversaire vous ciblait.", "qa-attack")
local function hideWindows()
    for _, name in ipairs({ "GrudgeLedgerWindow", "GrudgeLedgerGuilds", "GrudgeLedgerNote", "GrudgeLedgerSettings", "GrudgeLedgerCorrections", "GrudgeLedgerDiagnostic", "GrudgeLedgerNearbyAlert" }) do
        if _G[name] then _G[name]:Hide() end
    end
end
local function click(label)
    for _, f in ipairs(mock.frames) do
        if f:GetText() == label and f.scripts.OnClick then f.scripts.OnClick(f, "LeftButton") return end
    end
    error("Missing UI action: " .. label)
end
QA = { mock = mock, records = records, selected = record }
function QA.capture(name)
    hideWindows()
    if name == "journal" then GL.ShowLedger(record.key) return GrudgeLedgerWindow
    elseif name == "journal-empty" then GL.ShowLedger() GrudgeLedgerWindow.search:SetText("Aucune correspondance QA") return GrudgeLedgerWindow
    elseif name == "guilds" then GL.ShowGuilds(record) return GrudgeLedgerGuilds
    elseif name == "note" then GL.EditNote(record) GrudgeLedgerNote.edit:SetText("Une bonne équipe au monastère.\n\nJoueur patient, consignes claires et partage équitable du butin. À retrouver pour une prochaine sortie.") return GrudgeLedgerNote
    elseif name == "settings" then SlashCmdList.GRUDGELEDGER("settings") return GrudgeLedgerSettings
    elseif name == "corrections" then GL.ShowLedger(record.key) click("Corriger le PvP") GrudgeLedgerWindow:Hide() return GrudgeLedgerCorrections
    elseif name == "diagnostic" then SlashCmdList.GRUDGELEDGER("debug") return GrudgeLedgerDiagnostic
    elseif name == "minimap" or name == "minimap-large" then
        Minimap:SetSize(name == "minimap" and 160 or 260, name == "minimap" and 160 or 260)
        GL.SetSetting("minimapAngle", 225)
        return Minimap
    elseif name == "alert" then
        qaClock = qaClock + 200
        mock.units.target = { name = "Bastian", surname = "Griseforge", guid = "Player-1-qa2", guild = record.guild }
        GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
        return GrudgeLedgerNearbyAlert
    elseif name == "alert-probable" then
        qaClock = qaClock + 200
        mock.units.target = { name = "Nicolas", surname = "Brisevent", guid = "Player-1-qa-probable" }
        GL.RecordPvP(GL.Identity("target"), "death", "probable", "Un seul adversaire vous ciblait.", "qa-probable")
        GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
        return GrudgeLedgerNearbyAlert
    elseif name == "alert-long-guild" then
        qaClock = qaClock + 200
        local guild = "La Confrérie des Très Longues Nuits de la Dernière Alliance"
        GL.SetGuildReaction(guild, "enemy", "Plusieurs mauvaises rencontres dans la région. Texte de stress avec un fragment littéral |Ttexture:99|t et une note prolongée pour vérifier la limite de deux lignes.")
        mock.units.target = { name = "Alexandrine", surname = "de-la-Vallée-des-Brumes-Éternelles", guid = "Player-1-qa-long", guild = guild }
        GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
        return GrudgeLedgerNearbyAlert
    end
end
function QA.snapshot(root)
    local result = {}
    for i, f in ipairs(mock.frames) do f.qaID = i end
    for i, f in ipairs(mock.frames) do
        local anchors = {}
        for _, a in pairs(f.qaAnchors or {}) do
            anchors[#anchors + 1] = { point = a.point, relative = a.relative and a.relative.qaID,
                relativePoint = a.relativePoint, x = a.x, y = a.y }
        end
        local name = type(f.name) == "string" and f.name or nil
        result[i] = { id = i, parent = f.parent and f.parent.qaID, kind = f.qaKind or "Frame", name = name,
            width = f.width, height = f.height, scale = f.scale or 1, anchors = anchors,
            layer = f.qaLayer, sublevel = f.qaSublevel, level = f.qaLevel, strata = f.qaStrata,
            shown = f.shown, enabled = f.enabled, text = f.text, checked = f.checked, fontString = f.fontString and f.fontString.qaID,
            buttonState = f.qaButtonState,
            template = f.qaTemplate, fontObject = f.qaFontObject, font = f.qaFont, fontSize = f.qaFontSize,
            color = f.qaFill, textColor = f.qaTextColor, tint = f.qaTint, alpha = f.qaAlpha,
            texture = type(f.texture) == "string" and f.texture or nil, mask = f.mask ~= nil,
            justifyH = f.qaJustifyH, justifyV = f.qaJustifyV, spacing = f.qaSpacing,
            maxLines = f.qaMaxLines, wordWrap = f.qaWordWrap, insets = f.qaInsets,
            scrollChild = f.scrollChild and f.scrollChild.qaID, vertical = f.vertical or 0 }
    end
    return result, root.qaID
end
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
