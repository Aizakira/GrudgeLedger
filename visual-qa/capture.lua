-- OFFLINE ONLY. Execute real addon UI code; capture its actual native region tree.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local qaClock = 1794400000
time = function() return qaClock end
date = function(format, timestamp) return os.date(format or "%c", timestamp or qaClock) end
local methods = getmetatable(UIParent).__index
function methods:Click()
    assert(self:IsEnabled(), "Attempt to click a disabled control: " .. self:GetText())
    self:GetScript("OnClick")(self, "LeftButton")
end
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
function methods:SetFontObject(value) self.qaFontObject, self.qaFont, self.qaFontSize, self.qaFontFlags = value, nil, nil, nil end
function methods:SetFont(path, size, flags) self.qaFont, self.qaFontSize, self.qaFontFlags = path, size, flags return true end
function methods:GetFont()
    local path = self.qaFontObject == "ChatFontNormal" and "Fonts\\ARIALN.TTF"
        or self.qaFontObject == "QuestFont_Large" and "Fonts\\MORPHEUS.TTF" or "Fonts\\FRIZQT__.TTF"
    return self.qaFont or path, self.qaFontSize or QA_FontSize(self.qaFontObject), self.qaFontFlags or ""
end
function methods:SetJustifyH(value) self.qaJustifyH = value end
function methods:SetJustifyV(value) self.qaJustifyV = value end
function methods:SetWordWrap(value) self.qaWordWrap = value end
function methods:SetNonSpaceWrap(value) self.qaNonSpaceWrap = value end
function methods:SetMaxLines(value) self.qaMaxLines = value end
function methods:SetSpacing(value) self.qaSpacing = value end
function methods:GetSpacing() return self.qaSpacing or 0 end
function methods:SetTextInsets(...) self.qaInsets = { ... } end
function methods:GetStringHeight()
    local path, size = self:GetFont()
    return QA_TextHeight(self:GetText(), self.width or 400, size, self.qaSpacing or 0, path)
end
function methods:GetStringWidth()
    local path, size = self:GetFont()
    return QA_TextWidth(self:GetText(), size, path)
end
function methods:GetNumLines()
    local path, size = self:GetFont()
    return QA_TextLines(self:GetText(), self.width or 400, size, path)
end
function methods:SetColorTexture(...) self.qaFill = { ... } end
function methods:SetTexture(value) self.texture = value end
function methods:SetDesaturated(value) self.qaDesaturated=value end
-- Classic reference sheet: Ketho/BlizzardInterfaceResources a7142e9e,
-- Resources/AtlasInfo.lua. Only supply entries supported by this exact sheet.
local raceArt = "Interface\\Glues\\CharacterCreate\\CharacterCreateIcons"
local atlasCoords = {
    ["raceicon-dwarf-male"] = {0.646484375, 0.771484375, 0.001953125, 0.126953125},
    ["raceicon-orc-male"] = {0.130859375, 0.255859375, 0.517578125, 0.642578125},
}
C_Texture = { GetAtlasInfo = function(atlas) return atlasCoords[atlas] end }
function methods:SetAtlas(atlas)
    self:SetTexture(raceArt)
    self:SetTexCoord(unpack(assert(atlasCoords[atlas])))
end
CLASS_ICON_TCOORDS = { SHAMAN = {0.25, 0.49609375, 0.25, 0.5} }
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
    if self.normalTexture then self.normalTexture.qaButtonState = "normal" end
end
function methods:GetNormalTexture() return self.normalTexture end
function methods:SetHighlightTexture(value) self.qaHighlight = value if type(value) == "table" then value.qaButtonState = "highlight" end end
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
GetNormalizedRealmName = GetRealmName
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
local namespace = {}
local toc = assert(io.open(TEST_ROOT .. "/GrudgeLedger.toc", "r"))
for line in toc:lines() do
    line = line:gsub("\r", "")
    if line:match("%.lua$") then assert(loadfile(TEST_ROOT .. "/" .. line))("GrudgeLedger", namespace) end
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
    id.faction = i % 2 == 0 and "Alliance" or "Horde"
    id.class, id.className = "SHAMAN", "Chaman"
    id.race, id.raceName, id.sex = i % 2 == 0 and "Dwarf" or "Orc", i % 2 == 0 and "Nain" or "Orc", 2
    records[i] = GL.SetReaction(id, v[3])
end
GL.SetGuildReaction("Les Veilleurs de l'Aube", "friend", "Bons compagnons, fiables et patients.")
GL.SetGuildReaction("Les Corbeaux de la Dernière Nuit", "enemy", "Plusieurs mauvaises rencontres. À surveiller à proximité.")
GL.SetGuildReaction("La Compagnie du Lys", "warning", "Avis partagé : vérifier la personne avant de juger.")
GL.SetGuildReaction("Les Voyageurs", "neutral", "Aucun avis pour le moment.")
local record = records[2]
record.level = 39
record.reaction = nil
GL.AddNote(record, "Très bon tank au monastère. A pris le temps d'expliquer les mécaniques et de partager le butin.")
GL.AddNote(record, "Rencontre suivante plus tendue : à recontacter pour éclaircir le malentendu.")
GL.RecordGroup(record, "qa-group-1", "Monastère écarlate")
local oldZone, oldSubzone = GetRealZoneText, GetSubZoneText
local districts = {"Base de Kurzen", "Ruines de Tkashi", "Baie-du-Butin"}
local district = 1
GetRealZoneText = function() return "Vallée de Strangleronce" end
GetSubZoneText = function() return districts[district] end
IsInInstance = function() return false, "none" end
assert(GL.RecordHonor(record, 38))
assert(GL.RecordHonor(record, 17))
assert(GL.RecordHonor(nil, 12))
for i = 1, 7 do
    district = (i - 1) % #districts + 1
    GL.RecordPvP(record, "death", "confirmed", "Un seul adversaire hostile vous ciblait avant la mort. Attribution déduite ; aucune confirmation du coup fatal.", "qa-event-" .. i, {playerLevel=34, opponentLevel=39})
