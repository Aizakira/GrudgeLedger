-- Grudge Ledger: personal markers, memory tooltips and proximity alerts.
-- Nameplate lifecycle/tooltip approach adapted from Worth Remembering by Kyle
-- (GPL-3.0); https://github.com/kk-on-gh/WorthRemembering. No runtime dependency.
local GL = GrudgeLedger
local L = GL.L
local D = {}
GL.Display = D

local styles = {
    friend = { label = "Ami", priority = 1, color = { 0.25, 1, 0.45 }, icon = "Interface\\AddOns\\GrudgeLedger\\Media\\RelationFriend" },
    warning = { label = "Méfiance", priority = 2, color = { 1, 0.6, 0.1 }, icon = "Interface\\AddOns\\GrudgeLedger\\Media\\RelationWarning" },
    enemy = { label = "Ennemi", priority = 3, color = { 1, 0.25, 0.2 }, icon = "Interface\\AddOns\\GrudgeLedger\\Media\\RelationEnemy" },
    neutral = { label = "Neutre", priority = 0, color = { 0.8, 0.8, 0.8 }, icon = "Interface\\AddOns\\GrudgeLedger\\Media\\RelationNeutral" },
}
local visible, markers, lastAlert, pendingNames = {}, {}, {}, {}
local guildBursts = {}
local signals, latestSignal = {}, nil
local toast, previewToast, elapsed = nil, nil, 0
local alert
local guildKiller
local lastSound
local function alertSetting(relation) return relation == "friend" and "friendAlerts" or "enemyAlerts" end

local function activeBounty(identity)
    local order = identity and GL.Bounties and GL.Bounties.OpenFor(identity.guid)
    if order and order.state == "open" then return order end
end

local function isGroupmate(record, unit)
    if unit and (GL.Safe(UnitInParty, unit) == true or type(GL.Safe(UnitInRaid, unit)) == "number") then return true end
    if not record.guid then return false end
    local count = GL.Clean(GL.Safe(GetNumGroupMembers), "number") or 0
    local raid = GL.Safe(IsInRaid) == true
    -- Only a live roster proves membership; group-history tracking may be off.
    for i = 1, count > 0 and (raid and math.min(count, 40) or 4) or 0 do
        if GL.Safe(UnitGUID, (raid and "raid" or "party") .. i) == record.guid then return true end
    end
    return false
end

local function newFriendEncounter(record, unit)
    if not unit or (not unit:match("^nameplate%d+$") and GL.Safe(UnitIsVisible, unit) ~= true) then return false end
    local me = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if not me then return false end
    record.friendPresence = type(record.friendPresence) == "table" and record.friendPresence or {}
    local previous = GL.Clean(record.friendPresence[me], "number")
    if previous and not (previous >= 0 and previous < math.huge) then previous = nil end
    local now = GL.Now()
    record.friendPresence[me] = now
    -- Sliding absence, not time since the last popup. A 600-second gap is still
    -- the same encounter; UI reloads and other characters keep separate clocks.
    return not previous or now - previous > 600
end

local function partyWarning(record, unit)
    if not record or not GL.db or GL.Settings().partyWarnings ~= true then return end
    local _, instanceType = GL.Safe(IsInInstance)
    local count = GL.Clean(GL.Safe(GetNumGroupMembers), "number")
    if (instanceType ~= "none" and instanceType ~= "party") or GL.Safe(IsInRaid) ~= false
        or not count or count < 2 or count > 5 or count % 1 ~= 0 then return end
    if not unit or (not unit:match("^nameplate%d+$") and GL.Safe(UnitIsVisible, unit) ~= true) then return end
    local me = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if not me or record.guid == me or GL.Safe(UnitIsUnit, unit, "player") == true or isGroupmate(record, unit) then return end
    local relation, pvp = GL.Relation(record), record.pvp or {}
    if relation ~= "warning" and relation ~= "enemy" then return end
    local confirmed = (pvp.deaths or 0) + (pvp.aggressions or 0) > 0
    if not confirmed then return end
    local name = GL.Clean(record.fullName or record.name, "string")
    -- Only the name and a fixed summary leave the personal journal, never notes.
    if not name or name == "" or #name > 120 or name:find("[%z\1-\31\127|{}]") then return end
    local now = GL.Clean(GL.Now(), "number")
    if not now or now ~= now or now <= 0 or now == math.huge then return end
    record.partyPresence = type(record.partyPresence) == "table" and record.partyPresence or {}
    local presence = record.partyPresence[me]
    if type(presence) ~= "table" then presence = {} record.partyPresence[me] = presence end
    GL.db.partyWarningLastAttempt = type(GL.db.partyWarningLastAttempt) == "table" and GL.db.partyWarningLastAttempt or {}
    -- Rebase future timestamps after a clock rollback rather than releasing
    -- every cooldown. Each opponent/character stores only two timestamps.
    local function timestamp(value)
        value = GL.Clean(value, "number")
        if value and value >= 0 and value < math.huge then return math.min(value, now) end
    end
    local previous = timestamp(presence.seenAt)
    local attempt = timestamp(presence.attemptAt)
    local globalAttempt = timestamp(GL.db.partyWarningLastAttempt[me])
    presence.seenAt, presence.attemptAt = now, attempt
    GL.db.partyWarningLastAttempt[me] = globalAttempt
    if (previous and now - previous <= 600) or (attempt and now - attempt < 1800)
        or (globalAttempt and now - globalAttempt < 60) then return end
    -- ponytail: no message queue. A crowded encounter never drains a backlog;
    -- failed/unavailable sends can retry only after a genuine new encounter.
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(send) ~= "function" then return end
    presence.attemptAt, GL.db.partyWarningLastAttempt[me] = now, now
    local message = L("[Grudge Ledger] Attention, %s : agression PvP enregistrée dans mon journal."):format(name)
    local ok = pcall(send, message, "PARTY")
    if not ok then GL.Debug(L("Avertissement de groupe refusé par le jeu ; aucun nouvel essai pendant cette rencontre.")) end
end

local function guildLabel(record, relation)
    if not record.guild then return nil end
    if GL.RelationSource(record) == "guild" and relation ~= "neutral" then
        return (relation == "friend" and L("Amitié de guilde : %s") or L("Rancune de guilde : %s")):format(record.guild)
    end
    return L("Guilde : %s"):format(record.guild)
end

