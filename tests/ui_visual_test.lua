local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local methods = getmetatable(UIParent).__index
local setPoint = methods.SetPoint
function methods:SetPoint(...) setPoint(self, ...) self.anchor = { ... } end
function methods:SetScale(value) assert(value > 0 and value < math.huge) self.scale = value end
function methods:SetTexture(value) self.texture = value end
function methods:SetMaxLines(value) self.maxLines = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetJustifyV(value) self.justifyV = value end
function methods:HighlightText() self.highlighted = true end
function methods:GetEffectiveScale() return self.effectiveScale or 1 end
function methods:GetCenter() return self.cx or 500, self.cy or 300 end
function methods:IsVisible() return self.shown end
local shape, cursorX, cursorY = "ROUND", 500, 300
function GetMinimapShape() return shape end
function GetCursorPosition() return cursorX, cursorY end
Minimap:SetSize(160, 160)
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
local GL = GrudgeLedger
GL.InitDB()
local b = GrudgeLedgerMinimapButton
assert(b.parent == UIParent, "outer icon must not inherit minimap clipping")
assert(b:GetWidth() == 31 and b:GetHeight() == 31 and b.icon.texture == GL.minimapIcon)
assert(b.icon:GetWidth() == 17 and b.icon:GetHeight() == 17 and b.icon.anchor[1] == "TOPLEFT" and b.icon.anchor[2] == 7 and b.icon.anchor[3] == -6)
assert(b.background.texture == "Interface\\Minimap\\UI-Minimap-Background" and b.background:GetWidth() == 20)
assert(b.border.texture == "Interface\\Minimap\\MiniMap-TrackingBorder" and b.border:GetWidth() == 53)
assert(b.border.anchor[1] == "TOPLEFT" and b.border.anchor[2] == 0 and b.border.anchor[3] == 0)
assert(b.icon.mask and b.highlightTexture, "circular icon mask and native hover highlight")
local function near(a, expected) assert(math.abs(a - expected) < 0.001, tostring(a) .. " ~= " .. expected) end
local function xy() return b.anchor[4], b.anchor[5] end
GL.SetSetting("minimapAngle", 0)
local x, y = xy()
near(x, 98) near(y, 0)
assert(x - b:GetWidth() / 2 > Minimap:GetWidth() / 2, "icon edge must stay outside map")
Minimap:SetSize(320, 320)
Minimap.scripts.OnSizeChanged(Minimap, 320, 320)
x, y = xy() near(x, 178)
shape = "SQUARE"
GL.SetSetting("minimapAngle", 45)
x, y = xy() near(x, 178) near(y, 178)
shape = "SIDE-LEFT"
GL.SetSetting("minimapAngle", 135)
x, y = xy() near(math.sqrt(x*x+y*y), 178)
GL.SetSetting("minimapAngle", 45)
x, y = xy() near(x, 178) near(y, 178)
shape = "UNKNOWN-CUSTOM-MASK"
GL.SetSetting("minimapAngle", 45)
x, y = xy() near(x, 178) near(y, 178)
shape = "ROUND"
Minimap:SetSize(240, 120)
GL.SetSetting("minimapAngle", 45)
x, y = xy()
local clearance = math.huge
for i = 0, 7200 do
    local theta = i * math.pi * 2 / 7200
    clearance = math.min(clearance, math.sqrt((x - 120 * math.cos(theta))^2 + (y - 60 * math.sin(theta))^2))
end
assert(clearance >= 17.99, "elliptical minimap must preserve the full medallion gap along the true edge")
Minimap:SetSize(200, 120)
Minimap.effectiveScale, UIParent.effectiveScale = 1.5, 0.75
GL.SetSetting("minimapAngle", 90)
x, y = xy() near(x, 0) near(y, 78) near(b.scale, 2)

local settingsChanges = 0
GL.On("SETTINGS", function() settingsChanges = settingsChanges + 1 end)
local oldAngle = GL.Settings().minimapAngle
cursorX, cursorY = 900, 450 -- map center is (750,450) pixels with 1.5 scale.
b.scripts.OnDragStart(b)
for i = 1, 20 do b.scripts.OnUpdate(b, 0.01) end
x, y = xy() near(x, 118) near(y, 0)
assert(GL.Settings().minimapAngle == oldAngle and settingsChanges == 0, "drag moves visually without SETTINGS spam")
b.scripts.OnDragStop(b)
near(GL.Settings().minimapAngle, 0)
assert(settingsChanges == 1 and not b.dragging, "release saves once")
Minimap:Hide()
assert(not b:IsShown())
Minimap:Show()
assert(b:IsShown(), "map show restores outer button")
Minimap.effectiveScale = mock.secret
shape = "ROUND"
b.scripts.OnUpdate(b, 1)
assert(b.scale > 0 and b.scale < math.huge, "secret or unavailable scale has a safe fallback")

-- Shared styles preserve ordinary flows, state labels and bounded row names.
b.scripts.OnClick(b, "LeftButton")
local ledger = GrudgeLedgerWindow
assert(ledger:IsShown() and ledger.filters.all.normalTexture)
assert(ledger.actions[1].enabled == false and ledger.actions[1].disabledFont == "GameFontDisableSmall")
assert(ledger.actions[1].normalFont ~= ledger.actions[1].disabledFont and ledger.actions[1].normalTexture ~= ledger.actions[1].disabledTexture,
    "native button states retain separate disabled font and background")
