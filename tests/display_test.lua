-- Executes the real Core + Display against a small strict WoW-frame fixture.
local now, combat = 1000, false
local regions, units, plates, timers, sounds = {}, {}, {}, {}, {}
local secret = setmetatable({}, { __eq = function() error("secret compared") end, __tostring = function() error("secret printed") end })
issecretvalue = function(v) return rawequal(v, secret) end
time = function() return now end
GetRealZoneText = function() return "Hurlevent" end
InCombatLockdown = function() return combat end
UnitExists = function(u) return units[u] ~= nil end
UnitIsPlayer = function(u) return units[u] and units[u].player ~= false end
UnitIsUnit = function(a, b) return units[a] and units[b] and units[a].guid == units[b].guid or false end
UnitName = function(u) local v = units[u]; if v then return v.name, v.surname end end
UnitGUID = function(u) return units[u] and units[u].guid end
UnitClass = function() return "Mage", "MAGE" end
UnitFactionGroup = function() return "Alliance" end
UnitLevel = function() return 34 end
GetRealmName = function() return "Forever" end
GetGuildInfo = function(u) local v = units[u]; return v and v.guild, nil, nil, v and v.guildRealm end
SetCVar = function() error("Display must not change game settings") end
TargetUnit = function() error("Display must never auto-target") end
SOUNDKIT = { RAID_WARNING = 1, IG_QUEST_LOG_OPEN = 2 }
PlaySound = function(id, channel) sounds[#sounds + 1] = { id, channel } end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function flushTimers()
    local pending = timers; timers = {}
    for _, callback in ipairs(pending) do callback() end
end
local anchors = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local methods = {}
local function region(kind, name, parent)
    local r = setmetatable({ kind = kind, nameID = name, parent = parent, children = {}, shown = true,
        scripts = {}, hooks = {}, color = { 1, 1, 1, 1 }, alpha = 1, frameLevel = 0 }, { __index = methods })
    regions[#regions + 1] = r
    if parent then parent.children[#parent.children + 1] = r end
    if name then _G[name] = r end
    return r
end
function methods:SetPoint(point, relative, relativePoint, x, y)
    assert(anchors[point], "invalid anchor: " .. tostring(point))
    if type(relativePoint) == "string" then assert(anchors[relativePoint]) end
    self.anchor = { point, relative, relativePoint, x, y }
end
function methods:ClearAllPoints() self.anchor = nil end
function methods:SetAllPoints() end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetFrameLevel(level) self.frameLevel = level end
function methods:GetFrameLevel() return self.frameLevel end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:SetClampedToScreen() end
function methods:EnableMouse() end
function methods:RegisterForClicks() end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:UnregisterEvent(event) if self.events then self.events[event] = nil end end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback) self.hooks[event] = callback end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:IsProtected() return self.protected or false end
function methods:CanChangeProtectedState() return not combat or not self.protected end
function methods:SetAlpha(a) self.alpha = a end
function methods:GetAlpha() return self.alpha end
function methods:SetIgnoreParentAlpha(value) self.ignoreParentAlpha = value end
function methods:SetIgnoreParentScale(value) self.ignoreParentScale = value end
function methods:CreateTexture(name) return region("Texture", name, self) end
function methods:CreateFontString(name) return region("FontString", name, self) end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetVertexColor(...) self.vertex = {...} end
function methods:SetColorTexture(...) self.textureColor = {...} end
function methods:SetText(text) self.text = text end
function methods:SetTextColor(r, g, b, a)
    if combat and self.protected then error("protected color mutation") end
    self.color = { r, g, b, a or 1 }
end
function methods:GetTextColor() return unpack(self.color) end
function methods:SetJustifyH() end
function methods:SetJustifyV(value) self.justifyV = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
function methods:SetMaxLines(value) self.maxLines = value end
function methods:SetClipsChildren(value) self.clipsChildren = value end
function methods:AddLine(...) self.lines = self.lines or {}; self.lines[#self.lines + 1] = {...} end
local tooltipUnit
function methods:GetUnit() return "Unit", tooltipUnit end
CreateFrame = function(kind, name, parent) return region(kind, name, parent) end
UIParent = region("Frame")
GameTooltip = region("Tooltip")
local tooltipCallback
Enum = { TooltipDataType = { Unit = 1 } }
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) tooltipCallback = callback end }
C_NamePlate = {
    GetNamePlateForUnit = function(unit) return plates[unit] end,
    GetNamePlates = function() local list = {}; for _, plate in pairs(plates) do list[#list + 1] = plate end; return list end,
}
local function makePlate(token, tp)
    local plate = region("Frame")
    plate.namePlateUnitToken = token
    plate.UnitFrame = region("Frame", nil, plate)
    plate.UnitFrame.unit = token
    if tp then
        plate.TPFrame = region("Frame", nil, plate)
        plate.TPFrame.frameLevel = 40
        plate.TPFrame.visual = { NameText = region("FontString", nil, plate.TPFrame) }
    else plate.UnitFrame.name = region("FontString", nil, plate.UnitFrame) end
    plates[token] = plate
    return plate, tp and plate.TPFrame.visual.NameText or plate.UnitFrame.name
end
local function markerFor(plate)
    for _, child in ipairs(plate.children) do
        if child.kind == "Frame" and child ~= plate.UnitFrame and child ~= plate.TPFrame then return child end
    end
end
units.player = { name = "Me", surname = "Self", guid = "Player-1-1" }
units.nameplate1 = { name = "Alex", surname = "One", guid = "Player-1-11" }
local plate, font = makePlate("nameplate1", true)
font:SetTextColor(0.3, 0.4, 0.5)
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
local friend = GL.Identity("nameplate1")
GL.SetReaction(friend, "friend")
GL.AddNote(friend, "Super donjon ensemble")
local openedKey
GL.ShowLedger = function(key) openedKey = key end
assert(loadfile(TEST_ROOT .. "/Display.lua"))()
GL.Emit("READY")
local D, eventFrame = GL.Display, GrudgeLedgerDisplayEvents
local marker = assert(markerFor(plate), "READY must scan existing plates")
local icon = marker.children[2]
assert(marker.shown and icon.texture:find("Shield") and icon.vertex[2] == 1)
assert(marker.frameLevel > plate.TPFrame.frameLevel)
assert(marker.anchor[2] == font, "icon must follow visible ThreatPlates name")
assert(font.color[1] == 0.3 and font.color[3] == 0.5, "name colors off by default")
assert(marker.alpha == 1 and plate.alpha == 1, "never alter plate alpha")
assert(marker.ignoreParentAlpha and marker.ignoreParentScale, "TP overlay must ignore underlying Blizzard alpha/scale")
plate:SetAlpha(0)
D.Refresh()
assert(marker.shown and marker.ignoreParentAlpha and plate.alpha == 0)
plate:SetAlpha(1)
local toast = assert(GrudgeLedgerNearbyAlert)
assert(toast.shown and toast.name.text == "Alex One" and toast.note.text == "Super donjon ensemble")
assert(toast.width == 416 and toast.height == 112 and toast.clipsChildren)
for _, text in ipairs({ toast.title, toast.name, toast.note, toast.hint }) do
    assert(text.anchor[2] + text.width <= toast.width - 12)
    assert(-text.anchor[3] + text.height <= toast.height - 3)
    assert(text.justifyV == "TOP" and text.nonSpaceWrap and text.maxLines <= 2)
end
assert(not toast.title.wordWrap and not toast.name.wordWrap and toast.note.wordWrap and toast.note.maxLines == 2)
toast.scripts.OnEnter(toast)
assert(toast.border.textureColor[1] == 0.68)
toast.scripts.OnLeave(toast)
assert(toast.border.textureColor[1] == 0.48)
assert(#sounds == 1 and sounds[1][1] == SOUNDKIT.IG_QUEST_LOG_OPEN)
units.nameplate5 = { name = "Second", surname = "Friend", guid = "Player-1-55" }
makePlate("nameplate5")
GL.SetReaction(GL.Identity("nameplate5"), "friend")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate5")
assert(#sounds == 1, "a burst of friends must play only one positive sound")
flushTimers()
units.target, units.mouseover = units.nameplate1, units.nameplate1
D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
D.OnEvent(nil, "UPDATE_MOUSEOVER_UNIT")
assert(#sounds == 1, "multiple unit views must not duplicate alerts")

GL.SetSetting("nameColor", true)
assert(font.color[2] == 1)
GL.SetReaction(friend, "enemy")
assert(icon.texture:find("Skull") and font.color[1] == 1 and toast.relation == "enemy")
GL.SetSetting("nameColor", false)
assert(font.color[1] == 0.3 and font.color[2] == 0.4 and font.color[3] == 0.5)
GL.SetSetting("nameColor", true)
font:SetTextColor(0.8, 0.7, 0.6) -- ThreatPlates changed its own base color.
D.Refresh()
assert(font.color[1] == 1)
GL.SetReaction(friend, "neutral")
assert(not marker.shown and font.color[1] == 0.8 and font.color[3] == 0.6)

now = now + 181
GL.SetReaction(friend, "enemy")
D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(toast.relation == "enemy" and toast.shown)
assert(sounds[#sounds][1] == SOUNDKIT.RAID_WARNING)
local soundsBefore = #sounds
GL.SetSetting("enemyAlerts", false)
assert(not toast.shown)
D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(#sounds == soundsBefore)
GL.SetSetting("enemyAlerts", true)
GL.SetSetting("sounds", false)
now = now + 181
D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(toast.shown and #sounds == soundsBefore)
local capturedKey = toast.key
units.target = nil
toast.scripts.OnClick(toast, "LeftButton")
assert(openedKey == capturedKey, "click must open captured player despite target change")

-- Recycled plate belongs to a different, unknown player: no stale red icon/name.
units.nameplate1 = { name = "New", surname = "Unknown", guid = "Player-1-22" }
font:SetTextColor(0.6, 0.5, 0.4) -- the game already colored the new occupant
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
flushTimers()
assert(not marker.shown and font.color[1] == 0.6)

local second = GL.Identity("nameplate1")
GL.SetReaction(second, "friend")
assert(marker.shown and icon.texture:find("Shield"), "manual change refreshes current plates immediately")
GL.SetSetting("markers", false)
assert(not marker.shown and font.color[1] == 0.6)
GL.SetSetting("markers", true)
assert(marker.shown)
plates.nameplate1 = nil -- REMOVED can arrive after GetNamePlateForUnit stops resolving
D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not marker.shown and font.color[1] == 0.6)

-- Restoring a protected name must be deferred, not forgotten when its unit leaves.
plates.nameplate1 = plate
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(font.color[2] == 1)
font.protected, combat = true, true
plates.nameplate1 = nil
D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(font.color[2] == 1, "combat denies color restoration")
combat = false
D.OnEvent(nil, "PLAYER_REGEN_ENABLED")
assert(font.color[1] == 0.6 and font.color[2] == 0.5, "deferred restore survives removal")
font.protected = false

-- Old deferred callbacks must not paint a removed/reused token.
plates.nameplate1 = plate
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
plates.nameplate1 = nil
D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
flushTimers()
assert(not marker.shown)

-- A late REMOVED from a different token must not hide its new plate owner.
plates.nameplate1 = plate
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
units.nameplate2, plates.nameplate2 = units.nameplate1, plate
plates.nameplate1 = nil
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate2")
D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(marker.shown)

-- Delayed identity resolution is retried; protected plates are not modified in combat.
units.nameplate3 = { name = secret, surname = "Hidden", guid = "Player-1-33" }
local protected = makePlate("nameplate3")
protected.protected = true
combat = true
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate3")
assert(not markerFor(protected))
units.nameplate3.name = "Delayed"
local delayed = GL.Identity("nameplate3")
GL.SetReaction(delayed, "enemy")
assert(not markerFor(protected))
combat = false
D.OnEvent(nil, "PLAYER_REGEN_ENABLED")
assert(markerFor(protected).shown)
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", secret)
D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", secret)

-- Tooltips show notes plus separate probable/confirmed counters exactly once.
GL.RecordPvP(delayed, "death", "probable", "target", "test-probable")
GL.RecordPvP(delayed, "kill", "confirmed", "combat log", "test-confirmed")
GL.AddNote(delayed, "Attention à lui")
tooltipUnit = "nameplate3"
tooltipCallback(GameTooltip)
local count = #GameTooltip.lines
tooltipCallback(GameTooltip)
assert(#GameTooltip.lines == count)
local text = ""
for _, line in ipairs(GameTooltip.lines) do text = text .. tostring(line[1]) end
assert(text:find("Attention à lui") and text:find("PvP probable") and text:find("PvP confirmé"))
GameTooltip.hooks.OnTooltipCleared(GameTooltip)
GameTooltip.lines = {}
tooltipUnit = secret
tooltipCallback(GameTooltip)
assert(#GameTooltip.lines == 0)

-- Aggression is orange and distinct from a red kill, sharing the enemy-alert toggle.
units.nameplate4 = { name = "Aggressor", surname = "Orange", guid = "Player-1-44" }
local warningPlate = makePlate("nameplate4")
local warning = GL.Identity("nameplate4")
now = now + 200
eventFrame.scripts.OnUpdate(eventFrame, 1)
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate4")
assert(not markerFor(warningPlate), "unclassified nearby player starts without a marker")
GL.RecordAggression(warning, "probable", "hostile target", "test-warning")
local warningMarker = assert(markerFor(warningPlate))
assert(warningMarker.shown and warningMarker.children[2].texture:find("AlertNew"))
assert(warningMarker.children[2].vertex[2] == 0.6)
assert(toast.relation == "warning" and toast.title.text == "Agression (probable) à proximité")
assert(warningMarker.children[3].shown and warningMarker.children[3].text == "?")
GL.SetSetting("enemyAlerts", false)
assert(not toast.shown, "orange alerts use enemyAlerts setting")
GL.SetSetting("enemyAlerts", true)
GameTooltip.hooks.OnTooltipCleared(GameTooltip)
GameTooltip.lines, tooltipUnit = {}, "nameplate4"
tooltipCallback(GameTooltip)
text = ""
for _, line in ipairs(GameTooltip.lines) do text = text .. tostring(line[1]) end
assert(text:find("Agressions : 0 confirmée%(s%), 1 probable%(s%)"))
assert(text:find("Camaraderie : %-1"))
assert(text:find("Identification PvP probable"))

-- A personal note cannot conceal uncertainty, and confirmed evidence clears it.
GL.AddNote(warning, "Note personnelle conservée")
now = now + 200
units.target = units.nameplate4
D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(toast.note.text == "Note personnelle conservée" and toast.title.text:find("%(probable%)"))
GameTooltip.hooks.OnTooltipCleared(GameTooltip)
GameTooltip.lines, tooltipUnit = {}, "nameplate4"
tooltipCallback(GameTooltip)
text = ""
for _, line in ipairs(GameTooltip.lines) do text = text .. tostring(line[1]) end
assert(text:find("Note personnelle conservée") and text:find("Identification PvP probable"))
GL.RecordAggression(warning, "confirmed", "combat log", "test-warning-confirmed")
assert(not warningMarker.children[3].shown and toast.title.text == "Agression à proximité")
local warningRecord = GL.Get(warning)
assert(GL.VoidPvP(warning, warningRecord.history[#warningRecord.history]))
assert(warningMarker.children[3].shown and toast.title.text:find("%(probable%)"), "correction restores uncertainty")
GL.RecordPvP(warning, "death", "probable", "target", "test-warning-death")
assert(warningMarker.children[2].texture:find("Skull") and warningMarker.children[3].shown)
assert(GL.VoidPvP(warning, warningRecord.history[#warningRecord.history]))
assert(warningMarker.children[2].texture:find("AlertNew") and warningMarker.children[3].shown, "voiding death downgrades to aggression")
GL.RecordPvP(warning, "death", "confirmed", "combat log", "test-warning-confirmed-death")
assert(warningMarker.children[2].texture:find("Skull") and not warningMarker.children[3].shown)
assert(GL.VoidPvP(warning, warningRecord.history[#warningRecord.history]))
assert(warningMarker.children[3].shown, "removing confirmed death leaves only probable aggression")
GL.SetReaction(warning, "warning")
assert(not warningMarker.children[3].shown, "manual choices never display inferred uncertainty")
GL.SetReaction(warning, "neutral")
assert(not warningMarker.shown and not warningMarker.children[3].shown)
warningRecord.reaction = nil
D.Refresh()
assert(warningMarker.children[3].shown)
units.nameplate4 = { name = "Recycled", surname = "Player", guid = "Player-1-444" }
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate4")
assert(not warningMarker.shown and not warningMarker.children[3].shown, "recycled plates cannot retain '?' badges")

-- A guild rule applies immediately to already visible, previously unknown members.
units.nameplate6 = { name = "Guild", surname = "Member", guid = "Player-1-66", guild = "Les Corbeaux" }
units.nameplate7 = { name = "Other", surname = "Member", guid = "Player-1-77", guild = "Les Moineaux" }
local guildPlate, guildFont = makePlate("nameplate6")
local otherGuildPlate = makePlate("nameplate7")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate6")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate7")
assert(not markerFor(guildPlate) and not markerFor(otherGuildPlate))
now = now + 200
GL.SetGuildReaction("Les Corbeaux", "warning", "Ils nous ont agressés")
local guildMarker = assert(markerFor(guildPlate), "guild rule must refresh already visible members")
assert(guildMarker.shown and guildMarker.children[2].vertex[2] == 0.6)
assert(not guildMarker.children[3].shown, "guild opinions do not claim inferred PvP evidence")
assert(not markerFor(otherGuildPlate), "a different guild must not inherit this rule")
assert(toast.shown and toast.relation == "warning" and toast.title.text == "Rancune de guilde : Les Corbeaux")
assert(toast.name.text == "Guild Member" and toast.note.text == "Ils nous ont agressés")
GL.SetGuildReaction("Les Corbeaux", "enemy", "Plusieurs attaques")
assert(guildMarker.children[2].texture:find("Skull") and toast.relation == "enemy")
GameTooltip.hooks.OnTooltipCleared(GameTooltip)
GameTooltip.lines, tooltipUnit = {}, "nameplate6"
tooltipCallback(GameTooltip)
text = ""
for _, line in ipairs(GameTooltip.lines) do text = text .. tostring(line[1]) end
assert(text:find("Rancune de guilde : Les Corbeaux") and text:find("Plusieurs attaques"))
local guildMember = GL.Identity("nameplate6")
GL.AddNote(guildMember, "Sa note personnelle")
GameTooltip.hooks.OnTooltipCleared(GameTooltip)
GameTooltip.lines = {}
tooltipCallback(GameTooltip)
text = ""
for _, line in ipairs(GameTooltip.lines) do text = text .. tostring(line[1]) end
assert(text:find("Sa note personnelle") and not text:find("Plusieurs attaques"), "personal notes take precedence")
units.nameplate6.guild = nil
D.Refresh()
assert(not guildMarker.shown and not toast.shown, "leaving the guild clears inherited marker and stale toast")
assert(GL.Get(guildMember).guild == nil and guildFont.color[1] == 1 and guildFont.color[2] == 1)

-- An individually marked friend is exempt from a guild grudge, even after a rule change.
units.nameplate6.guild = "Les Corbeaux"
GL.SetReaction(GL.Identity("nameplate6"), "friend")
assert(guildMarker.shown and guildMarker.children[2].texture:find("Shield"))
GL.SetGuildReaction("Les Corbeaux", "warning")
assert(guildMarker.children[2].texture:find("Shield") and GL.RelationSource(GL.Get(guildMember)) == "manual")
GL.SetGuildReaction("Les Moineaux", "friend", "Une guilde sympathique")
local otherGuildMarker = assert(markerFor(otherGuildPlate))
assert(otherGuildMarker.shown and otherGuildMarker.children[2].texture:find("Shield"))
assert(toast.title.text == "Amitié de guilde : Les Moineaux" and toast.note.text == "Une guilde sympathique")
GL.SetGuildReaction("Les Moineaux", "neutral")
assert(not otherGuildMarker.shown and not toast.shown, "neutral guild rule clears inherited display")

-- Same-guild bursts keep the first captured player, count unique observations,
-- and never group individually tagged players or active PvP danger.
flushTimers()
now = now + 200
GL.SetSetting("sounds", true)
GL.SetGuildReaction("Burst Guild", "warning", "Attention au groupe")
for i = 8, 12 do
    units["nameplate" .. i] = { name = "Burst", surname = "Member" .. i, guid = "Player-1-burst" .. i, guild = "Burst Guild" }
    makePlate("nameplate" .. i)
end
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate8")
local firstBurstKey, firstBurstExpires = toast.key, toast.expires
local burstSounds = #sounds
now = now + 1
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate9")
assert(toast.key == firstBurstKey and toast.expires == firstBurstExpires and toast.hint.text:find("2 membres aperçus", 1, true))
assert(#sounds == burstSounds, "same-guild grouping must not play another sound")
units.target, units.mouseover = units.nameplate9, units.nameplate9
D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
D.OnEvent(nil, "UPDATE_MOUSEOVER_UNIT")
flushTimers()
assert(toast.hint.text:find("2 membres aperçus", 1, true), "duplicate unit views must not inflate guild count")
local ninth = GL.Identity("nameplate9")
GL.RecordAggression(ninth, "confirmed", "combat log", "burst-danger")
assert(toast.key == ninth.key and toast.source == "pvp", "guild cooldown must not consume real PvP warning")
assert(not toast.guildBurst and not toast.hint.text:find("membres"))
GL.SetReaction(GL.Identity("nameplate10"), "enemy")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate10")
local personalKey = GL.Identity("nameplate10").key
assert(toast.key == personalKey and toast.relation == "enemy" and not toast.guildBurst)
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate11")
assert(toast.key == personalKey, "lower severity guild notices must not displace a personal enemy")

now = now + 10
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate11")
assert(toast.key == GL.Identity("nameplate11").key and toast.guildBurst.count == 1)
GL.SetSetting("enemyAlerts", false)
assert(not toast.shown)
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate12")
assert(not toast.shown, "disabled alerts must not start/update a guild toast")
GL.SetSetting("enemyAlerts", true)
now = now + 10
units.target = units.nameplate12
D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(toast.key == GL.Identity("nameplate12").key and toast.guildBurst.count == 1)
units.target = units.nameplate11
D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(toast.guildBurst.count == 1, "per-person cooldown survives later guild bursts")
units.nameplate13 = { name = "Burst", surname = "Member13", guid = "Player-1-burst13", guild = "Burst Guild" }
makePlate("nameplate13")
local thirteenth = GL.Identity("nameplate13")
GL.RecordAggression(thirteenth, "probable", "target", "voided-burst-danger")
local thirteenthRecord = GL.Get(thirteenth)
assert(GL.VoidPvP(thirteenth, thirteenthRecord.history[#thirteenthRecord.history]))
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate13")
assert(toast.guildBurst.count == 2 and toast.key == GL.Identity("nameplate12").key, "voided history does not prevent guild grouping")
toast.scripts.OnClick(toast, "LeftButton")
assert(openedKey == GL.Identity("nameplate12").key, "grouped toast opens the first captured person's record")
now = now + 10
GL.SetGuildReaction("Burst Guild", "enemy")
assert(toast.key == ninth.key and toast.source == "guild" and not toast.guildBurst, "active aggression is not grouped even when a red guild rule takes precedence")
units.nameplate14 = { name = "Burst", surname = "Member14", guid = "Player-1-burst14", guild = "Burst Guild" }
makePlate("nameplate14")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate14")
assert(toast.key == ninth.key, "equal-severity guild crowds cannot replace an actual aggressor")

-- A visible toast refreshes its entire text when confidence or notes change,
-- without replaying the sound or extending its lifetime through the cooldown.
now = now + 10
units.nameplate15 = { name = "Audit", surname = "Source", guid = "Player-1-audit" }
makePlate("nameplate15")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate15")
local audit = GL.Identity("nameplate15")
GL.RecordAggression(audit, "probable", "target", "audit-probable")
assert(toast.note.text:find("déduite", 1, true))
local auditSounds, auditExpires = #sounds, toast.expires
GL.RecordAggression(audit, "confirmed", "combat log", "audit-confirmed")
assert(not toast.title.text:find("probable", 1, true) and not toast.note.text:find("déduite", 1, true))
GL.AddNote(audit, "Note fraîche")
assert(toast.note.text == "Note fraîche")
GL.AddNote(audit, "Note corrigée")
assert(toast.note.text == "Note corrigée" and #sounds == auditSounds and toast.expires == auditExpires)

-- A same-severity guild change cannot reuse the old guild's burst, even for
-- identical guild names on different realms. Refresh uses current live identity.
now = now + 10
GL.SetGuildReaction("Audit A", "enemy", "Guilde A", "Forever")
GL.SetGuildReaction("Audit B", "enemy", "Guilde B", "Forever")
GL.SetGuildReaction("Audit B", "enemy", "Autre serveur", "OtherRealm")
units.nameplate16 = { name = "First", surname = "GuildSwitch", guid = "Player-1-guildswitch", guild = "Audit A" }
makePlate("nameplate16")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate16")
local originalBurst, switchKey = toast.guildBurst, toast.key
assert(toast.guildKey == GL.GetGuildRule("Audit A", "Forever").key and originalBurst.count == 1)
units.nameplate16.guild = "Audit B"
D.Refresh()
assert(toast.shown and toast.key == switchKey and toast.title.text == "Rancune de guilde : Audit B")
assert(toast.guildBurst ~= originalBurst and toast.guildBurst.count == 1 and toast.note.text == "Guilde B")
local secondBurst = toast.guildBurst
units.nameplate17 = { name = "Second", surname = "OriginalGuild", guid = "Player-1-originalguild", guild = "Audit A" }
makePlate("nameplate17")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate17")
assert(toast.guildBurst == secondBurst and toast.guildBurst.count == 1 and not toast.hint.text:find("2 membres", 1, true))
units.nameplate16.guildRealm = "OtherRealm"
D.Refresh()
assert(toast.shown and toast.guildKey == GL.GetGuildRule("Audit B", "OtherRealm").key)
assert(toast.guildBurst ~= secondBurst and toast.guildBurst.count == 1 and toast.note.text == "Autre serveur")
GL.SetGuildReaction("Audit B", "enemy", "Note de guilde actualisée", "OtherRealm")
assert(toast.note.text == "Note de guilde actualisée", "guild-note edits refresh the current toast")

-- Native text bounds contain long guild/name/note strings; the full text remains
-- saved for the click-through file and note markup is rendered literally.
now = now + 10
local longGuild = string.rep("TrèsLongueGuilde", 8)
GL.SetGuildReaction(longGuild, "enemy", string.rep("Une longue note à conserver. ", 35) .. "|Ttest:999:999|t")
units.nameplate18 = { name = string.rep("Éloïse", 12), surname = string.rep("Longnom", 16), guid = "Player-1-longtext", guild = longGuild }
makePlate("nameplate18")
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate18")
assert(#toast.title.text > 120 and #toast.name.text > 200 and #toast.note.text > 800)
assert(toast.title.maxLines == 1 and toast.name.maxLines == 1 and toast.note.maxLines == 2)
assert(toast.note.text:find("||Ttest", 1, true), "note markup cannot create oversized inline textures")
assert(GL.GetGuildRule(longGuild).note:find("|Ttest", 1, true), "rendering does not change stored notes")

-- Missing nameplate API clears old markers, while target-based alerts stay safe.
C_NamePlate = nil
D.Refresh()
assert(not marker.shown and not markerFor(protected).shown)
now = now + 10
eventFrame.scripts.OnUpdate(eventFrame, 1)
assert(not toast.shown)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS display: existing plates, ThreatPlates, confidence badges/corrections, color restoration, recycling, secret/protected values, cooldowns/sounds, captured clicks, guild inheritance/burst grouping/PvP exemptions, tooltips and missing APIs")