local function recordNote(record)
    local note = record.notes and record.notes[#record.notes]
    if note and note.text ~= "" then return note.text:gsub("|", "||") end
    local rule = GL.RelationSource(record) == "guild" and GL.GetGuildRule(record)
    if rule and rule.note and rule.note ~= "" then return rule.note:gsub("|", "||") end
end

local function inheritedGuildKey(record)
    local rule = GL.RelationSource(record) == "guild" and GL.GetGuildRule(record)
    return rule and rule.key or nil
end

local function alertTitle(record, relation)
    if GL.RelationSource(record) == "guild" then return guildLabel(record, relation) end
    if GL.RelationSource(record) == "guildmates" then
        local opinion = GL.GuildOpinion(record.guid)
        local count = opinion and opinion.count > 0 and (" · " .. L("%d avis"):format(opinion.count)) or ""
        return L("Avis de la guilde : %s"):format(L(styles[relation].label)) .. count
    end
    return L("%s à proximité"):format(L(styles[relation].label))
end

local function refreshToastText(frame, record)
    if frame.banner then
        frame.title:SetText(frame.banner.title)
        frame.name:SetText(frame.banner.name)
        frame.note:SetText(frame.banner.note)
        return
    end
    if frame.sighting then
        local sight = frame.sighting
        local age = math.max(0, GL.Now() - sight.at)
        frame.title:SetText(sight.help and L("Appel à l’aide de %s"):format(sight.member or L("Membre de guilde"))
            or L("Repéré par la guilde · %s"):format(sight.bounty and L("Prime") or L(styles[frame.relation].label)))
        frame.name:SetText(record and (record.fullName or record.name) or sight.name ~= "" and sight.name or L("Joueur connu"))
        local who = L("Vu par %s · %s"):format(sight.member or L("Membre de guilde"), sight.zone ~= "" and sight.zone or L("lieu inconnu"))
        frame.note:SetText(who .. "\n" .. (age < 5 and L("à l'instant") or L("il y a %d s"):format(age))
            .. (frame.sameZone and (" · " .. L("dans votre zone")) or ""))
        return
    end
    if frame.signal then
        local age = math.max(0, GL.Now() - frame.signalAt)
        local title = L("Signal indirect · %s")
        frame.title:SetText(title:format(L(styles[frame.relation].label)))
        frame.name:SetText(record.fullName or record.name)
        frame.note:SetText(age == 0 and L("%s · à l’instant\nDistance inconnue"):format(L(frame.signal))
            or L("%s · il y a %d s\nDistance inconnue"):format(L(frame.signal), age))
        return
    end
    frame.title:SetText(frame.bounty and L("Cible de prime à proximité") or alertTitle(record, frame.relation))
    local name = record.fullName or record.name or L("Joueur connu")
    if record.guild and GL.RelationSource(record) ~= "guild" then name = name .. " <" .. record.guild .. ">" end
    frame.name:SetText(name)
    local hint = frame.bounty and L("Aucune consigne particulière.")
        or L("Déjà rencontré : %s"):format(record.lastZone or L("lieu inconnu"))
    local note = frame.bounty and frame.bounty.note
    -- A wanted player: what the guild offers and who asked, before the issuer's note.
    local price = ""
    if frame.bounty and GL.BountyTotal and GL.BountyMoney then
        local pot = GL.BountyTotal(frame.bounty)
        local issuer = GL.Bounties and GL.Bounties.MemberName and GL.Bounties.MemberName(frame.bounty.owner)
        price = (pot > 0 and L("Récompense : %s"):format(GL.BountyMoney(pot)) or L("Avis de recherche, sans or"))
            .. (issuer and (" · " .. L("demandé par %s"):format(issuer)) or "") .. "\n"
    end
    frame.note:SetText(price .. (note and note ~= "" and note:gsub("|", "||") or recordNote(record) or hint))
end

local function validateToast()
    if not toast or not toast:IsShown() then return end
    if GL.IsPvPInstance() then toast:Hide() return end
    if toast.banner then
        if GL.Now() >= toast.expires then toast:Hide() end
        return
    end
    if toast.sighting then
        if GL.Now() >= toast.expires or not GL.Settings().guildSightings then
            toast:Hide()
        else
            refreshToastText(toast, GL.Get(toast.key))
        end
        return
    end
    local record = GL.Get(toast.key) or toast.bountyIdentity
    local bounty = toast.bounty and activeBounty(record)
    if not record or (toast.bounty and (not bounty or bounty.id ~= toast.bounty.id))
        or (not toast.bounty and (GL.Relation(record) ~= toast.relation or GL.RelationSource(record) ~= toast.source
        or inheritedGuildKey(record) ~= toast.guildKey))
        or GL.Now() >= toast.expires or not GL.Settings()[alertSetting(toast.relation)]
        or (toast.signal and not GL.Settings().indirectAlerts)
        or ((toast.signal or toast.relation == "friend") and isGroupmate(record)) then toast:Hide()
    else toast.bounty = bounty; refreshToastText(toast, record) end
end

local function canChange(region)
    if not GL.Safe(InCombatLockdown) then return true end
    if GL.Safe(region.IsProtected, region) == false then return true end
    return GL.Safe(region.CanChangeProtectedState, region) == true
end

local function colorOf(font)
    if not font then return nil end
    local r, g, b, a = GL.Safe(font.GetTextColor, font)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return { r, g, b, type(a) == "number" and a or 1 }
    end
end

local function sameColor(a, b)
    return a and b and math.abs(a[1] - b[1]) < 0.001
        and math.abs(a[2] - b[2]) < 0.001 and math.abs(a[3] - b[3]) < 0.001
end

local function restoreName(marker)
    -- Do not overwrite a newer color already set by Blizzard/another nameplate addon.
    if marker.font and marker.baseColor and sameColor(colorOf(marker.font), marker.appliedColor) then
        local ok = false
        if canChange(marker.font) then ok = pcall(marker.font.SetTextColor, marker.font, unpack(marker.baseColor)) end
        if not ok then pendingNames[marker.font] = { base = marker.baseColor, applied = marker.appliedColor } end
    end
    marker.font, marker.baseColor, marker.appliedColor = nil, nil, nil
end

local function hideMarker(marker)
    if not marker then return end
    restoreName(marker)
    GL.Safe(marker.frame.Hide, marker.frame)
    marker.key, marker.owner = nil, nil
end

local function findName(plate)
    local tp = plate.TPFrame
    local font = tp and tp.visual and tp.visual.NameText
    if font and GL.Safe(tp.IsShown, tp) ~= false and GL.Safe(font.IsShown, font) ~= false
        and GL.Safe(font.IsVisible, font) ~= false then return font end
    local unitFrame = plate.UnitFrame
    font = unitFrame and (unitFrame.name or unitFrame.Name)
    if font and GL.Safe(font.IsShown, font) ~= false and GL.Safe(font.IsVisible, font) ~= false then return font end
end

local function ensureMarker(plate)
    if markers[plate] then return markers[plate] end
    local frame = CreateFrame("Frame", nil, plate)
    frame:EnableMouse(false)
    local level = GL.Safe(plate.GetFrameLevel, plate) or 0
    local tpLevel = plate.TPFrame and GL.Safe(plate.TPFrame.GetFrameLevel, plate.TPFrame) or 0
    frame:SetFrameLevel(math.max(level, tpLevel) + 20)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.025, 0.025, 0.025, 0.95)
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetVertexColor(1, 1, 1)
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local marker = { frame = frame, icon = icon }
    markers[plate] = marker
    return marker
