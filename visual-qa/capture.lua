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
local function dossierExample()
    local guid="Player-999-00DAABBA"
    if GL.Get("guid:"..guid) then return guid end
    local id=GL.IdentityFromName("Isabeau","Clairfeuille",guid)
    id.class,id.className,id.race,id.raceName,id.faction,id.level="DRUID","Druide","NightElf","Elfe de la nuit","Alliance",41
    GL.Remember(id)
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
function QA.capture(name)
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
        if name=="bounty-contract" then
            local opponent=records[7]
            if not QA.contract then
                QA.contract=assert(GL.Bounties.Post(opponent.guid,opponent.fullName,1200000,{quota=3,
                    group="party",split="equal",souvenir="screenshot",note="Prendre une capture de la dernière victoire pour la guilde."}))
            end
            return GL.OpenBounties(opponent.guid,"view")
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
            GL.OpenPlayerDossier(guid)
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
        return GrudgeLedgerWindow
    elseif name:find("^honor") or name:find("^chronicle") then
        if name:find("%-small") then UIParent:SetSize(1024, 600) end
        local mode = name:find("%-annual") and "year" or name:find("%-story") and "story" or name:find("^honor") and "summary" or "history"
        GL.ShowJournal(mode)
        local f = GrudgeLedgerJournal
        if name == "honor-podium" then f.dimensionButtons.opponents:Click() end
        if name:find("^honor%-initiative") then f.dimensionButtons.initiative:Click() end
        if name == "honor-races" then f.dimensionButtons.race:Click() end
        if name == "honor-classes" then f.dimensionButtons.class:Click() end
        if name == "honor-zones" or name == "honor-subzones" then f.dimensionButtons.zone:Click() end
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
        return f
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
