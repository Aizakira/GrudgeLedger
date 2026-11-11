local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local methods = getmetatable(UIParent).__index
local setPoint = methods.SetPoint
local createTexture = methods.CreateTexture
function methods:CreateTexture(name, layer, template, sublevel)
    local texture = createTexture(self, name, layer, template, sublevel)
    texture.drawLayer, texture.sublevel = layer, sublevel
    return texture
end
function methods:SetAllPoints(region) self.allPoints = region or self.parent end
function methods:SetPoint(...) setPoint(self, ...) self.anchor = { ... } end
function methods:SetScale(value) assert(value > 0 and value < math.huge) self.scale = value end
function methods:SetTexture(value) self.texture, self.requestedTexture, self.color = value, value, nil end
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
assert(ledger.actions[1].fontString.color[1] == 0.50, "empty-state captions visibly reflect disabled state on the light page")
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
assert(ledger.bookSurface.texture:find("JournalBookSurface", 1, true) and ledger.bookSurface.allPoints == ledger)
assert(ledger.closeButton.anchor[3] == -29 and ledger.total.anchor[3] == -51,
    "close and count stay on the calm leather band, away from metal corners and lower stitching")
assert(ledger.total.anchor[2] >= 450 and ledger.total.anchor[2] + ledger.total:GetWidth() <= 685)
for _, controls in ipairs({ ledger.filters, ledger.factions, ledger.rows }) do
    for _, control in pairs(controls) do
        assert(control.anchor[2] >= 36 and control.anchor[2] + control:GetWidth() <= 292, "index controls respect the worn page margins")
    end
end
for _, control in ipairs(ledger.actions) do
    assert(control.anchor[2] + control:GetWidth() <= 904, "right-hand controls stay clear of the rough outer edge")
end
for _, region in ipairs({ ledger.outerBorder, ledger.cover, ledger.innerBorder, ledger.grain, ledger.header, ledger.headerFill, ledger.headerLine }) do
    assert(not region:IsShown(), "old opaque chrome cannot cover the open-book artwork or protrude through its corners")
end
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
local function solidFallback(texture)
    for _, child in ipairs(texture.parent.children) do
        if child.color and (child.allPoints == texture or texture.allPoints == child) then
            assert(child.drawLayer == texture.drawLayer and child.sublevel < texture.sublevel,
                "solid fallback must stay below its image without relying on creation order")
            return child
        end
    end
    error("paper texture has no independent, matching solid fallback")
end
local function checkPage(frame)
    for _, fill in ipairs({ frame.paper, frame.indexPaper }) do
        assert(fill.drawLayer == frame.bookSurface.drawLayer and fill.sublevel < frame.bookSurface.sublevel)
        assert((luminance(fill.color) + 0.05) / (luminance(frame.detailText.color) + 0.05) >= 4.5,
            "both pages remain readable without the open-book image")
    end
    for _, child in ipairs(frame.children) do
        if child ~= frame.paper and child ~= frame.indexPaper and child.drawLayer == "BACKGROUND" and child.color then
            assert(child.sublevel < frame.paper.sublevel, "leather, lining and borders must be below the reading page")
        end
    end
end
checkPage(ledger)
readable(ledger.detailText.color) readable(ledger.detailIdentity.color)
for _, relation in ipairs({ "friend", "warning", "enemy", "neutral" }) do
    GL.SetReaction(identity, relation)
    readable(ledger.detailTitle.color) readable(ledger.detailStatus.color)
    for value, control in pairs(ledger.reactions) do
        assert(control.selection:IsShown() == (value == relation), "exactly the effective relation is selected")
    end
    local row = ledger.rows[1]
    local names = { friend = "Ami", warning = "Méfiance", enemy = "Ennemi", neutral = "Neutre" }
    local icons = { friend = "RelationFriend", warning = "RelationWarning", enemy = "RelationEnemy" }
    assert(row.relation:GetText() == names[relation] and row.relation.wordWrap == false and row.relation.maxLines == 1)
    assert(row.name:GetText() == GL.Get(identity.key).fullName, "relation has its own icon and label, not a cryptic name prefix")
    assert(row.relationIcon:IsShown() == (relation ~= "neutral"))
    assert(icons[relation] and row.relationIcon.texture:find(icons[relation], 1, true) or relation == "neutral" and not row.relationIcon.texture,
        "recycled rows must update or clear the previous relation icon")
    assert(row.identity.anchor[2] + row.identity:GetWidth() < row.relation.anchor[2]
        and row.relation.anchor[2] + row.relation:GetWidth() < row:GetWidth(), "identity and explicit relation labels cannot overlap")
    assert((luminance(row.bg.color) + 0.05) / (luminance(row.name.color) + 0.05) >= 4.5,
        "relation ink stays readable on the selected ochre index row")
    assert((luminance(row.bg.color) + 0.05) / (luminance(row.relation.color) + 0.05) >= 4.5)
    readable(row.name.color) readable(row.identity.color) readable(row.relation.color)