end

local nearbyDead,followAlerts={},{}
local function encounterState(record,unit)
    if not record or not record.guid or not GL.Settings().enemyAlerts then return end
    local watched=record.followEncounter
    if not watched and GL.Relation(record)~="enemy" then return end
    local now=GL.Now()
    local dead=GL.Safe(UnitIsDeadOrGhost,unit)
    if dead==true then
        nearbyDead[record.guid]=now
    elseif dead==false then
        local seen=nearbyDead[record.guid]
        nearbyDead[record.guid]=nil
        if seen and now>=seen and now-seen<=120 then
            GL.Print(record.fullName.." vient de ressusciter à proximité.")
            followAlerts[record.guid]=now
        elseif watched and (not followAlerts[record.guid] or now-followAlerts[record.guid]>=90) then
            GL.Print(record.fullName.." est à proximité.")
        end
        if watched then followAlerts[record.guid]=now end
    end
end

local function updateMarker(entry, reuseObservation)
    local plate = C_NamePlate and GL.Safe(C_NamePlate.GetNamePlateForUnit, entry.unit)
    if entry.plate ~= plate then
        local previous = entry.plate and markers[entry.plate]
        if previous and previous.owner == entry then hideMarker(previous) end
        entry.plate = plate
    end
    if not plate then entry.identity = nil; return end
    local marker = markers[plate]
    local identity = GL.Identity(entry.unit, reuseObservation)
    entry.identity = identity
    -- Refresh membership as well as identity: guild rules can change while the
    -- same player stays visible, and leaving a guild must remove its marker.
    local record = identity and GL.RecordSeen(identity, true)
    -- Unknown to you but judged by guildmates: shown as they see the player, never added to your journal.
    if not record and identity and GL.GuildOpinion(identity.guid) then record = identity end
    encounterState(record,entry.unit)
    partyWarning(record, entry.unit)
    local relation = record and GL.Relation(record)
    local guildKey = record and inheritedGuildKey(record)
    local bounty = activeBounty(identity)
    local bountyID = bounty and bounty.id
    if alert and ((bountyID and entry.bountyID ~= bountyID) or (record and
        (relation == "friend" or entry.recordKey ~= record.key or entry.relation ~= relation or entry.guildKey ~= guildKey))) then
        alert(identity, entry.unit)
    end
    entry.bountyID = bountyID
    entry.recordKey, entry.relation, entry.guildKey = record and record.key, relation, guildKey
    local style = relation and styles[relation]
    if not style or GL.IsGroupOnly(record) or not GL.Settings().markers then
        if marker and (not marker.owner or marker.owner == entry) then hideMarker(marker) end
        return
    end
    if not canChange(plate) then GL.Trace("protected", identity, entry.unit) hideMarker(marker) return end
    marker = marker or ensureMarker(plate)
    if marker.key ~= record.key then restoreName(marker) end
    marker.key, marker.owner = record.key, entry
    local font = findName(plate)
    -- ThreatPlates ignores Blizzard's faded/hidden plate alpha and scale itself.
    -- Our overlay must do the same when its visible name is supplied by TP.
    local usesTP = plate.TPFrame ~= nil and GL.Safe(plate.TPFrame.IsShown, plate.TPFrame) ~= false
    if marker.usesTP ~= usesTP then
        GL.Safe(marker.frame.SetIgnoreParentAlpha, marker.frame, usesTP)
        GL.Safe(marker.frame.SetIgnoreParentScale, marker.frame, usesTP)
        marker.usesTP = usesTP
    end
    local level = GL.Safe(plate.GetFrameLevel, plate) or 0
    local tpLevel = usesTP and GL.Safe(plate.TPFrame.GetFrameLevel, plate.TPFrame) or 0
    level = math.max(level, tpLevel or 0) + 20
    if marker.level ~= level then marker.frame:SetFrameLevel(level) marker.level = level end
    local size = GL.Settings().iconSize or 20
    if marker.size ~= size then marker.frame:SetSize(size, size) marker.size = size end
    local anchor = font or plate
    if marker.anchor ~= anchor then
        marker.frame:ClearAllPoints()
        if font then marker.frame:SetPoint("RIGHT", font, "LEFT", -5, 0)
        else marker.frame:SetPoint("BOTTOM", plate, "TOP", 0, 5) end
        marker.anchor = anchor
    end
    if marker.texture ~= style.icon then marker.icon:SetTexture(style.icon) marker.texture = style.icon end
    marker.frame:Show()
    if relation ~= "neutral" and GL.Settings().nameColor and font and canChange(font) then
        if marker.font ~= font then restoreName(marker) end
        local current = colorOf(font)
        if current and not sameColor(current, marker.appliedColor) then marker.baseColor = current end
        marker.font = font
        marker.appliedColor = style.color
        if not sameColor(current, style.color) then
            GL.Safe(font.SetTextColor, font, style.color[1], style.color[2], style.color[3], 1)
        end
    else restoreName(marker) end
end

