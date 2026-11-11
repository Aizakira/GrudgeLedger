-- Load the real TOC as one addon and exercise menu -> DB -> marker -> alert -> UI.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local methods = getmetatable(UIParent).__index
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(value) self.level = value end
function methods:SetIgnoreParentAlpha(value) self.ignoreAlpha = value end
function methods:SetIgnoreParentScale(value) self.ignoreScale = value end
function methods:SetVertexColor(...) self.vertex = { ... } end
function methods:SetTexture(value) self.texture = value end
function methods:GetTextColor() return unpack(self.color or { 1, 1, 1, 1 }) end
function methods:IsProtected() return false end
function methods:CanChangeProtectedState() return true end
function methods:AddLine(value) self.lines = self.lines or {} self.lines[#self.lines + 1] = value end
function methods:HookScript(event, fn)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end fn(...) end
end
GameTooltip = CreateFrame("Frame", "GameTooltip", UIParent)
function GameTooltip:GetUnit() return "Aqua Water", "target" end
GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end
GetTimePreciseSec = function() return 123.456 end
UnitIsDeadOrGhost = function() return false end
UnitAffectingCombat = function() return false end
UnitIsPVP = function() return true end
UnitHealth = function() return 100 end
UnitHealthMax = function() return 100 end
UnitCanAttack = function() return false end
local sounds = {}
SOUNDKIT = { RAID_WARNING = 1, IG_QUEST_LOG_OPEN = 2 }
PlaySound = function(id) sounds[#sounds + 1] = id end
local hooks = {}
hooksecurefunc = function(owner, name, fn)
    if type(owner) == "string" then hooks[owner] = name else hooks[name] = fn end
end
DoEmote = function() end
StartDuel = function() end
C_ChatInfo.PerformEmote = function() end
local plate = CreateFrame("Frame", "IntegrationPlate", UIParent)
plate.namePlateUnitToken = "nameplate1"
plate.TPFrame = CreateFrame("Frame", nil, plate)
plate.TPFrame.visual = { NameText = plate.TPFrame:CreateFontString(nil, "OVERLAY") }
plate.TPFrame.visual.NameText:SetText("Aqua Water")
mock.units.nameplate1 = mock.units.target
C_NamePlate = {
    GetNamePlateForUnit = function(unit) if unit == "nameplate1" then return plate end end,
    GetNamePlates = function() return { plate } end,
}
local file = assert(io.open(TEST_ROOT .. "/GrudgeLedger.toc", "r"))
for line in file:lines() do
    line = line:gsub("\r", "")
    if line:match("%.lua$") then assert(loadfile(TEST_ROOT .. "/" .. line))("GrudgeLedger") end
end
file:close()
mock.Fire("ADDON_LOADED", "GrudgeLedger")
mock.Fire("PLAYER_LOGIN")
mock.Fire("PLAYER_ENTERING_WORLD")
local GL = GrudgeLedger
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
assert(not GrudgeLedgerWindow, "no window on login")
assert(next(mock.cvars) == nil, "no automatic game setting changes")
local menuRoot = mock.NewMenu()
mock.menuHooks.MENU_UNIT_PLAYER(nil, menuRoot, { unit = "target" })
local menu = assert(menuRoot.children["Grudge Ledger"])
assert(menu.buttons.Ami and menu.buttons.Ennemi)
menu.buttons.Ami()
local identity = GL.Identity("target")
assert(GL.Relation(GL.Get(identity)) == "friend")
mock.Fire("PLAYER_TARGET_CHANGED")
assert(GrudgeLedgerNearbyAlert:IsShown())
assert(GrudgeLedgerNearbyAlert.name:GetText() == "Aqua Water")
assert(sounds[#sounds] == SOUNDKIT.IG_QUEST_LOG_OPEN)
menu.buttons.Ennemi()
mock.Fire("PLAYER_TARGET_CHANGED")
assert(GL.Relation(GL.Get(identity)) == "enemy")
assert(GrudgeLedgerNearbyAlert.relation == "enemy" and sounds[#sounds] == SOUNDKIT.RAID_WARNING)
GrudgeLedgerNearbyAlert.scripts.OnClick(GrudgeLedgerNearbyAlert, "LeftButton")
assert(GrudgeLedgerWindow:IsShown(), "alert click opens captured record")
SlashCmdList.GRUDGELEDGER("note Super donjon ensemble.")
assert(GL.Get(identity).notes[1].text == "Super donjon ensemble.")
SlashCmdList.GRUDGELEDGER("ami")
SlashCmdList.GRUDGELEDGER("- Un mauvais souvenir")
assert(GL.Get(identity).reputation == 0)
SlashCmdList.GRUDGELEDGER("- Un autre mauvais souvenir")
assert(GL.Relation(GL.Get(identity)) == "warning")
mock.Fire("PLAYER_TARGET_CHANGED")
assert(GrudgeLedgerNearbyAlert.relation == "warning")
GL.Display.Tooltip(GameTooltip)
assert(#GameTooltip.lines > 1)
GL.ShowLedger(identity.key)
for _, f in ipairs(mock.frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.5) end end
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
assert(next(mock.cvars) == nil)
-- A correction from the real UI propagates through Core to an existing alert.
mock.units.target = { name = "Another", surname = "Fighter", guid = "Player-1-integration" }
mock.units.nameplate1 = mock.units.target
mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
local opponent = GL.Identity("target")
local record = GL.RecordPvP(opponent, "death", "probable", "Uncertain attribution", "integration-death")
assert(GrudgeLedgerNearbyAlert.key == record.key and GrudgeLedgerNearbyAlert:IsShown())
assert(GrudgeLedgerNearbyAlert.title:GetText():find("probable", 1, true))
GL.ShowLedger(record.key)
local correctionButton
for _, child in ipairs(GrudgeLedgerWindow.children) do
    if child.text == "Corriger le PvP" then correctionButton = child end
end
assert(correctionButton).scripts.OnClick()
local undo = GrudgeLedgerCorrections.rows[1].undo
undo.scripts.OnClick(undo, "LeftButton")
assert(record.pvp.probableDeaths == 0 and GL.Relation(record) == "neutral")
assert(not GrudgeLedgerNearbyAlert:IsShown(), "correction immediately removes the obsolete alert")
assert(GrudgeLedgerWindow.detailText:GetText():find("annulé", 1, true))
-- An Alliance player marked as a personal enemy becomes red after explicit setup.
SlashCmdList.GRUDGELEDGER("reperage")
GL.SetReaction(opponent, "enemy")
local redName = plate.TPFrame.visual.NameText.color
assert(mock.cvars.nameplateShowFriendlyPlayers == 1 and mock.cvars.nameplateShowAll == 1)
assert(redName and redName[1] == 1 and redName[2] == 0.25 and redName[3] == 0.2,
    "a same-faction enemy must be red on the actual displayed nameplate font")
-- A targeted kiss marks a party member as a friend: keep the heart, suppress only the toast.
GrudgeLedgerNearbyAlert:Hide() -- end the previous enemy-alert scenario
mock.units.target = { name = "New", surname = "Companion", guid = "Player-1-companion" }
mock.units.nameplate1 = mock.units.target
mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
opponent = GL.Identity("target")
mock.units.party1 = mock.units.nameplate1
GetNumGroupMembers = function() return 2 end
UnitInParty = function(unit) return UnitIsUnit(unit, "party1") end
UnitIsVisible = function(unit) return UnitExists(unit) end
mock.SetCombat(true) -- this fixture's world nameplate is not protected
hooks.PerformEmote("KISS")
assert(GL.Relation(GL.Get(opponent)) == "friend" and GL.Get(opponent).reputation == 1)
local heart
for _, child in ipairs(plate.children) do
    local icon = child.children[2]
    if icon and type(icon.texture) == "string" and icon.texture:find("RelationFriend") then heart = child end
end
assert(heart and heart:IsShown(), "party friends retain their heart even in combat on modifiable plates")
assert(not GrudgeLedgerNearbyAlert:IsShown(), "party suppression must affect only the alert")
GL.SetSetting("friendAlerts", false)
assert(heart:IsShown(), "turning off friend alerts must not hide their hearts")
mock.SetCombat(false)
-- Instanced PvP pauses all automatic memories and display, not manual journal access.
local instanceType = "none"
IsInInstance = function() return instanceType ~= "none", instanceType end
for _, kind in ipairs({ "pvp", "arena" }) do
    GL.SetReaction(opponent, "enemy")
    local record = GL.Get(opponent)
    local beforeHistory, beforeScore = #record.history, record.reputation
    local beforeSeen, beforeGroups = record.lastSeen, record.groupCount
    local beforeSounds = #sounds
    instanceType = kind
    mock.Fire("PLAYER_ENTERING_WORLD")
    mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    mock.Fire("PLAYER_TARGET_CHANGED")
    mock.Fire("GROUP_ROSTER_UPDATE")
    GL.Display.Refresh(record)
    assert(not GrudgeLedgerNearbyAlert:IsShown() and not heart:IsShown(), "BG hides alerts and markers")
    assert(plate.TPFrame.visual.NameText.color[2] == 1, "BG restores the original name color")
    GameTooltip.lines, GameTooltip._grudgeLedgerKey = {}, nil
    GL.Display.Tooltip(GameTooltip)
    assert(#GameTooltip.lines == 0, "BG tooltip must not add a relationship")
    hooks.PerformEmote("RUDE")
    assert(GL.SendGesture("SPIT"), "native emotes remain usable without recording an opinion")
    local stranger = GL.IdentityFromName("Unrecorded", kind, "Player-1-unrecorded-" .. kind)
    for _, who in ipairs({ opponent, stranger }) do
        assert(GL.RecordPvP(who, "death", "confirmed", "BG death", "bg-death") == nil)
        assert(GL.RecordPvP(who, "kill", "probable", "BG kill", "bg-kill") == nil)
        assert(GL.RecordAggression(who, "confirmed", "BG damage", "bg-damage") == nil)
        assert(GL.RecordSeen(who, true) == nil)
        assert(GL.RecordGroup(who, "bg-group", "Battleground") == nil)
        assert(GL.AdjustReputation(who, -1, "BG emote", "emote") == nil)
    end
    assert(not GL.Get(stranger), "BG must not introduce unknown players")
    assert(#record.history == beforeHistory and record.reputation == beforeScore
        and record.lastSeen == beforeSeen and record.groupCount == beforeGroups and #sounds == beforeSounds,
        "BG must preserve existing scores, history, sightings, groups and silence")
    assert(GL.AddNote(opponent, "A manual note remains possible."))
    GL.ShowLedger(opponent.key)
    assert(GrudgeLedgerWindow:IsShown(), "manual journal remains accessible")
    instanceType = "none"
    mock.Fire("PLAYER_ENTERING_WORLD")
    assert(heart:IsShown(), "markers resume after leaving instanced PvP")
    assert(GL.RecordAggression(stranger, "confirmed", "World PvP", "world-" .. kind),
        "outdoor PvP resumes without changing saved settings")
    assert(GL.Settings().pvpTracking and GL.Settings().socialTracking and GL.Settings().groupTracking)
end
for _, kind in ipairs({ "none", "party", "raid", "scenario" }) do
    instanceType = kind
    assert(not GL.IsPvPInstance(), "only battlegrounds and arenas are paused")
    assert(GL.RecordSeen(opponent, true), "non-PvP contexts retain ordinary encounters")
end
IsInInstance = function() return true, mock.secret end
assert(not GL.IsPvPInstance(), "unreadable type must not be compared or persisted")
IsInInstance = nil
assert(not GL.IsPvPInstance(), "an absent optional API must not crash the journal")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS integrated TOC: boot, menus, persistence writes, markers/alerts, notes, macros, tooltip, UI correction propagation, BG/arena pause and resume; no forced UI/target/CVars")