end
for _, controls in ipairs({ ledger.filters, ledger.factions, ledger.reactions }) do
    for _, control in pairs(controls) do
        local textL, fillL = luminance(control.caption.color), luminance(control.normalSurface.color)
        assert((math.max(textL, fillL) + 0.05) / (math.min(textL, fillL) + 0.05) >= 4.5,
            "active burgundy and inactive parchment controls both preserve readable text")
    end
end
for i = 6, #ledger.actions do
    local control = ledger.actions[i]
    assert(-control.anchor[3] > -ledger.detailScroll.anchor[3] + ledger.detailScroll:GetHeight(), "secondary actions follow the reading area")
    assert(-control.anchor[3] + control:GetHeight() < -ledger.paper.anchor[3] + ledger.paper:GetHeight(), "secondary actions stay on the page")
end
ledger.search:SetText("No matching person")
for _, control in pairs(ledger.reactions) do assert(not control.selection:IsShown() and not control.enabled) end
assert(ledger.actions[1].fontString.color[1] == 0.50, "clearing selection restores the disabled appearance")
GL.ShowLedger(identity.key)
assert(ledger.detailText:GetText():find("NOTES PERSONNELLES", 1, true) < ledger.detailText:GetText():find("HISTORIQUE RÉCENT", 1, true))
UIParent:SetSize(800, 600) ledger:Hide() ledger:Show()
assert(ledger:GetWidth() * ledger.scale <= 776 and ledger:GetHeight() * ledger.scale <= 576, "journal fits small displays")
UIParent:SetSize(1920, 1080)
GL.EditNote(identity)
assert(GrudgeLedgerNote.edit.justifyV == "TOP" and ledger.search.justifyV == "MIDDLE")
readable(GrudgeLedgerNote.edit.color)
for _, region in ipairs(mock.frames) do
    if type(region.requestedTexture) == "string" and region.requestedTexture:find("JournalPaper", 1, true) then solidFallback(region) end
end
SlashCmdList.GRUDGELEDGER("debug")
assert(GrudgeLedgerDiagnostic.edit.justifyV == "TOP", "multiline editors always begin at the upper-left")
assert(#GL.errors == 0)
-- The client's compartment layout uses the same alternate dimensions as LibDBIcon.
for _, frame in ipairs(mock.frames) do if frame.name then _G[frame.name] = nil end end
local modernMock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
AddonCompartmentFrame = {}
local modernMethods = getmetatable(UIParent).__index
local modernCreateTexture = modernMethods.CreateTexture
function modernMethods:CreateTexture(name, layer, template, sublevel)
    local texture = modernCreateTexture(self, name, layer, template, sublevel)
    texture.drawLayer, texture.sublevel = layer, sublevel
    return texture
end
function modernMethods:SetAllPoints(region) self.allPoints = region or self.parent end
-- Reproduce a session where the new parchment is unavailable but the book loads.
function modernMethods:SetTexture(value)
    self.texture, self.requestedTexture, self.color = value, value, nil
    if type(value) == "string" and (value:find("JournalPaper", 1, true) or value:find("JournalBookSurface", 1, true)) then self.texture = nil end
end
function modernMethods:SetPoint(...) self.anchor = { ... } end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
GrudgeLedger.InitDB()
local modernButton = GrudgeLedgerMinimapButton
assert(modernButton:GetWidth() == 31 and modernButton.icon:GetWidth() == 18)
assert(modernButton.icon.anchor[1] == "CENTER" and modernButton.background.anchor[1] == "CENTER")
assert(modernButton.background:GetWidth() == 24 and modernButton.border:GetWidth() == 50)
assert(modernButton.icon.texture == GrudgeLedger.minimapIcon and GrudgeLedger.minimapIcon ~= GrudgeLedger.icon)
GrudgeLedger.ShowLedger()
GrudgeLedger.EditNote(GrudgeLedger.Identity("target"))
GrudgeLedger.ShowGuilds()
local missingPaperCount = 0
for _, region in ipairs(modernMock.frames) do
    if type(region.requestedTexture) == "string" and region.requestedTexture:find("JournalPaper", 1, true) then
        assert(region.texture == nil)
        local fill = solidFallback(region)
        if region.parent == GrudgeLedgerNote.edit then
            assert((luminance(fill.color) + 0.05) / (luminance(GrudgeLedgerNote.edit.color) + 0.05) >= 4.5)
        end
        missingPaperCount = missingPaperCount + 1
    end
end
assert(missingPaperCount == 8, "main, note, guild windows and note editor all keep their solid fills")
assert(not GrudgeLedgerWindow.bookSurface.texture and GrudgeLedgerWindow.paper.color and GrudgeLedgerWindow.indexPaper.color)
checkPage(GrudgeLedgerWindow)
assert(#GrudgeLedger.errors == 0)
print("PASS visual UI: native minimap frame with small borderless artwork (legacy/compartment), shape/size/scale-aware rim, unclipped parent, one drag commit, resize/visibility, selected rows and headings.")