local function makeToast(preview)
    if preview and previewToast then return previewToast end
    if not preview and toast then return toast end
    local frame = CreateFrame("Button", preview and "GrudgeLedgerAlertPreview" or "GrudgeLedgerNearbyAlert", UIParent)
    frame:SetSize(416, 112)
    if ChatFrame1 then
        -- Follow the chat layout, leaving room for tabs and small panels above it.
        frame:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 96)
    else
        -- ponytail: custom chat replacements without ChatFrame1 use a fixed corner.
        -- Add a custom anchor only if such a layout needs its own positioning.
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 320)
    end
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    GL.Safe(frame.SetClipsChildren, frame, true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetAllPoints()
    frame.border:SetColorTexture(0.48, 0.35, 0.18, 1)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetPoint("TOPLEFT", 1, -1)
    frame.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.bg:SetColorTexture(0.055, 0.043, 0.042, 0.98)
    local leather = frame:CreateTexture(nil, "BORDER")
    leather:SetAllPoints()
    leather:SetTexture("Interface\\AddOns\\GrudgeLedger\\Media\\JournalDialog")
    frame.stripe = frame:CreateTexture(nil, "ARTWORK")
    frame.stripe:SetPoint("TOPLEFT", 1, -1)
    frame.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    frame.stripe:SetWidth(3)
    frame.iconBacking = frame:CreateTexture(nil, "ARTWORK")
    frame.iconBacking:SetPoint("TOPLEFT", 18, -34)
    frame.iconBacking:SetSize(42, 42)
    frame.iconBacking:SetColorTexture(0.48, 0.35, 0.18, 1)
    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetSize(38, 38)
    frame.icon:SetPoint("TOPLEFT", 20, -36)
    local function textLine(font, x, y, width, height, lines, r, g, b)
        local text = frame:CreateFontString(nil, "OVERLAY", font)
        text:SetPoint("TOPLEFT", x, -y)
        text:SetSize(width, height)
        text:SetJustifyH("LEFT")
        text:SetTextColor(r, g, b)
        GL.Safe(text.SetJustifyV, text, "TOP")
        GL.Safe(text.SetWordWrap, text, lines > 1)
        GL.Safe(text.SetNonSpaceWrap, text, true)
        GL.Safe(text.SetMaxLines, text, lines)
        return text
    end
    -- Fixed text rectangles remain bounded on clients without SetMaxLines;
    -- the complete name and note remain available in the captured player's file.
    frame.title = textLine("GameFontNormal", 76, 9, 324, 18, 1, 0.91, 0.86, 0.74)
    frame.name = textLine("GameFontNormalLarge", 76, 33, 324, 21, 1, 0.91, 0.86, 0.74)
    frame.note = textLine("GameFontHighlightSmall", 76, 57, 324, 28, 2, 0.78, 0.72, 0.61)
    frame.divider = frame:CreateTexture(nil, "ARTWORK")
    frame.divider:SetPoint("TOPLEFT", 16, -88)
    frame.divider:SetSize(384, 1)
    frame.divider:SetColorTexture(0.48, 0.35, 0.18, 0.6)
    frame.hint = textLine("GameFontHighlightSmall", 16, 95, 384, 14, 1, 0.65, 0.59, 0.48)
    frame.hint:SetText(L("Clic : fiche  •  clic droit : fermer"))
    -- An action of its own on some alerts ("Rechercher" on a guild killer), beside the hint.
    if GL.UITheme and GL.UITheme.button then
        frame.action = GL.UITheme.button(frame, "", 294, -90, 106, function()
            local action = frame.banner and frame.banner.action
            frame:Hide()
            if action then action.run() end
        end)
        frame.action:SetHeight(20)
        frame.action:Hide()
    end
    frame.accent = { 0.48, 0.35, 0.18 }
    frame:SetScript("OnEnter", function(self) self.border:SetColorTexture(0.68, 0.51, 0.28, 1) end)
    frame:SetScript("OnLeave", function(self) self.border:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 1) end)
    frame:SetScript("OnClick", function(self, button)
        local key = self.key
        self:Hide()
        if button == "LeftButton" then
            if self.banner and self.banner.onClick then self.banner.onClick()
            elseif self.bounty and GL.OpenBounties then GL.OpenBounties(self.bounty.target)
            elseif self.sighting and key and GL.OpenPlayerDossier then
                -- A player the guild spotted may not be in your journal: open the sheet directly.
                GL.OpenPlayerDossier(key:match("^guid:(.+)$") or key, nil, self.sighting.name)
            elseif key and GL.ShowLedger then GL.ShowLedger(key) end
        end
    end)
    -- ponytail: clicking opens the captured record, avoiding protected targeting
    -- and recycled unit-token hazards. A future targeting control needs secure UI.
    frame:Hide()
    if preview then previewToast = frame else toast = frame end
    return frame
end

-- The two special alerts: their frame, stripe and title in their own colour (the art will come later).
local accents = { wanted = { 0.88, 0.66, 0.20 }, killer = { 0.85, 0.40, 0.10 } }
local function styleToast(frame, style, accent)
    local color = accents[accent] or style.color
    frame.icon:SetTexture(style.icon)
    frame.icon:SetVertexColor(1, 1, 1)
    frame.stripe:SetColorTexture(color[1], color[2], color[3], 1)
    frame.stripe:SetWidth(accent and 6 or 3)
    frame.title:SetTextColor(unpack(color))
    frame.accent = accents[accent] or { 0.48, 0.35, 0.18 }
    frame.border:SetColorTexture(frame.accent[1], frame.accent[2], frame.accent[3], 1)
    if frame.action then frame.action:Hide() end
end

local function alertSound(relation)
    local sounds = SOUNDKIT or {}
    if relation == "friend" then return sounds.IG_QUEST_LOG_OPEN end
    return sounds.RAID_WARNING
end

function D.PreviewAlert(relation)
    if relation ~= "friend" and relation ~= "enemy" then return false end
    if toast and toast:IsShown() then return false end
    local frame = makeToast(true)
    styleToast(frame, styles[relation])
    frame.title:SetText(L("Aperçu · %s"):format(L("%s à proximité"):format(L(styles[relation].label))))
    frame.name:SetText(relation == "friend" and "Célestine Longuebrise" or "Bastian Griseforge")
    frame.note:SetText(L("Exemple affiché depuis les réglages."))
    frame.hint:SetText(L("Cliquer pour fermer"))
    frame.expires = GL.Now() + 6
    frame:Show()
    local sound = alertSound(relation)
    if sound and GL.Settings().sounds then GL.Safe(PlaySound, sound, "Master") end
    return true
end

