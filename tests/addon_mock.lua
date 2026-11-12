-- Load the real TOC with simulated WoW APIs for integration tests and benchmarks.
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
return mock, plate, sounds, hooks