end
GL.RecordAggression(record, "confirmed", "Baisse de santé observée pendant qu'un seul adversaire vous ciblait.", "qa-attack", {playerLevel=34, opponentLevel=39})
GL.RecordPvP(records[3], "kill", "confirmed", "Coup fatal observé.", "qa-victory")
qaClock = qaClock + 1
for i, entry in ipairs({ {records[5], "player", false}, {records[12], "player", true}, {record, "player", true}, {records[8], "opponent", false} }) do
    local id = "qa-opening-" .. i
    local opening = assert(GL.RecordOpening(entry[1], entry[2], entry[3], id))
    if entry[2] == "opponent" then GL.RecordAggression(entry[1], "confirmed", nil, id .. "-hit", opening) end
    GL.RecordPvP(entry[1], "kill", "confirmed", nil, id .. "-kill", opening)
end
district = 2
GL.RecordPvP(records[7], "kill", "confirmed", "Adversaire observé mort après le combat.", "qa-combat-victory")
GetRealZoneText, GetSubZoneText = oldZone, oldSubzone
for i, r in ipairs(records) do
    r.encounters = { count = 15 - i, seen = { ["Player-1-self"] = qaClock - 3600 * i } }
    r.lastEncounterAt = qaClock - 3600 * i
    r.lastEncounterZone, r.lastEncounterSubzone = "Vallée de Strangleronce", "Baie-du-Butin"
    if GL.Relation(r) == "friend" then r.groupCount = 15 - i end
end
local function hideWindows()
    if GrudgeLedgerGuildProfiles then GrudgeLedgerGuildProfiles:Hide() end
    for _, name in ipairs({ "GrudgeLedgerWindow", "GrudgeLedgerJournal", "GrudgeLedgerStatistics", "GrudgeLedgerGuilds", "GrudgeLedgerNote", "GrudgeLedgerSettings", "GrudgeLedgerCorrections", "GrudgeLedgerDiagnostic", "GrudgeLedgerNearbyAlert", "GrudgeLedgerAlertPreview", "GrudgeLedgerGuide", "GrudgeLedgerBounties", "GrudgeLedgerPlayerDossier" }) do
        if _G[name] then _G[name]:Hide() end
    end
end
local function click(label)
    for _, f in ipairs(mock.frames) do
        if f:GetText() == GL.L(label) and f.scripts.OnClick then f.scripts.OnClick(f, "LeftButton") return end
    end
    error("Missing UI action: " .. label)
end
QA = { mock = mock, records = records, selected = record }
-- render.py runs each reference view in its own Lua runtime: these synthetic
-- contacts cannot change the regular fixtures or any SavedVariables on disk.
local function referenceJournal()
    GL.db.players, GL.db.aliases, GL.db.guilds = {}, {}, {}
    GL.db.unassignedHonor = {}
    GL.SetSetting("listDetail", "pvp")
    GL.SetSetting("grudgeAggression", 2)
    GL.SetSetting("grudgeDeath", 5)
    GL.SetSetting("grudgeVictory", 5)
    local stamp = os.time({year=2026, month=11, day=22, hour=12})
    local names = {
        {"Nodby", "Druid", 0, 1}, {"Mortymmer", "Ap...", 2, 1},
        {"Khäze", "Mog", 0, 1}, {"Father", "Emile", 0, 1},
        {"Nhaya", "Forever", 2, 3}, {"Chirho", "Nika", 0, 3},
        {"Rival", "Đyztw", 0, 1},
    }
    local zone = GetLocale() == "enUS" and "Searing Gorge" or GetLocale() == "esES" and "La Garganta de Fuego" or "Gorge des Vents brûlants"
    GetRealZoneText, GetSubZoneText = function() return zone end, function() return "" end
    local selected
    for i = 1, 79 do
        qaClock = stamp - (i - 1) * 60
        local spec = names[i] or {"Contact", ("Fictif %02d"):format(i), 0, 0}
        local id = GL.IdentityFromName(spec[1], spec[2], ("Player-999-%08X"):format(i))
        id.guildKnown, id.realm = true, "QA"
        if i == 1 then
            id.faction, id.race, id.raceName, id.sex, id.level = "Horde", "Tauren", "Tauren", 2, 54
            id.class = "DRUID"
            id.className = GetLocale() == "enUS" and "Druid" or GetLocale() == "esES" and "Druida" or "Druide"
        end
        local contact = GL.Remember(id)
        if i == 1 then
            selected = contact
            GL.RecordAggression(contact, "confirmed", nil, "qa-reference-aggression", {initiative="opponent", opponentLevel=54})
        elseif i ~= 6 then
            GL.SetReaction(contact, i <= 7 and "enemy" or "neutral")
        end
        -- Nhaya's older deaths leave Chirho as the recent nemesis, as in the reference.
        if i == 5 then qaClock = qaClock - 14 * 86400 end
        for n = 1, spec[4] do
            GL.RecordPvP(contact, "death", "confirmed", nil, "qa-reference-death-" .. i .. "-" .. n,
                {initiative="opponent", opponentLevel=contact.level}, nil, true)
        end
        qaClock = stamp - (i - 1) * 60
        for n = 1, spec[3] do
            GL.RecordPvP(contact, "kill", "confirmed", nil, "qa-reference-kill-" .. i .. "-" .. n)
        end
        contact.firstSeen = stamp
        contact.lastEncounterAt, contact.lastEncounterZone = qaClock, zone
    end
    qaClock = stamp
    record = selected
    QA.selected = selected
    assert(GL.JournalCounts().all == 79)
    assert(selected.pvp.deaths == 1 and selected.pvp.kills == 0 and GL.AutomaticBalance(selected) == -7)
    assert(GL.RelationSource(selected) == "pvp")
    QA.reference = {synthetic=true, contacts=79, selected=selected.fullName,
        portraits="Unavailable offline; actual addon fallback is shown, not a player portrait."}