alert = function(identity, unit)
    if not GL.db or not identity or GL.IsPvPInstance() then return end
    local bounty = activeBounty(identity)
    local record = GL.Get(identity)
    if not bounty and guildKiller(identity, record) then return end
    -- A received contract does not create a personal journal entry or enemy rating.
    if bounty and not record then record = identity end
    if not record and GL.GuildOpinion(identity.guid) then record = identity end
    if not record then GL.Trace("unknown", identity, unit) return end
    local relation = bounty and "enemy" or GL.Relation(record)
    if relation == "neutral" then GL.Trace("neutral", identity, unit) return end
    if relation == "friend" then
        local fresh = newFriendEncounter(record, unit)
        if isGroupmate(record, unit) then GL.Trace("grouped", identity, unit) return end
        if not fresh then GL.Trace("present", identity, unit) return end
    end
    if relation ~= "friend" then GL.Emit("THREAT_SEEN", identity, relation, bounty ~= nil) end
    local style = styles[relation]
    local settings = GL.Settings()
    if not style or not settings[alertSetting(relation)] then GL.Trace("disabled", identity, unit) return end
    local now = GL.Now()
    local source = bounty and "bounty" or GL.RelationSource(record)
    local guildKey = not bounty and inheritedGuildKey(record) or nil
    local pvp = record.pvp or {}
    local groupGuild = source == "guild" and (pvp.deaths or 0)
        + (pvp.aggressions or 0) == 0
    local key = record.key .. ":" .. relation .. ":" .. source .. ":" .. (guildKey or "") .. (groupGuild and ":group" or "")
    if relation ~= "friend" and lastAlert[key] and now - lastAlert[key] < (settings.alertCooldown or 180) then GL.Trace("cooldown", identity, unit) return end
    validateToast()
    -- Guild crowds must not displace an equally serious personal/PvP warning.
    if toast and toast:IsShown() and not toast.signal and (styles[toast.relation].priority > style.priority
        or (groupGuild and relation ~= "friend" and not toast.guildBurst and styles[toast.relation].priority == style.priority)) then GL.Trace("priority", identity, unit) return end
    lastAlert[key] = now
    local burstKey, burst
    if groupGuild then
        burstKey = guildKey and guildKey .. ":" .. relation
        burst = burstKey and guildBursts[burstKey]
        -- Count distinct people observed during this six-second burst, not a
        -- total for the zone; the toast continues to open its first person's file.
        if burst and now - burst.started < 6 then
            GL.Trace("burst", identity, unit)
            if not burst.people[record.key] then
                burst.people[record.key], burst.count = true, burst.count + 1
                if toast and toast:IsShown() and toast.guildBurst == burst then
                    toast.hint:SetText(L("%d membres aperçus • clic : première fiche"):format(burst.count))
                end
            end
            return
        end
        if burstKey then
            burst = { started = now, count = 1, people = { [record.key] = true } }
            guildBursts[burstKey] = burst
        end
    end
    local frame = makeToast()
    if previewToast and previewToast:IsShown() then previewToast:Hide() end
    frame.key, frame.relation, frame.source, frame.expires = record.key, relation, source, now + 6
    frame.signal, frame.signalAt, frame.sighting, frame.banner = nil, nil, nil, nil
    frame.bounty, frame.bountyIdentity = bounty, bounty and identity or nil
    frame.guildKey, frame.guildBurst = guildKey, burst
    frame.hint:SetText(L(bounty and "Clic : prime  •  clic droit : fermer" or "Clic : fiche  •  clic droit : fermer"))
    styleToast(frame, style, bounty and "wanted" or nil)
    refreshToastText(frame, record)
    frame:Show()
    GL.Trace("shown", identity, unit)
    if settings.sounds then
        -- A wanted player sounds like coins: the bounty, not the usual warning.
        local sounds = SOUNDKIT or {}
        local sound = bounty and (sounds.LOOT_WINDOW_COIN_SOUND or sounds.IG_BACKPACK_COIN_SELECT or sounds.RAID_WARNING) or alertSound(relation)
        if sound and (not lastSound or now - lastSound.time >= 2 or style.priority > lastSound.priority) then
            GL.Safe(PlaySound, sound, "Master")
            lastSound = { time = now, priority = style.priority }
        end
    end
end

local signalSources = { say = "Parole entendue", yell = "Cri entendu", partyTarget = "Cible d’un équipier proche" }
local function indirectSignal(guid, source)
    local settings = GL.Settings()
    if not settings.indirectAlerts or not settings.enemyAlerts or GL.IsPvPInstance() then return end
    guid = GL.Clean(guid, "string")
    local me = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if not me or not guid or #guid > 128 or not guid:match("^Player%-%w") or guid == me then return end
    local record = GL.Get("guid:" .. guid)
    if not record or record.guid ~= guid then return end
    local relation = GL.Relation(record)
    if (relation ~= "enemy" and relation ~= "warning") or isGroupmate(record) then return end
    local now = GL.Now()
    local cooldown = math.max(15, settings.alertCooldown or 180)
    local seen = record.encounters and record.encounters.seen[me]
    if seen and now >= seen and now - seen < cooldown then return end
    local previous = signals[guid]
    if previous and now >= previous and now - previous < cooldown then
        signals[guid] = now
        return
    end
    validateToast()
    if (toast and toast:IsShown()) or (latestSignal and now >= latestSignal and now - latestSignal < 15) then return end
    -- ponytail: cap temporary hints at 64 contacts and one banner per 15 s.
    -- Only known threats reach this path; it never records sightings or PvP.
    local count, oldest = 0, nil
    for key, at in pairs(signals) do
        if now < at or now - at >= cooldown then signals[key] = nil
        else
            count = count + 1
            if not oldest or at < signals[oldest] then oldest = key end
        end
    end
    if count >= 64 then signals[oldest] = nil end
    signals[guid], latestSignal = now, now
    if previewToast and previewToast:IsShown() then previewToast:Hide() end
    local frame = makeToast()
    frame.key, frame.relation, frame.source = record.key, relation, GL.RelationSource(record)
    frame.guildKey, frame.guildBurst = inheritedGuildKey(record), nil
    frame.signal, frame.signalAt, frame.expires = signalSources[source], now, now + 6
    frame.sighting, frame.banner = nil, nil
    frame.bounty, frame.bountyIdentity = nil, nil
    frame.hint:SetText(L("Clic : fiche  •  clic droit : fermer"))
    styleToast(frame, styles[relation])
    frame.stripe:SetColorTexture(0.74, 0.57, 0.32, 1)
    frame.title:SetTextColor(0.94, 0.80, 0.57)
    refreshToastText(frame, record)
    frame:Show()
    GL.Trace("indirect", record, source)
    local sounds = SOUNDKIT or {}
    local sound = sounds.MAP_PING or sounds.IG_MAINMENU_OPTION_CHECKBOX_ON or sounds.IG_QUEST_LOG_OPEN
    if sound and settings.sounds then GL.Safe(PlaySound, sound, "Master") end