assert(ledger.actions[1].fontString:GetText() == "Ami", "native Button text remains attached to custom caption")
assert(ledger.actions[1].fontString.color[1] == 0.52, "empty-state captions visibly reflect disabled state")
for _, control in pairs(ledger.reactions) do assert(not control.selection:IsShown()) end
local identity = GL.Identity("target")
GL.SetReaction(identity, "friend")
GL.ShowLedger(identity.key)
assert(ledger.rows[1].name.wordWrap == false and ledger.rows[1].name.maxLines == 1)
assert(ledger.rows[1].selection:IsShown())
assert(ledger.reactions.friend.selection:IsShown() and ledger.actions[1].fontString.color[1] > 0.9,
    "selecting a person restores readable enabled captions and its effective reaction")
local selectedColor = ledger.filters.all.normalSurface.color
local inactiveColor = ledger.filters.enemy.normalSurface.color
assert(selectedColor[1] ~= inactiveColor[1], "active filter has a visible fill")
assert(ledger.detailText:GetText():find("|cff653c20NOTES PERSONNELLES|r", 1, true), "section headings use dark ink on parchment")
assert(ledger.detailText:GetText():find("|cff5c4029Dernier lieu", 1, true), "secondary metadata stays readable on parchment")
assert(ledger.paper.texture:find("JournalPaper", 1, true) and ledger.illustration.texture:find("JournalIllustration", 1, true))
near(ledger.illustration:GetWidth() / ledger.illustration:GetHeight(), 2)
assert(ledger.illustration:GetWidth() <= 144, "header decoration must leave room for controls")
for _, region in ipairs({ ledger.detailTitle, ledger.detailStatus, ledger.detailIdentity, ledger.detailScroll }) do
    assert(region.anchor[2] >= ledger.paper.anchor[2] and region.anchor[2] + region:GetWidth() < ledger.paper.anchor[2] + ledger.paper:GetWidth())
    assert(-region.anchor[3] + region:GetHeight() < -ledger.paper.anchor[3] + ledger.paper:GetHeight(), "reading content stays inside the page")
end
local function luminance(c)
    local result = 0
    for i, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
        local v = c[i] <= 0.04045 and c[i] / 12.92 or ((c[i] + 0.055) / 1.055) ^ 2.4
        result = result + weight * v
    end
    return result
end
local paperLuminance = luminance({ 0.86, 0.79, 0.65 }) -- darker than the calm center of the shipped paper
local function readable(c) assert((paperLuminance + 0.05) / (luminance(c) + 0.05) >= 4.5, "page text needs at least 4.5:1 contrast") end
readable(ledger.detailText.color) readable(ledger.detailIdentity.color)
for _, relation in ipairs({ "friend", "warning", "enemy", "neutral" }) do
    GL.SetReaction(identity, relation)
    readable(ledger.detailTitle.color) readable(ledger.detailStatus.color)
    for value, control in pairs(ledger.reactions) do
        assert(control.selection:IsShown() == (value == relation), "exactly the effective relation is selected")
    end
    local row = ledger.rows[1]
    assert((luminance(row.name.color) + 0.05) / (luminance(row.bg.color) + 0.05) >= 4.5,
        "subdued relation text stays readable on the selected index row")
end
ledger.search:SetText("No matching person")
for _, control in pairs(ledger.reactions) do assert(not control.selection:IsShown() and not control.enabled) end
assert(ledger.actions[1].fontString.color[1] == 0.52, "clearing selection restores the disabled appearance")
GL.ShowLedger(identity.key)
assert(ledger.detailText:GetText():find("NOTES PERSONNELLES", 1, true) < ledger.detailText:GetText():find("HISTORIQUE RÉCENT", 1, true))
UIParent:SetSize(800, 600) ledger:Hide() ledger:Show()
assert(ledger:GetWidth() * ledger.scale <= 776 and ledger:GetHeight() * ledger.scale <= 576, "journal fits small displays")
UIParent:SetSize(1920, 1080)
GL.EditNote(identity)
assert(GrudgeLedgerNote.edit.justifyV == "TOP" and ledger.search.justifyV == "MIDDLE")
readable(GrudgeLedgerNote.edit.color)
SlashCmdList.GRUDGELEDGER("debug")
assert(GrudgeLedgerDiagnostic.edit.justifyV == "TOP", "multiline editors always begin at the upper-left")
assert(#GL.errors == 0)
-- The client's compartment layout uses the same alternate dimensions as LibDBIcon.
for _, frame in ipairs(mock.frames) do if frame.name then _G[frame.name] = nil end end
local modernMock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
AddonCompartmentFrame = {}
local modernMethods = getmetatable(UIParent).__index
function modernMethods:SetTexture(value) self.texture = value end
function modernMethods:SetPoint(...) self.anchor = { ... } end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
GrudgeLedger.InitDB()
local modernButton = GrudgeLedgerMinimapButton
assert(modernButton:GetWidth() == 31 and modernButton.icon:GetWidth() == 18)
assert(modernButton.icon.anchor[1] == "CENTER" and modernButton.background.anchor[1] == "CENTER")
assert(modernButton.background:GetWidth() == 24 and modernButton.border:GetWidth() == 50)
assert(modernButton.icon.texture == GrudgeLedger.minimapIcon and GrudgeLedger.minimapIcon ~= GrudgeLedger.icon)
assert(#GrudgeLedger.errors == 0)
print("PASS visual UI: native minimap frame with small borderless artwork (legacy/compartment), shape/size/scale-aware rim, unclipped parent, one drag commit, resize/visibility, selected rows and headings.")
