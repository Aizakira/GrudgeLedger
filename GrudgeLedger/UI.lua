-- Grudge Ledger: a single journal, explicit relations and optional notes.
local GL = GrudgeLedger
local L = GL.L
local ledger, noteWindow, settingsWindow, minimapButton, guildWindow
local correctionWindow, diagnosticWindow
local statisticsWindow, journalWindow, guideWindow, honorBook
local showSettings, inspectEvent
local selectedKey, filter, offset = nil, "all", 0
local factionFilter = "all"
local tagFilter = "all"
local notesOnly = false
local listSort, listDetail = "recent", "seen"
local sortChoices = { { "recent", L("Dernière interaction") }, { "name", L("Nom") }, { "reputation", L("Réputation") }, { "kills", L("Victoires") }, { "deaths", L("Morts") }, { "encounters", L("Nb de rencontres") } }
local detailChoices = { { "seen", L("Présence") }, { "identity", L("Identité") }, { "guild", L("Guilde") }, { "pvp", L("JcJ") }, { "notes", L("Notes") } }
local drafts = {}
local guildDrafts = {}
local relationNames = { friend = L("Ami"), warning = L("Méfiance"), enemy = L("Ennemi"), neutral = L("Neutre") }
local factionNames = { Alliance = GL.Clean(FACTION_ALLIANCE, "string") or L("Alliance"),
    Horde = GL.Clean(FACTION_HORDE, "string") or L("Horde"), Neutral = L("Neutre") }
local colors = { friend = { 0.48, 0.86, 0.56 }, warning = { 0.97, 0.76, 0.39 }, enemy = { 0.98, 0.55, 0.50 }, neutral = { 0.79, 0.74, 0.65 } }
local inkColors = { friend = { 0.10, 0.34, 0.15 }, warning = { 0.50, 0.22, 0.03 }, enemy = { 0.57, 0.12, 0.11 }, neutral = { 0.34, 0.27, 0.20 } }
local relationIcons = { friend = "RelationFriend", warning = "RelationWarning", enemy = "RelationEnemy", neutral = "RelationNeutral" }
local referenceRelationIcons = { warning = "JournalReferenceEye" }
local referenceFactionIcons = { Horde = "JournalReferenceHorde", Alliance = "JournalReferenceAlliance" }
-- A thin red outline inside an opinion button: the relation the addon computed, not one you chose.
local function suggestedOutline(control, shown)
    if not control.outline then
        if not shown then return end
        control.outline = {}
        for _, side in ipairs({ { "TOPLEFT", 3, -2, "TOPRIGHT", -3, -2, nil, 2 }, { "BOTTOMLEFT", 3, 2, "BOTTOMRIGHT", -3, 2, nil, 2 },
            { "TOPLEFT", 2, -3, "BOTTOMLEFT", 2, 3, 2 }, { "TOPRIGHT", -2, -3, "BOTTOMRIGHT", -2, 3, 2 } }) do
            local line = control:CreateTexture(nil, "OVERLAY")
            line:SetColorTexture(0.62, 0.12, 0.09, 0.9)
            line:SetPoint(side[1], side[2], side[3]) line:SetPoint(side[4], side[5], side[6])
            if side[7] then line:SetWidth(side[7]) else line:SetHeight(side[8]) end
            control.outline[#control.outline + 1] = line
        end
    end
    for _, line in ipairs(control.outline) do if shown then line:Show() else line:Hide() end end
end
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
    local profile = GL.ArmoryProfile(record)
    local public = profile and profile.identity
    return factionNames[record.faction] or (public and public.faction) or L("Faction inconnue"),
        raceLabel(record.race, record.raceName or (public and public.race), record.raceID),
        classLabel(record.class or (public and public.classFile), record.className or (public and public.class), record.sex)
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
    if not class then
        local profile = GL.ArmoryProfile(record)
        class = profile and profile.identity and profile.identity.classFile
    end
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
-- Only a capture from the game identifies the face when the unit is gone.
local spareFaces = {}
-- The list and detail pane can show the same person at once. Native portrait
-- textures cannot be copied after the unit disappears, so paint two while visible.
local function observeFace(unit, refresh)
    if not unit or not SetPortraitTexture then return end
    local guid = GL.Clean(GL.Safe(UnitGUID, unit), "string")
    if not guid or not guid:match("^Player%-") or not visibleGUID(unit, guid)
        or not GL.Get("guid:" .. guid) or (IsUnitModelReadyForUI and not GL.Safe(IsUnitModelReadyForUI, unit)) then return end
    if GL.QueueNativePortrait then GL.QueueNativePortrait(unit,guid) end
    if refresh then
        for row in pairs(portraitRows) do
            if row.livePortraitGUID == guid then pcall(SetPortraitTexture, row.raceIcon, unit, true) end
        end
    end
    local count = 0
    for _, saved in ipairs(spareFaces) do
        if saved.guid == guid then
            count = count + 1
            if refresh then pcall(SetPortraitTexture, saved.face, unit, true) end
            if count >= 2 and not refresh then return end
        end
    end
    for _ = count + 1, 2 do
        local index
        if #spareFaces >= 64 then
            for i, old in ipairs(spareFaces) do if old.guid ~= guid then index = i break end end
        end
        local saved = index and table.remove(spareFaces, index) or {face = portraitFrames:CreateTexture(nil, "ARTWORK")}
        saved.face:Hide()
        saved.guid = pcall(SetPortraitTexture, saved.face, unit, true) and guid or nil
        spareFaces[#spareFaces + 1] = saved
        if not saved.guid then return end
    end
end
GL.ObservePortrait = observeFace
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

-- Reconstruct only from the selected record's in-game items. The viewer uses
-- this same textured mannequin, whose facial features are approximate.
local function animatedHead(row, record, unit, refreshUnit)
    local profile = GL.ArmoryProfile(record)
    local display = GL.MannequinDisplay and GL.MannequinDisplay(record, profile and profile.identity)
    if not unit and not display then
        if row.headshot then row.headshot:Hide() end
        return
    end
    local inspection = GL.DossierInspection and GL.DossierInspection(record) or record.inspection
    local updated = tonumber(profile and profile.updated) or 0
    if updated >= 100000000000 then updated = updated / 1000 end
    local gear = inspection and (tonumber(inspection.gearAt) or 0) >= updated and inspection.gear
    local function piece(slot, index)
        if gear and (gear[index] or not inspection.partialGear) then return gear[index] end
        local item = GL.ArmoryItem(record, slot)
        if not item and slot == "shoulder" then item = GL.ArmoryItem(record, "shoulders") end
        return type(item) == "table" and (item.ref or (item.id and ("item:" .. item.id))) or nil
    end
    local head, shoulders = piece("head", 1), piece("shoulder", 3)
    local model = row.headshot
    if not model then
        model = CreateFrame("DressUpModel", nil, row)
        row.headshot = model
        model:SetAllPoints(row.faceAnchor or row.raceIcon)
        model:EnableMouse(false)
        GL.Safe(model.SetKeepModelOnHide, model, true)
        if model.SetMouseMotionEnabled and model.SetMouseClickEnabled then
            model:SetMouseMotionEnabled(true)
            model:SetMouseClickEnabled(false)
            model:SetScript("OnEnter", function(self)
                if (row.liveModelPortrait or row.reconstructedPortrait) and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(row.liveModelPortrait and L("Portrait actuel du joueur") or L("Aperçu reconstitué en jeu"))
                    GameTooltip:Show()
                end
            end)
            model:SetScript("OnLeave", function(self)
                if GameTooltip and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
            end)
        end
        local function finish()
            if not model.active or (model:GetModelFileID() or 0) == 0 then return end
            if model.unit then
                if not visibleGUID(model.unit, model.guid) then
                    model:SetAlpha(0)
                    row.raceIcon:SetAlpha(1)
                    row.liveModelPortrait = nil
                    return
                end
                model:SetPortraitZoom(1)
                model:SetAlpha(1)
                row.raceIcon:SetAlpha(0)
                row.liveModelPortrait = true
                return
            end
            if model:GetDisplayInfo() ~= model.display then return end
            if not model.dressed then
                model:Undress()
                model.dressed = true
                for _, link in pairs(model.outfit) do
                    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
                    if itemID and C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
                        if not model.pending[itemID] then
                            model.pending[itemID] = true
                            GL.Safe(C_Item.RequestLoadItemDataByID, itemID)
                        end
                    elseif itemID then
                        GL.Safe(model.TryOn, model, link)
                    end
                end
                model:SetPortraitZoom(1)
            end
            model:SetAlpha(1)
            row.raceIcon:SetAlpha(0)
            row.reconstructedPortrait = true
        end
        model.finish = finish
        model:SetScript("OnModelLoaded", finish)
        model:SetScript("OnEvent", function(_, _, id, success)
            if model.pending and model.pending[id] then
                if success then
                    model.pending[id] = nil
                    model.dressed = nil
                    finish()
                elseif model.pending[id] == true and C_Timer and C_Timer.After then
                    local pending = model.pending
                    pending[id] = "retry"
                    C_Timer.After(1, function()
                        if model.active and model.pending == pending and pending[id] then
                            GL.Safe(C_Item.RequestLoadItemDataByID, id)
                        end
                    end)
                end
            end
        end)
        GL.Safe(model.RegisterEvent, model, "GET_ITEM_INFO_RECEIVED")
        GL.Safe(model.RegisterEvent, model, "ITEM_DATA_LOAD_RESULT")
    end
    if not (model.ClearModel and model.GetModelFileID and model.SetPortraitZoom) then return end
    model:Show()
    if unit and visibleGUID(unit, record.guid) and model.SetUnit
        and (not IsUnitModelReadyForUI or GL.Safe(IsUnitModelReadyForUI, unit)) then
        if refreshUnit or model.unit ~= unit or model.guid ~= record.guid then
            model.active, model.display, model.unit, model.guid, model.pending = nil, nil, nil, nil, nil
            model:SetAlpha(0)
            model:ClearModel()
            local ok, loaded = pcall(model.SetUnit, model, unit, false)
            if ok and loaded ~= false then model.unit, model.guid = unit, record.guid end
        end
        if model.unit then
            model.active = true
            model.finish()
            return
        end
    end
    model.unit, model.guid = nil, nil
    if not display or not (model.SetDisplayInfo and model.GetDisplayInfo and model.TryOn and model.Undress) then
        model:Hide()
        return
    end
    if model.display ~= display or not model.outfit or model.outfit[1] ~= head or model.outfit[3] ~= shoulders then
        model.outfit, model.pending, model.dressed = {[1]=head, [3]=shoulders}, {}, nil
    end
    if model.display ~= display then
        model:SetAlpha(0)
        model:ClearModel()
        model.display = display
        model.active = true
        model:SetDisplayInfo(display)
    end
    model.active = true
    model.finish()
end

local function paintStaticPortrait(row, record, unit)
    local guid = GL.Clean(record.guid, "string")
    row.raceIcon:SetAlpha(1)
    row.reconstructedPortrait, row.liveModelPortrait = nil, nil
    if row.headshot then row.headshot.active = nil end
    local known = guid and row.livePortraitGUID == guid
    if guid and not known and not unit then
        for _, saved in ipairs(spareFaces) do
            if saved.guid == guid then known = true break end
        end
        if not known then
            -- A hidden page can lend its native texture once the unit has disappeared.
            for owner in pairs(portraitRows) do
                if owner.livePortraitGUID == guid and not owner.raceIcon:IsVisible() then
                    usePortrait(owner, nil)
                    known = true
                    break
                end
            end
        end
    end
    local face = usePortrait(row, (unit or known) and guid or nil)
    row.portraitUnit, row.archivedPortrait = nil, nil
    face:SetAlpha(1)
    face:SetTexCoord(0, 1, 0, 1)
    row.classIcon:SetTexCoord(0, 1, 0, 1)
    row.classIcon:SetTexture(nil)
    row.classIcon:SetAlpha(classIcon(row.classIcon, record) and 1 or 0)
    if unit and (not IsUnitModelReadyForUI or GL.Safe(IsUnitModelReadyForUI, unit)) and pcall(SetPortraitTexture, face, unit, true) then
        if GL.QueueNativePortrait and GL.Get(record) then GL.QueueNativePortrait(unit,guid) end
        row.livePortraitGUID = record.guid
        row.portraitUnit = unit
        return
    end
    if guid and row.livePortraitGUID == guid then return end
    face = usePortrait(row, nil)
    if guid and guid:match("^Player%-%d+%-%x+$") and
        ((type(GrudgeLedgerNativePortraits) == "table" and GrudgeLedgerNativePortraits[guid] == true)
        or (type(GrudgeLedgerPortraitIndex) == "table" and GrudgeLedgerPortraitIndex[guid] == "native")) then
        face:SetTexture("Interface\\AddOns\\GrudgeLedgerPortraits\\" .. guid .. "-native")
        row.archivedPortrait = "native"
        return
    end
    face:SetTexture(GL.icon)
end

local function paintPortrait(row, record, unit, refreshUnit)
    row.modelWantedUnit = unit
    paintStaticPortrait(row, record, unit)
    animatedHead(row, record, unit, refreshUnit)
end

-- The animated head is a child frame: it would cover the row's own textures. The gold frame,
-- the class icon and the level medallion live on an overlay kept above it (owner report, 0.30.0).
-- Every portrait wears the same frame and faction backdrop as the Journal's list, in the books and
-- in the dialogs (owner request, 23/11).
local function portraitOverlay(row)
    row.referenceSkin = true
    local overlay = row.portraitOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, row)
        row.portraitOverlay = overlay
        overlay:SetAllPoints(row)
        local anchor = row.faceAnchor or row.raceIcon
        if row.portraitRim then
            GL.Safe(row.portraitRim.SetParent, row.portraitRim, overlay)
            row.portraitRim:SetTexture(media .. "JournalReferencePortrait")
        else
            row.portraitRim = overlay:CreateTexture(nil, "ARTWORK")
            row.portraitRim:SetPoint("TOPLEFT", anchor, "TOPLEFT", -3, 3)
            row.portraitRim:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 3, -3)
            row.portraitRim:SetTexture(media .. "JournalReferencePortrait")
        end
        GL.Safe(row.classIcon.SetParent, row.classIcon, overlay)
    end
    local base = row.headshot or row
    local level = (GL.Safe(base.GetFrameLevel, base) or 1) + 2
    GL.Safe(overlay.SetFrameLevel, overlay, level)
    if row.levelBadge then GL.Safe(row.levelBadge.SetFrameLevel, row.levelBadge, level + 1) end
    -- No frame without a face: the compact list hides its portraits.
    if row.raceIcon:IsShown() then overlay:Show() else overlay:Hide() end
    -- Hiding the face (showIf) hides its frame too.
    row.raceIcon.portraitOverlay = overlay
    if row.faceAnchor then row.faceAnchor.portraitOverlay = overlay end
end
local portraitBackdrops = { Horde = "JournalPortraitHorde", Alliance = "JournalPortraitAlliance" }
local function portraitBackdrop(row, record)
    if not row.referenceSkin then return end
    local back = row.portraitBack
    if not back then
        back = row:CreateTexture(nil, "ARTWORK", nil, -8)
        row.portraitBack = back
        back:SetAllPoints(row.faceAnchor or row.raceIcon)
    end
    local profile = GL.ArmoryProfile(record)
    local public = profile and profile.identity
    local texture = portraitBackdrops[record.faction or (public and public.faction)]
    if texture then back:SetTexture(media .. texture) end
    local overlay = row.portraitOverlay
    if texture and row.raceIcon:IsShown() and (not overlay or overlay:IsShown()) then back:Show() else back:Hide() end
end
local function identityIcons(row, record)
    row.classIcon:SetDrawLayer("OVERLAY")
    portraitRows[row] = record
    paintPortrait(row, record, portraitUnit(record))
    portraitOverlay(row)
    portraitBackdrop(row, record)
end

-- ponytail: the client paints a live texture, not a serializable image. Refresh
-- only visible journal slots, once per event burst, regardless of contact count.
local redrawPortraits
local function refreshPortraits(frame)
    frame:SetScript("OnUpdate", nil)
    for row, record in pairs(portraitRows) do
        if row.raceIcon:IsVisible() then
            local unit = portraitUnit(record)
            if unit ~= row.modelWantedUnit or unit ~= row.portraitUnit or (unit and redrawPortraits) then paintPortrait(row, record, unit, redrawPortraits) end
        end
    end
    redrawPortraits = nil
end
portraitFrames:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
        observeFace(unit, true)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        observeFace("focus")
    end
    if not ((ledger and ledger:IsShown()) or (statisticsWindow and statisticsWindow:IsShown())
        or (journalWindow and journalWindow:IsVisible()) or (correctionWindow and correctionWindow:IsShown())
        or (GrudgeLedgerPlayerDossier and GrudgeLedgerPlayerDossier:IsShown()) or (GrudgeLedgerBounties and GrudgeLedgerBounties:IsShown())) then return end
    if event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" or event == "PORTRAITS_UPDATED" then redrawPortraits = true end
    self:SetScript("OnUpdate", refreshPortraits)
end)
for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "PORTRAITS_UPDATED", "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "GROUP_ROSTER_UPDATE", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE", "PLAYER_ENTERING_WORLD" }) do
    GL.Safe(portraitFrames.RegisterEvent, portraitFrames, event)