end

-- Guild watch: a guildmate just saw a player. Alert when that player matters to you (your enemy,
-- suspicious, a bounty target, disliked by the guild), or when a guildmate's enemy is in your zone.
local watchAlerts = {}
-- A moment of your story, shown like an alert: revenge taken, a score settled, a good group.
-- A banner never replaces another banner still on screen (0.60.1): it waits its turn, five at most, and
-- shows when the first closes. Two payments at once are both read. A banner still replaces a plain
-- nearby alert at once (a revenge is told when it happens), and a banner on the same subject is
-- updated in place.
local waitingBanners = {}
local function banner(key, relation, title, name, note, hint, onClick, accent, action)
    if GL.IsPvPInstance() then return end
    if toast and toast:IsShown() and toast.banner and toast.key ~= key and GL.Now() < (toast.expires or 0) then
        if #waitingBanners < 5 then
            waitingBanners[#waitingBanners + 1] = { key, relation, title, name, note, hint, onClick, accent, action }
        end
        return toast
    end
    if previewToast and previewToast:IsShown() then previewToast:Hide() end
    local frame = makeToast()
    frame.key, frame.relation, frame.source, frame.expires = key, relation, "banner", GL.Now() + 8
    frame.guildKey, frame.guildBurst, frame.signal, frame.signalAt, frame.sighting = nil, nil, nil, nil, nil
    frame.bounty, frame.bountyIdentity = nil, nil
    frame.banner = { title = title, name = name, note = note, onClick = onClick, action = action }
    frame.hint:SetText(hint or L("Clic : fiche  •  clic droit : fermer"))
    styleToast(frame, styles[relation], accent)
    if action and frame.action then
        frame.action:SetText(action.label)
        frame.action:Show()
    end
    refreshToastText(frame)
    frame:Show()
    return frame
end
GL.On("REVENGE", function(record, before, after)
    if not GL.Settings().enemyAlerts or type(record) ~= "table" then return end
    local settled = after <= 0
    local note = settled and L("Sa dette de %d est effacée."):format(before)
        or L("Dette de %d ramenée à %d."):format(before, after)
    banner(record.key, settled and "friend" or "enemy", settled and L("Compte réglé") or L("Revanche"),
        record.fullName or record.name or L("Joueur connu"), note)
    local sounds = SOUNDKIT or {}
    local sound = sounds.UI_QUEST_ROLLING_FORWARD_01 or sounds.IG_QUEST_LIST_COMPLETE or sounds.IG_QUEST_LOG_OPEN
    if sound and GL.Settings().sounds then GL.Safe(PlaySound, sound, "Master") end
end)
GL.ShowStoryBanner = banner
-- A player who killed a member of the guild (guild vision, GuildMap.lua): a banner of its own and
-- a sound of its own, even when this player is not in your journal. Your own enemies keep your
-- own alert.
local function since(at)
    local delta = math.max(0, GL.Now() - at)
    if delta < 3600 then return L("il y a %d min"):format(math.max(1, math.floor(delta / 60))) end
    if delta < 86400 then return L("il y a %d h"):format(math.floor(delta / 3600)) end
    return L("il y a %d j"):format(math.floor(delta / 86400))
end
guildKiller = function(identity, record)
    local killer = GL.GuildMap and identity.guid and GL.GuildMap.Killer(identity.guid)
    if not killer then return false end
    local settings = GL.Settings()
    if not settings.enemyAlerts then return false end
    if record and GL.Relation(record) == "enemy" and GL.RelationSource(record) ~= "guild" then return false end
    local now = GL.Now()
    local key = "guildkiller:" .. identity.guid
    if lastAlert[key] and now - lastAlert[key] < (settings.alertCooldown or 180) then return true end
    lastAlert[key] = now
    GL.Emit("THREAT_SEEN", identity, "enemy", false)
    local victim = GL.Bounties and GL.Bounties.MemberName and GL.Bounties.MemberName(killer.actor) or L("un membre")
    local note = L("A tué %s %s."):format(victim, since(killer.time))
    if killer.deaths > 1 then note = note .. " " .. L("%d morts dans la guilde."):format(killer.deaths) end
    local who = identity.fullName or identity.name or killer.name or L("Joueur connu")
    -- "Rechercher": a wanted notice without gold, posted from the alert itself.
    local action = GL.Bounties and GL.Bounties.Post and {
        label = L("Rechercher"),
        run = function()
            local id, err = GL.Bounties.Post(identity.guid, who, 0)
            if id then
                GL.Print(L("Avis de recherche publié : %s. Sans or, valable 7 jours."):format(who))
            elseif err == "duplicate" then
                GL.Print(L("Une prime ou un avis de recherche existe déjà sur ce joueur."))
            else
                GL.Print(L("L’avis de recherche n’a pas pu être publié."))
            end
        end,
    } or nil
    local frame = banner(identity.key, "enemy", L("Tueur de guilde"), who, note, L("Clic : fiche  •  clic droit : fermer"), function()
        if GL.OpenPlayerDossier then GL.OpenPlayerDossier(identity.guid, nil, who) end
    end, "killer", action)
    if not frame then return true end
    -- The horn of a battleground that opens: not the sound of any other alert.
    local sounds = SOUNDKIT or {}
    local sound = sounds.PVP_THROUGH_QUEUE or sounds.RAID_BOSS_EMOTE_WARNING or sounds.ALARM_CLOCK_WARNING_3 or sounds.RAID_WARNING
    if sound and settings.sounds then GL.Safe(PlaySound, sound, "Master") end
    return true
end
-- After a good group with a player who is not in your book: one click adds them as a friend.
GL.On("COMPANION_SUGGESTION", function(identity, seconds)
    if not GL.Settings().friendAlerts or type(identity) ~= "table" or GL.Get(identity) then return end
    local name = identity.fullName or (identity.name and (identity.name .. (identity.surname and (" " .. identity.surname) or "")))
    banner(identity.key, "friend", L("Bon groupe"), name or L("Joueur connu"),
        L("%d min en groupe avec vous."):format(math.floor((seconds or 0) / 60)),
        L("Clic : l’ajouter en ami  •  clic droit : fermer"), function()
            GL.AdjustReputation(identity, 1, "Groupe apprécié", "manual")
        end)
end)

local function guildSighting(target, sight, sameZone)
    local settings = GL.Settings()
    if not settings.guildSightings or not settings.enemyAlerts or GL.IsPvPInstance() then return end
    if type(target) ~= "string" or type(sight) ~= "table" then return end
    -- A call for help is an explicit request: it reaches every member, wherever they are.
    if sight.help then
        if previewToast and previewToast:IsShown() then previewToast:Hide() end
        local frame = makeToast()
        frame.key, frame.relation, frame.source = "guid:" .. target, "enemy", "watch"
        frame.guildKey, frame.guildBurst, frame.signal, frame.signalAt, frame.banner = nil, nil, nil, nil, nil
        frame.bounty, frame.bountyIdentity = nil, nil
        frame.sighting, frame.sameZone, frame.expires = sight, sameZone == true, GL.Now() + 10
        frame.hint:SetText(L("Clic : fiche  •  clic droit : fermer"))
        styleToast(frame, styles.enemy)
        refreshToastText(frame, GL.Get(frame.key))
        frame:Show()
        local sound = alertSound("enemy")
        if sound and settings.sounds then GL.Safe(PlaySound, sound, "Master") end
        return
    end
    local identity = { guid = target, key = "guid:" .. target }
    local record = GL.Get(identity.key)
    local relation = GL.Relation(record or identity)
    local bounty = activeBounty(record or identity)
    local mine = relation == "enemy" or relation == "warning" or bounty ~= nil
    if not mine and not (sameZone and sight.relation == "enemy") then return end
    if record and isGroupmate(record) then return end
    local now = GL.Now()
    -- You see this player yourself right now: the usual alert already told you.
    local me = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    local seen = record and record.encounters and me and record.encounters.seen[me]
    if seen and now >= seen and now - seen < 30 then return end
    if watchAlerts[target] and now - watchAlerts[target] < 120 then return end
    validateToast()
    if toast and toast:IsShown() and not toast.sighting and not toast.signal then return end
    watchAlerts[target] = now
    if previewToast and previewToast:IsShown() then previewToast:Hide() end
    local frame = makeToast()
    frame.key, frame.relation, frame.source = identity.key, mine and relation ~= "neutral" and relation ~= "friend" and relation or "warning", "watch"
    if bounty then frame.relation = "enemy" end
    frame.guildKey, frame.guildBurst, frame.signal, frame.signalAt = nil, nil, nil, nil
    frame.bounty, frame.bountyIdentity = nil, nil
    frame.sighting, frame.sameZone, frame.expires, frame.banner = sight, sameZone == true, now + 8, nil
    frame.hint:SetText(L("Clic : fiche  •  clic droit : fermer"))
    styleToast(frame, styles[frame.relation])
    refreshToastText(frame, record)
    frame:Show()
    GL.Trace("watch", identity, "guild")
    local sound = alertSound(frame.relation)
    if sound and settings.sounds then GL.Safe(PlaySound, sound, "Master") end
end
GL.On("GUILD_SIGHTING", guildSighting)

local function observe(unit, notify, reuseObservation)
    unit = GL.Clean(unit, "string")
    if not unit or not GL.db or GL.IsPvPInstance() then return end
    if not unit:match("^nameplate%d+$") and (not notify or UnitIsVisible) and GL.Safe(UnitIsVisible, unit) ~= true then return end
    local identity = GL.Identity(unit, reuseObservation)
    if identity then
        GL.Trace("observed", identity, unit)
        if GL.SharedDossiers and notify then GL.SharedDossiers.Observe(identity) end
        local record = GL.RecordSeen(identity, true)
        encounterState(record,unit)
        partyWarning(record, unit)
        if notify or (record and GL.Relation(record) == "friend") then alert(identity, unit) end
    elseif notify then
        GL.Trace("unreadable", nil, unit)
    end
    return identity
end

local function removeUnit(unit)
    local entry = visible[unit]
    if entry then
        -- The API may already return nil by REMOVED, so use the stored frame.
        local marker = entry.plate and markers[entry.plate]
        if marker and marker.owner == entry then hideMarker(marker) end
        visible[unit] = nil
    end
end

local function addUnit(unit)
    unit = GL.Clean(unit, "string")
    if not unit or not GL.db then return end
    removeUnit(unit)
    local entry = { unit = unit }
    visible[unit] = entry
    local function update()
        if visible[unit] ~= entry then return end
        entry.plate = C_NamePlate and GL.Safe(C_NamePlate.GetNamePlateForUnit, unit)
        observe(unit, true)
        updateMarker(entry)
    end
    update()
    if C_Timer and C_Timer.After then C_Timer.After(0.25, update) end
end

function D.Refresh(changedRecord, reason)
    if not GL.db or reason == "honor" then return end
    for font, saved in pairs(pendingNames) do
        if not sameColor(colorOf(font), saved.applied) then pendingNames[font] = nil
        elseif canChange(font) then
            local ok = pcall(font.SetTextColor, font, unpack(saved.base))
            if ok then pendingNames[font] = nil end
        end
    end
    validateToast()
    if GL.IsPvPInstance() then
        for _, marker in pairs(markers) do hideMarker(marker) end
        return
    end
    for _, entry in pairs(visible) do
        updateMarker(entry, true)
        local record = entry.identity and GL.Get(entry.identity)
        if type(changedRecord) == "table" and record and record.key == changedRecord.key then
            alert(entry.identity, entry.unit)
        end
    end
    observe("target", false, true)
    observe("mouseover", false, true)
    local count = GL.Clean(GL.Safe(GetNumGroupMembers), "number") or 0
    local raid = GL.Safe(IsInRaid) == true
    for i = 1, count > 0 and (raid and math.min(count, 40) or 4) or 0 do
        observe((raid and "raid" or "party") .. i, false, true)
    end
    validateToast()
end

function D.Tooltip(tooltip)
    if not GL.db or tooltip ~= GameTooltip or GL.IsPvPInstance() then return end
    local _, unit = GL.Safe(tooltip.GetUnit, tooltip)
    unit = GL.Clean(unit, "string")
    local identity = unit and GL.Identity(unit)
    local direct = unit and (unit:match("^nameplate%d+$") or not UnitIsVisible or GL.Safe(UnitIsVisible, unit) == true)
    local record = identity and (direct and GL.RecordSeen(identity, true) or GL.Get(identity))
    partyWarning(record, unit)
    if record and GL.Relation(record) == "friend" then alert(identity, unit) end
    if not record or tooltip._grudgeLedgerKey == record.key or GL.IsGroupOnly(record) then return end
    tooltip._grudgeLedgerKey = record.key
    local relation = GL.Relation(record)
    local style = styles[relation]
    tooltip:AddLine(" ")
    tooltip:AddLine("Grudge Ledger — " .. L(style and style.label or "Neutre"),
        style and style.color[1] or 0.85, style and style.color[2] or 0.85,
        style and style.color[3] or 0.85)
    local tags = GL.TagText and GL.TagText(record)
    if tags then tooltip:AddLine(L("Étiquettes : %s"):format(tags), 0.95, 0.82, 0.58, true) end
    tooltip._grudgeLedgerExpanded = not GL.Settings().compactTooltips or GL.Safe(IsShiftKeyDown) == true
    if not tooltip._grudgeLedgerExpanded then
        tooltip:AddLine(L("Maj : notes et bilan PvP"), 0.8, 0.75, 0.64)
        return
    end
    local guild = guildLabel(record, relation)
    if guild then tooltip:AddLine(guild, 0.85, 0.85, 0.85, true) end
    local note = recordNote(record)
    if note then tooltip:AddLine(note, 0.9, 0.85, 0.7, true) end
    tooltip:AddLine(L("Camaraderie : %s"):format(tostring(record.reputation or 0)), 0.85, 0.85, 0.85)
    local pvp = record.pvp or {}
    if (pvp.aggressions or 0) > 0 then
        tooltip:AddLine(L("Agressions") .. " : " .. (pvp.aggressions or 0), 1, 0.6, 0.1, true)
    end
    if (pvp.kills or 0) + (pvp.deaths or 0) > 0 then
        tooltip:AddLine(L("PvP : %d victoire(s), %d mort(s)"):format(pvp.kills or 0, pvp.deaths or 0), 0.85, 0.85, 0.85, true)
    end
end

local function scanPlates()
    local plates = C_NamePlate and GL.Safe(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        local unit = GL.Clean(plate.namePlateUnitToken, "string")
            or (plate.UnitFrame and GL.Clean(plate.UnitFrame.unit, "string"))
        if unit and not visible[unit] then addUnit(unit) end
    end
end

local awaitingResurrection
function D.OnEvent(_, event, unit, ...)
    if not GL.db then return end
    if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" then
        -- In both native events field 12 is the speaker GUID. Never read chat text.
        indirectSignal(select(11, ...), event == "CHAT_MSG_SAY" and "say" or "yell")
    elseif event == "UNIT_TARGET" then
        unit = GL.Clean(unit, "string")
        if unit and unit:match("^party[1-4]$") and GL.Safe(UnitIsVisible, unit) == true then
            indirectSignal(GL.Safe(UnitGUID, unit .. "target"), "partyTarget")
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        unit = GL.Clean(unit, "string")
        if GL.Settings().compactTooltips and (unit == "LSHIFT" or unit == "RSHIFT") and GameTooltip and GameTooltip._grudgeLedgerKey
            and GameTooltip:IsShown() and GameTooltip._grudgeLedgerExpanded ~= (GL.Safe(IsShiftKeyDown) == true) then
            local _, token = GL.Safe(GameTooltip.GetUnit, GameTooltip)
            if token and GL.Safe(UnitExists, token) then
                if GameTooltip.RefreshData and (not GameTooltip.GetPrimaryTooltipInfo or GL.Safe(GameTooltip.GetPrimaryTooltipInfo, GameTooltip)) then GL.Safe(GameTooltip.RefreshData, GameTooltip)
                else GL.Safe(GameTooltip.SetUnit, GameTooltip, token) end
            end
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then addUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        unit = GL.Clean(unit, "string")
        if unit then removeUnit(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then observe("target", true)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then observe("mouseover", true)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        for token in pairs(visible) do removeUnit(token) end
        guildBursts = {}
        nearbyDead,followAlerts={},{}
        signals, latestSignal = {}, nil
        if toast then toast:Hide() end
        if previewToast then previewToast:Hide() end
        scanPlates()
    elseif event == "PLAYER_DEAD" then
        awaitingResurrection = true
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if awaitingResurrection and GL.Safe(UnitIsDeadOrGhost, "player") == false then
            followAlerts={}
            awaitingResurrection, lastAlert, lastSound = nil, {}, nil
            for _, entry in pairs(visible) do entry.recordKey = nil end
            scanPlates()
            D.Refresh()
            observe("target", true)
        end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "GROUP_ROSTER_UPDATE" then D.Refresh()
    end
end

local eventFrame = CreateFrame("Frame", "GrudgeLedgerDisplayEvents")
local listening = false
local function syncSignals()
    local enabled = GL.Settings().indirectAlerts and GL.Settings().enemyAlerts
    if listening == enabled then return end
    listening = enabled
    local method = enabled and eventFrame.RegisterEvent or eventFrame.UnregisterEvent
    for _, event in ipairs({ "UNIT_TARGET", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }) do GL.Safe(method, eventFrame, event) end
    if not enabled then signals, latestSignal = {}, nil end
end
eventFrame:SetScript("OnEvent", D.OnEvent)
eventFrame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.5 or not GL.db then return end
    elapsed = 0
    -- ponytail: O(visible nameplates) twice a second keeps optional colors compatible
    -- with ThreatPlates updates. Use its update hook if very large crowds prove costly.
    D.Refresh()
    if toast and toast:IsShown() and GL.Now() >= toast.expires then toast:Hide() end
    if #waitingBanners > 0 and not (toast and toast:IsShown()) then
        local next = table.remove(waitingBanners, 1)
        banner(unpack(next, 1, 9))
    end
    if previewToast and previewToast:IsShown() and GL.Now() >= previewToast.expires then previewToast:Hide() end
end)
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "MODIFIER_STATE_CHANGED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
    GL.Safe(eventFrame.RegisterEvent, eventFrame, event)
end
GL.On("READY", function()
    syncSignals()
    if GameTooltip and GameTooltip.HookScript then
        GL.Safe(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function(tt) tt._grudgeLedgerKey = nil end)
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            GL.Safe(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, D.Tooltip)
        else GL.Safe(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", D.Tooltip) end
    end
    scanPlates()
end)
GL.On("CHANGED", D.Refresh)
GL.On("BOUNTIES_CHANGED", function()
    D.Refresh()
    observe("target", true)
    observe("mouseover", true)
end)
GL.On("SETTINGS", D.Refresh)
GL.On("SETTINGS", syncSignals)
