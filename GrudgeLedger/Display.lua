-- Grudge Ledger: personal markers, memory tooltips and proximity alerts.
-- Nameplate lifecycle/tooltip approach adapted from Worth Remembering by Kyle
-- (GPL-3.0); https://github.com/kk-on-gh/WorthRemembering. No runtime dependency.
local GL = GrudgeLedger
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
local toast, elapsed = nil, 0
local alert
local lastSound
local function alertSetting(relation) return relation == "friend" and "friendAlerts" or "enemyAlerts" end

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

local function guildLabel(record, relation)
    if not record.guild then return nil end
    if GL.RelationSource(record) == "guild" and relation ~= "neutral" then
        return (relation == "friend" and "Amitié de guilde : " or "Rancune de guilde : ") .. record.guild
    end
    return "Guilde : " .. record.guild
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
    return styles[relation].label .. (GL.RelationConfidence(record) == "probable" and " (probable)" or "") .. " à proximité"
end

local function refreshToastText(frame, record)
    frame.title:SetText(alertTitle(record, frame.relation))
    local name = record.fullName or record.name or "Joueur connu"
    if record.guild and GL.RelationSource(record) ~= "guild" then name = name .. " <" .. record.guild .. ">" end
    frame.name:SetText(name)
    local hint = "Déjà rencontré : " .. (record.lastZone or "lieu inconnu")
    if GL.RelationConfidence(record) == "probable" then hint = "Identification déduite d'un combat — à confirmer" end
    frame.note:SetText(recordNote(record) or hint)
end

local function validateToast()
    if not toast or not toast:IsShown() then return end
    if GL.IsPvPInstance() then toast:Hide() return end
    local record = GL.Get(toast.key)
    if not record or GL.Relation(record) ~= toast.relation or GL.RelationSource(record) ~= toast.source
        or inheritedGuildKey(record) ~= toast.guildKey
        or GL.Now() >= toast.expires or not GL.Settings()[alertSetting(toast.relation)]
        or (toast.relation == "friend" and isGroupmate(record)) then toast:Hide()
    else refreshToastText(toast, record) end
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
    marker.probable:Hide()
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
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local probable = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    probable:SetPoint("RIGHT", frame, "LEFT", -1, 0)
    probable:SetText("?")
    probable:SetTextColor(1, 0.85, 0.3)
    probable:Hide()
    local marker = { frame = frame, icon = icon, probable = probable }
    markers[plate] = marker
    return marker
end

local function updateMarker(entry)
    local plate = C_NamePlate and GL.Safe(C_NamePlate.GetNamePlateForUnit, entry.unit)
    if entry.plate ~= plate then
        local previous = entry.plate and markers[entry.plate]
        if previous and previous.owner == entry then hideMarker(previous) end
        entry.plate = plate
    end
    if not plate then entry.identity = nil; return end
    local marker = markers[plate]
    local identity = GL.Identity(entry.unit)
    entry.identity = identity
    -- Refresh membership as well as identity: guild rules can change while the
    -- same player stays visible, and leaving a guild must remove its marker.
    local record = identity and GL.RecordSeen(identity, true)
    local relation = record and GL.Relation(record)
    local guildKey = record and inheritedGuildKey(record)
    if record and (relation == "friend" or entry.recordKey ~= record.key or entry.relation ~= relation or entry.guildKey ~= guildKey) and alert then
        alert(identity, entry.unit)
    end
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
    local usesTP = plate.TPFrame and GL.Safe(plate.TPFrame.IsShown, plate.TPFrame) ~= false
    GL.Safe(marker.frame.SetIgnoreParentAlpha, marker.frame, usesTP and true or false)
    GL.Safe(marker.frame.SetIgnoreParentScale, marker.frame, usesTP and true or false)
    local level = GL.Safe(plate.GetFrameLevel, plate) or 0
    local tpLevel = usesTP and GL.Safe(plate.TPFrame.GetFrameLevel, plate.TPFrame) or 0
    marker.frame:SetFrameLevel(math.max(level, tpLevel or 0) + 20)
    marker.frame:SetSize(GL.Settings().iconSize or 20, GL.Settings().iconSize or 20)
    marker.frame:ClearAllPoints()
    if font then marker.frame:SetPoint("RIGHT", font, "LEFT", -5, 0)
    else marker.frame:SetPoint("BOTTOM", plate, "TOP", 0, 5) end
    marker.icon:SetTexture(style.icon)
    marker.icon:SetVertexColor(1, 1, 1)
    if GL.RelationConfidence(record) == "probable" then marker.probable:Show() else marker.probable:Hide() end
    marker.frame:Show()
    if relation ~= "neutral" and GL.Settings().nameColor and font and canChange(font) then
        if marker.font ~= font then restoreName(marker) end
        local current = colorOf(font)
        if current and not sameColor(current, marker.appliedColor) then marker.baseColor = current end
        marker.font = font
        marker.appliedColor = style.color
        GL.Safe(font.SetTextColor, font, style.color[1], style.color[2], style.color[3], 1)
    else restoreName(marker) end