end
local function dossierExample()
    local guid="Player-999-00DAABBA"
    if GL.Get("guid:"..guid) then return guid end
    local id=GL.IdentityFromName("Isabeau","Clairfeuille",guid)
    id.class,id.className,id.race,id.raceName,id.faction,id.level="DRUID","Druide","NightElf","Elfe de la nuit","Alliance",41
    GL.Remember(id)
    -- Two dated fights with both levels, so the overview and the Combats tab have content.
    GL.RecordPvP(id,"kill","confirmed","fixture","qa-dossier-kill",{opponentLevel=41,playerLevel=40})
    GL.RecordPvP(id,"death","confirmed","fixture","qa-dossier-death",{opponentLevel=41,playerLevel=39})
    -- Example habits: openings, one fight report and visits over a week (example values).
    local record=GL.Get("guid:"..guid)
    local me,hour=UnitGUID("player"),3600
    for i,opener in ipairs({"opponent","opponent","player","opponent"}) do
        record.history[#record.history+1]={kind="opening",time=qaClock-i*30*hour,opener=opener,actorGUID=me,zone="Hurlevent"}
    end
    for _,e in ipairs(record.history) do
        if e.kind=="death" then
            e.report={live={{src=guid,dst=me,spell="Mot de l'ombre : Douleur",amount=80,at=1},{src=guid,dst=me,spell="Mot de l'ombre : Douleur",amount=75,at=2},
                {src=guid,dst=me,spell="Racines enchevêtrées",at=3},{src="Player-999-00QAHELP",dst=me,from="Aldric Brisefer",spell="Frappe",amount=40,at=4}}}
        end
    end
    for i,shift in ipairs({-7*24+9,-6*24+10,-5*24+9,-4*24+8,-3*24+9,-2*24+10,-2*24+2,-24+9,-24+11,-3}) do
        GL.CharacterInsights.RecordVisit(guid,qaClock+shift*hour,i%3==0 and "Strangleronce" or "Forêt d’Elwynn")
    end
    local p={level=41,updated=qaClock,averageItemLevel=37,identity={classFile="DRUID"},gear={},
        stats={HEALTH=1933,MANA=1894,STRENGTH=70,AGILITY=108,STAMINA=143,INTELLECT=84,CRITICALSTRIKE="6 %"},
        trees={{id="feral-combat",name="Combat farouche",points=8,
            talents={{134399,"Férocité",3,132190},{134400,"Fureur",5,135881}}}},
        honorableKills=385,pvpRank=0,
        battlegrounds={{name="Bassin d’Arathi",games=3,wins=2,losses=1},{name="Goulet des Chanteguerres",games=7,wins=4,losses=3}},
        reputations={{group="Alliance",name="Darnassus",standing="Honoré",value=1200,max=12000},
            {group="Alliance",name="Hurlevent",standing="Amical",value=2800,max=6000},
            {group="Forces de l’Alliance",name="Sentinelles d’Aile-argent",standing="Neutre",value=675,max=3000}}}
    local items={}
    for i,v in ipairs({
        {"head","Casque de forestier du tigre",133111},{"neck","Pendentif de Skibi",133282},
        {"shoulder","Épaulières barbares",135039},{"back","Cape de chasseur de fauves",133762},
        {"chest","Tunique totémique en cuir",132717},{"shirt","Chemise élégante",135006},
        {"wrist","Garde-bras de la secte",132611},{"hand","Gants de dressage de chien",132941},
        {"waist","Ceinture d’escarmouche en cuir",236895},{"leg","Jambières barbares",134592},
        {"foot","Bottes d’Excelsior",132541},{"leftFinger","Anneau du tigre",133355},{"rightFinger","Anneau du sous-bois",133354},
        {"leftTrinket","Sacoche de potions",133633},{"weapon","Maillet de cérémonie",133043}}) do
        p.gear[v[1]]=i; items[i]={name=v[2],icon=v[3]}
    end
    GrudgeLedgerArmory={profiles={[guid]=p},items=items}
    return guid
end
local function referenceInteraction(f, state)
    if not state or state == "transparent" then return end
    local targets = { ["hover-open"] = f.openSheet, ["hover-enemy"] = f.reactions.enemy,
        ["hover-filter"] = f.openFilters, ["hover-pages"] = f.detailScroll.next,
        ["pressed-open"] = f.openSheet, ["after-hover"] = f.openSheet }
    local target = assert(targets[state], "Unknown reference interaction: " .. state)
    assert(target:IsEnabled() and target:IsShown(), "Reference interaction target is unavailable")
    local function appearance()
        return { active = target.active == true, hovered = target.hovered == true, pressed = target.pressed == true,
            caption = target.caption:GetText(), captionColor = {target.caption:GetTextColor()},
            texture = target.skin.texture, tint = target.skin.qaTint, slices = #(target.skinCaps or {}) }
    end
    local before, events = appearance(), {"OnEnter"}
    if before.active then
        assert(before.texture:find("JournalReferenceButtonRed", 1, true), "Selected action must already be red at rest")
        for i = 1, 3 do assert(before.captionColor[i] == 1, "Selected action caption must already be white") end
    end
    assert(target:GetScript("OnEnter"))(target)
    if state == "pressed-open" then
        assert(target:GetScript("OnMouseDown"))(target, "LeftButton")
        events[#events + 1] = "OnMouseDown"
    elseif state == "after-hover" then
        assert(target:GetScript("OnLeave"))(target)
        events[#events + 1] = "OnLeave"
    end
    local after = appearance()
    assert(after.active == before.active, "Pointer state must not change the selected action")
    assert(after.hovered == (state ~= "after-hover") and after.pressed == (state == "pressed-open"))
    if state == "after-hover" then
        assert(after.texture == before.texture, "Leaving hover did not restore the button texture")
        for i = 1, 3 do assert(after.captionColor[i] == before.captionColor[i]) end
    else
        assert(after.texture:find("JournalReferenceButtonRed", 1, true), "Hover did not select the real red skin")
        for i = 1, 3 do assert(after.captionColor[i] == 1, "Hover caption must be white") end
        assert(after.slices == 2, "Hover must preserve the real three-piece skin")
        if state == "pressed-open" then assert(after.tint[1] < 1, "Pressed skin must be darker") end
    end
    -- No OnClick dispatch: hovering must not change the synthetic contact or open its dossier.
    assert(record.reaction == nil and record.pvp.deaths == 1 and record.pvp.kills == 0)
    QA.interaction, QA.interactionTarget = { state = state, events = events, before = before, after = after }, target
end
function QA.capture(name)
    local referenceState
    if name == "journal-reference" or name:find("^journal%-reference%-") then
        referenceState = name:match("^journal%-reference%-(.+)$")
        referenceJournal()
        name = "journal"
    end
    -- Only the dossier-photos view has the Avatar Replay Lab's photos.
    AvatarReplayLabPhotos = nil
    hideWindows()
    records[10].tags = nil
    GL.SetSetting("readableFont", name:find("%-readable") ~= nil)
    GL.SetSetting("readingScale", name:find("%-largeprint") and 1.25 or 1)
    GL.SetSetting("compactMode", name:find("%-compact") ~= nil)
    name = name:gsub("%-readable", "")
    name = name:gsub("%-largeprint", "")
    UIParent:SetSize(1920, 1080)
    if name=="guild-profiles" then
        mock.units.player.guild="Les Veilleurs de l'Aube"
        local g=GL.GuildProfiles
        local card=assert(g.Publish(records[10]))
        g.SetTag(card,"reliable",true)
        local scope,me=GL.Bounties.GuildScope()
        g.Receive(scope,me,records[4].guid,table.concat({"T",card.owner,card.target,card.digest,1,GL.Now(),"0123456789abcdef","unreliable","1"},";"))
        GL.OpenGuildProfiles(records[10])
        return GrudgeLedgerGuildProfiles
    end
    if name == "journal-filters" then
        -- The filter panel open over the list, with two filters on.
        GL.ShowLedger(records[1].key)
        local f = GrudgeLedgerWindow
        f.openFilters:Click()
        f.filters.enemy:Click()
        f.factions.Alliance:Click()
        return f
    end
    if name:find("^journal%-tags") then
        local contact = records[10]
        contact.tags = {reliable=true}
        if name:find("%-all") then
            for _, choice in ipairs(GL.TagChoices) do contact.tags[choice[1]] = true end
        end
        if name:find("%-small") then UIParent:SetSize(1024, 600) end
        GL.ShowLedger(contact.key)
        GrudgeLedgerWindow.detailTabs.summary:Click()
        return GrudgeLedgerWindow
    end
    if name:find("^dossier%-") or name:find("^bounty%-") then
        local guid=dossierExample()
        mock.units.player.guild="Les Veilleurs de l'Aube"
        if name=="bounty-target" then return GL.OpenBounties(nil,"create") end
        if name=="bounty-history" then
            local target=records[3]
            if not QA.completedContract then
                QA.completedContract=assert(GL.Bounties.Post(target.guid,target.fullName,0))
                local player=mock.units.player.guid
                mock.units.player.guid=records[4].guid
                assert(GL.Bounties.Pledge(QA.completedContract,120000))
                mock.units.player.guid=player
                GL.Bounties.Kill(target.guid)
            end
            return GL.OpenBounties(target.guid,"view")
        end
        if name=="bounty-list" or name=="bounty-form" then
            -- The list of the guild's bounties, and the creation of a bounty in gold on a known target.
            for _,i in ipairs({5,6,8}) do
                local opponent=records[i]
                if opponent and not GL.Bounties.OpenFor(opponent.guid) then
                    GL.Bounties.Post(opponent.guid,opponent.fullName,i==6 and 0 or i*50000,{quota=i==5 and 3 or 1,group=i==8 and "party" or "solo",
                        split="winner",souvenir="none",note=""}) -- (records 3 and 7 serve the other views)
                end
            end
            if name=="bounty-form" then
                local f=GL.OpenBounties(records[7].guid,"create")
                f.form.gift.scripts.OnClick(f.form.gift,"LeftButton")
                return f
            end
            return GL.OpenBounties()
        end
        if name=="bounty-contract" then
            local opponent=records[7]
            if not QA.contract then
                QA.contract=assert(GL.Bounties.Post(opponent.guid,opponent.fullName,1200000,{quota=3,
                    group="party",split="equal",souvenir="screenshot",note="Prendre une capture de la dernière victoire pour la guilde."}))
            end
            return GL.OpenBounties(opponent.guid,"view")
        end
        if name:find("^dossier%-") then
            -- Two archived contracts, older than the guild event log (example values).
            local scope=GL.Bounties.GuildScope()
            local hunter,day=records[4].guid,86400
            scope.bountyRecords={[guid]={name="Isabeau Clairfeuille",at=qaClock-12*day,orders={
                ["Player-1-qa:1"]={at=qaClock-45*day,owner=hunter,pot=600000,state="paid",endedAt=qaClock-45*day+7200,
                    expires=qaClock-38*day,quota=1,hunter=hunter,helpers="Player-1-qa-helper",killedAt=qaClock-45*day+7200},
                ["Player-1-qa:2"]={at=qaClock-12*day,owner=hunter,pot=250000,state="open",expires=qaClock-5*day,quota=1}}}}
        end
        if name=="dossier-relations" then
            GL.GuildProfiles.Publish(GL.Get("guid:"..guid))
            local scope=GL.Bounties.GuildScope()
            scope.socialReports={qa={actor=records[4].guid,target=guid,seq=1,at=qaClock,received=qaClock,
                authorName="Célestine Longuebrise",score=-11,relation="enemy",events={
                    {kind="death",time=qaClock-1800,killingBlow=1,zone="Vallée de Strangleronce"},
                    {kind="aggression",time=qaClock-1840,zone="Vallée de Strangleronce"}}}}
        end
        assert(GL.OpenPlayerDossier(guid))
        local f=GrudgeLedgerPlayerDossier
        if name:find("^dossier%-fresh") or name:find("^dossier%-read") then
            -- What every user gets with the addon alone: no Armory archive, no studio photo.
            -- fresh: a killer who struck from out of sight, a minute ago. read: the in-game
            -- reading succeeded during the fight (example values).
            local killer="Player-999-00F4E5"
            if not GL.Get("guid:"..killer) then
                GetPlayerInfoByGUID=function(id) if id==killer then return "Voleur","ROGUE","Mort-vivant","Scourge",2 end end
                local id=GL.IdentityFromName("Helvard","Lamenoire",killer)
                GL.RecordAggression(id,"confirmed","Combat log","qa-fresh-a")
                GL.RecordPvP(id,"death","confirmed","Combat log","qa-fresh-d")
                local me=UnitGUID("player")
                for _,e in ipairs(GL.Get("guid:"..killer).history) do
                    if e.kind=="death" then
                        e.report={live={{src=killer,dst=me,spell="Embuscade",amount=412,at=1},
                            {src=killer,dst=me,spell="Attaque pernicieuse",amount=188,at=2},
                            {src=killer,dst=me,spell="Éviscération",amount=356,at=4,fatal=true}}}
                    end
                end
            end
            local fresh=GL.Get("guid:"..killer)
            fresh.inspection,fresh.level=nil,nil
            if name:find("^dossier%-read") then
                fresh.level=38
                local function item(id,label) return "|cff1eff00|Hitem:"..id.."::::::::38:::::|h["..label.."]|h|r" end
                fresh.inspection={stats={HEALTH=2140,ENERGY=100,AGILITY=152,STAMINA=118,ARMOR=1240},statsAt=qaClock,
                    gearAt=qaClock,talentsAt=qaClock,averageItemLevel=34,
                    gear={[1]=item(10008,"Coiffe d’ombrecuir"),[3]=item(7477,"Spallières en cuir"),[5]=item(2800,"Cotte noire"),
                        [7]=item(9624,"Jambières de l’embusqué"),[8]=item(9406,"Bottes du rôdeur"),[10]=item(7348,"Gants d’escarmouche"),
                        [16]=item(2244,"Lame de Krol"),[17]=item(3187,"Dague sacrificielle")},
                    trees={{id="assassination",name="Assassinat",points=8,talents={{135252,"Malice",5,132277},{135251,"Némésis",3,132122}}},
                        {id="combat",name="Combat",points=0,talents={}},
                        {id="subtlety",name="Finesse",points=21,talents={}}}}
            end
            GL.OpenPlayerDossier(killer)
            local page=name:match("^dossier%-%a+%-(%a+)")
            if page then f.tabs[page]:Click() end
            return f
        end
        if name=="dossier-gear" then
            -- A character seen over a week: level, guild and two pieces changed (example values).
            local day=86400
            GL.db.characterHistory=GL.db.characterHistory or {}
            GL.db.characterHistory[guid]={seen=1794391200,state={},stateAt={},changes={
                {at=1794391200-7*day,key="level",value=36},{at=1794391200,key="level",value=41},
                {at=1794391200-7*day,key="guild",value="Les Sentinelles"},{at=1794391200-2*day,key="guild",value="Cercle d'Elune"},
                {at=1794391200-7*day,key="gear:head",value=100},{at=1794391200-day,key="gear:head",value=101},
                {at=1794391200-7*day,key="gear:chest",value=200},{at=1794391200,key="gear:chest",value=201}}}
            GL.OpenPlayerDossier(guid)
        end
        if name=="dossier-shared" then
            -- A colleague's inspection, relayed by another member; the helmet was seen three days earlier.
            local profile=GrudgeLedgerArmory.profiles[guid]
            local at=1794391200
            profile.gearAt=at
            profile.provenance={gear={source="inspection",by="Player-1-qa-source",via="Player-1-qa-relay",at=at}}
            profile.dates={gear={head=at-3*86400}}
            local names={["Player-1-qa-source"]="Célestine Longuebrise",["Player-1-qa-relay"]="Aubin Clairval"}
            local memberName=GL.Bounties.MemberName
            GL.Bounties.MemberName=function(id) return names[id] or memberName(id) end
            GL.OpenPlayerDossier(guid,nil,nil,"gear")
            return f
        end
        if name=="dossier-facts" then
            -- The first fact card opens the full list with its dated events.
            f.overview.cards[1]:Click()
            return f
        end
        if name=="dossier-habits" then
            -- Thirty zones and many changes (example values) to show lists that turn their own pages.
            for k=1,30 do GL.CharacterInsights.RecordVisit(guid,qaClock-k*7200,"Zone d’exemple "..k) end
            f.tabs.habits:Click()
            return f
        end
        if name=="dossier-ally" then
            -- A player of your own faction never fought: groups, a trade and guild tags (example values).
            local id=GL.IdentityFromName("Bastien","Griseforge","Player-999-00A11E")
            id.class,id.className,id.race,id.raceName,id.faction,id.level="WARRIOR","Guerrier","Dwarf","Nain","Alliance",44
            local ally=GL.Remember(id)
            ally.faction="Alliance"
            ally.tags={ninja=true,leaver=true}
            GL.RecordGroup(id,"qa-group-1","Les Mortemines")
            GL.RecordGroup(id,"qa-group-2","Les Mortemines")
            GL.OpenPlayerDossier(id.guid)
            return f
        end
        if name=="dossier-photos" then
            -- The Avatar Replay Lab's read-only photo access, with synthetic example images.
            local base="Interface/AddOns/AvatarReplayLab/Studio/example"
            AvatarReplayLabPhotos={Get=function(g)
                if g~=guid then return end
                return {at=qaClock,bust=base.."-buste",poses={recherche=base.."-recherche",combat=base.."-combat"}}
            end}
            GL.OpenPlayerDossier(guid,nil,nil,"gear")
            return f
        end
        if name=="dossier-stats" then
            f.tabs.gear:Click()
            f.statsToggle:Click()
            return f
        end
        f.tabs[name:sub(9)]:Click()
        return f
    elseif name == "journal" or name == "journal-compact" or name == "journal-transparent" or name == "journal-no-paper" or name == "journal-no-book" or name == "journal-small" or name == "journal-small-bottom" or name:find("^journal%-history") or name:find("^journal%-notes") or name == "journal-matchup" then
        if name:find("^journal%-small") then UIParent:SetSize(1024, 600) end
        if name:find("%-small$") then UIParent:SetSize(1024, 600) end
        GL.ShowLedger(record.key)
        GrudgeLedgerWindow.search:SetText("")
        GrudgeLedgerWindow.filters.all.scripts.OnClick()
        GrudgeLedgerWindow.factions.all.scripts.OnClick()
        GL.ShowLedger(record.key)
        local tab = name:find("%-history") and "history" or name:find("%-notes") and "notes" or name == "journal-matchup" and "matchup" or "summary"
        local f = GrudgeLedgerWindow
        if f.detailTabs then f.detailTabs[tab].scripts.OnClick(f.detailTabs[tab]) end
        if name == "journal-history-page2" then f.historyPage.next:Click() end
        if name == "journal-history-filter" then f.historyPage.options.pvp:Click() end
        if name == "journal-history-honor" then f.historyPage.options.honor:Click() end
        if name == "journal-small-bottom" then
            local f = GrudgeLedgerWindow
            assert(f.detailBody:GetHeight() >= f.detailText:GetStringHeight() + 12)
            f.detailScroll:SetVerticalScroll(math.max(0, f.detailBody:GetHeight() - f.detailScroll:GetHeight()))
        end
        if QA.reference then
            assert(f.pageSize == 8 and f.rows[1].key == record.key, "reference must show eight rows with Nodby first")
            assert(f.rows[8]:IsShown() and not f.rows[9]:IsShown(), "reference pagination changed")
            referenceInteraction(f, referenceState)
        end
        return GrudgeLedgerWindow
    elseif name:find("^honor") or name:find("^chronicle") then
        if name:find("%-small") then UIParent:SetSize(1024, 600) end
        local mode = name:find("%-annual") and "year" or name:find("%-story") and "story" or name:find("^honor") and "summary" or "history"
        GL.ShowJournal(mode)
        local f = GrudgeLedgerJournal
        if name == "honor-podium" then f.chips.opponents:Click() end
        if name:find("^honor%-initiative") then f.chips.initiative:Click() end
        if name == "honor-races" then f.chips.race:Click() end
        if name == "honor-classes" then f.chips.class:Click() end
        if name == "honor-zones" or name == "honor-subzones" then f.chips.zone:Click() end
        f.period, f.scope, f.kind, f.offset = "all", "character", "all", 0
        f.search:SetText("")
        if name:find("%-empty") then f.scope = "legacy" end
        if name:find("%-year") then f.period, f.year = "year", tonumber(date("%Y", qaClock)) end
        if name:find("%-notes") then f.kind = "notes" end
        if name == "chronicle-honor" then f.kind = "honor" end
        GL.ShowJournal(mode)
        if name == "honor-subzones" then
            f.breakdownRows[1]:Click()
            assert(f.zoneKey == "Vallée de Strangleronce" and f.breakdownRows[3]:IsShown())
        end
        if name == "honor-annual-copy" then f.copyAnnual:Click() end
        -- The tables are a page of the Relations book.
        return GrudgeLedgerRelations or GrudgeLedgerJournalBook
    elseif name == "journal-horde-friends" then
        GL.ShowLedger(records[1].key)
        GrudgeLedgerWindow.filters.friend.scripts.OnClick()
        GrudgeLedgerWindow.factions.Horde.scripts.OnClick()
        return GrudgeLedgerWindow
    elseif name == "journal-empty" then
        GL.ShowLedger()
        local f = GrudgeLedgerWindow
        f.search:SetText("Aucune correspondance QA")
        f.search.scripts.OnEnterPressed(f.search)
        return f
    elseif name:find("^recap") then
        -- The Bilan's five cards, on the example journal.
        GL.Recap.Open(tonumber(name:match("^recap%-(%d)")) or 1)
        local recap = GrudgeLedgerRelations.host.pages.recap
        if name:find("%-copy") then recap.copy.scripts.OnClick(recap.copy, "LeftButton") end
        return GrudgeLedgerRelations
    elseif name:find("^relations") then
        -- The Relations book, with the example journal. "-empty" shows a new player's book.
        local page = name:match("^relations%-(%a+)")
        if name:find("%-empty") then
            local saved = GL.db.players
            GL.db.players = {}
            GL.ShowRelations(page)
            GL.db.players = saved
            return GrudgeLedgerRelations
        end
        if (page == "guildlog" or page == "enemies") and GL.GuildMap then
            -- Synthetic guild fights: the renderer has no guild.
            local at = GL.Now()
            GL.GuildMap.Enabled = function() return true, true end
            GL.GuildMap.Points = function()
                return {
                    { actor = "Player-1-QA000001", time = at - 600, mapID = 1, kind = "death", target = "Player-1-QA0000E1", name = "Krogan Sombrelame" },
                    { actor = "Player-1-QA000000", mine = true, time = at - 4200, mapID = 1, kind = "kill", target = "Player-1-QA0000E1", name = "Krogan Sombrelame" },
                    { actor = "Player-1-QA000002", time = at - 9000, mapID = 1, kind = "kill", target = "Player-1-QA0000E2", name = "Zulrak" },
                    { actor = "Player-1-QA000001", time = at - 90000, mapID = 1, kind = "death", name = "Vexa la Très Longue Lame du Crépuscule Éternel" },
                    { actor = "Player-1-QA000000", mine = true, time = at - 200000, mapID = 1, kind = "death", target = "Player-1-QA0000E3", name = "Morgash" },
                    { actor = "Player-1-QA000003", time = at - 400000, mapID = 1, kind = "death" },
                    { actor = "Player-1-QA000002", time = at - 500000, mapID = 1, kind = "kill", target = "Player-1-QA0000E4", name = "Thazdin" },
                    { actor = "Player-1-QA000002", time = at - 600000, mapID = 1, kind = "kill", target = "Player-1-QA0000E4", name = "Thazdin" },
                }
            end
        end
        if page == "members" and GL.GuildMap then
            -- Synthetic members (example names): you, two up to date (one an alt), one old, one unknown.
            local at = GL.Now()
            GL.GuildMap.Members = function()
                return {
                    { id = "Player-1-QA000000", name = "Testeur Exemple", version = "0.62.1", current = true, online = true, at = at, shares = true, mark = "a1", you = true },
                    { id = "Player-1-QA000001", name = "Célestine Longuebrise", version = "0.62.1", current = true, online = true, at = at, shares = true, mark = "b2" },
                    { id = "Player-1-QA000002", name = "Aubin Clairval", version = "0.62.1", current = true, online = false, at = at - 7200, shares = false, mark = "b2" },
                    { id = "Player-1-QA000003", name = "Isabeau Clairfeuille", version = "0.58.11", current = false, online = false, at = at - 3 * 86400, shares = true, mark = "c3" },
                    { id = "Player-1-QA000004", name = "Gaspard Rougelune", online = false, at = at - 12 * 86400, shares = false },
                }
            end
        end
        GL.ShowRelations(page)
        if name == "relations-guildlog-filters" then
            local log = GrudgeLedgerGuild.host.pages.guildlog
            log.openFilters.scripts.OnClick(log.openFilters, "LeftButton")
        end
        if page == "guildlog" or page == "enemies" or page == "guilds" or page == "members" then return GrudgeLedgerGuild end
        return GrudgeLedgerRelations
    elseif name:find("^statistics") or name:find("^guild%-") then
        if name:find("%-small") then UIParent:SetSize(1024, 600) end
        local guild = name:find("^guild") ~= nil
        GL.ShowStatistics(guild and "guilds" or "players")
        local f = GrudgeLedgerStatistics
        f.category, f.choice, f.offset, f.faction, f.selected = 1, 1, 0, "all", nil
        if name:find("%-friends") or name:find("%-group") then f.category = 2 end
        if name:find("%-encounters") then f.choice = 2 end
        if name:find("%-recent") then f.choice = 3 end
        if name:find("%-group") then f.choice = 4 end
        if name:find("%-combat") then f.category = guild and 2 or 3 end
        if name:find("%-empty") then f.faction = "unknown" end
        if name:find("%-horde") then f.faction = "Horde" end
        GL.ShowStatistics(guild and "guilds" or "players")
        if guild and f.rows[1].item then f.rows[1].scripts.OnClick(f.rows[1]) end
        if name == "guild-exceptions" and f.guildDetail.exceptionButton:IsEnabled() then f.guildDetail.exceptionButton:Click() end
        return f
    elseif name == "guilds" then GL.ShowGuilds(record) return GrudgeLedgerGuilds
    elseif name == "note-edit" or name == "note-delete" then
        GL.EditNote(record, record.notes[1])
        if name == "note-delete" then GrudgeLedgerNote.remove.scripts.OnClick() end
        return GrudgeLedgerWindow
    elseif name == "note" then GL.EditNote(record) GrudgeLedgerNote.edit:SetText("Une bonne équipe au monastère.\n\nJoueur patient, consignes claires et partage équitable du butin. À retrouver pour une prochaine sortie.") return GrudgeLedgerWindow
    elseif name == "settings" or name:find("^settings%-") then
        SlashCmdList.GRUDGELEDGER("settings")
        local f = GrudgeLedgerSettings
        local category = name:match("^settings%-([a-z]+)") or "appearance"
        category = category:gsub("%-small$", "")
        if name:find("%-small$") then UIParent:SetSize(1024, 600) f:Hide() f:Show() end
        if f.tabs then
            local tab = assert(f.tabs[category], "Missing settings category: " .. category)
            tab.scripts.OnClick(tab)
        end
        if name == "settings-appearance-markers" then GL.SetSetting("iconSize", 40) end
        if name == "settings-data-experimental" then f.experimental:Click() end
        return f
    elseif name == "alert-preview" then GL.Display.PreviewAlert("enemy") return GrudgeLedgerAlertPreview
    elseif name == "guide" then GL.ShowGuide() return GrudgeLedgerGuide
    elseif name == "corrections" or name == "correction-voided" or name == "kill-details" or name == "combat-report" then
        GL.ShowLedger((name == "kill-details" or name == "combat-report") and records[7].key or record.key)
        click("Corriger le PvP")
        local row = GrudgeLedgerWindow.historyPage.rows[1]
        if name == "combat-report" then
            row.event.report = {live = {
                {kind="SPELL_DAMAGE", at=100, src=row.event.actorGUID, dst=records[7].guid, spell="Éclair", amount=247},
                {kind="SWING_DAMAGE", at=102, src=records[7].guid, dst=row.event.actorGUID, amount=132},
                {kind="SWING_DAMAGE", at=103, src="Creature-1-wolf", from="Loup gris", dst=row.event.actorGUID, amount=58},
            }}
        end
        if name == "kill-details" then
            -- Both builds as recorded at the fight (example values).
            row.event.build = {
                opponent = {level=41, spec="31/0/20", specName="Restauration", ilvl=37, stats={HEALTH=1933}, at=1794391200, source="inspection"},
                me = {level=40, ilvl=35, stats={HEALTH=1760}},
            }
        end
        local details = row.details
        details:Click()
        if name == "combat-report" then row.event.report = nil end
        if name == "kill-details" then assert(GrudgeLedgerCorrections.event.kind == "kill") end
        if name == "correction-voided" then GrudgeLedgerCorrections.confirm:Click() details:Click() end
        return GrudgeLedgerCorrections
    elseif name == "death-report" or name == "death-export" then
        -- The example druid's death: its blow-by-blow and both builds (example values).
        local guid = dossierExample()
        local contact = GL.Get("guid:" .. guid)
        local death
        for _, e in ipairs(contact.history) do
            if e.kind == "death" then death = e end
        end
        death.combat.healthPct, death.combat.opponents = 92, 2
        death.build = {opponent = {level=41, spec="0/31/20", specName="Combat farouche", ilvl=37, stats={HEALTH=1933, ARMOR=1650}},
            me = {level=39, spec="0/5/31", specName="Givre", ilvl=33, stats={HEALTH=1480, MANA=2100, ARMOR=610}, gear={head=4387, chest=10021}}}
        if name == "death-report" then
            GL.InspectEvent(contact, death)
            return GrudgeLedgerCorrections
        end
        return GL.DeathReport.ShowExport()
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
    elseif name == "alert-after-death" then
        qaClock = qaClock + 200
        mock.units.target = { name = "Nicolas", surname = "Brisevent", guid = "Player-1-qa-combat" }
        GL.RecordPvP(GL.Identity("target"), "death", "confirmed", "Un seul adversaire vous ciblait.", "qa-combat")
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
    if QA.interaction then QA.interaction.target_id = QA.interactionTarget.qaID end
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
            buttonState = f.qaButtonState, hasDisabledTexture = f.disabledTexture ~= nil,
            active = f.active == true, hovered = f.hovered == true, pressed = f.pressed == true, blendMode = f.blendMode,
            template = f.qaTemplate, fontObject = f.qaFontObject, font = (f.qaKind == "FontString" or f.qaKind == "EditBox") and f:GetFont() or nil, fontSize = f.qaFontSize,
            shadow = f.qaShadow, shadowOffset = f.qaShadowOffset,
            color = f.qaFill, textColor = f.qaTextColor, tint = f.qaTint, alpha = f.qaAlpha,
            ignoreParentAlpha = f.qaIgnoreAlpha, texCoord = f.texCoord,
            texture = type(f.texture) == "number" and ("FileDataID/"..f.texture) or type(f.texture) == "string" and f.texture or nil,
            desaturated = f.qaDesaturated, mask = f.mask and f.mask.texture,
            justifyH = f.qaJustifyH, justifyV = f.qaJustifyV, spacing = f.qaSpacing,
            maxLines = f.qaMaxLines, wordWrap = f.qaWordWrap, insets = f.qaInsets,
            scrollChild = f.scrollChild and f.scrollChild.qaID, vertical = f.vertical or 0 }
    end
    return result, root.qaID
end
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