end
local function subdued(text) return "|cff5c4029" .. text .. "|r" end
GL.PaintBookPortrait = identityIcons
GL.VisiblePortraitUnit = portraitUnit
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
    if type(c.playerLevel) == "number" and type(c.opponentLevel) == "number" then
        local difference = c.opponentLevel - c.playerLevel
        local levels = L("Niveaux : vous ") .. c.playerLevel .. L(", adversaire ") .. c.opponentLevel
        parts[#parts + 1] = levels .. (difference ~= 0 and (" (%+d)"):format(difference) or "")
    elseif type(c.opponentLevel) == "number" then parts[#parts + 1] = L("Adversaire de niveau ") .. c.opponentLevel
    elseif type(c.playerLevel) == "number" then parts[#parts + 1] = L("Votre niveau : %d"):format(c.playerLevel) end
    if c.pet then parts[#parts + 1] = L("Familier impliqué") end
    if type(c.opponents) == "number" and c.opponents > (compact and 1 or 0) then
        parts[#parts + 1] = counted(c.opponents, "adversaire observé", "adversaires observés")
    end
    if c.pve then parts[#parts + 1] = compact and L("Monstre engagé") or L("Monstre engagé pendant le combat") end
    if type(c.healthPct) == "number" then parts[#parts + 1] = (compact and L("Vie au premier signal : ") or L("Votre vie au premier signal JcJ : ")) .. c.healthPct .. " %" end
    if #parts > 0 then return table.concat(parts, compact and " · " or "\n", 1, compact and math.min(2, #parts) or #parts) end
end
local function realmLabel(realm)
    local region, shard, rules = (realm or ""):match("^CAMWOW%s*([%u]+%d*)%s*Realm%s*(%d+)%s*(%a*)$")
    if region then
        local area, group = region:match("^(%a+)(%d*)$")
        local mode = ({pvp = L("Joueur contre joueur"), pve = L("Joueur contre environnement")})[rules:lower()] or rules
        local label = L("Royaume %s"):format(shard) .. (mode ~= "" and " · " .. mode or "")
        return label .. " · " .. (area == "EU" and L("Europe") or area) .. (group ~= "" and " " .. group or "")
    end
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
    -- Everyone who hit you during your death killed you, as in the scores; the killing blow is a detail.
    if event.kind == "death" then
        if event.evidence == "Le familier de ce joueur vous a porté le coup fatal." then return L("Vous a tué · coup fatal de son familier") end
        if event.killingBlow or event.evidence == "Dégâts létaux explicitement attribués à ce joueur." then return L("Vous a tué · coup fatal") end
        if event.killingBlow == false or event.evidence == "Participation à l’attaque ayant causé votre mort." then return L("Vous a tué · avec d'autres joueurs") end
        return L("Vous a tué")
    end
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
    if event.kind == "assist" then return L("Coup de main : d’autres l’ont achevé") end
    return event.kind == "note" and L("Vous avez ajouté une note") or L("Événement enregistré")
end
local activeBook
local function showBook(frame)
    if activeBook and activeBook ~= frame then activeBook:Hide() end
    activeBook = frame
    for _, page in pairs({ ledger, statisticsWindow, honorBook, settingsWindow }) do
        if page ~= frame then page:Hide() end
    end
    if guideWindow then guideWindow:Hide() end
    frame:Show()
    frame:Raise()
end

-- The Primes tab of every book counts the bounties you still have to pay, as "Filtres · n" counts
-- the filters (0.58.4).
local bountyTabs = {}
function GL.PaintBountyReminder()
    local due = GL.bountyDue
    local n = due and due.count or 0
    for _, b in ipairs(bountyTabs) do
        b.caption:SetText(n > 0 and L("Primes · %d"):format(n) or L("Primes"))
    end
end
local function bookNavigation(f, selected)
    f.navigation = {}
    for i, entry in ipairs({
        { "ledger", L("Journal"), function() GL.ShowLedger() end },
        { "players", L("Relations"), function() GL.ShowRelations() end },
        { "guild", L("Guilde"), function() GL.ShowGuild() end },
        { "bounties", L("Primes"), function() GL.OpenBounties() end },
    }) do
        -- Same place and size on every page, the Journal included: the tabs must not jump (owner, 23/11).
        local b = button(f, entry[2], 72 + (i - 1) * 208, -96, 192, entry[3], true)
        b:SetHeight(38)
        journalFont(b.caption, "GameFontNormalLarge", 19)
        b.caption:SetHeight(32)
        f.navigation[entry[1]] = b
        if f.referenceSkin then
            b.selectionTexture = "JournalReferenceTabActive"
            b.skin:SetTexture(media .. "JournalReferenceTab")
        end
        UI.selectButton(b, entry[1] == selected)
        if f.referenceSkin then b.selection:SetTexture(media .. "JournalReferenceTabActive") end
        if entry[1] == "bounties" then bountyTabs[#bountyTabs + 1] = b end
    end
    GL.PaintBountyReminder()
    -- On the close button's line, just left of it (owner 23/11): same centre height (-35), and 30 instead of 32
    -- because the gear's frame fills more of its texture than the cross does; both then look the same size.
    f.settingsButton = UI.iconButton(f, "JournalSettings", L("Réglages et aide"), 880, -20, 30, showSettings)
    if selected == "settings" then f.settingsButton:LockHighlight() end
end

local function currentRecord() return selectedKey and GL.Get(selectedKey) end
GL.SetupBookNavigation, GL.ShowBookPage = bookNavigation, showBook
local function activeBounty(guid)
    if not guid or not GL.Bounties then return end
    return GL.Bounties.OpenFor and GL.Bounties.OpenFor(guid)
end
function GL.ContactBountyMode(record)
    if not record or not record.guid or not GL.Bounties then return end
    if activeBounty(record.guid) then return "view" end
    if GL.BountyTargetEligible(record) then return "create" end
    local history=GL.db and GL.db.bountyHistory
    for _,order in pairs(history and history[GL.Safe(UnitGUID,"player")] or {}) do
        if order.target==record.guid then return "view" end
    end
end
function GL.OpenContactBounty(guid)
    if not guid then return end
    local mode=GL.ContactBountyMode(GL.Get("guid:"..guid) or {guid=guid})
    if mode then return GL.OpenBounties(guid,mode) end
end
local refresh

local function selectedRealm(f)
    local text = f.realm:GetText()
    return f.realmId and text == realmLabel(f.realmId) and f.realmId or text
end
local function selectRealm(f, realm)
    f.realmId = realm
    f.realm:SetText(realm and realmLabel(realm) or "")
end
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
            row.bg:SetAlpha(f.name:GetText() == rule.name and selectedRealm(f) == rule.realm and 1 or 0.2)
            row:Show()
        else row.rule = nil row:Hide() end
    end
    f.total:SetText(counted(#rules, "guilde enregistrée", "guildes enregistrées"))
    if #rules == 0 then f.empty:Show() else f.empty:Hide() end
    f.previous:SetEnabled(f.offset > 0)
    f.next:SetEnabled(f.offset + 9 < #rules)
    local current = GL.GetGuildRule(f.name:GetText(), selectedRealm(f))
    local key = guildDraftKey(f.name:GetText(), selectedRealm(f))
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
        f.empty = label(f, L("Aucune guilde enregistrée.\n\nSaisissez son nom exact à droite ou utilisez la guilde de votre cible."), nil, 23, -119, 230)
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
            local rule = GL.SetGuildReaction(f.name:GetText(), reaction, f.note:GetText(), selectedRealm(f))
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
            local rule = GL.GetGuildRule(f.name:GetText(), selectedRealm(f))
            save(rule and rule.reaction or "neutral")
        end)
        button(f, L("Guilde de la cible"), 288, -426, 343, function()
            local target = GL.Identity("target")
            if not target or not target.guild then f.status:SetText(L("Sélectionnez un joueur dont la guilde est connue.")) return end
            GL.ShowGuilds(target)
        end)
        selectRealm(f, GL.Clean(GL.Safe(GetRealmName), "string"))
    end
    if identity and identity.guild then
        guildWindow.changingIdentity = true
        guildWindow.name:SetText(identity.guild)
        selectRealm(guildWindow, identity.realm or GL.Clean(GL.Safe(GetRealmName), "string"))
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
    -- A portrait takes its frame, class icon and medallion with it.
    local overlay = region.portraitOverlay
    if overlay then
        if visible then overlay:Show() else overlay:Hide() end
    end
end
-- The four-column texture follows the display order in GL.TagChoices.
local function journalTags(parent, record, compact)
    local header = parent == ledger
    local strip = parent.tagStrip
    if not GL.HasTag or not GL.HasTag(record) then
        if strip then strip.record = nil strip:Hide() end
        return 0
    end
    if not strip then
        strip = CreateFrame("Frame", nil, parent)
        parent.tagStrip, strip.icons = strip, {}
        strip.caption = label(strip, "", nil, 0, 0)
        journalFont(strip.caption, "GameFontNormalLarge", header and 13 or 11)
        GL.Safe(strip.caption.SetJustifyV, strip.caption, "MIDDLE")
        strip.caption:SetTextColor(unpack(header and theme.ink or theme.brass))
        strip:EnableMouse(header)
        if header then
            strip:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L("Étiquettes personnelles"))
                for i, choice in ipairs(GL.TagChoices) do
                    if GL.HasTag(self.record, choice[1]) then
                        local x, y = ((i-1)%4)*64, math.floor((i-1)/4)*64
                        local glyph = ("|T%sJournalTags:16:16:0:0:256:128:%d:%d:%d:%d|t"):format(media, x, x+64, y, y+64)
                        GameTooltip:AddLine(glyph .. " " .. L(choice[2]), 1, 1, 1)
                    end
                end
                GameTooltip:Show()
            end)
            strip:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
    local size = header and 24 or 18
    local limit = header and #GL.TagChoices or (compact and 1 or 3)
    local count, shown, width, single = 0, 0, 0
    for i, choice in ipairs(GL.TagChoices) do
        if GL.HasTag(record, choice[1]) then
            count, single = count + 1, L(choice[2])
            if shown < limit then
                shown = shown + 1
                local icon = strip.icons[shown]
                if not icon then
                    icon = bookIcon(strip, width, 0, size, media .. "JournalTags")
                    strip.icons[shown] = icon
                end
                local col, row = (i-1)%4, math.floor((i-1)/4)
                icon:SetTexCoord(col/4, (col+1)/4, row/2, (row+1)/2)
                icon:Show()
                width = width + size + 2
            end
        end
    end
    for i = shown+1, #strip.icons do strip.icons[i]:Hide() end
    local caption = count > shown and ("+" .. (count-shown)) or (count == 1 and not compact and single) or ""
    strip.caption:SetText(caption)
    local textWidth = math.ceil(GL.Safe(strip.caption.GetStringWidth, strip.caption) or #caption*8)
    local withText = caption ~= "" and (header or textWidth <= 65)
    showIf(strip.caption, withText)
    if withText then
        moveTo(strip.caption, width, 0)
        strip.caption:SetHeight(size)
        width = width + textWidth + 2
    end
    strip:SetSize(width, size)
    moveTo(strip, (header and 895 or (compact and 229 or 301)) - width, header and 218 or (compact and 6 or 26))
    strip.record = record
    strip:Show()
    return width
end
local encounterHelp = L("Une rencontre recommence après plus de 10 min sans observation. Le total inclut les rencontres avant le changement d'avis ; les anciens passages ne sont pas reconstitués.")
local recentHelp = L("Dernière observation enregistrée, tous vos personnages confondus. Une personne vue récemment n'est pas forcément encore à proximité.")
local confirmedHelp = L("Mon bilan PvP")
local statisticsChoices = {
    players = {
        { name = L("Menaces"), entries = {
            { "grudge", L("Rancunes les plus fortes"), L("Vos ennemis et les personnes à surveiller, selon leur solde négatif actuel."), "point", L("Solde actuel"), L("Les rancunes restent tenaces : une mort pèse bien plus qu’une victoire. Un avis manuel ou de guilde peut aussi signaler un danger sans solde négatif.") },
            { "enemiesSeen", L("Menaces les plus recroisées"), L("Celles que vous avez rencontrées le plus souvent."), "rencontre", L("Rencontres"), encounterHelp },
            { "enemiesRecent", L("Menaces vues récemment"), L("Vos ennemis et les personnes à surveiller, du plus récemment aperçu au plus ancien."), "date", L("Dernière observation"), recentHelp },
            { "aggressions", L("Le plus d'agressions"), L("Les joueurs avec le plus d'agressions enregistrées à votre encontre."), "agression", L("Agressions"), L("Nombre d'épisodes enregistrés, pas de coups reçus ni de fréquence horaire.") },
        } },
        { name = L("Amis"), entries = {
            { "friendsSeen", L("Amis les plus recroisés"), L("Vos amis actuels que vous avez rencontrés le plus souvent."), "rencontre", L("Rencontres"), encounterHelp },
            { "reputation", L("Affinités les plus fortes"), L("Vos amis classés selon leur solde positif actuel."), "point", L("Solde actuel"), L("Les avis, les gestes et les faits PvP alimentent le solde. Un ami désigné par un avis de guilde peut avoir un solde nul.") },
            { "friendsRecent", L("Amis vus récemment"), L("Vos amis actuels, du plus récemment aperçu au plus ancien."), "date", L("Dernière observation"), recentHelp },
            { "friendsGrouped", L("Compagnons de groupe"), L("Les amis actuels avec lesquels vous avez partagé le plus de sessions de groupe."), "session", L("Sessions partagées"), L("Ouvrez la fiche pour lire la durée en ligne des sessions mesurées. Partager un groupe ne rend personne ami automatiquement.") },
            { "friendsOnline", L("Temps passé en groupe"), L("Les amis avec lesquels vous avez passé le plus de temps en groupe, tous deux en ligne."), "durée", L("Temps en groupe"), L("Les durées commencent lorsque le suivi observe les deux joueurs connectés. Les anciennes sessions et les champs de bataille sont exclus du calcul.") },
        } },
        { name = L("Combats"), entries = {
            { "deaths", L("Morts par adversaire"), L("Nombre de vos morts auxquelles chaque adversaire a participé."), "mort", L("Morts"), L("Plusieurs adversaires peuvent participer au même combat. Le coup fatal est indiqué lorsqu’il est connu.") },
            { "kills", L("Adversaires les plus vaincus"), L("Les joueurs contre lesquels vous avez le plus de victoires."), "victoire", L("Victoires"), confirmedHelp },
        } },
    },
    guilds = {
        { name = L("Relations"), entries = {
            { "grudges", L("Le plus de rancunes"), L("Guildes réunissant le plus de membres avec une rancune personnelle."), "rancune", L("Rancunes personnelles"), L("Dernière guilde connue des personnes de votre livre. Un avis global sur une guilde ne crée pas artificiellement des rancunes personnelles.") },
            { "friends", L("Le plus d'amis"), L("Guildes réunissant le plus de membres que vous appréciez personnellement."), "ami", L("Amis personnels"), L("Dernière guilde connue des personnes de votre livre. Les relations héritées d'un avis global sur la guilde ne gonflent pas ce total.") },
        } },
        { name = L("Combats"), entries = {
            { "deaths", L("Morts par guilde adverse"), L("Morts, rattachées à la guilde connue au moment des faits."), "mort", L("Morts"), L("Une même mort n'est comptée qu'une fois par guilde impliquée. Les faits sans guilde connue restent non attribués.") },
            { "kills", L("Guildes les plus vaincues"), L("Victoires contre les membres de ces guildes."), "victoire", L("Victoires"), L("Guilde mémorisée au moment du combat.") },
            { "aggressions", L("Le plus d'agressions"), L("Agressions attribuées aux membres de ces guildes."), "agression", L("Agressions"), L("Guilde mémorisée lors des faits. Plusieurs membres peuvent participer à un même épisode ; les faits sans guilde restent non attribués.") },
        } },
        { name = L("Mes règles"), entries = {
            { "rules", L("Mes règles de guilde"), L("Les avis de guilde que vous avez enregistrés, par ordre alphabétique."), "avis", L("Avis de guilde"), L("Les avis individuels restent prioritaires. La fiche indique les exceptions à la règle choisie.") },
        } },
    },
}
-- The Relations book draws the same rankings on its own page: same choices, same wording of a value.
GL.RankingChoices, GL.RelationNames, GL.RelationInks, GL.RealmLabel = statisticsChoices, relationNames, inkColors, realmLabel
function GL.RankingValueText(choice, value)
    if choice[4] == "date" then return date("%d/%m/%y %H:%M", value) end
    if choice[4] == "durée" then return groupDurationText(value) end
    return (choice[1] == "grudge" and "−" or choice[1] == "reputation" and "+" or "") .. tostring(value)
end
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
    f.heading:SetText(choice[2])
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
    for i, tab in ipairs(f.sections) do
        UI.selectButton(tab, i == (guild and #f.sections or f.category))
    end
    if guild then f.factionButton:Hide() else f.factionButton:Show() end
    f.factionButton:SetText(f.faction == "all" and L("Toutes les factions") or factionNames[f.faction] or L("Faction inconnue"))
    f.manage:SetText(guild and L("Gérer les avis de guilde") or L("Mon bilan PvP"))
    for mode, panels in pairs(f.filters) do
        for i, panel in ipairs(panels) do
            local visible = mode == f.mode and (guild or i == f.category)
            showIf(panel, visible)
            if visible then
                for j, control in ipairs(panel.choices) do
                    UI.selectButton(control, i == f.category and j == f.choice)
                end
            end
        end
    end
    moveTo(f.helpHeading, 36, guild and 495 or 433)
    moveTo(f.footnote, 36, guild and 522 or 462)
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
    f.empty:SetText(#rows == 0 and (L("Aucun résultat dans cette sélection.\n\n") .. emptyHelp .. (not guild and f.faction ~= "all" and L("\nEssayez aussi « Toutes les factions ».") or "")) or "")
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
        or L("Cliquez sur une personne pour lire son histoire."))
    f.footnote:SetText(choice[6])
end
-- Relations opens on its own book (Relations.lua); without it, on the rankings as before.
-- The guild's book (Relations.lua), opened where it was left.
function GL.ShowGuild(page)
    if not GL.RelationsPages then return GL.ShowStatistics("guilds") end
    return GL.RelationsPages.OpenGuild(page)
end
function GL.ShowRelations(page)
    if not GL.RelationsPages then return GL.ShowStatistics() end
    return GL.RelationsPages.Open(page)
end
function GL.ShowStatistics(mode, category)
    if not GL.db then return end
    -- The rankings live in the Relations book (/gl stats, /gl guildes). This old wide window only
    -- serves when Relations.lua is not loaded, as in the tests that load the addon without it.
    if GL.RelationsPages then return GL.RelationsPages.OpenRankings(mode == "guilds") end
    mode = mode or (statisticsWindow and statisticsWindow.mode)
    mode = mode == "guilds" and "guilds" or "players"
    if not statisticsChoices[mode][category] then category = nil end
    if not statisticsWindow then
        local f = bookWindow("GrudgeLedgerStatistics", "Grudge Ledger")
        statisticsWindow = f
        f.rows, f.sections, f.filters, f.guildActions = {}, {}, {}, {}
        bookNavigation(f, "players")
        f.backToStory = button(f, "‹ " .. L("Relations"), 36, -157, 274, function() GL.ShowRelations() end)
        f.backToStory:SetHeight(30)
        local playerGroups = statisticsChoices.players
        for i = 1, #playerGroups + 1 do
            local group = playerGroups[i]
            local tab = button(f, group and group.name or L("Guildes"), 36 + ((i - 1) % 2) * 140,
                -192 - math.floor((i - 1) / 2) * 35, 134, function()
                    GL.ShowStatistics(group and "players" or "guilds", group and i or nil)
                end, true)
            tab:SetHeight(30)
            tab.caption:SetWidth(126)
            journalFont(tab.caption, "GameFontNormalLarge", 14)
            f.sections[i] = tab
        end
        for scope, groups in pairs(statisticsChoices) do
            local y = 271
            f.filters[scope] = {}
            for i, group in ipairs(groups) do
                local panel = CreateFrame("Frame", nil, f)
                f.filters[scope][i] = panel
                panel.choices = {}
                panel:SetPoint("TOPLEFT", 36, -y)
                local offset = 0
                if scope == "guilds" and #group.entries > 1 then
                    bookText(panel, 2, 0, 260, 20, 13, group.name, theme.paper)
                    offset = 22
                end
                for j, entry in ipairs(group.entries) do
                    local control = button(panel, entry[2], 0, -offset, 274, function()
                        f.category, f.choice, f.offset, f.selected = i, j, 0, nil
                        refreshStatistics()
                    end, true)
                    control.skin:Hide()
                    journalFont(control.caption, "GameFontHighlight", 13)
                    control.caption:SetWidth(258)
                    control.caption:SetJustifyH("LEFT")
                    control:SetScript("OnEnter", function(self)
                        if self.caption.IsTruncated and self.caption:IsTruncated() then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetText(self:GetText())
                            GameTooltip:Show()
                        end
                    end)
                    control:SetScript("OnLeave", function(self)
                        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
                    end)
                    control.metric = entry[1]
                    panel.choices[j] = control
                    offset = offset + 30
                end
                panel:SetSize(274, offset)
                if scope == "guilds" then y = y + offset + 8 end
            end
        end
        -- Below the longest list of rankings (the guild ones), which the story entries pushed down in 0.40.0.
        f.helpHeading = bookText(f, 36, 478, 256, 21, 13, L("Comment lire ce classement"), theme.paper)
        f.footnote = label(f, "", nil, 36, -504, 256)
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
    if f.mode ~= mode or (category and category ~= f.category) then
        f.mode, f.category, f.choice = mode, category or 1, (mode == "players" and not category) and 2 or 1
        f.offset, f.selected = 0, nil
    end
    f.faction = f.faction or "all"
    -- The way back to the Relations book, when it is loaded.
    if GL.RelationsPages then f.backToStory:Show() else f.backToStory:Hide() end
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
-- The detailed tables (owner, 23/11; audit briefs/audit-ui-tableaux-detailles.md): a page of the
-- Relations book, after the Bilan. Every filter sits at the top of the sheet, one kind of list and one
-- pager for every view, the figures of the selection in the key figures of the left column.
-- Sheet coordinates: 664 x 510 from the host's top left corner (window 240, 152); nothing below 490.
-- honorBook: the narrow book that carries the page when Relations.lua is not loaded (tests).
local HONOR_ROWS, ZONE_ROWS, CHRONICLE_ROWS = 6, 5, 5
local honorModes = {
    { "summary", L("Vue d’ensemble"), L("Votre tableau d’honneur") },
    { "history", L("Chronique"), L("La chronique de vos rencontres") },
    { "year", L("Mon année"), L("Une année de rencontres") },
    { "story", L("Récit"), L("Votre récit de campagne") },
}
local honorDimensions = { { "opponents", L("Adversaires") }, { "race", L("Par race") }, { "class", L("Par classe") },
    { "zone", L("Par zone") }, { "initiative", L("Initiative") } }
local function sheetText(parent, x, y, width, size, bold, color)
    local region = label(parent, "", nil, x, -y, width)
    journalFont(region, bold and "GameFontNormalLarge" or "GameFontHighlight", size)
    region:SetTextColor(unpack(color or theme.ink))
    GL.Safe(region.SetWordWrap, region, false)
    return region
end
-- A value that never leaves its box in any language: the font shrinks down to the smallest size.
local function fitText(region, text, width, biggest, smallest, bold)
    region:SetText(text or "")
    local size = biggest
    journalFont(region, bold and "GameFontNormalLarge" or "GameFontHighlight", size)
    while size > smallest and (GL.Safe(region.GetStringWidth, region) or 0) > width do
        size = size - 1
        journalFont(region, bold and "GameFontNormalLarge" or "GameFontHighlight", size)
    end
end
local function sheetRule(parent)
    local rule = parent:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT") rule:SetPoint("BOTTOMRIGHT") rule:SetHeight(1)
    rule:SetColorTexture(0.49, 0.32, 0.13, 0.32)
    return rule
end
local function sheetFace(parent, x, y, size)
    local face = CreateFrame("Frame", nil, parent)
    face:SetPoint("TOPLEFT", x, -y) face:SetSize(size, size)
    face.raceIcon = face:CreateTexture(nil, "ARTWORK") face.raceIcon:SetAllPoints()
    face.classIcon = face:CreateTexture(nil, "OVERLAY") face.classIcon:SetSize(16, 16) face.classIcon:SetPoint("BOTTOMRIGHT")
    return face
end
local function hoverHelp(control, title, text)
    control:HookScript("OnEnter", function(self)
        local body = type(text) == "function" and text() or text
        if not GameTooltip or not body or body == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title)
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
-- The periods turn on one button: all, 7 days, 30 days, then each year of the journal. "Mon année"
-- only turns through the years.
local function periodChoices(annual)
    local list = {}
    if not annual then
        for i = 1, 3 do list[#list + 1] = { journalPeriods[i][1], nil, journalPeriods[i][2] } end
    end
    for _, year in ipairs(GL.JournalYears()) do list[#list + 1] = { "year", year, L("Année : ") .. year } end
    if #list == 0 then list[1] = { "year", tonumber(date("%Y")), L("Année : ") .. date("%Y") } end
    return list
end
local function periodIndex(list, period, year)
    for i, entry in ipairs(list) do
        if entry[1] == period and (period ~= "year" or entry[2] == year) then return i end
    end
end
local function helpText(f)
    if f.mode == "history" then return L("Ouvrez les détails d’un événement. Validez la recherche avec Entrée.") end
    if f.mode == "year" then return L("Cette carte résume les faits PvP conservés pour l’année et les personnages choisis.") end
    if f.mode == "story" then return L("Choisissez une période et les personnages dont vous souhaitez relire les combats.") end
    return f.dimension == "opponents" and L("Vos morts et vos victoires, adversaire par adversaire. Cliquez sur un nom pour ouvrir sa fiche.")
        or f.dimension == "initiative" and L("La rancune est celle du journal avant le combat. Une revanche est une victoire que vous engagez après une mort contre ce joueur avec le même personnage.")
        or f.dimension == "zone" and L("Cliquez sur une zone pour lire ses sous-zones. Le temps mesure la présence en monde ouvert depuis l’activation, hors absences et instances.")
        or L("La race et la classe sont celles relevées au combat. « Inconnue » signifie que l'information manque.")
end

local function refreshJournal()
    local f = journalWindow
    if not f or not f:IsVisible() then return end
    local history, annual = f.mode == "history", f.mode == "year"
    local choices = periodChoices(annual)
    if annual and f.period ~= "year" then f.period = "year" end
    f.year = tonumber(f.year) or GL.JournalYears()[1] or tonumber(date("%Y"))
    local options = { period = f.period, year = f.year, scope = f.scope, kind = f.kind, query = f.query or "" }
    -- A year chosen elsewhere (the Bilan, an older card) may hold no fact yet: it is named all the same.
    local entry = f.period == "year" and { "year", f.year, f.year and (L("Année : ") .. f.year) or L("Année inconnue") }
        or choices[periodIndex(choices, f.period, f.year) or 1]
    f.periodButton:SetText(entry[3]) f.scopeButton:SetText(choiceLabel(journalScopes, f.scope))
    fitText(f.periodButton.caption, entry[3], 122, 12, 9)
    fitText(f.scopeButton.caption, choiceLabel(journalScopes, f.scope), 122, 12, 9)
    for _, mode in ipairs(honorModes) do
        UI.selectButton(f.tabs[mode[1]], mode[1] == f.mode)
        if mode[1] == f.mode then f.heading:SetText(mode[3]) end
    end
    for key, view in pairs(f.views) do showIf(view, key == f.mode) end
    local notices = {}
    local stats = GL.PersonalStatistics({ period = options.period, year = options.year, scope = options.scope, kind = "pvp", query = "" })
    f.stats = stats
    -- The key figures of the left column: the selection's victories, deaths, aggressions and honour.
    local function chronicle(kind, scope)
        return function()
            f.mode, f.kind, f.query, f.offset = "history", kind, "", 0
            if scope then f.scope = scope end
            f.search:SetText("") GL.ShowJournal("history")
        end
    end
    f.tallyLines = {
        { L("Victoires"), stats.kills, chronicle("pvp") }, { L("Morts"), stats.deaths, chronicle("pvp") },
        { L("Agressions"), stats.aggressions, chronicle("pvp") }, { L("Honneur reçu"), stats.honor or 0, chronicle("honor") },
        { L("Faits de combat"), stats.events or 0, chronicle("all") },
    }
    if (stats.unknownActorEvents or 0) > 0 then f.tallyLines[6] = { L("Sans auteur connu"), stats.unknownActorEvents, chronicle("all", "legacy") } end
    if f.mode == "summary" and stats.honorAwards > 0 then notices[#notices + 1] = honorDetail(stats) end
    if f.mode == "summary" then
        for _, dimension in ipairs(honorDimensions) do UI.selectButton(f.chips[dimension[1]], dimension[1] == f.dimension) end
        local initiative, geographic = f.dimension == "initiative", f.dimension == "zone"
        local zoom = geographic and f.zoneKey
        showIf(f.initiative, initiative) showIf(f.table, not initiative)
        if initiative then
            local ratio = "—"
            if stats.attackers > 0 then
                local decimal = DECIMAL_SEPERATOR or (frenchNumbers and "," or ".")
                ratio = ("%.2f"):format(stats.victims / stats.attackers):gsub("%.", decimal)
            end
            for key, value in pairs(f.initiative.values) do value:SetText(key == "ratio" and ratio or tostring(stats[key])) end
            local openings = stats.initiated + stats.responded
            if openings > 0 then
                local share = math.floor(100 * stats.initiated / openings + 0.5)
                f.initiative.values.initiated:SetText(L("%d · %d %%"):format(stats.initiated, share))
                f.initiative.values.responded:SetText(L("%d · %d %%"):format(stats.responded, 100 - share))
            end
        else
            local opponents = f.dimension == "opponents"
            options.zone = zoom
            local lines = opponents and (stats.opponents or {}) or GL.PvPBreakdown(options, zoom and "subzone" or f.dimension) or {}
            local exposure, partial = {}, nil
            if geographic and not zoom and GL.ZoneTimes then exposure, partial = GL.ZoneTimes(options) end
            if geographic and not zoom then
                local known, peaceful = {}, {}
                for _, item in ipairs(lines) do known[item.key] = true end
                for place, seconds in pairs(exposure) do
                    if not known[place] then peaceful[#peaceful + 1] = { key = place, label = place, kills = 0, deaths = 0,
                        correctedKills = 0, correctedDeaths = 0, seconds = seconds } end
                end
                table.sort(peaceful, function(a, b) return a.seconds > b.seconds or a.seconds == b.seconds and a.key < b.key end)
                for _, item in ipairs(peaceful) do lines[#lines + 1] = item end
            end
            local showTime = geographic and not zoom and (GL.Settings().zoneTime or next(exposure) ~= nil)
            local perPage = geographic and not zoom and ZONE_ROWS or HONOR_ROWS
            f.breakdownPerPage = perPage
            f.breakdownOffset = math.min(f.breakdownOffset, math.max(0, math.floor((#lines - 1) / perPage) * perPage))
            local corrected = 0
            for _, item in ipairs(lines) do corrected = corrected + (item.correctedKills or 0) + (item.correctedDeaths or 0) end
            if corrected > 0 then notices[#notices + 1] = counted(corrected, "rapport annulé", "rapports annulés") .. L(", hors totaux") end
            if showTime and partial then notices[#notices + 1] = L("Durées minimales · archives de présence partielles") end
            showIf(f.zoneBack, zoom) showIf(f.zoneTracking, geographic and not zoom and GL.ZoneTimes ~= nil)
            f.zoneTracking:SetText(GL.Settings().zoneTime and L("Suspendre le suivi du temps") or L("Mesurer le temps par zone"))
            fitText(f.zoneTracking.caption, f.zoneTracking:GetText(), 226, 12, 9)
            f.columnName:SetText(zoom and plain(f.zoneLabel) or opponents and L("Adversaire")
                or f.dimension == "race" and L("Race") or f.dimension == "class" and L("Classe") or L("Zone · ouvrir les lieux"))
            moveTo(f.columnName, zoom and 160 or 4, 154)
            showIf(f.columnTime, showTime)
            f.columnDeaths:SetText(L("Morts"))
            for i, row in ipairs(f.breakdownRows) do
                local item = i <= perPage and lines[f.breakdownOffset + i]
                row.item, row.zone = item or nil, nil
                if item then
                    row.rank:SetText(tostring(f.breakdownOffset + i))
                    if opponents then
                        local record = item.record
                        row.face:Show()
                        GL.PaintBookPortrait(row.face, record)
                        moveTo(row.name, 70, 4)
                        fitText(row.name, plain(record.fullName), 300, 14, 10, true)
                        row.name:SetTextColor(unpack(inkColors[GL.Relation(record)] or theme.ink))
                        local faction, _, class = GL.IdentityLabels(record)
                        local meta = { (plain(faction)), (plain(class)) }
                        if record.guild then meta[#meta + 1] = plain(record.guild) end
                        fitText(row.meta, table.concat(meta, " · "), 400, 11, 9)
                        row.meta:Show()
                        row.kills:SetText(tostring(item.kills))
                    else
                        row.face:Hide()
                        row.meta:Hide()
                        if geographic and not zoom and item.key ~= "mixed" and item.key ~= "unknown" then row.zone = item end
                        local text = item.label
                        if item.key == "unknown" or item.key == "mixed" then text = L(text)
                        elseif f.dimension == "race" then text = raceLabel(item.key, text, item.raceID)
                        elseif f.dimension == "class" then text = classLabel(item.key, text) end
                        moveTo(row.name, 30, 12)
                        fitText(row.name, plain(text), showTime and 240 or 360, 14, 10, true)
                        row.name:SetTextColor(unpack(theme.ink))
                        row.kills:SetText(tostring(item.kills))
                    end
                    showIf(row.time, showTime)
                    if showTime then row.time:SetText(exposure[item.key] and groupDurationText(exposure[item.key]) or "—") end
                    row.deaths:SetText(tostring(item.deaths))
                    -- A death reads in red; no death stays quiet.
                    row.deaths:SetTextColor(unpack(item.deaths > 0 and inkColors.enemy or theme.inkMuted))
                    row:EnableMouse(opponents or row.zone ~= nil)
                    row:Show()
                else
                    row:Hide()
                end
            end
            f.tableEmpty:SetText(#lines == 0 and (opponents and L("Aucun adversaire sur cette période.")
                or zoom and L("Aucun combat enregistré dans cette zone pour cette sélection.")
                or L("Aucune victoire ni mort enregistrée pour cette sélection.")) or "")
            f.listTotal = #lines
        end
    elseif annual then
        local card = f.annual
        card.name:SetText(f.scope == "character" and plain(stats.actorName or L("Votre personnage")) or f.scope == "legacy" and L("Archives sans auteur") or L("Votre compte"))
        card.period:SetText(f.year and (L("Votre campagne de ") .. f.year) or L("Année inconnue"))
        for key, metric in pairs(card.metrics) do metric:SetText(tostring(key == "honor" and (stats.honor or 0) or stats[key])) end
        for key, recap in pairs(card.recaps) do
            local item = stats[key]
            recap.record = item and item.record
            if item then
                recap.face:Show() GL.PaintBookPortrait(recap.face, item.record)
                fitText(recap.name, plain(item.record.fullName), 400, 14, 10, true)
                recap.name:SetTextColor(unpack(inkColors[GL.Relation(item.record)] or theme.ink))
            else
                recap.face:Hide()
                recap.name:SetText(L("Aucun adversaire")) recap.name:SetTextColor(unpack(theme.inkMuted))
            end
            recap.score:SetText(item and counted(item.value, key == "mostDeaths" and "mort" or "victoire") or "—")
            recap:EnableMouse(item ~= nil)
        end
        card.coverage:SetText((stats.events > 0 or stats.honorAwards > 0) and counted(stats.events, "fait de combat", "faits de combat") .. L(" · Hors champs de bataille et arènes.") or L("Aucun fait PvP conservé pour cette année et cette sélection."))
        local period = choiceLabel(journalPeriods, "year") .. " " .. tostring(f.year or "?")
        local text = table.concat({ "Grudge Ledger · " .. period .. " · " .. choiceLabel(journalScopes, f.scope),
            L("Bilan : ") .. counted(stats.kills, "victoire") .. ", " .. counted(stats.deaths, "mort") .. ", " .. counted(stats.aggressions, "agression") .. ".",
            honorTotal(stats) }, "\n")
        if text ~= f.annualText then f.cardCopy:Hide() end
        f.annualText = text
    elseif f.mode == "story" then
        local story = {
            L("Vous avez remporté ") .. counted(stats.kills, "victoire", "victoires") .. L(" et subi ") .. counted(stats.deaths, "mort", "morts") .. ".", "" }
        if stats.aggressions > 0 then story[#story + 1] = L("Le registre compte aussi ") .. counted(stats.aggressions, "agression", "agressions") .. ".\n" end
        if stats.mostDeaths then story[#story + 1] = L("Votre némésis sur cette période : ") .. plain(stats.mostDeaths.record.fullName) .. " (" .. counted(stats.mostDeaths.value, "mort", "morts") .. ").\n" end
        if stats.mostKilled then story[#story + 1] = L("Votre adversaire le plus vaincu : ") .. plain(stats.mostKilled.record.fullName) .. " (" .. counted(stats.mostKilled.value, "victoire", "victoires") .. ").\n" end
        if (stats.events or 0) == 0 then
            story = stats.honorAwards > 0 and {} or { L("Le récit de cette période reste à écrire."), "", L("Aucun fait PvP comptabilisé dans cette sélection. Essayez une période plus large ou un autre personnage.") }
        end
        story[#story + 1] = honorTotal(stats)
        if stats.honorAwards > 0 then story[#story + 1] = honorDetail(stats) end
        story[#story + 1] = ""
        story[#story + 1] = subdued(L("Ce récit résume vos archives, pas l'ensemble de votre carrière. Champs de bataille et rapports annulés sont exclus."))
        f.storyPages:SetText(table.concat(story, "\n"), true)
    else
        local events = GL.JournalEvents(options)
        f.kindButton:SetText(choiceLabel(journalKinds, f.kind) .. " · " .. #events)
        fitText(f.kindButton.caption, f.kindButton:GetText(), 228, 12, 9)
        UI.selectButton(f.kindButton, f.kind ~= "all")
        showIf(f.reset, f.kind ~= "all" or (f.query or "") ~= "")
        f.offset = math.min(f.offset, math.max(0, math.floor((#events - 1) / CHRONICLE_ROWS) * CHRONICLE_ROWS))
        for i, row in ipairs(f.rows) do
            local item = events[f.offset + i] row.item = item
            if item then
                local event, record = item.event, item.record
                local title = pvpNames[event.kind] or eventTitle(event)
                if event.kind == "note" then title = event.text or L("Note personnelle") end
                if event.voided then title = title .. L(" — exclu des compteurs") end
                local place = event.subzone or event.zone
                local author = not event.actorGUID and L(" · auteur inconnu") or f.scope == "all" and (" · " .. plain(event.actorName or L("Autre personnage"))) or ""
                if record then row.face:Show() GL.PaintBookPortrait(row.face, record) else row.face:Hide() end
                local hasTime = type(event.time) == "number" and event.time > 0
                fitText(row.name, (hasTime and date("%H:%M", event.time) .. "  ·  " or "") .. (record and plain(record.fullName) or L("Adversaire non identifié")), 396, 14, 10, true)
                row.name:SetTextColor(unpack(record and inkColors[GL.Relation(record)] or theme.ink))
                row.when:SetText(hasTime and date("%d/%m/%Y", event.time) or L("Date inconnue"))
                local context = event.kind == "trade" and plain((eventEvidence(event) or ""):gsub("\n", " · ")) or combatDetails(event, true)
                    or event.questTitle and L("Quête suivie · ") .. plain(event.questTitle) or event.guild and L("Guilde lors du combat · ") .. plain(event.guild) or ""
                local second = plain(title):gsub("[\r\n]+", " ")
                local tail = (place and (" · " .. plain(place)) or "") .. (context ~= "" and (" · " .. context) or "") .. author
                fitText(row.action, second .. "|cff6b5038" .. tail .. "|r", 526, 12, 10)
                row.stripe:SetColorTexture(unpack(inkColors[GL.Relation(record)] or inkColors.neutral)) row:Show()
            else row:Hide() end
        end
        f.empty:SetText(#events == 0 and L("Aucune rencontre dans cette sélection.\nÉlargissez la période ou les filtres.") or "")
        f.listTotal = #events
    end
    -- One pager for the lists: the chronicle and the tables of the overview.
    local list = history or (f.mode == "summary" and f.dimension ~= "initiative")
    local perPage = history and CHRONICLE_ROWS or f.breakdownPerPage or HONOR_ROWS
    local first = history and f.offset or f.breakdownOffset
    local total = list and f.listTotal or 0
    showIf(f.previous, list) showIf(f.next, list) showIf(f.count, list)
    f.previous:SetEnabled(first > 0)
    f.next:SetEnabled(first + perPage < total)
    f.count:SetText(total > 0 and L("%d à %d sur %d"):format(first + 1, math.min(first + perPage, total), total) or "")
    f.lead:SetText(#notices > 0 and table.concat(notices, " · ") or helpText(f))
    if f.paintTally then f.paintTally() end
end

-- Builds the page in a host of 664 x 510: the Relations book's sheet, or the fallback book.
function GL.BuildHonorPage(host)
    local f = CreateFrame("Frame", "GrudgeLedgerJournal", host)
    f:SetAllPoints(host)
    journalWindow = f
    f.mode, f.period, f.scope, f.kind, f.offset, f.dimension, f.breakdownOffset = "summary", "all", "character", "all", 0, "opponents", 0
    f.year = GL.JournalYears()[1] or tonumber(date("%Y"))
    f.heading = sheetText(f, 0, 18, 380, 21, true)
    f.periodButton = button(f, "", 392, -14, 134, function()
        local list = periodChoices(f.mode == "year")
        local nextEntry = list[(periodIndex(list, f.period, f.year) or 0) % #list + 1]
        f.period, f.year, f.offset, f.breakdownOffset = nextEntry[1], nextEntry[2] or f.year, 0, 0
        refreshJournal()
    end, nil, true)
    f.scopeButton = button(f, "", 530, -14, 134, function()
        f.scope, f.offset, f.breakdownOffset = nextChoice(journalScopes, f.scope), 0, 0
        refreshJournal()
    end, nil, true)
    f.lead = sheetText(f, 0, 47, 664, 13, false, theme.inkMuted)
    f.lead:SetHeight(30) GL.Safe(f.lead.SetWordWrap, f.lead, true)
    f.tabs = {}
    for i, mode in ipairs(honorModes) do
        local key = mode[1]
        f.tabs[key] = button(f, mode[2], (i - 1) * 167, -84, 162, function() GL.ShowJournal(key) end, true, true)
    end
    f.views = {}
    for _, mode in ipairs(honorModes) do
        local view = CreateFrame("Frame", nil, f) view:SetAllPoints(f) f.views[mode[1]] = view
    end
    -- Vue d'ensemble: five chips, then one table or the initiative's two columns.
    local summary = f.views.summary
    f.chips = {}
    for i, dimension in ipairs(honorDimensions) do
        local key = dimension[1]
        local chip = button(summary, dimension[2], (i - 1) * 134, -116, 128, function()
            f.dimension, f.breakdownOffset, f.zoneKey = key, 0, nil refreshJournal()
        end, true, true)
        fitText(chip.caption, dimension[2], 116, 12, 9)
        f.chips[key] = chip
    end
    f.table = CreateFrame("Frame", nil, summary) f.table:SetAllPoints(f)
    local band = f.table:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT", 0, -150) band:SetSize(664, 22) band:SetColorTexture(0.44, 0.28, 0.13, 0.18)
    f.columnName = sheetText(f.table, 4, 154, 270, 12, false, theme.inkMuted)
    f.columnTime = sheetText(f.table, 280, 154, 110, 12, false, theme.inkMuted) f.columnTime:SetJustifyH("RIGHT")
    f.columnTime:SetText(L("Présence"))
    f.columnKills = sheetText(f.table, 400, 154, 120, 12, false, theme.inkMuted) f.columnKills:SetJustifyH("RIGHT")
    f.columnKills:SetText(L("Victoires"))
    f.columnDeaths = sheetText(f.table, 544, 154, 116, 12, false, theme.inkMuted) f.columnDeaths:SetJustifyH("RIGHT")
    f.zoneBack = button(f.table, L("‹ Toutes les zones"), 0, -148, 150, function()
        f.zoneKey, f.breakdownOffset = nil, 0 refreshJournal()
    end, nil, true)
    f.breakdownRows = {}
    for i = 1, HONOR_ROWS do
        local row = CreateFrame("Button", nil, f.table)
        row:SetPoint("TOPLEFT", 0, -174 - (i - 1) * 44) row:SetSize(664, 42)
        sheetRule(row)
        row.rank = sheetText(row, 0, 12, 22, 12, false, theme.inkMuted)
        row.face = sheetFace(row, 28, 4, 34)
        row.name = sheetText(row, 70, 4, 300, 14, true)
        row.meta = sheetText(row, 70, 23, 400, 11, false, theme.inkMuted)
        row.time = sheetText(row, 280, 12, 110, 14, false, theme.inkMuted) row.time:SetJustifyH("RIGHT")
        row.kills = sheetText(row, 400, 10, 120, 16, true) row.kills:SetJustifyH("RIGHT")
        row.deaths = sheetText(row, 544, 10, 116, 16, true, inkColors.enemy) row.deaths:SetJustifyH("RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
            if self.zone then f.zoneKey, f.zoneLabel, f.breakdownOffset = self.zone.key, self.zone.label, 0 refreshJournal()
            elseif self.item and self.item.record then GL.ShowLedger(self.item.record.key) end
        end)
        f.breakdownRows[i] = row
    end
    f.tableEmpty = sheetText(f.table, 0, 182, 664, 13, false, theme.inkMuted)
    f.zoneTracking = button(f.table, "", 0, -420, 240, function()
        GL.SetSetting("zoneTime", not GL.Settings().zoneTime) refreshJournal()
    end, nil, true)
    f.initiative = CreateFrame("Frame", nil, summary) f.initiative:SetAllPoints(f)
    f.initiative.values = {}
    for _, group in ipairs({
        { x = 0, y = 152, title = L("Joueurs distincts"), { "victims", L("Vaincus") }, { "attackers", L("Vous ayant blessé") }, { "ratio", L("Vaincus / attaquants") } },
        { x = 0, y = 270, title = L("Premier dégât observé"), { "initiated", L("Porté par vous") }, { "responded", L("Porté par l’adversaire") } },
        { x = 344, y = 152, title = L("Victoires"), { "initiatedKillsNoGrudge" }, { "initiatedKillsGrudge" },
            { "revengeKills" }, { "responseKills" }, { "unknownOpeningKills" } },
    }) do
        sheetText(f.initiative, group.x, group.y, 320, 14, true):SetText(group.title)
        for i, entry in ipairs(group) do
            local line = CreateFrame("Frame", nil, f.initiative)
            line:SetPoint("TOPLEFT", group.x, -(group.y + 26 + (i - 1) * 26)) line:SetSize(320, 24)
            sheetRule(line)
            local caption = sheetText(line, 0, 5, 226, 13, false, theme.inkMuted)
            fitText(caption, entry[2] or killOpeningLabels[entry[1]], 226, 13, 10)
            local value = sheetText(line, 230, 3, 90, 15, true) value:SetJustifyH("RIGHT")
            f.initiative.values[entry[1]] = value
        end
    end
    -- Chronique: the guild journal's bar (search, kind with its count, clear), then five lines.
    local chronicle = f.views.history
    f.search = CreateFrame("EditBox", nil, chronicle) f.search:SetPoint("TOPLEFT", 0, -116) f.search:SetSize(241, 26)
    f.search:SetAutoFocus(false) f.search:SetMaxLetters(200) styleInput(f.search, false, true)
    f.searchHint = sheetText(f.search, 8, 6, 225, 12, false, theme.inkMuted) f.searchHint:SetText(L("Rechercher dans la chronique"))
    local function searchJournal() f.query, f.offset = f.search:GetText(), 0 f.search:ClearFocus() refreshJournal() end
    f.search:SetScript("OnEnterPressed", searchJournal)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search:SetScript("OnTextChanged", function(self) showIf(f.searchHint, (self:GetText() or "") == "") end)
    f.kindButton = button(chronicle, "", 249, -116, 241, function() f.kind, f.offset = nextChoice(journalKinds, f.kind), 0 refreshJournal() end, nil, true)
    f.reset = button(chronicle, L("Effacer les filtres"), 498, -116, 166, function()
        f.query, f.kind, f.offset = "", "all", 0 f.search:SetText("") refreshJournal()
    end, nil, true)
    f.rows = {}
    for i = 1, CHRONICLE_ROWS do
        local row = CreateFrame("Button", nil, chronicle) row:SetPoint("TOPLEFT", 0, -150 - (i - 1) * 56) row:SetSize(664, 54)
        sheetRule(row)
        row.stripe = row:CreateTexture(nil, "ARTWORK") row.stripe:SetPoint("TOPLEFT", 0, -4) row.stripe:SetPoint("BOTTOMLEFT", 0, 5) row.stripe:SetWidth(2)
        row.face = sheetFace(row, 8, 10, 34)
        row.name = sheetText(row, 50, 7, 396, 14, true)
        row.when = sheetText(row, 452, 9, 120, 11, false, theme.inkMuted) row.when:SetJustifyH("RIGHT")
        row.action = sheetText(row, 50, 30, 526, 12)
        row.details = button(row, L("Détails"), 585, -14, 79, function()
            local item = row.item
            if not item then return end
            if item.event.note then GL.EditNote(item.record, item.event.note) else inspectEvent(item.record, item.event) end
        end, nil, true)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
            if not self.item then return end
            if self.item.record then GL.ShowLedger(self.item.record.key) else inspectEvent(nil, self.item.event) end
        end)
        f.rows[i] = row
    end
    f.empty = sheetText(chronicle, 0, 160, 664, 13, false, theme.inkMuted)
    f.empty:SetHeight(40) GL.Safe(f.empty.SetWordWrap, f.empty, true)
    -- Mon année: the Bilan's centred card, without a frame inside the frame.
    local annual = f.views.year
    f.annual, annual.metrics, annual.recaps = annual, {}, {}
    annual.name = sheetText(annual, 40, 122, 584, 22, true) annual.name:SetJustifyH("CENTER")
    annual.period = sheetText(annual, 40, 152, 584, 14, false, theme.inkMuted) annual.period:SetJustifyH("CENTER")
    for i, entry in ipairs({ { "kills", L("Victoires") }, { "deaths", L("Morts PvP") }, { "aggressions", L("Agressions") }, { "honor", L("Honneur reçu") } }) do
        local x = (i - 1) * 166
        annual.metrics[entry[1]] = sheetText(annual, x, 182, 166, 30, true)
        annual.metrics[entry[1]]:SetJustifyH("CENTER")
        local caption = sheetText(annual, x, 218, 166, 13)
        caption:SetJustifyH("CENTER") caption:SetText(entry[2])
    end
    for i, entry in ipairs({ { "mostDeaths", L("Votre pire antagoniste") }, { "mostKilled", L("Votre adversaire le plus vaincu") } }) do
        local row = CreateFrame("Button", nil, annual)
        row:SetPoint("TOPLEFT", 0, -250 - (i - 1) * 44) row:SetSize(664, 42)
        sheetRule(row)
        row.face = sheetFace(row, 28, 4, 34)
        row.name = sheetText(row, 70, 4, 400, 14, true)
        sheetText(row, 70, 23, 400, 11, false, theme.inkMuted):SetText(entry[2])
        row.score = sheetText(row, 480, 10, 180, 16, true) row.score:SetJustifyH("RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self) if self.record then GL.ShowLedger(self.record.key) end end)
        annual.recaps[entry[1]] = row
    end
    annual.coverage = sheetText(annual, 40, 350, 584, 12, false, theme.inkMuted) annual.coverage:SetJustifyH("CENTER")
    annual.events = button(annual, L("Voir les événements de l’année"), 102, -392, 226, function()
        f.period, f.kind, f.query, f.offset = "year", "pvp", "", 0
        f.search:SetText("") GL.ShowJournal("history")
    end, nil, true)
    fitText(annual.events.caption, L("Voir les événements de l’année"), 214, 12, 9)
    f.cardCopy = CreateFrame("Frame", nil, annual)
    f.cardCopy:SetPoint("TOPLEFT", 155, -120) f.cardCopy:SetSize(354, 176)
    surface(f.cardCopy, theme.paper):SetAlpha(0.96)
    local copyField = CreateFrame("EditBox", nil, f.cardCopy)
    copyField:SetPoint("TOPLEFT", 8, -8) copyField:SetSize(338, 136) copyField:SetMultiLine(true)
    copyField:SetAutoFocus(false) styleInput(copyField, true, true)
    copyField:SetScript("OnEscapePressed", function() f.cardCopy:Hide() end)
    f.cardCopy:SetScript("OnHide", function() copyField:ClearFocus() end)
    sheetText(f.cardCopy, 8, 152, 338, 12, false, theme.inkMuted):SetText(L("Ctrl+C pour copier."))
    f.cardCopy:Hide()
    f.copyAnnual = button(annual, L("Copier le bilan annuel"), 336, -392, 226, function()
        f.cardCopy:Show() copyField:SetText(f.annualText) copyField:SetFocus() copyField:HighlightText()
    end, nil, true)
    -- Récit: the paged text, and the export of your deaths, which is text as well.
    local story = f.views.story
    f.storyPages = UI.textPages(story, 664, 362)
    f.storyPages:SetPoint("TOPLEFT", 0, -128)
    f.storyText = f.storyPages.body
    journalFont(f.storyText, "QuestFont_Large", 15)
    f.storyText:SetSpacing(5)
    f.exportDeaths = button(story, L("Exporter mes morts pour une IA"), 0, -464, 260, function() GL.DeathReport.ShowExport() end, nil, true)
    fitText(f.exportDeaths.caption, L("Exporter mes morts pour une IA"), 248, 12, 9)
    -- The one pager of the lists.
    f.previous = button(f, "‹", 0, -464, 49, function()
        if f.mode == "history" then f.offset = math.max(0, f.offset - CHRONICLE_ROWS)
        else f.breakdownOffset = math.max(0, f.breakdownOffset - (f.breakdownPerPage or HONOR_ROWS)) end
        refreshJournal()
    end, nil, true)
    f.next = button(f, "›", 615, -464, 49, function()
        if f.mode == "history" then f.offset = f.offset + CHRONICLE_ROWS
        else f.breakdownOffset = f.breakdownOffset + (f.breakdownPerPage or HONOR_ROWS) end
        refreshJournal()
    end, nil, true)
    f.count = sheetText(f, 60, 470, 544, 12, false, theme.inkMuted) f.count:SetJustifyH("CENTER")
    for _, mode in ipairs(honorModes) do
        hoverHelp(f.tabs[mode[1]], mode[2], function()
            local saved = f.mode f.mode = mode[1] local text = helpText(f) f.mode = saved return text
        end)
    end
    for _, dimension in ipairs(honorDimensions) do
        hoverHelp(f.chips[dimension[1]], dimension[2], function()
            local saved = f.dimension f.dimension = dimension[1] local text = helpText(f) f.dimension = saved return text
        end)
    end
    f:SetScript("OnShow", refreshJournal)
    return f
end
function GL.PaintHonorPage() refreshJournal() end
-- The figures of the left column on this page (Relations.lua paints them): label, value, action.
function GL.HonorTally() return journalWindow and journalWindow.tallyLines or {} end

-- Opens the tables on a mode. context: the Bilan's period and characters, carried over.
function GL.ShowJournal(mode, context)
    if not GL.db then return end
    mode = (mode == "history" or mode == "story" or mode == "year") and mode or "summary"
    if GL.RelationsPages then
        GL.RelationsPages.Open("honor")
    elseif not honorBook then
        -- Without Relations.lua: the same page in a narrow book of its own.
        honorBook = bookWindow("GrudgeLedgerJournalBook", "Grudge Ledger", true)
        bookNavigation(honorBook, "players")
        local host = CreateFrame("Frame", nil, honorBook)
        host:SetPoint("TOPLEFT", 240, -152) host:SetSize(664, 510)
        GL.BuildHonorPage(host)
    end
    local f = journalWindow
    if type(context) == "table" then
        f.scope = context.scope == "all" and "all" or "character"
        f.period = context.period == "week" and "week" or context.period == "month" and "month" or context.period == "year" and "year" or "all"
        if f.period == "year" then f.year = tonumber(date("%Y")) end
        f.offset, f.breakdownOffset = 0, 0
    end
    f.mode = mode
    if not GL.RelationsPages then showBook(honorBook) end
    refreshJournal()
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
    if e.kind == "trade" then return L("Échange terminé") end
    if e.voidReason == "battleground" then return L("Champ de bataille · exclu") end
    if e.voided then return L("Annulé · exclu") end
    if e.kind == "honor" then return L("Honneur") end
    if e.kind == "opening" then return L("Initiative") end
    if e.playerConfirmedAt then return L("Témoignage") end
    if pvpNames[e.kind] then return L("JcJ") end
    return e.source == "emote" and L("Geste") or e.kind == "grouped" and L("Groupe") or L("Journal")
end

local function honorRecipient(e)
    return L("Reçu par %s"):format(plain(e.actorName or L("Auteur inconnu")))
end

local function eventAction(e)
    local delta = type(e.delta) == "number" and e.delta ~= 0 and (L(" — avis ") .. (e.delta > 0 and "+" or "") .. e.delta) or ""
    return eventTitle(e) .. delta
end

-- One fight in one line: "Agression » Vous a tué · coup fatal » Vaincu avec votre groupe".
function GL.FightTitle(fight)
    local parts = {}
    if fight.aggressions > 0 and fight.main and fight.main.kind ~= "aggression" then parts[1] = L("Agression") end
    for _, e in ipairs(fight.events) do
        if e.kind == "kill" and type(e.combat) == "table" and e.combat.assist then
            parts[#parts + 1] = L("Vaincu avec votre groupe")
        elseif e.kind ~= "aggression" then
            parts[#parts + 1] = eventTitle(e)
        end
    end
    if #parts == 0 then return L("Escarmouche sans mort · il vous a agressé") end
    return table.concat(parts, " » ")
end

-- Reuse journal wording for personal facts; shared facts name both participants.
function GL.HistoryTitle(e, actor, target)
    if not actor then return eventAction(e) end
    actor,target=plain(actor),plain(target)
    if e.kind=="kill" then return L("%s a vaincu %s"):format(actor,target) end
    if e.kind=="death" then
        return L("%s a été tué par %s"):format(actor,target)
    end
    if e.kind=="aggression" then return L("%s a subi des dégâts de %s"):format(actor,target) end
    if e.kind=="reputation" then return L("%s a modifié son avis sur %s"):format(actor,target).." · "..string.format("%+d",e.delta or 0) end
    if e.kind=="reaction" then return L("%s a classé %s"):format(actor,target).." · "..(relationNames[e.reaction] or L("Automatique")) end
    if e.kind=="trade" then return L("Échange entre %s et %s"):format(actor,target) end
    return L("%s a partagé un groupe avec %s"):format(actor,target)
end

local function eventReason(e)
    if e.kind == "honor" then
        return honorRecipient(e) .. "\n" .. L("Le jeu annonce votre gain d’honneur. Plusieurs joueurs peuvent recevoir de l’honneur pour le même combat.")
    end
    if e.voidReason == "other-killer" then return L("Le jeu a attribué le coup fatal à un autre joueur.") end
    if e.playerConfirmedAt then return L("Coup fatal indiqué le %s."):format(stamp(e.playerConfirmedAt)) end
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

local function renderCombatReport(f)
    local e, report = f.event, f.event.report
    local rows = report and report[f.source]
    local text = {}
    local opponent, actor = f.identity and f.identity.guid, e.actorGUID
    local function participant(guid, name, pet)
        if pet and name then return plain(name) end
        if guid and guid == actor then return L("Vous") end
        if guid and guid == opponent then return f.who:GetText() end
        return plain(name or L("Source inconnue"))
    end
    -- Both players' builds as recorded at the fight, before the blow-by-blow.
    local build = GL.FightBuildText and GL.FightBuildText(e)
    -- A death adds its report: damage by source and spell, killing blow, length of the fight.
    local death = GL.DeathReport and GL.DeathReport.Text(e, opponent, f.who:GetText())
    local tabs = report ~= nil and (e.kind == "kill" or e.kind == "death")
    local view = tabs and (f.view or "summary") or "all"
    local summary, blows = {}, {}
    if build and view ~= "summary" then text[#text+1] = build end
    if death then summary[#summary+1] = death end
    local dealt, received, others
    if rows and #rows > 0 then
        local lines = {}
        for _, hit in ipairs(rows) do
            local outgoing = actor and opponent and hit.src == actor and hit.dst == opponent
            local incoming = actor and opponent and hit.src == opponent and hit.dst == actor
            if hit.amount then
                if outgoing then dealt = (dealt or 0) + hit.amount
                elseif incoming then received = (received or 0) + hit.amount
                elseif actor and hit.dst == actor and (hit.src or hit.kind == "ENVIRONMENTAL_DAMAGE") then
                    others = (others or 0) + hit.amount
                end
            end
            if not f.pairOnly or incoming or outgoing then
                local from = participant(hit.src, hit.from, hit.srcPet)
                local action = hit.spell
                if hit.kind == "ENVIRONMENTAL_DAMAGE" then
                    from = L("Environnement")
                    action = hit.environment and _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. hit.environment:upper()] or from
                elseif hit.kind == "SWING_DAMAGE" then action = ACTION_SWING or L("Attaque de mêlée") end
                local detail = hit.amount and tostring(hit.amount) or (hit.kind == "SPELL_CAST_SUCCESS" and L("Sort lancé") or "—")
                if hit.fatal then detail = detail .. " · " .. L("Coup fatal") end
                lines[#lines+1] = ("+%d s   %s › %s   ·   %s   ·   %s"):format(
                    math.max(0, math.floor(hit.at - rows[1].at)), from, participant(hit.dst, hit.to, hit.dstPet),
                    plain(action or L("Sort non identifié")), detail)
            end
        end
        summary[#summary+1] = L("Dégâts observés") .. "\n" .. L("Infligés à l’adversaire") .. "  " .. (dealt or "—")
            .. "     ·     " .. L("Reçus de l’adversaire") .. "  " .. (received or "—")
            .. "\n" .. L("Reçus d’autres sources") .. "  " .. (others or "—")
        if f.source == "live" and report.clipped then blows[#blows+1] = L("Seules les 64 dernières actions sont conservées.") end
        blows[#blows+1] = #lines > 0 and table.concat(lines, "\n") or L("Aucun échange direct relevé.")
    elseif e.kind == "kill" or e.kind == "death" then
        summary[#summary+1] = L("Aucun relevé de dégâts disponible pour ce combat.")
    end
    if view == "summary" then
        text = #summary > 0 and summary or { build or L("Aucun relevé de dégâts disponible pour ce combat.") }
    elseif view == "builds" then
        text = { build or L("Aucun build relevé pour ce combat.") }
    elseif view == "proof" then
        text = blows
        if f.evidenceText ~= "" then text[#text+1] = f.evidenceText end
    else
        for _, part in ipairs(summary) do text[#text+1] = part end
        for _, part in ipairs(blows) do text[#text+1] = part end
        if f.evidenceText ~= "" then text[#text+1] = f.evidenceText end
    end
    -- Sub-tabs, and the blow-by-blow controls on the Preuves tab only.
    local proof = view == "proof"
    for key, b in pairs(f.views) do
        showIf(b, tabs)
        UI.selectButton(b, view == key)
    end
    showIf(f.section, not tabs)
    showIf(f.all, proof) showIf(f.pair, proof)
    showIf(f.otherSource, proof and report and report.live and report.recap)
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", 26, proof and -280 or -242)
    f.scroll:SetHeight(tabs and (proof and 166 or 204) or 77)
    f.scroll:SetText(table.concat(text, "\n\n"))
    UI.selectButton(f.pair, f.pairOnly) UI.selectButton(f.all, not f.pairOnly)
    f.otherSource:SetText(f.source == "live" and L("Voir les derniers coups reçus") or L("Voir les actions observées"))
    f.section:SetText(rows and (f.source == "recap" and L("Derniers coups reçus") or L("Actions observées")) or L("Pourquoi cet événement ?"))
end

-- The player dossier opens the same fight detail as the journal history.
function GL.InspectEvent(record, e)
    return inspectEvent(record, e)
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
        f.section = field(26, -209, 301, 26, 17)
        f.otherSource = button(f, "", 300, -241, 258, function()
            f.source = f.source == "live" and "recap" or "live"
            renderCombatReport(f)
        end, nil, true)
        f.all = button(f, L("Tous les intervenants"), 26, -241, 150, function()
            f.pairOnly = false renderCombatReport(f)
        end, true, true)
        f.pair = button(f, L("Nos échanges"), 180, -241, 116, function()
            f.pairOnly = true renderCombatReport(f)
        end, true, true)
        -- A fight with a damage report reads in three sub-tabs instead of one long text.
        f.views = {}
        local vx = 26
        for _, view in ipairs({ { "summary", L("Résumé"), 104 }, { "builds", L("Builds"), 90 }, { "proof", L("Preuves"), 100 } }) do
            local key = view[1]
            f.views[key] = button(f, view[2], vx, -207, view[3], function()
                f.view = key
                renderCombatReport(f)
            end, true, true)
            vx = vx + view[3] + 4
        end
        -- Pages instead of a scroll bar.
        f.scroll = UI.textPages(f, 532, 77)
        f.scroll:SetPoint("TOPLEFT", 26, -242)
        f.proof = f.scroll.body
        f.effect = field(26, -334, 532, 49, 13)
        f.keep = button(f, L("Fermer"), 24, -396, 105, function() f:Hide() end, true, true)
        UI.selectButton(f.keep, true)
        f.confirm = button(f, L("Annuler cet événement"), 351, -396, 211, nil, nil, true)
        f.keep:ClearAllPoints() f.keep:SetPoint("BOTTOMLEFT", 24, 25)
        f.confirm:ClearAllPoints() f.confirm:SetPoint("BOTTOMRIGHT", -24, 25)
        f.effect:ClearAllPoints() f.effect:SetPoint("BOTTOMLEFT", 26, 64)
    end
    local f = correctionWindow
    f.identity, f.event = record and { key=record.key, guid=record.guid, alias=record.alias }, e
    local isCombat = e.kind == "kill" or e.kind == "death"
    local report = isCombat and e.report
    f.source, f.pairOnly = report and report.live and "live" or "recap", false
    f:SetHeight(report and 575 or 447)
    f.view = "summary"
    f.title:SetText(isCombat and L("Détail du combat") or pvpNames[e.kind] and L("Vérifier cet événement") or L("Détails de la rencontre"))
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
    if e.guildSource and e.guild then evidence[#evidence+1] = L("Guilde mémorisée : ") .. plain(e.guild) .. (e.guildRealm and " (" .. realmLabel(e.guildRealm) .. ")" or "") .. (e.guildSource == "last-known" and L(" — observée auparavant") or "") end
    f.evidenceText = #evidence > 0 and table.concat(evidence, "\n") or L("Aucune précision enregistrée.")
    renderCombatReport(f)
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
        f.scroll = CreateFrame("ScrollFrame", nil, f)
        UI.wheelScroll(f.scroll)
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
                GL.Print(L("Essai dans 3 secondes : placez la souris sur le monde, hors fenêtres, puis restez immobile."))
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
    -- 0.61.0: what a ticket needs. The language, how much the book holds, the guild's players with
    -- the addon, and the last errors kept from one session to the next. Never a name: in the
    -- anonymous report, player identifiers are masked.
    local sheets = 0
    for _ in pairs(GL.db and GL.db.players or {}) do sheets = sheets + 1 end
    local open = 0
    for _, order in pairs(GL.Bounties and GL.Bounties.List and GL.Bounties.List() or {}) do
        if order.state == "open" or order.state == "claimed" then open = open + 1 end
    end
    local usage = { L("Langue : ") .. tostring(GL.Safe(GetLocale) or L("indisponible")), L("Fiches : ") .. sheets,
        L("Primes en cours : ") .. open }
    if GL.GuildMap and GL.GuildMap.Players then
        local playerCount, characters = GL.GuildMap.Players()
        usage[#usage + 1] = L("Joueurs de la guilde avec l’addon : %d (%d personnages)"):format(playerCount, characters)
    end
    for i, line in ipairs(usage) do table.insert(lines, 6 + i, line) end
    local kept = GL.db and type(GL.db.errorLog) == "table" and GL.db.errorLog or {}
    if #kept > 0 then
        table.insert(lines, 7 + #usage, L("Dernières erreurs :"))
        local at = 8 + #usage
        for i = math.max(1, #kept - 9), #kept do
            local entry = kept[i]
            if type(entry) == "table" and type(entry.text) == "string" then
                local text = entry.text:gsub("%c+", " ")
                if private ~= true then
                    -- Only a Lua error (file, line, technical message) is shown as it is: it never holds
                    -- a value. Any other note may name a player: its text stays in /gl traces.
                    if text:find("%.lua:%d+:") then
                        text = text:gsub("Player%-[%w%-]+", "Player-…")
                    else
                        text = L("note interne (détail dans /gl traces)")
                    end
                end
                table.insert(lines, at, ("  %s · %s · ×%d · %s"):format(date("%d/%m %H:%M", tonumber(entry.time) or 0),
                    tostring(entry.version or "?"), tonumber(entry.count) or 1, text))
                at = at + 1
            end
        end
    end
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
    diagnosticWindow.privacy:SetText(private == true and L("Journal local : contient les noms de votre livre. Ne le publiez pas tel quel.")
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
            local combat = e.combat or {}
            local yours, theirs = GL.ValidLevel(combat.playerLevel), GL.ValidLevel(combat.opponentLevel)
            showIf(row.playerLevel, yours ~= nil)
            showIf(row.opponentLevel, theirs ~= nil)
            if yours then row.playerLevel:SetText(L("Vous · niv. %d"):format(yours)) end
            if theirs then row.opponentLevel:SetText(L("Adversaire · niv. %d"):format(theirs)) end
            showIf(row.hint, not yours and not theirs)
            row.hint:SetText(hint or "")
            local icon = ({death="Ability_Rogue_FeignDeath", kill="Ability_DualWield", aggression="Ability_Warrior_Charge"})[e.kind]
            row.icon:SetTexture(icon and ("Interface\\Icons\\" .. icon) or GL.icon)
            row.details:SetText((e.kind == "kill" or e.kind == "death") and L("Voir le combat") or L("Détails"))
            row:Show()
        else row:Hide() end
    end
    p.empty:SetText(count == 0 and L("Aucun événement dans cette sélection.") or "")
    p.total:SetText(count == 0 and L("0 événement") or (p.offset+1) .. "–" .. math.min(count,p.offset+size) .. L(" sur ") .. count)
    p.prev:SetEnabled(p.offset > 0) p.next:SetEnabled(p.offset + size < count)
end

local function renderDetail()
    local record = currentRecord()
    local tagWidth = journalTags(ledger, record)
    moveTo(ledger.detailSource, 746, tagWidth > 0 and 194 or 206)
    ledger.detailSource:SetHeight(tagWidth > 0 and 21 or 39)
    ledger.detailGuild:SetWidth(math.min(285, 446-tagWidth))
    local tab = ledger.detailTab or "summary"
    if record then ledger.emptyPage:Hide() else ledger.emptyPage:Show() end
    for key, control in pairs(ledger.detailTabs) do
        control:Hide()
        UI.selectButton(control, tab == key)
    end
    showIf(ledger.backToSummary, record ~= nil and tab ~= "summary")
    UI.paintStains(ledger, record and record.key or "")  -- each contact's sheet keeps its own stains
    for _, b in ipairs(ledger.actions) do b:SetEnabled(record ~= nil) end
    ledger.guildButton:SetEnabled(record ~= nil and record.guild ~= nil)
    ledger.tools:SetEnabled(record ~= nil)
    local bountyMode=tab=="summary" and ledger:IsShown() and GL.ContactBountyMode(record)
    -- The prime keeps its place in the row (greyed when no prime can be made): the row never reflows.
    showIf(ledger.contactBounty, tab == "summary" and record ~= nil)
    ledger.contactBounty:SetEnabled(bountyMode and true or false)
    ledger.contactBounty.actionIcon:SetAlpha(bountyMode and 1 or 0.45)
    ledger.contactBounty:SetText(bountyMode=="view" and L("Voir la prime") or L("Créer une prime"))
    if not record then ledger.toolsMenu:Hide() end
    -- Red marks only your own opinion. Without one, "Automatique" is lit and the relation the PvP balance
    -- or a guild rule computes gets a thin outline: clicking Automatique visibly does something (owner 23/11).
    local shownRelation, relationSource = "neutral", "neutral"
    if record then shownRelation, relationSource = GL.Relation(record), GL.RelationSource(record) end
    local chosenOpinion = record and (relationSource == "manual" and shownRelation or "neutral")
    for reaction, control in pairs(ledger.reactions) do
        UI.selectButton(control, chosenOpinion == reaction)
        suggestedOutline(control, record ~= nil and relationSource ~= "manual" and shownRelation ~= "neutral" and shownRelation == reaction)
    end
    local showHistory, showNotes = record and tab == "history", record and tab == "notes"
    local summary = tab == "summary" and record ~= nil
    if showHistory then ledger.historyPage:Show() else ledger.historyPage:Hide() end
    if not showNotes and noteWindow then noteWindow:Hide() end
    if showHistory or showNotes or not record then ledger.detailScroll:Hide() else ledger.detailScroll:Show() end
    for i = 1, 5 do
        local control = ledger.actions[i]
        showIf(control, summary)
    end
    if not summary then ledger.hint:Hide() ledger.tools:Hide() ledger.toolsMenu:Hide() ledger.openSheet:Hide()
    else ledger.hint:Show() ledger.tools:Show() ledger.openSheet:Show() end
    local row = { ledger.openSheet }
    row[#row + 1] = ledger.contactBounty
    row[#row + 1] = ledger.addNote
    row[#row + 1] = ledger.tools
    local width = math.floor((530 - 6 * (#row - 1)) / #row)
    for i, control in ipairs(row) do
        control:SetWidth(width)
        moveTo(control, 365 + (i - 1) * (width + 6), 602)
    end
    showIf(ledger.counters, summary)
    showIf(ledger.balancePanel, summary)
    showIf(ledger.summaryRule, summary)
    if ledger.summarySeal then showIf(ledger.summarySeal, summary) end
    ledger.detailScroll:ClearAllPoints()
    local storyTop = 377 + math.ceil(23 * (GL.Settings().readingScale or 1))
    ledger.detailScroll:SetPoint("TOPLEFT", 367, summary and -storyTop or -283)
    -- The story takes the 13 units the actions gave up.
    ledger.detailScroll:SetHeight(summary and (535 - storyTop) or 293)
    ledger.detailTitle:SetTextColor(unpack(theme.ink))
    local profile = GL.ArmoryProfile(record)
    local public = profile and profile.identity
    local level = record and (GL.ValidLevel(record.level) or GL.ValidLevel(profile and profile.level))
    showIf(ledger.portraitRim, record ~= nil)
    showIf(ledger.levelBadge, level ~= nil)
    if level then ledger.levelBadge.caption:SetText(tostring(level)) end
    local lines, summaryStory, followingStart = {}, {}, 2
    if not record then
        ledger.detailTitle:SetText("")
        ledger.detailIcon:Hide()
        ledger.detailStatus:SetText("")
        ledger.detailStatus:SetTextColor(unpack(theme.inkMuted))
        ledger.detailIdentity:SetText("")
        ledger.detailSource:SetText("") ledger.detailGuild:SetText("")
        if ledger.headshot then ledger.headshot.active = nil; ledger.headshot:Hide() end
        ledger.raceIcon:Hide() ledger.classIcon:Hide() ledger.detailFaction:Hide()
        if ledger.portraitBack then ledger.portraitBack:Hide() end
        if ledger.portraitOverlay then ledger.portraitOverlay:Hide() end
    else
        ledger.detailIcon:Show()
        local relation, pvp = GL.Relation(record), record.pvp or {}
        ledger.detailTitle:SetText(plain(record.fullName or record.name or record.key))
        ledger.detailIcon:SetTexture(media .. (referenceRelationIcons[relation] or relationIcons[relation]))
        ledger.detailIcon:SetSize(36, relation == "warning" and 22 or 36)
        moveTo(ledger.detailIcon, 760, relation == "warning" and 171 or 164)
        local source = GL.RelationSource(record)
        local nemesisKey, companionKey = GL.Titles()
        ledger.detailStatus:SetText(record.key == nemesisKey and L("Némésis") or record.key == companionKey and L("Compagnon")
            or relationNames[relation])
        ledger.detailSource:SetText(({ manual = L("Avis personnel"), emote = L("Avis issu de vos gestes"), pvp = L("Avis issu du PvP"), guild = L("Avis hérité de la guilde"), automatic = L("Avis automatique"), neutral = L("Aucun avis") })[source] or L("Avis automatique"))
        ledger.detailStatus:SetTextColor(unpack(inkColors[relation]))
        local faction, race, class = identityLabels(record)
        local factionKey = record.faction or (public and public.faction)
        local banner = referenceFactionIcons[factionKey] and media .. referenceFactionIcons[factionKey]
            or factionPortrait[factionKey]
        if banner then ledger.detailFaction:SetTexture(banner) end
        showIf(ledger.detailFaction, banner)
        ledger.detailIdentity:SetText(plain(faction .. " · " .. race .. " · " .. class))
        local guildName = record.guild or (public and public.guild)
        ledger.detailGuild:SetText(guildName and L("Guilde : %s"):format(plain(guildName)) or "")
        ledger.raceIcon:Show() ledger.classIcon:Show() identityIcons(ledger, record)
        if summary then
            for _, field in ipairs({ "kills", "deaths" }) do
                local card = ledger.metrics[field]
                local n = pvp[field] or 0
                card.caption:SetText(field == "kills" and L("Vous l’avez tué") or L("Il vous a tué"))
                card.value:SetText(n == 1 and L("1 fois") or L("%d fois"):format(n))
            end
        end
        if summary then
            local score, raw, gestures = GL.AutomaticBalance(record)
            -- Owner report (0.61.1): two victories for one death showed "0" beside a calculation
            -- giving 3. When you are ahead, the figure says so ("+3"); the relation does not change,
            -- because a victory does not make a friend.
            local ahead = gestures == 0 and raw > 0 and score == 0
            ledger.balance:SetText(ahead and ("+" .. raw) or tostring(score))
            ledger.balance:SetTextColor(unpack(score < 0 and inkColors.enemy or score > 0 and inkColors.friend or theme.ink))
            if ahead then
                -- A deep gold that stays readable on the parchment, and the stars sized to the figure.
                ledger.balance:SetTextColor(0.72, 0.50, 0.06)
                local width = GL.Clean(GL.Safe(ledger.balance.GetStringWidth, ledger.balance), "number") or 40
                ledger.balanceStars:SetWidth(math.max(40, width) + 28)
                ledger.balanceStars:Show()
            else
                ledger.balanceStars:Hide()
            end
            local deaths = (pvp.deaths or 0)
            local wins = (pvp.kills or 0)
            local hits = (pvp.aggressions or 0)
            -- The calculation in full, with today's weights: "2 agressions × −5 · 2 morts × −5 = −20".
            local formula = GL.BalanceFormula(record)
            if formula == "" then formula = counted(wins, "victoire") .. " × +1" end
            if gestures ~= 0 then
                formula = (L("Combats %+.0f   ·   Gestes %+.0f")):format(raw, gestures)
            else
                formula = formula .. "  =  " .. raw
            end
            ledger.formula:SetText(formula)
            local context = source == "manual" and L("Avis personnel prioritaire · %s"):format(relationNames[relation]) or ""
            if ahead then
                local reason = L("Vous menez de %d : il ne vous doit plus rien. Une victoire ne crée pas d’amitié."):format(raw)
                context = context ~= "" and context .. " · " .. reason or reason
            elseif score ~= raw + gestures then
                local reason = math.abs(score) == 100 and L("Solde plafonné à 100 en valeur absolue.")
                    or raw < 0 and L("Un geste amical n’efface pas une dette PvP.") or L("Une victoire seule ne crée pas d’amitié.")
                context = context ~= "" and context .. " · " .. reason or reason
            end
            ledger.scoreContext:SetText(context)
            local contextHeight = math.max(17, GL.Safe(ledger.scoreContext.GetStringHeight, ledger.scoreContext) or 17)
            ledger.scoreContext:SetHeight(contextHeight)
            -- The seal band hangs under the balance (and its context line), the heading just under its cord.
            local sealCentre = (context ~= "" and 359 + contextHeight or 357) + 22
            local headingTop = sealCentre + 16
            moveTo(ledger.storyHeading, 367, headingTop)
            moveTo(ledger.summaryRule, 367, headingTop - 3)
            if ledger.summarySeal then
                ledger.summarySeal:ClearAllPoints()
                ledger.summarySeal:SetPoint("CENTER", ledger, "TOPLEFT", 631, -sealCentre)
            end
            -- The page turner sits at the bottom right, just above the opinions (owner 23/11, reference).
            for _, entry in ipairs({ { ledger.detailScroll.prev, 767, 542 }, { ledger.detailScroll.pageLabel, 803, 548 },
                { ledger.detailScroll.next, 861, 542 } }) do
                entry[1]:ClearAllPoints()
                entry[1]:SetPoint("TOPLEFT", ledger, "TOPLEFT", entry[2], -entry[3])
            end
            local bodyTop = headingTop + math.ceil(23 * (GL.Settings().readingScale or 1))
            moveTo(ledger.detailScroll, 367, bodyTop)
            ledger.detailScroll:SetHeight(535 - bodyTop)
            local guildRule = GL.GetGuildRule(record)
            lines = {
                "|cff653c20" .. L("Dernière rencontre") .. "|r",
                record.lastEncounterAt and (stamp(record.lastEncounterAt) .. (record.lastEncounterZone and "  ·  " .. plain(record.lastEncounterSubzone or record.lastEncounterZone) or "")) or L("Date non enregistrée"),
            }
            local story = GL.CharacterInsights and GL.CharacterInsights.Story(record) or {}
            if #story > 0 then
                local told = { "|cff653c20" .. L("Votre histoire") .. "|r" }
                -- The two counters just above already say it: the Journal skips that sentence (the sheet keeps it).
                local tally = record.pvp or {}
                local repeated = L("Il vous a tué %d fois ; vous l’avez vaincu %d fois."):format(tally.deaths or 0, tally.kills or 0)
                for _, sentence in ipairs(story) do
                    if sentence == repeated then sentence = nil end
                    if sentence then
                    summaryStory[#summaryStory + 1] = plain(sentence)
                    told[#told + 1] = plain(sentence)
                    end
                end
                told[#told + 1] = ""
                for i = #told, 1, -1 do table.insert(lines, 1, told[i]) end
                followingStart = #told + 2
            end
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
            if record.creatorName then
                lines[#lines + 1] = L("Créée par %s · %s"):format(plain(record.creatorName),eventDate({time=record.firstSeen}))
            end
            if record.tagHistory and #record.tagHistory>0 then
                lines[#lines+1] = "\n"..L("Étiquettes personnelles")
                local names={}
                for _,choice in ipairs(GL.TagChoices) do names[choice[1]]=L(choice[2]) end
                local changes={}
                for i,e in ipairs(record.tagHistory) do changes[i]=e end
                table.sort(changes,function(a,b) return a.time>b.time end)
                for _,e in ipairs(changes) do
                    lines[#lines+1]=eventDate(e).." · "..plain(e.actorName or e.actorGUID).."   "..(e.enabled and "+" or "−").." "..(names[e.id] or "")
                end
            end
            lines[#lines + 1] = counted(pvp.aggressions or 0, "agression")
            local awards = GL.ContactMatchup(record)
            lines[#lines + 1] = honorTotal(awards)
            lines[#lines + 1] = L("Honneur adverse inconnu")
            if guildRule and guildRule.note and guildRule.note ~= "" then lines[#lines + 1] = L("Note de guilde : %s"):format(plain(guildRule.note)) end
            if (record.groupCount or 0) > 0 then lines[#lines + 1] = subdued(L("Sessions de groupe : %d"):format(record.groupCount)) end
        elseif tab == "history" then
            renderHistory(ledger.historyPage, record)
        elseif tab == "notes" then
            local editor = noteEditor()
            if editor.identity ~= record then
                if editor.tagMenu then editor.tagMenu:Hide() end
                editor.identity, editor.noteOffset = record, 0
                selectNote(editor, record.notes[#record.notes])
            else editor:RefreshList() end
            editor:Show()
        end
    end
    ledger.detailText:SetSpacing(GL.Settings().compactMode and 2 or 4)
    local view = ledger.detailScroll
    local fullText = table.concat(lines, "\n")
    view.summaryMode = summary
    if summary then
        local currentPage, pages = view.page, {}
        -- ponytail: reuse measured text pages for the two sections; keep every sentence and the complete source text.
        if #summaryStory > 0 then
            view:SetText(table.concat(summaryStory, "\n"))
            for _, page in ipairs(view.pages) do pages[#pages + 1] = page end
        end
        view.storyPageCount = #pages
        view:SetText(table.concat(lines, "\n", followingStart))
        for _, page in ipairs(view.pages) do pages[#pages + 1] = page end
        view.pages, view.fullText = pages, fullText
        view.page = math.min(currentPage, #pages)
        view:Paint()
    else
        view.storyPageCount = 0
        view:SetText(fullText, true)
    end
end

local function enableRecognition()
    if GL.Safe(InCombatLockdown) then GL.Print(L("Activez le repérage hors combat.")) return end
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
        or L("Icônes et couleurs activées, mais le jeu n'a pas confirmé toutes les barres de noms. Vérifiez les réglages d'affichage."))
end

-- The settings were laid out on the old wide page (x 356 to 905). In the narrow book the sheet runs
-- from 240 to 900: positions and widths are spread over it, sizes of small controls are kept.
local SHEET_K = 660 / 549
local function sheetX(x) return math.floor(240 + (x - 356) * SHEET_K + 0.5) end
local function sheetW(w) return w < 40 and w or math.floor(w * SHEET_K + 0.5) end
-- Heights: the old page ran from 160 to 650; the sheet's last line must stay above 620.
local function sheetY(y) return math.floor(162 + (y - 160) * 0.92 + 0.5) end
local function sheetButton(page, text, x, y, width, ...)
    return button(page, text, sheetX(x), -sheetY(-y), sheetW(width), ...)
end
local function sheetIcon(page, x, y, size, texture) return bookIcon(page, sheetX(x), sheetY(y), size, texture) end
local function settingText(page, text, x, y, width, size, color)
    if page.onSheet then x, y, width = sheetX(x), sheetY(y), sheetW(width) end
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
        local f = bookWindow("GrudgeLedgerSettings", "Grudge Ledger", true)
        settingsWindow = f
        bookNavigation(f, "settings")
        f.tabs, f.pages, f.checks, f.sliders, f.previewRows = {}, {}, {}, {}, {}
        local categories = {
            {"appearance", L("Apparence"), L("Apparence et lisibilité")},
            {"alerts", L("Alertes"), L("Alertes de proximité")},
            {"relations", L("Relations et JcJ"), L("Ce que votre livre retient")},
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
            -- The entries of the Relations book: same place, size and step.
            local tab = button(f, entry[2], 38, -158 - (i - 1) * 36, 168, function() f:SelectCategory(key) end, true)
            tab:SetHeight(30)
            f.tabs[key] = tab
            local page = CreateFrame("Frame", nil, f)
            page:SetAllPoints(f) page.onSheet = true f.pages[key] = page
            settingText(page, entry[3], 356, 160, 554, 22)
        end
        local function check(category, key, text, y, width, x, save)
            local control = CreateFrame("CheckButton", nil, f.pages[category], "UICheckButtonTemplate")
            width = sheetW(width or 522)
            control:SetPoint("TOPLEFT", sheetX(x or 356) - 3, -sheetY(y)) control:SetSize(26, 26)
            control:SetHitRectInsets(0, -width + 28, 0, 0)
            settingText(control, text, 32, 4, width - 33, 14)
            control:SetScript("OnClick", function(self) if save then save(self:GetChecked() and true or false) else GL.SetSetting(key, self:GetChecked() and true or false) end end)
            if not save then f.checks[key] = control end
            return control
        end
        local function range(page, key, title, x, y, width, low, high, step, format)
            x, y, width = sheetX(x), sheetY(y), sheetW(width) - 8
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
            local valueText = label(page, "", nil, x, -y, width)
            journalFont(valueText, "GameFontHighlight", 14) valueText:SetTextColor(unpack(theme.ink))
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
        f.grimoire = sheetButton(p, L("Grimoire · PT Serif"), 356, -243, 145, function() GL.SetSetting("readableFont", false) end, true, true)
        f.classic = sheetButton(p, L("Classique"), 509, -243, 127, function() GL.SetSetting("readableFont", true) end, true, true)
        check("appearance", "compactMode", L("Espacement compact"), 282, 266)
        f.readingLabel = settingText(p, "", 356, 326, 142, 13)
        sheetButton(p, "−", 500, -317, 29, function() GL.SetSetting("readingScale", (GL.Settings().readingScale or 1) - 0.05) end, nil, true)
        sheetButton(p, "+", 535, -317, 29, function() GL.SetSetting("readingScale", (GL.Settings().readingScale or 1) + 0.05) end, nil, true)
        sheetButton(p, "100 %", 569, -317, 68, function() GL.SetSetting("readingScale", 1) end, nil, true)
        check("appearance", "markers", L("Icônes près des noms"), 368, 272)
        check("appearance", "nameColor", L("Colorer aussi le nom"), 402, 272)
        check("appearance", "chatBadges", L("Marquer les contacts dans le chat"), 482, 272, 640)
        range(p, "iconSize", L("Taille des icônes"), 356, 457, 258, 12, 40, 1, function(n) return math.floor(n + .5) .. " px" end)
        settingText(p, L("Aperçu des marqueurs"), 640, 213, 261, 17)
        for i, data in ipairs({{"friend", L("Oriane · Ami")}, {"warning", L("Hélène · Méfiance")}, {"enemy", L("Bastian · Ennemi")}, {"neutral", L("Neutre")}}) do
            local y = 256 + (i-1)*52
            local icon = sheetIcon(p, 644, y, 20, media .. relationIcons[data[1]])
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
        sheetButton(p, L("Activer le repérage"), 356, -586, 222, enableRecognition, nil, true)
        settingText(p, L("Le repérage utilise les barres de nom compatibles."), 590, 586, 315, 13, theme.inkMuted)
        check("appearance", "compactTooltips", L("Infobulle compacte (Maj pour les détails)"), 626)
        p = f.pages.alerts
        check("alerts", "friendAlerts", L("Signaler un ami"), 217, 268)
        check("alerts", "enemyAlerts", L("Signaler une menace"), 251, 268)
        check("alerts", "sounds", L("Jouer un son"), 285, 268)
        check("alerts", "indirectAlerts", L("Signaux indirects de menace"), 318, 268)
        -- Guild watch: receive on by default; sending reveals your zone, so it is opt-in.
        settingText(p, L("Veille de guilde"), 356, 478, 275, 16)
        check("alerts", "guildSightings", L("M’alerter des repérages"), 501, 270)
        f.shareSightings = check("alerts", nil, L("Signaler mes repérages"), 501, 270, 638,
            function(value)
                GL.SharedDossiers.ShareSightings(value)
                f:SyncControls()
            end)
        f.shareSightings:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:AddLine(L("Envoie à votre guilde le nom du joueur et la zone où vous le voyez, au plus une fois toutes les deux minutes par joueur. Désactivé par défaut."),1,1,1,true)
            GameTooltip:Show()
        end)
        f.shareSightings:SetScript("OnLeave",function() GameTooltip:Hide() end)
        range(p, "alertCooldown", L("Délai des menaces"), 356, 350, 261, 15, 3600, 15, delayText)
        settingText(p, L("Tester au-dessus du chat"), 638, 213, 275, 17)
        for i, entry in ipairs({{"enemy", L("Aperçu d’une menace")}, {"friend", L("Aperçu d’un ami")}}) do
            local relation, y = entry[1], 254 + (i-1)*67
            sheetIcon(p, 641, y, 34, media .. relationIcons[relation])
            local b = sheetButton(p, entry[2], 688, -y-3, 219, function()
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
        check("alerts", "tagReminders", L("Rappels privés des étiquettes en groupe"), 629)
        settingText(p, L("Petit groupe en monde ouvert ou donjon. Un message au plus par minute et par personne toutes les 30 minutes."), 356, 582, 547, 13, theme.inkMuted)
        p = f.pages.relations
        check("relations", "pvpTracking", L("Enregistrer le PvP en monde ouvert"), 203)
        check("relations", "socialTracking", L("Noter mes gestes envers les joueurs"), 235)
        check("relations", "groupTracking", L("Compter les groupes avec mes contacts"), 267)
        check("relations", "tradeTracking", L("Consigner les échanges réussis avec mes contacts"), 299)
        settingText(p, L("Comment évolue une rancune ?"), 356, 340, 544, 18)
        -- Each player sets their own weights; the balances are recomputed at once.
        range(p, "grudgeAggression", L("Il vous agresse"), 356, 366, 178, 0, 10, 1, function(value) return "−" .. value end)
        range(p, "grudgeDeath", L("Il vous tue"), 541, 366, 178, 0, 10, 1, function(value) return L("−%d de plus"):format(value) end)
        range(p, "grudgeVictory", L("Vous le tuez"), 726, 366, 178, 0, 10, 1, function(value) return "+" .. value end)
        settingText(p, L("Par défaut, une vie pour une vie. Un agresseur reste ennemi même tué. Riposte : −1."), 356, 425, 548, 14)
        settingText(p, L("Champs de bataille et arènes"), 356, 606, 548, 17)
        settingText(p, L("Enregistrement et alertes en pause. Vos notes et vos choix manuels restent accessibles et prioritaires."), 356, 635, 548, 13, theme.inkMuted)
        f.shareGuild = settingText(p, "", 356, 461, 541, 16)
        f.shareFights = check("relations", nil, L("Partager mes victoires et morts avec ma guilde"), 489, nil, nil,
            function(value) GL.Bounties.ShareFights(value); f:SyncControls() end)
        f.shareDeaths = check("relations", nil, L("Signaler mes morts pour les primes automatiques"), 520, nil, nil,
            function(value) GL.Bounties.ShareDeaths(value); f:SyncControls() end)
        f.shareSocial = check("relations", nil, L("Partager mes faits datés et mon avis de guilde"), 551, nil, nil,
            function(value) GL.SharedDossiers.ShareSocial(value); f:SyncControls() end)
        f.shareSocial:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:AddLine(L("Partage votre solde, votre relation et jusqu’à 32 faits récents par personnage publié ou mis à prix. Les notes et motifs libres restent privés."),1,1,1,true)
            GameTooltip:Show()
        end)
        f.shareSocial:SetScript("OnLeave",function() GameTooltip:Hide() end)
        -- What leaves without any box checked (audit 0.12.0, problem 8).
        local publicHelp = L("Sans rien cocher, seuls vos relevés publics (Armurerie, inspection) répondent à la guilde.")
        settingText(p, publicHelp, 356, 582, 548, 12, theme.inkMuted)
        p = f.pages.shortcuts
        check("shortcuts", "quickGestures", L("Afficher les boutons bisou et crachat"), 219)
        for i, entry in ipairs({{media.."GestureKiss", L("Envoyer un baiser · +1")}, {"Interface\\Icons\\Spell_Nature_CorrosiveBreath", L("Cracher · −1")}}) do
            local x = 358 + (i-1)*280
            sheetIcon(p, x+6, 284, 64, entry[1])
            settingText(p, entry[2], x, 362, 260, 16)
        end
        settingText(p, L("Sélectionnez d’abord un joueur. Les deux gestes utilisent votre cible actuelle."), 356, 419, 547, 15)
        sheetButton(p, L("Replacer les boutons"), 356, -494, 245, function() if GL.ResetGesturePosition then GL.ResetGesturePosition() end end, nil, true)
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
        f.report = sheetButton(p, L("Afficher le rapport"), 356, -437, 253, function() showDiagnostic(false) end, nil, true)
        f.traces = sheetButton(p, L("Consulter les traces"), 644, -437, 260, function() showDiagnostic(true) end, nil, true)
        settingText(p, L("Version de l’addon : %s"):format(tostring(GL.version)), 356, 491, 548, 13)
        f.guide = sheetButton(p, L("Revoir les premiers pas"), 356, -530, 253, function() GL.ShowGuide() end, nil, true)
        f.clearAction = sheetButton(p, L("Effacer les traces…"), 644, -530, 260, function(self)
            if self.armed then
                GL.ClearDetectionLog() self.armed = false self:SetText(L("Effacer les traces…"))
            else self.armed = true self:SetText(L("Confirmer l’effacement")) end
        end, nil, true)
        f.experimental = sheetButton(p, L("Outils expérimentaux"), 356, -596, 253, function()
            showIf(f.experimentalText, not f.experimentalText:IsShown())
        end, nil, true)
        f.experimentalText = settingText(p, L("Radar druide en recherche. L’essai manuel reste accessible dans le diagnostic."), 644, 591, 262, 13, theme.inkMuted)
        f.experimentalText:Hide()
        function f:SyncControls()
            local settings = GL.Settings()
            for key, c in pairs(self.checks) do c:SetChecked(settings[key]) end
            local guild = GL.Safe(GetGuildInfo, "player")
            local fights, deaths
            if GL.Bounties and GL.Bounties.Sharing then fights, deaths = GL.Bounties.Sharing() end
            self.shareFights:SetChecked(fights == true); self.shareDeaths:SetChecked(deaths == true)
            self.shareFights:SetEnabled(guild ~= nil and GL.Bounties ~= nil); self.shareDeaths:SetEnabled(guild ~= nil and GL.Bounties ~= nil)
            self.shareSocial:SetChecked(GL.SharedDossiers and GL.SharedDossiers.SharingSocial() or false)
            self.shareSocial:SetEnabled(guild ~= nil and GL.SharedDossiers ~= nil)
            self.shareSightings:SetChecked(GL.SharedDossiers and GL.SharedDossiers.SharingSightings() or false)
            self.shareSightings:SetEnabled(guild ~= nil and GL.SharedDossiers ~= nil)
            self.shareGuild:SetText(guild and L("Partage avec %s"):format(UI.plain(guild)) or L("Partage de guilde · hors guilde"))
            self.readingLabel:SetText(L("Lecture : %d %%"):format(math.floor(settings.readingScale*100 + .5)))
            for key, slider in pairs(self.sliders) do slider:Sync(settings[key]) end
            self:DrawMarkers(settings.iconSize)
            UI.selectButton(self.classic, settings.readableFont)
            UI.selectButton(self.grimoire, not settings.readableFont)
            self:UpdatePlateStatus()
        end
        f:RegisterEvent("PLAYER_GUILD_UPDATE")
        f:SetScript("OnEvent", function(self) if self:IsShown() then self:SyncControls() end end)
    end
    settingsWindow:SyncControls()
    showBook(settingsWindow)
    settingsWindow:SelectCategory(settingsWindow.category)
end

function GL.ShowGuide()
    if not GL.db then return end
    if not guideWindow then
        local f = bookWindow("GrudgeLedgerGuide", "Grudge Ledger", true)
        guideWindow = f
        bookNavigation(f, "ledger")
        -- The narrow book: the emblem in the leather column, the three steps on the sheet.
        bookIcon(f, 44, 190, 154, GL.icon)
        local heading = settingText(f, L("Votre livre commence ici"), 262, 172, 620, 24)
        heading:SetJustifyH("CENTER")
        settingText(f, L("1. Sélectionnez un joueur"), 282, 236, 600, 20)
        settingText(f, L("Cliquez sur son personnage ou sur son portrait."), 282, 272, 600, 15)
        settingText(f, L("2. Donnez votre avis"), 282, 326, 600, 20)
        bookIcon(f, 284, 364, 44, media .. "GestureKiss")
        settingText(f, L("Bisou  +1"), 340, 377, 200, 17)
        bookIcon(f, 562, 364, 44, "Interface\Icons\Spell_Nature_CorrosiveBreath")
        settingText(f, L("Crachat  −1"), 618, 377, 230, 17)
        settingText(f, L("Le clic droit sur le portrait permet aussi de choisir un statut."), 282, 424, 600, 14)
        -- The first thing a new player must know: the book fills itself in PvP, nothing to set up.
        settingText(f, L("3. Le reste se fait seul"), 282, 474, 600, 20)
        settingText(f, L("Un joueur qui vous attaque ou vous tue entre dans le Journal, avec le récit du combat. Vos avis et vos notes s’y retrouvent."),
            282, 512, 600, 14)
        f.openJournal = button(f, L("Ouvrir le Journal"), 412, -574, 340, function() GL.ShowLedger() end, nil, true)
        UI.selectButton(f.openJournal, true)
        local revisit = settingText(f, L("Retrouvez ce guide dans les réglages, sous Données et diagnostic."), 262, 614, 620, 12, theme.inkMuted)
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
    -- Left column centred on the leather (23 to 347, owner 23/11): 300 units from x 35.
    f.addTarget = button(f, L("Ajouter la cible"), 188, -193, 147, function()
        local identity = GL.Identity("target")
        if not identity then GL.Print(L("Sélectionnez un joueur pour ouvrir sa fiche.")) return end
        local record = GL.Remember(identity, true)
        if record then
            if GL.Safe(UnitIsVisible, "target") == true then GL.RecordSeen(identity, true) end
            GL.ShowLedger(record.key)
        end
    end, nil, false)
    journalFont(f.addTarget.caption, "GameFontHighlightSmall", 12)
    f.search = CreateFrame("EditBox", nil, f)
    f.search:SetPoint("TOPLEFT", 35, -159)
    f.search:SetSize(300, 26)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(100)
    f.search.referenceSkin = true
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
    f.searchHint = label(f.search, L("Rechercher…"), nil, 28, -4, 260)
    f.searchHint:SetHeight(19)
    GL.Safe(f.searchHint.SetJustifyV, f.searchHint, "MIDDLE")
    GL.Safe(f.searchHint.SetWordWrap, f.searchHint, false)
    f.searchHint:SetTextColor(unpack(theme.muted))
    -- The list follows the typing (owner 23/11), a quarter of a second after the last key.
    local typed = 0
    f.search:SetScript("OnTextChanged", function(self, userInput)
        if self:GetText():find("%S") then f.searchHint:Hide() else
            f.searchHint:Show()
            if f.query and f.query ~= "" then f.query, offset = "", 0 refresh() end
            return
        end
        if not userInput then return end
        typed = typed + 1
        local mine = typed
        local function follow()
            if mine ~= typed then return end
            local query = self:GetText():match("^%s*(.-)%s*$")
            if query ~= (f.query or "") then f.query, offset = query, 0 refresh() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.25, follow) else follow() end
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
    -- One button names the current list with its count; a click shows the next of the four lists
    -- people open most. A list always starts clean: the other filters are put back.
    f.viewNames = { all = L("Tous"), debt = L("À régler"), friend = L("Amis"), any = L("Signalés") }
    function f.ShowView(key)
        closeMenu()
        filter = (key == "debt" or key == "friend") and key or "all"
        tagFilter = key == "any" and "any" or "all"
        factionFilter, notesOnly, offset = "all", false, 0
        refresh()
    end
    -- No "Tous · N" button any more (owner 23/11): it cycled four hidden lists and silently reset the
    -- other filters; the same lists are in the Filtres panel (Avis, Étiquettes).
    f.bookmarks = {}
    -- Every other filter lives in one panel, opened on demand; it stays open while you choose.
    local panel = CreateFrame("Frame", nil, f)
    f.filterPanel = panel
    panel:SetPoint("TOPLEFT", 43, -228)
    panel:SetSize(283, 300)
    panel:EnableMouse(true)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetToplevel(true)
    if panel.SetFrameLevel then panel:SetFrameLevel(f:GetFrameLevel() + 8) end
    surface(panel, theme.gold)
    surface(panel, theme.panel, 1)
    panel:Hide()
    local function group(title, y, options, select, columns, width)
        local caption = label(panel, title, nil, 8, -y, 267)
        caption:SetTextColor(unpack(theme.brass))
        local choices = {}
        for i, entry in ipairs(options) do
            local value = entry[2]
            local x, row = 8 + ((i - 1) % columns) * (width + 2), math.floor((i - 1) / columns)
            choices[value] = button(panel, entry[1], x, -(y + 18) - row * 28, width, function()
                select(value)
                offset = 0
                refresh()
            end, true)
        end
        return caption, choices
    end
    f.relationFilter, f.filters = group(L("Avis"), 8, { { L("Tous les avis"), "all" }, { L("Comptes à régler"), "debt" },
        { L("Amis"), "friend" }, { L("Méfiance"), "warning" }, { L("Ennemis"), "enemy" }, { L("Neutres"), "neutral" } },
        function(value) filter = value end, 2, 133)
    f.factionFilter, f.factions = group(L("Faction"), 116, { { L("Toutes factions"), "all" }, { L("Alliance"), "Alliance" },
        { L("Horde"), "Horde" }, { L("Inconnue"), "unknown" } }, function(value) factionFilter = value end, 2, 133)
    local tail = 196
    if GL.TagChoices then
        local options = { { L("Toutes les étiquettes"), "all" }, { L("Tous les signalés"), "any" } }
        for _, entry in ipairs(GL.TagChoices) do options[#options + 1] = { L(entry[2]), entry[1] } end
        f.tagFilter, f.tagFilters = group(L("Étiquettes"), tail, options, function(value) tagFilter = value end, 2, 133)
        tail = tail + 18 + math.ceil(#options / 2) * 28 + 8
    end
    f.rows = {}
    f.notesOnly = button(panel, L("Avec notes"), 8, -tail, 133, function()
        notesOnly, offset = not notesOnly, 0
        refresh()
    end, true, false)
    -- The order of the list can only be chosen during a search; it lives with the other choices.
    f.sort = button(panel, L("Dernière interaction"), 8, -(tail + 30), 268, function()
        if not f.query or f.query == "" then return end
        for i, choice in ipairs(sortChoices) do
            if choice[1] == listSort then listSort = sortChoices[i % #sortChoices + 1][1] break end
        end
        offset = 0
        GL.SetSetting("listSort", listSort)
        refresh()
    end, nil, false)
    f.detail = button(panel, L("Détail : Identité"), 143, -tail, 133, function()
        for i, choice in ipairs(detailChoices) do
            if choice[1] == listDetail then listDetail = detailChoices[i % #detailChoices + 1][1] break end
        end
        GL.SetSetting("listDetail", listDetail)
        refresh()
    end, nil, false)
    if GL.TagChoices then
        f.sharedProfiles = button(panel, L("Fiches de guilde"), 8, -(tail + 60), 133, function()
            closeMenu()
            GL.OpenGuildProfiles(currentRecord())
        end)
    end
    f.reset = button(panel, L("Effacer"), 143, -(tail + 60), 65, function()
        filter, factionFilter, tagFilter, notesOnly, offset, f.query = "all", "all", "all", false, 0, ""
        f.search:SetText("")
        refresh()
    end)
    f.closeFilters = button(panel, L("Fermer"), 211, -(tail + 60), 65, closeMenu)
    panel:SetHeight(tail + 94)
    f.openFilters = button(f, L("Filtres"), 35, -193, 147, function() toggleMenu(panel) end)
    f.openFilters:SetHeight(25)
    for i = 1, 13 do
        local row = CreateFrame("Button", nil, f)
        row.referenceSkin = true
        row:SetPoint("TOPLEFT", 35, -230 - (i - 1) * 50)
        row:SetSize(300, 48)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(theme.red[1], theme.red[2], theme.red[3], 1)
        row.selection = row:CreateTexture(nil, "BORDER")
        row.selection:SetAllPoints()
        row.selection:SetTexture(media .. "JournalReferenceSelected")
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT") rule:SetPoint("BOTTOMRIGHT") rule:SetHeight(1)
        rule:SetColorTexture(theme.gold[1], theme.gold[2], theme.gold[3], 0.62)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.57, 0.39, 0.18, 0.16)
        row:SetHighlightTexture(hover)
        row.relationIcon = row:CreateTexture(nil, "ARTWORK")
        row.relationIcon:SetPoint("TOPLEFT", 238, -28)
        row.relationIcon:SetSize(18, 18)
        row.name = label(row, "", nil, 52, -4, 263)
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
        row.identity = label(row, "", nil, 70, -29, 164)
        -- 13 points and a lighter parchment tone: at 12 in the muted tone it read badly on the leather (owner 23/11).
        journalFont(row.identity, "GameFontHighlightSmall", 13)
        row.identity:SetTextColor(0.85, 0.77, 0.63)
        row.identity:SetHeight(18)
        GL.Safe(row.identity.SetWordWrap, row.identity, false)
        GL.Safe(row.identity.SetMaxLines, row.identity, 1)
        row.relation = label(row, "", nil, 255, -29, 63)
        journalFont(row.relation, "GameFontHighlightSmall", 12)
        row.relation:SetJustifyH("RIGHT")
        row.relation:SetHeight(18)
        GL.Safe(row.relation.SetWordWrap, row.relation, false)
        GL.Safe(row.relation.SetMaxLines, row.relation, 1)
        row:SetScript("OnClick", function(self) closeMenu() selectedKey = self.key f.detailScroll.page = 1 refresh() end)
        row:SetScript("OnEnter", function(self)
            local record = self.key and GL.Get(self.key)
            if not record or not GameTooltip then return end
            local faction, race, class = identityLabels(record)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(plain(record.fullName or record.name))
            GameTooltip:AddLine(plain(faction .. " · " .. race .. " · " .. class) .. (GL.ValidLevel(record.level) and " · " .. L("Niveau %d"):format(record.level) or ""))
            GameTooltip:AddLine(self.reconstructedPortrait and L("Aperçu reconstitué en jeu") or (self.liveModelPortrait or self.portraitUnit) and L("Portrait actuel du joueur") or (self.livePortraitGUID or self.archivedPortrait)
                and L("Portrait vu en jeu") or L("Icône générique"), 0.82, 0.78, 0.69)
            if record.guild then GameTooltip:AddLine(plain(record.guild)) end
            local tags = GL.TagText and GL.TagText(record)
            if tags then GameTooltip:AddLine(L("Étiquettes : %s"):format(tags), 1, 0.88, 0.55, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = row
    end
    f.previous = button(f, "‹", 42, -638, 32, function() offset = math.max(0, offset - f.pageSize) refresh() end, nil, false)
    f.next = button(f, "›", 298, -638, 32, function() offset = offset + f.pageSize refresh() end, nil, false)
    f.total = label(f, "", nil, 78, -644, 216)
    f.total:SetHeight(20) f.total:SetJustifyH("CENTER")
    journalFont(f.total, "GameFontHighlightSmall", 12)
    GL.Safe(f.total.SetWordWrap, f.total, false)
    f.total:SetTextColor(unpack(theme.muted))
    f.empty = label(f, "", nil, 43, -345, 284)
    f.empty:SetTextColor(unpack(theme.muted))
    f.raceIcon = f:CreateTexture(nil, "ARTWORK")
    f.raceIcon:SetPoint("TOPLEFT", 368, -166) f.raceIcon:SetSize(65, 66)
    f.portraitRim = f:CreateTexture(nil, "OVERLAY", nil, -1)
    f.portraitRim:SetPoint("TOPLEFT", 365, -163)
    f.portraitRim:SetSize(71, 72)
    f.portraitRim:SetTexture(media .. "JournalReferencePortrait")
    f.levelBadge = CreateFrame("Frame", nil, f)
    f.levelBadge:SetSize(28, 28)
    f.levelBadge:SetPoint("BOTTOMLEFT", f.raceIcon, "BOTTOMLEFT", -4, -4)
    bookIcon(f.levelBadge, 0, 0, 28, media .. "LevelMedallion")
    f.levelBadge.caption = bookText(f.levelBadge, 0, 0, 28, 28, 14, "", theme.paper)
    f.levelBadge.caption:SetJustifyH("CENTER")
    GL.Safe(f.levelBadge.caption.SetJustifyV, f.levelBadge.caption, "MIDDLE")
    f.levelBadge:EnableMouse(true)
    f.levelBadge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("Dernier niveau observé : %s"):format(self.caption:GetText()))
        GameTooltip:Show()
    end)
    f.levelBadge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.detailTitle = label(f, "", "large", 449, -160, 272)
    f.detailTitle:SetHeight(37)
    local function dossier()
        local r = currentRecord()
        if r and GL.OpenPlayerDossier then GL.OpenPlayerDossier(r.guid or r.key, function() GL.ShowLedger() end, r.fullName or r.name) end
    end
    local nameLink = CreateFrame("Button", nil, f)
    nameLink:SetAllPoints(f.detailTitle)
    nameLink:SetScript("OnClick", dossier)
    nameLink:SetScript("OnEnter", function(self)
        if currentRecord() then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText(L("Équipement et talents")) GameTooltip:Show() end
    end)
    nameLink:SetScript("OnLeave", function() GameTooltip:Hide() end)
    GL.Safe(f.detailTitle.SetWordWrap, f.detailTitle, false)
    journalFont(f.detailTitle, "Fancy24Font", 24)
    f.detailIcon = f:CreateTexture(nil, "ARTWORK")
    f.detailIcon:SetPoint("TOPLEFT", 760, -164)
    f.detailIcon:SetSize(36, 36)
    f.detailStatus = label(f, "", nil, 801, -168, 94)
    journalFont(f.detailStatus, "GameFontNormalLarge", 18) f.detailStatus:SetHeight(29)
    GL.Safe(f.detailStatus.SetWordWrap, f.detailStatus, false)
    f.classIcon = f:CreateTexture(nil, "ARTWORK")
    f.classIcon:SetPoint("TOPLEFT", 421, -220) f.classIcon:SetSize(15, 15)
    f.detailFaction = bookIcon(f, 447, 190, 20)  -- 3 higher: centred on the identity line (owner 23/11)
    f.detailIdentity = label(f, "", nil, 470, -194, 270)
    journalFont(f.detailIdentity, "GameFontHighlightSmall", 13)
    f.detailIdentity:SetTextColor(unpack(theme.inkMuted))
    f.detailIdentity:SetHeight(20)
    GL.Safe(f.detailIdentity.SetWordWrap, f.detailIdentity, false)
    f.detailGuild = label(f, "", nil, 449, -215, 285)
    f.detailGuild:SetTextColor(unpack(theme.ink)) f.detailGuild:SetHeight(22)
    GL.Safe(f.detailGuild.SetWordWrap, f.detailGuild, false)
    f.detailSource = label(f, "", nil, 746, -206, 149)
    journalFont(f.detailSource, "GameFontHighlight", 13, true)
    f.detailSource:SetJustifyH("RIGHT") f.detailSource:SetHeight(39) f.detailSource:SetTextColor(unpack(theme.inkMuted))
    f.actions, f.reactions = {}, {}
    for _, option in ipairs({ { L("Ami"), "friend", 365, 116 }, { L("Méfiance"), "warning", 487, 136 },
        { L("Ennemi"), "enemy", 629, 128 }, { L("Automatique"), "neutral", 763, 132 } }) do
        local value = option[2]
        -- Reactions and actions end on the list's last row (628, owner 23/11): 13 lower than before.
        local control = button(f, option[1], option[3], -572, option[4], function()
            local record = currentRecord()
            if record then GL.SetReaction(record, value) end
        end, true, true)
        control:SetHeight(25)
        journalFont(control.caption, "GameFontHighlightSmall", 13)
        if value ~= "neutral" then
            local icon = control:CreateTexture(nil, "OVERLAY")
            control.relationIcon = icon
            icon:SetTexture(media .. (referenceRelationIcons[value] or relationIcons[value]))
            icon:SetSize(value == "warning" and 24 or 18, value == "warning" and 14 or 18)
            icon:SetPoint("LEFT", 5, 0)
            local inset = value == "warning" and 31 or 25
            control.caption:ClearAllPoints()
            control.caption:SetPoint("LEFT", inset, 0)
            control.caption:SetPoint("RIGHT", -6, 0)
        end
        f.actions[#f.actions + 1], f.reactions[value] = control, control
    end
    f.addNote = button(f, L("Ajouter une note"), 763, -602, 132, function()
        local record = currentRecord()
        if record then GL.EditNote(record) end
    end, nil, true)
    f.addNote:SetHeight(26)
    f.actions[#f.actions + 1] = f.addNote
    f.toolsMenu = CreateFrame("Frame", nil, f)
    f.toolsMenu:SetSize(180, 154)
    f.toolsMenu:SetFrameStrata("FULLSCREEN_DIALOG") f.toolsMenu:SetToplevel(true) f.toolsMenu:EnableMouse(true)
    surface(f.toolsMenu, theme.gold) surface(f.toolsMenu, theme.panel, 1)
    f.tools = button(f, L("Autres actions"), 717, -602, 168, function() toggleMenu(f.toolsMenu) end, nil, true)
    f.tools:SetHeight(26)
    -- The menu opens above its button, right edges aligned, wherever the row places it.
    f.toolsMenu:SetPoint("BOTTOMRIGHT", f.tools, "TOPRIGHT", 0, 6)
    -- The full sheet is one visible click away, not hidden behind the name.
    f.openSheet = button(f, L("Ouvrir la fiche"), 365, -602, 172, function()
        local r = currentRecord()
        if r and GL.OpenPlayerDossier then
            GL.OpenPlayerDossier(r.guid or r.key, function() GL.ShowLedger() end, r.fullName or r.name)
        end
    end, nil, true)
    f.openSheet:SetHeight(26)
    -- No "+1 / -1" here any more (owner 23/11): Ami, Méfiance and Ennemi on the page, and the portrait's
    -- right-click menu, already set the opinion; a third way only blurred which one counts.
    f.guildButton = button(f.toolsMenu, L("Guilde"), 3, -3, 174, function()
        local record = currentRecord()
        f.toolsMenu:Hide()
        if record and record.guild then GL.ShowGuilds(record) end
    end)
    f.actions[#f.actions + 1] = button(f.toolsMenu, L("Corriger le PvP"), 3, -32, 174, function()
        f.toolsMenu:Hide()
        f.detailTab, f.historyPage.kind, f.historyPage.offset = "history", "pvp", 0
        renderDetail()
    end)
    local deleteDialog = "GRUDGE_LEDGER_DELETE_PROFILE"
    StaticPopupDialogs[deleteDialog] = {
        text = L("Supprimer votre fiche personnelle de %s ? Ses notes et son historique seront effacés sur ce compte. Pour retirer une publication dans toute la guilde, utilisez « Fiches de guilde »."),
        button1 = L("Supprimer"), button2 = L("Annuler"), timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, record)
            if currentRecord() ~= record or not GL.DeleteProfile(record) then
                GL.Print(L("La fiche a changé. Rouvrez-la pour la supprimer."))
            end
        end,
    }
    f:HookScript("OnHide", function() StaticPopup_Hide(deleteDialog) end)
    f.openHistory = button(f.toolsMenu, L("Histoire détaillée"), 3, -61, 174, function()
        f.toolsMenu:Hide()
        f.detailTab, f.historyPage.kind, f.historyPage.offset = "history", "all", 0
        renderDetail()
    end)
    f.openNotes = button(f.toolsMenu, L("Toutes les notes"), 3, -90, 174, function()
        f.toolsMenu:Hide()
        f.detailTab = "notes"
        renderDetail()
    end)
    -- Deleting stands a little apart from the harmless entries.
    f.actions[#f.actions + 1] = button(f.toolsMenu, L("Supprimer la fiche…"), 3, -125, 174, function()
        closeMenu()
        local record = currentRecord()
        if record then StaticPopup_Show(deleteDialog, plain(record.fullName or record.key), nil, record) end
    end)
    f.toolsMenu:Hide()
    f.contactBounty = button(f, L("Créer une prime"), 543, -602, 166, function()
        local r = currentRecord()
        if r then GL.OpenContactBounty(r.guid) end
    end, nil, true)
    f.contactBounty:SetHeight(26)
    -- Ink icons before the four actions (owner 23/11): open book, target, quill, menu.
    for i, control in ipairs({ f.openSheet, f.contactBounty, f.addNote, f.tools }) do
        local icon = control:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(media .. "JournalActionIcons")
        icon:SetTexCoord((i - 1) / 4, i / 4, 0, 1)
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 5, 0)
        control.actionIcon = icon
        control.caption:ClearAllPoints()
        control.caption:SetPoint("LEFT", 21, 0)
        control.caption:SetPoint("RIGHT", -4, 0)
        journalFont(control.caption, "GameFontHighlightSmall", 13)  -- as the opinions row, room for the icon
    end
    f.detailTabs = {}
    -- Never shown since 0.33.0: these three stay as the internal switches of the right page.
    for i, entry in ipairs({ { "summary", L("Synthèse") }, { "history", L("Histoire") }, { "notes", L("Notes") } }) do
        local key = entry[1]
        f.detailTabs[key] = button(f, entry[2], 354 + (i - 1) * 112, -234, 108, function()
            f.detailTab = key f.detailScroll.page = 1 renderDetail()
        end, true, true)
    end
    f.counters = CreateFrame("Frame", nil, f)
    f.counters:SetPoint("TOPLEFT", 365, -243) f.counters:SetSize(532, 126)
    f.backToSummary = button(f, "‹ " .. L("Retour au résumé"), 354, -234, 190, function()
        f.detailTab = "summary"
        f.detailScroll.page = 1
        renderDetail()
    end, nil, true)
    f.metrics = {}
    for i, entry in ipairs({ { "deaths", L("Vos morts") }, { "kills", L("Vous l’avez vaincu") } }) do
        local card = CreateFrame("Frame", nil, f.counters)
        card:SetPoint("TOPLEFT", (i - 1) * 270, 0) card:SetSize(262, 54)
        surface(card, theme.paper, 1, 1)
        card.skin = card:CreateTexture(nil, "BORDER")
        card.skin:SetAllPoints()
        card.skin:SetTexture(media .. "JournalReferenceStats")
        card.caption = label(card, entry[2], nil, 6, -4, card:GetWidth() - 12)
        journalFont(card.caption, "GameFontNormalLarge", 16)
        card.caption:SetTextColor(unpack(theme.ink)) card.caption:SetHeight(21) card.caption:SetJustifyH("CENTER")
        card.value = label(card, "0", "large", 6, -20, card:GetWidth() - 12)
        journalFont(card.value, "GameFontNormalLarge", 24)
        card.value:SetTextColor(unpack(theme.ink)) card.value:SetHeight(32) card.value:SetJustifyH("CENTER")
        f.metrics[entry[1]] = card
    end
    f.balancePanel = CreateFrame("Frame", nil, f.counters) f.balancePanel:SetAllPoints()
    local balanceCaption = label(f.balancePanel, L("Solde automatique"), nil, 32, -70, 238)
    journalFont(balanceCaption, "GameFontNormalLarge", 20) balanceCaption:SetTextColor(unpack(theme.ink)) balanceCaption:SetJustifyH("RIGHT")
    f.balance = label(f.balancePanel, "", nil, 286, -62, 160)
    -- The figure in Spectral SemiBold Italic, the face of the first reference pages (owner 23/11).
    journalFont(f.balance, "GameFontNormalLarge", 34, "Spectral-SemiBoldItalic") f.balance:SetTextColor(unpack(inkColors.enemy)) f.balance:SetHeight(44)
    -- When you are ahead (0.61.2): the figure turns gold and a few small stars twinkle around it, a
    -- quiet reward for good numbers. The stars live in their own frame, which only runs while shown.
    f.balanceStars = CreateFrame("Frame", nil, f.balancePanel)
    f.balanceStars:SetPoint("TOPLEFT", 272, -55)
    f.balanceStars:SetSize(70, 58)
    f.balanceStars.stars = {}
    for i, spot in ipairs({ { "TOPLEFT", 3, -14, 10 }, { "TOPRIGHT", -3, -8, 9 }, { "TOPRIGHT", 3, -42, 11 },
        { "TOPLEFT", -1, -46, 8 }, { "TOP", 0, -2, 7 } }) do
        local star = f.balanceStars:CreateTexture(nil, "OVERLAY")
        star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
        star:SetSize(spot[4], spot[4])
        star:SetPoint("CENTER", f.balanceStars, spot[1], spot[2], spot[3])
        star.phase, star.base = i * 1.3, spot[4]
        f.balanceStars.stars[i] = star
    end
    f.balanceStars.clock = 0
    f.balanceStars:SetScript("OnUpdate", function(self, elapsed)
        self.clock = self.clock + (tonumber(elapsed) or 0)
        for _, star in ipairs(self.stars) do
            local glow = 0.5 + 0.5 * math.sin(self.clock * 2.2 + star.phase)
            local side = star.base * (0.75 + 0.35 * glow)
            star:SetAlpha(0.25 + 0.75 * glow)
            star:SetSize(side, side)
        end
    end)
    f.balanceStars:Hide()
    f.formula = label(f.balancePanel, "", nil, 6, -96, 520)
    f.formula:SetTextColor(unpack(theme.ink)) f.formula:SetJustifyH("CENTER") f.formula:SetHeight(22)
    f.scoreContext = label(f.balancePanel, "", nil, 6, -114, 520)
    journalFont(f.scoreContext, "GameFontHighlightSmall", 11, true) f.scoreContext:SetTextColor(unpack(theme.inkMuted)) f.scoreContext:SetJustifyH("CENTER") f.scoreContext:SetHeight(17)
    f.summaryRule = f:CreateTexture(nil, "ARTWORK")
    f.summaryRule:SetPoint("TOPLEFT", 367, -374)
    f.summaryRule:SetSize(528, 1)
    f.summaryRule:SetColorTexture(theme.inkMuted[1], theme.inkMuted[2], theme.inkMuted[3], 0.45)
    if f.referenceSkin then
        -- Journal: the red seal on its gold cord closes the balance and opens the story, in place of the thin rule.
        f.summarySeal = f:CreateTexture(nil, "ARTWORK")
        f.summarySeal:SetTexture(media .. "JournalSeal")
        f.summarySeal:SetSize(464, 58)
        f.summarySeal:SetPoint("CENTER", f, "TOPLEFT", 631, -379)
        f.summaryRule:SetAlpha(0)
    end
    -- Pages instead of a scroll bar.
    f.detailScroll = UI.textPages(f, 528, 110)
    f.detailScroll:SetPoint("TOPLEFT", 367, -412)
    f.storyHeading = bookText(f, 367, 377, 380, 28, 19, L("Votre histoire"))
    f.encounterHeading = bookText(f, 367, 500, 360, 28, 19, L("Dernière rencontre"))
    f.encounterRule = f:CreateTexture(nil, "ARTWORK")
    f.encounterRule:SetPoint("TOPLEFT", 367, -496)
    f.encounterRule:SetSize(528, 1)
    f.encounterRule:SetColorTexture(theme.inkMuted[1], theme.inkMuted[2], theme.inkMuted[3], 0.45)
    local paintSummary = f.detailScroll.Paint
    function f.detailScroll:Paint()
        paintSummary(self)
        local storyPage = self.summaryMode and self.page <= (self.storyPageCount or 0)
        f.storyHeading:SetText(storyPage and L("Votre histoire") or L("Dernière rencontre"))
        showIf(f.storyHeading, self.summaryMode)
        local following = storyPage and self.page == self.storyPageCount
        showIf(f.encounterHeading, false)
        showIf(f.encounterRule, false)
    end
    for _, entry in ipairs({ { f.detailScroll.prev, 767, 542 }, { f.detailScroll.pageLabel, 803, 548 },
        { f.detailScroll.next, 861, 542 } }) do
        entry[1]:ClearAllPoints()
        entry[1]:SetPoint("TOPLEFT", f, "TOPLEFT", entry[2], -entry[3])
    end
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
        row.playerLevel = bookText(row, 55, 56, 149, 26, 16, "", theme.ink)
        row.opponentLevel = bookText(row, 207, 56, 222, 26, 16, "", theme.ink)
        row.badge = label(row, "", nil, 411, -29, 133) row.badge:SetJustifyH("RIGHT") row.badge:SetHeight(25)
        for _, field in ipairs({row.date, row.title, row.hint,row.badge}) do GL.Safe(field.SetWordWrap, field, false) end
        row.details = button(row, L("Détails"), 433, -56, 111, function() inspectEvent(row.record, row.event) end, nil, true)
        p.rows[i] = row
    end
    p.empty = label(p, "", nil, 14, -104, 512) p.empty:SetTextColor(unpack(theme.inkMuted))
    p.total = label(p, "", nil, 212, -329, 134) p.total:SetJustifyH("CENTER") p.total:SetTextColor(unpack(theme.ink))
    p.prev = button(p, L("Précédent"), 61, -323, 124, function() p.offset = math.max(0, p.offset - #p.rows) renderDetail() end, nil, true)
    p.next = button(p, L("Suivant"), 373, -323, 124, function() p.offset = p.offset + #p.rows renderDetail() end, nil, true)
    p:HookScript("OnHide", function() p.menu:Hide() end)
    f.detailBody = f.detailScroll
    f.detailText = f.detailScroll.body
    journalFont(f.detailText, "QuestFont_Large", 15)
    f.detailText:SetSpacing(4)
    -- The hint gave way to the "Ouvrir la fiche" button; the label stays for the font settings.
    local hint = label(f, "", nil, 356, -632, 181)
    f.hint = hint
    journalFont(hint, "GameFontHighlightSmall", 12, true)
    hint:SetHeight(34)
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
    -- The list fills the column down to the pager (owner 23/11: no empty band under it).
    local pageSize = compact and 13 or 8
    if f.pageSize == pageSize then return end
    f.pageSize, offset = pageSize, 0
    for i, row in ipairs(f.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 35, -230 - (i - 1) * (compact and 31 or 50))
        row:SetHeight(compact and 29 or 48)
        row.name:ClearAllPoints() row.name:SetPoint("TOPLEFT", compact and 34 or 52, compact and -7 or -4)
        row.relation:ClearAllPoints() row.relation:SetPoint("TOPLEFT", 231, compact and -8 or -6)
        row.relation:SetWidth(62)
        row.relationIcon:ClearAllPoints() row.relationIcon:SetPoint("TOPLEFT", compact and 6 or 216, -6)
        row.relationIcon:SetSize(compact and 20 or 18, compact and 20 or 18)
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
        notesOnly = notesOnly, tag = tagFilter, sort = listSort, selectedKey = selectedKey })
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
        ledger.detailScroll.page = 1
        ledger.toolsMenu:Hide()
    end
    local nemesisKey, companionKey = GL.Titles()
    for i, row in ipairs(ledger.rows) do
        local record = i <= ledger.pageSize and records[offset + i]
        if record then
            row.key = record.key
            local relation = GL.Relation(record)
            local color = colors[relation]
            row.name:SetText(plain(record.fullName or record.name or record.key))
            local chosen = selectedKey == record.key
            -- On the red selection the name keeps its hue, lightened halfway to white to stay readable.
            local lift = chosen and 0.5 or 0
            row.name:SetTextColor(color[1] + (1 - color[1]) * lift, color[2] + (1 - color[2]) * lift, color[3] + (1 - color[3]) * lift)
            -- Your nemesis and your best companion wear their title instead of the plain relation.
            local title = record.key == nemesisKey and L("Némésis") or record.key == companionKey and L("Compagnon")
            row.relation:SetText(title or "")
            row.relation:SetTextColor(color[1], color[2], color[3])
            if relationIcons[relation] then
                row.relationIcon:SetTexture(media .. (referenceRelationIcons[relation] or relationIcons[relation]))
                row.relationIcon:Show()
            else
                row.relationIcon:SetTexture(nil)
                row.relationIcon:Hide()
            end
            local faction, race, class = identityLabels(record)
            local detail = faction .. " · " .. race .. " · " .. class
            if listDetail == "seen" then
                -- Who, when and where: "Prêtre 44 · il y a 40 min · Feralas".
                local at = record.lastSeen or record.lastEncounterAt
                local age = at and math.max(0, GL.Now() - at)
                local when = not age and L("Pas encore croisé") or age < 60 and L("à l'instant")
                    or age < 3600 and L("il y a %d min"):format(math.floor(age / 60))
                    or age < 86400 and L("il y a %d h"):format(math.floor(age / 3600))
                    or L("il y a %d j"):format(math.floor(age / 86400))
                local level = GL.ValidLevel and GL.ValidLevel(record.level)
                local zone = record.lastZone or record.lastEncounterZone
                detail = class .. (level and (" " .. level) or "") .. " · " .. when .. (zone and (" · " .. zone) or "")
            elseif listDetail == "guild" then detail = record.guild or L("Guilde inconnue")
            elseif listDetail == "pvp" then
                local pvp = record.pvp or {}
                detail = counted(pvp.kills or 0, "victoire") .. " · " .. counted(pvp.deaths or 0, "mort")
            elseif listDetail == "notes" then
                local note = record.notes and record.notes[#record.notes]
                detail = note and note.text or L("Aucune note")
            end
            row.identity:SetText(plain(detail):gsub("[\r\n]", " "))
            local compact = GL.Settings().compactMode == true
            row.relationIcon:SetSize(relation == "warning" and 20 or compact and 20 or 18,
                relation == "warning" and 12 or compact and 20 or 18)
            local iconX = title and (relation == "warning" and 214 or 216) or (relation == "warning" and 272 or 274)
            moveTo(row.relationIcon, compact and 6 or iconX,
                relation == "warning" and (compact and 10 or 9) or 6)
            local tagWidth = journalTags(row, record, compact)
            row.name:SetWidth(compact and (195-tagWidth) or (title and 160 or 217))
            row.identity:SetWidth(compact and 225 or (225-tagWidth))
            identityIcons(row, record)
            local background = selectedKey == record.key and theme.red or theme.panel
            row.bg:SetColorTexture(unpack(background))
            row.bg:SetAlpha(selectedKey == record.key and 0.9 or 0)
            if selectedKey == record.key then row.selection:Show() else row.selection:Hide() end
            row:Show()
        else row.key = nil row:Hide() end
    end
    local pages = math.max(1, math.ceil(#records / ledger.pageSize))
    ledger.total:SetText(pages > 1 and L("Page %d/%d · %s"):format(math.floor(offset / ledger.pageSize) + 1, pages, counted(#records, "personne"))
        or counted(#records, "personne"))
    ledger.filtersActive = (ledger.query or "") ~= "" or filter ~= "all" or factionFilter ~= "all" or tagFilter ~= "all" or notesOnly
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
        blank.body:SetText(L("Ciblez un joueur pour ouvrir sa première fiche. Ceux qui vous attaquent ou vous tuent s’y inscrivent tout seuls."))
    end
    blank.action:SetText(ledger.filtersActive and L("Effacer les filtres") or L("Ajouter la cible"))
    for value, control in pairs(ledger.filters) do
        UI.selectButton(control, value == filter)
    end
    for value, control in pairs(ledger.factions) do
        UI.selectButton(control, value == factionFilter)
    end
    local relationName = filter == "all" and L("Tous les avis") or filter == "debt" and L("Comptes à régler") or relationNames[filter]
    ledger.relationFilter:SetText(L("Avis") .. " : " .. relationName)
    local factionName = factionNames[factionFilter] or (factionFilter == "unknown" and L("Inconnue") or L("Toutes factions"))
    ledger.factionFilter:SetText(L("Faction") .. " : " .. factionName)
    -- The quick view the filters amount to (used by the bookmarks).
    local unfiltered = factionFilter == "all" and not notesOnly
    local viewKey
    if unfiltered and tagFilter == "all" and (filter == "all" or filter == "debt" or filter == "friend") then
        viewKey = filter
    elseif unfiltered and filter == "all" and tagFilter == "any" then
        viewKey = "any"
    end
    ledger.viewKey = viewKey
    for key, bookmark in pairs(ledger.bookmarks) do
        bookmark.active = viewKey == key
        bookmark.skin:SetTexture(media .. bookmark.textureName .. (bookmark.active and "Active" or ""))
        local shade = bookmark.active and 1 or 0.6
        bookmark.skin:SetVertexColor(shade, shade, shade)
    end
    local active = (filter ~= "all" and 1 or 0) + (factionFilter ~= "all" and 1 or 0) + (tagFilter ~= "all" and 1 or 0) + (notesOnly and 1 or 0)
    ledger.openFilters:SetText(active > 0 and (L("Filtres") .. " · " .. active) or L("Filtres"))
    UI.selectButton(ledger.openFilters, active > 0)
    for value, control in pairs(ledger.tagFilters or {}) do
        UI.selectButton(control, value == tagFilter)
        if value == tagFilter then ledger.tagFilter:SetText(L("Étiquettes") .. " : " .. control:GetText()) end
    end
    ledger.previous:SetEnabled(offset > 0)
    ledger.next:SetEnabled(offset + ledger.pageSize < #records)
    ledger.sort:SetEnabled(searched)
    for _, choice in ipairs(sortChoices) do if choice[1] == listSort then ledger.sort:SetText(L("Tri : %s"):format(choice[2])) end end
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
    if honorBook then honorBook:Hide() end
    if key then
        selectedKey = record.key
        filter, factionFilter, tagFilter, offset, notesOnly = "all", "all", "all", 0, false
        ledger.query, ledger.detailTab = "", "summary"
        ledger.historyPage.kind, ledger.historyPage.offset = "all", 0
        ledger.search:SetText("")
        ledger.detailScroll.page = 1
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
    f.heading = label(f, L("Notes personnelles"), "large", 2, -4, 300) f.heading:SetTextColor(unpack(theme.ink))
    if GL.TagChoices then
        local menu = CreateFrame("Frame", nil, f)
        f.tagMenu, f.tagChoices = menu, {}
        menu:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -29) menu:SetSize(370, 98)
        menu:SetFrameStrata("FULLSCREEN_DIALOG") menu:SetToplevel(true) menu:EnableMouse(true)
        if menu.SetFrameLevel then menu:SetFrameLevel(f:GetFrameLevel()+8) end
        surface(menu, theme.gold) surface(menu, theme.paper, 1)
        for i, choice in ipairs(GL.TagChoices) do
            local id = choice[1]
            f.tagChoices[id] = button(menu, L(choice[2]), 5 + ((i-1)%2)*182, -5-math.floor((i-1)/2)*31, 178,
                function() GL.ToggleTag(f.identity, id) end, true, true)
        end
        f.tags = button(f, L("Étiquettes personnelles"), 328, -2, 222, function()
            if menu:IsShown() then menu:Hide() else menu:Show() menu:Raise() end
        end, nil, true)
        menu:Hide()
        f:HookScript("OnHide", function() menu:Hide() end)
    end
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
    local scroll = CreateFrame("ScrollFrame", nil, f)
    UI.wheelScroll(scroll)
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
        local tags = GL.TagText and GL.TagText(record)
        privacy:SetText(tags and L("Étiquettes : %s"):format(tags) or L("Ces notes restent dans votre livre."))
        for id, control in pairs(self.tagChoices or {}) do UI.selectButton(control, GL.HasTag(record, id)) end
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
    -- Center the medallion on the other launchers' orbit, including a custom LibDBIcon offset.
    local dbIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    local padding = GL.Clean(dbIcon and dbIcon.radius, "number") or 5
    if not (padding > -math.min(halfWidth, halfHeight) and padding < math.huge) then padding = 5 end
    local rimX, rimY = halfWidth + padding, halfHeight + padding
    local radius
    if roundQuadrants[shape] and roundQuadrants[shape][quadrant] then
        radius = 1 / math.sqrt((x / rimX)^2 + (y / rimY)^2)
    else
        radius = math.min(rimX / math.max(math.abs(x), 0.0001), rimY / math.max(math.abs(y), 0.0001))
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
        local due = GL.bountyDue
        if due and due.count > 0 then
            GameTooltip:AddLine(L("Primes à régler : %s"):format(due.text), 1, 0.35, 0.3)
        end
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
    if record and reason ~= "deleted" and record.guid then observeFace(portraitUnit(record)) end
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
    relations = "stats", relationships = "stats", relaciones = "stats",
    summary = "bilan", resumen = "bilan", history = "chronique", historial = "chronique",
    guilds = "guildes", hermandades = "guildes", guild = "guilde", hermandad = "guilde",
    logs = "traces", registros = "traces", ajustes = "settings", opciones = "options",
    markers = "reperage", marcadores = "reperage", diagnostico = "debug", ["diagnóstico"] = "debug",
    rapport = "debug", report = "debug", informe = "debug", bericht = "debug", relatorio = "debug", ["relatório"] = "debug",
    probe = "sonde", sonda = "sonde", map = "carte", mapa = "carte",
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
    elseif command == "carte" then
        if GL.RelationsPages then GL.RelationsPages.MapProbe() end
    elseif command == "sonde" then
        if GL.ReadingProbe then GL.ReadingProbe() end
    elseif command == "stats" then GL.ShowStatistics("players")
    elseif command == "bilan" then GL.ShowJournal("summary")
    elseif command == "chronique" then GL.ShowJournal("history")
    elseif command == "primes" or command == "bounties" then GL.OpenBounties()
    elseif command == "guildes" then GL.ShowStatistics("guilds")
    elseif command == "guide" then GL.ShowGuide()
    elseif command == "settings" or command == "options" then showSettings()
    elseif command == "reperage" or command == "repérage" then enableRecognition()
    elseif command == "guilde" then
        if reason == "" then GL.ShowGuilds() return end
        local relation = reason:gsub("[A-Z]", string.lower)
        local reaction = reactionCommands[commandAliases[relation] or relation]
        if not reaction then GL.Print(L("/gl guilde ami|ennemi|mefiance|neutre — utilisez la guilde de votre cible.")) return end
        local identity = GL.Identity("target")
        if not identity or not identity.guild then GL.Print(L("Sélectionnez un joueur dont la guilde est connue.")) return end
        GL.SetGuildReaction(identity, reaction)
    elseif command == "+" or command == "-" or reactionCommands[command] or command == "note" then
        local identity = GL.Identity("target")
        if not identity then GL.Print(L("Sélectionnez un joueur pour cette action.")) return end
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