end

local function makeToast()
    if toast then return toast end
    local frame = CreateFrame("Button", "GrudgeLedgerNearbyAlert", UIParent)
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
    frame.header = frame:CreateTexture(nil, "BORDER")
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(29)
    frame.header:SetColorTexture(0.22, 0.055, 0.065, 1)
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
    frame.hint:SetText("Clic : fiche  •  clic droit : fermer")
    frame:SetScript("OnEnter", function(self) self.border:SetColorTexture(0.68, 0.51, 0.28, 1) end)
    frame:SetScript("OnLeave", function(self) self.border:SetColorTexture(0.48, 0.35, 0.18, 1) end)
    frame:SetScript("OnClick", function(self, button)
        local key = self.key
        self:Hide()
        if button == "LeftButton" and key and GL.ShowLedger then GL.ShowLedger(key) end
    end)
    -- ponytail: clicking opens the captured record, avoiding protected targeting
    -- and recycled unit-token hazards. A future targeting control needs secure UI.
    frame:Hide()
    toast = frame
    return frame
end

alert = function(identity, unit)
    if not GL.db or not identity or GL.IsPvPInstance() then return end
    local record = GL.Get(identity)
    if not record then GL.Trace("unknown", identity, unit) return end
    local relation = GL.Relation(record)
    if relation == "neutral" then GL.Trace("neutral", identity, unit) return end
    if relation == "friend" then
        local fresh = newFriendEncounter(record, unit)
        if isGroupmate(record, unit) then GL.Trace("grouped", identity, unit) return end
        if not fresh then GL.Trace("present", identity, unit) return end
    end
    local style = styles[relation]
    local settings = GL.Settings()
    if not style or not settings[alertSetting(relation)] then GL.Trace("disabled", identity, unit) return end
    local now = GL.Now()
    local source = GL.RelationSource(record)
    local guildKey = inheritedGuildKey(record)
    local pvp = record.pvp or {}
    local groupGuild = source == "guild" and (pvp.deaths or 0) + (pvp.probableDeaths or 0)
        + (pvp.aggressions or 0) + (pvp.probableAggressions or 0) == 0
    local key = record.key .. ":" .. relation .. ":" .. source .. ":" .. (guildKey or "") .. (groupGuild and ":group" or "")
    if relation ~= "friend" and lastAlert[key] and now - lastAlert[key] < (settings.alertCooldown or 180) then GL.Trace("cooldown", identity, unit) return end
    validateToast()
    -- Guild crowds must not displace an equally serious personal/PvP warning.
    if toast and toast:IsShown() and (styles[toast.relation].priority > style.priority
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
                    toast.hint:SetText(burst.count .. " membres aperçus • clic : première fiche")
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
    frame.key, frame.relation, frame.source, frame.expires = record.key, relation, source, now + 6
    frame.guildKey, frame.guildBurst = guildKey, burst
    frame.hint:SetText("Clic : fiche  •  clic droit : fermer")
    frame.icon:SetTexture(style.icon)
    frame.icon:SetVertexColor(1, 1, 1)
    frame.stripe:SetColorTexture(style.color[1], style.color[2], style.color[3], 1)
    frame.title:SetTextColor(unpack(style.color))
    refreshToastText(frame, record)
    frame:Show()
    GL.Trace("shown", identity, unit)
    if settings.sounds then
        local sounds = SOUNDKIT or {}
        local sound
        if relation == "friend" then sound = sounds.IG_QUEST_LOG_OPEN else sound = sounds.RAID_WARNING end
        if sound and (not lastSound or now - lastSound.time >= 2 or style.priority > lastSound.priority) then
            GL.Safe(PlaySound, sound, "Master")
            lastSound = { time = now, priority = style.priority }
        end
    end
end

local function observe(unit, notify)
    unit = GL.Clean(unit, "string")
    if not unit or not GL.db or GL.IsPvPInstance() then return end
    if not notify and GL.Safe(UnitIsVisible, unit) ~= true then return end
    local identity = GL.Identity(unit)
    if identity then
        GL.Trace("observed", identity, unit)
        local record = GL.RecordSeen(identity, true)
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

function D.Refresh(changedRecord)
    if not GL.db then return end
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
        updateMarker(entry)
        local record = entry.identity and GL.Get(entry.identity)
        if type(changedRecord) == "table" and record and record.key == changedRecord.key then
            alert(entry.identity, entry.unit)
        end
    end
    observe("target", false)
    observe("mouseover", false)
    local count = GL.Clean(GL.Safe(GetNumGroupMembers), "number") or 0
    local raid = GL.Safe(IsInRaid) == true
    for i = 1, count > 0 and (raid and math.min(count, 40) or 4) or 0 do
        observe((raid and "raid" or "party") .. i, false)
    end
    validateToast()
end

function D.Tooltip(tooltip)
    if not GL.db or tooltip ~= GameTooltip then return end
    local _, unit = GL.Safe(tooltip.GetUnit, tooltip)
    unit = GL.Clean(unit, "string")
    local identity = unit and GL.Identity(unit)
    local record = identity and GL.RecordSeen(identity, true)
    if record and GL.Relation(record) == "friend" then alert(identity, unit) end
    if not record or tooltip._grudgeLedgerKey == record.key then return end
    tooltip._grudgeLedgerKey = record.key
    local relation = GL.Relation(record)
    local style = styles[relation]
    tooltip:AddLine(" ")
    tooltip:AddLine("Grudge Ledger — " .. (style and style.label or "Neutre"),
        style and style.color[1] or 0.85, style and style.color[2] or 0.85,
        style and style.color[3] or 0.85)
    if GL.RelationConfidence(record) == "probable" then
        tooltip:AddLine("? Identification PvP probable — à confirmer", 1, 0.85, 0.3, true)
    end
    local guild = guildLabel(record, relation)
    if guild then tooltip:AddLine(guild, 0.85, 0.85, 0.85, true) end
    local note = recordNote(record)
    if note then tooltip:AddLine(note, 0.9, 0.85, 0.7, true) end
    tooltip:AddLine("Camaraderie : " .. tostring(record.reputation or 0), 0.85, 0.85, 0.85)
    local pvp = record.pvp or {}
    if (pvp.aggressions or 0) + (pvp.probableAggressions or 0) > 0 then
        tooltip:AddLine(("Agressions : %d confirmée(s), %d probable(s)"):format(pvp.aggressions or 0, pvp.probableAggressions or 0), 1, 0.6, 0.1, true)
    end
    if (pvp.kills or 0) + (pvp.deaths or 0) > 0 then
        tooltip:AddLine(("PvP confirmé : %d victoire(s), %d mort(s)"):format(pvp.kills or 0, pvp.deaths or 0), 0.85, 0.85, 0.85, true)
    end
    if (pvp.probableKills or 0) + (pvp.probableDeaths or 0) > 0 then
        tooltip:AddLine(("PvP probable : %d victoire(s), %d mort(s)"):format(pvp.probableKills or 0, pvp.probableDeaths or 0), 1, 0.7, 0.35, true)
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

function D.OnEvent(_, event, unit)
    if not GL.db then return end
    if event == "NAME_PLATE_UNIT_ADDED" then addUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        unit = GL.Clean(unit, "string")
        if unit then removeUnit(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then observe("target", true)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then observe("mouseover", true)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        for token in pairs(visible) do removeUnit(token) end
        guildBursts = {}
        if toast then toast:Hide() end
        scanPlates()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "GROUP_ROSTER_UPDATE" then D.Refresh()
    end
end

local eventFrame = CreateFrame("Frame", "GrudgeLedgerDisplayEvents")
eventFrame:SetScript("OnEvent", D.OnEvent)
eventFrame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.5 or not GL.db then return end
    elapsed = 0
    -- ponytail: O(visible nameplates) twice a second keeps optional colors compatible
    -- with ThreatPlates updates. Use its update hook if very large crowds prove costly.
    D.Refresh()
    if toast and toast:IsShown() and GL.Now() >= toast.expires then toast:Hide() end
end)
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
    GL.Safe(eventFrame.RegisterEvent, eventFrame, event)
end
GL.On("READY", function()
    if GameTooltip and GameTooltip.HookScript then
        GL.Safe(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function(tt) tt._grudgeLedgerKey = nil end)
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            GL.Safe(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, D.Tooltip)
        else GL.Safe(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", D.Tooltip) end
    end
    scanPlates()
end)
GL.On("CHANGED", D.Refresh)
GL.On("SETTINGS", D.Refresh)
