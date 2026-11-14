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
function methods:SetAlpha(value) self.alpha = value end
function methods:SetDrawLayer(layer, sublevel) self.drawLayer, self.sublevel = layer, sublevel end
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
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
local GL = GrudgeLedger
GL.InitDB()
local translucent = GL.UITheme.surface(UIParent, { 0.45, 0.29, 0.12, 0.09 })
assert(translucent.color[4] == 0.09, "shared surfaces must preserve requested alpha instead of obscuring parchment")
translucent:Hide()
local b = GrudgeLedgerMinimapButton
assert(b.parent == UIParent, "outer icon must not inherit minimap clipping")
assert(b:GetWidth() == 31 and b:GetHeight() == 31 and b.icon.texture == GL.minimapIcon)
assert(b.icon:GetWidth() == 20 and b.icon:GetHeight() == 20 and b.icon.anchor[1] == "TOPLEFT" and b.icon.anchor[2] == 6 and b.icon.anchor[3] == -5)
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

-- Real callbacks exercise navigation, empty states and shared visual semantics.
local function click(control) assert(control and control.scripts.OnClick) control.scripts.OnClick(control, "LeftButton") end
local function luminance(c)
    local result = 0
    for i, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
        local v = c[i] <= 0.04045 and c[i] / 12.92 or ((c[i] + 0.055) / 1.055) ^ 2.4
        result = result + weight * v
    end
    return result
end
local function contrast(a, b)
    local x, y = luminance(a), luminance(b)
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end
local function readable(c) assert(contrast(c, { 0.86, 0.79, 0.65 }) >= 4.5, "ink on parchment needs 4.5:1 contrast") end
local function solidFallback(texture)
    for _, child in ipairs(texture.parent.children) do
        if child.color and (child.allPoints == texture or texture.allPoints == child) then
            assert(child.drawLayer == texture.drawLayer and child.sublevel < texture.sublevel)
            return child
        end
    end
    error("paper texture has no independent solid fallback")
end
local function checkPage(frame)
    assert(frame.paper.sublevel < frame.bookSurface.sublevel and frame.indexPaper.sublevel < frame.bookSurface.sublevel)
    assert(contrast(frame.paper.color, frame.detailText.color) >= 4.5, "light reading page fallback stays readable")
    assert(contrast(frame.indexPaper.color, frame.total.color) >= 4.5, "dark index fallback stays readable")
end
click(b)
local ledger = GrudgeLedgerWindow
assert(ledger:IsShown() and ledger.filters.all.normalTexture)
assert(not ledger.actions[1].enabled and ledger.actions[1].fontString:GetText() == "Ami")
assert(ledger.actions[1].disabledTexture ~= ledger.actions[1].normalTexture)
for _, control in pairs(ledger.reactions) do assert(not control.selection:IsShown()) end
local identity = GL.Identity("target")
GL.SetReaction(identity, "friend")
GL.AddNote(identity, "Une sortie agréable, à refaire.")
GL.ShowLedger(identity.key)
for _, slot in ipairs({ledger, ledger.rows[1]}) do
    assert(slot.raceIcon.drawLayer == "ARTWORK" and slot.classIcon.drawLayer == "OVERLAY",
        "the class badge must draw in front of the portrait")
end
assert(ledger.rows[1].name.wordWrap == false and ledger.rows[1].name.maxLines == 1)
assert(ledger.rows[1].selection:IsShown() and ledger.reactions.friend.selection:IsShown())
assert(ledger.actions[1].enabled and ledger.actions[1].caption.color[1] > 0.9)
assert(ledger.bookSurface.texture:find("JournalBookSurface", 1, true) and ledger.bookSurface.allPoints == ledger)
local previousTab
for _, key in ipairs({"ledger", "players", "guilds", "journal"}) do
    local control = ledger.navigation[key]
    local x, y = control.anchor[2], control.anchor[3]
    assert(control.caption.anchor[1] == "CENTER" and control.caption.justifyV == "MIDDLE",
        "center the glyphs inside each tab as well as the caption box")
    assert(control.caption:GetHeight() >= control.caption.font[2] * 1.25 + 2, "room for large print")
    if previousTab then
        assert(previousTab.anchor[3] == y and previousTab:GetHeight() == control:GetHeight())
        assert(x > previousTab.anchor[2] + previousTab:GetWidth(), "leave a gap between tab faces")
    end
    previousTab = control
    assert(control.selection:IsShown() == control.active)
    assert(contrast(control.caption.color, control.normalSurface.color) >= 4.5,
        "navigation labels remain readable in active and inactive states")
    assert(control.pushedTexture.alpha > 0 and control.highlightTexture, "navigation keeps interaction feedback")
end
assert(ledger.navigation.ledger.anchor[2] == ledger:GetWidth() - previousTab.anchor[2] - previousTab:GetWidth(),
    "balance the tabs between the covers")
local activeTab = ledger.detailTabs.summary
assert(activeTab.active and activeTab.selection:IsShown())
assert(activeTab.normalTexture.drawLayer == "BACKGROUND" and activeTab.disabledTexture.drawLayer == "BACKGROUND")
assert(activeTab.skin.drawLayer == "ARTWORK" and activeTab.selection.drawLayer == "ARTWORK" and activeTab.selection.sublevel == 1,
    "an active tab's illustrated brass border draws above the native button fill")
activeTab:SetEnabled(false)
assert(activeTab.selection.alpha < 1, "disabled active tab visibly dims its selection")
activeTab:SetEnabled(true)
assert(activeTab.active and activeTab.selection:IsShown() and activeTab.selection.alpha == 1)
assert(contrast(activeTab.caption.color, activeTab.normalSurface.color) >= 4.5,
    "reenabling an active parchment tab restores light text on its dark selection")
assert(ledger.seal.texture:match("JournalMedallion$") and ledger.title:GetText() == "Grudge Ledger")
assert(ledger.wordmark.texture:match("JournalWordmark$") and ledger.wordmark:IsShown() and not ledger.title:IsShown(),
    "the independent gold wordmark replaces the visible title exactly once")
assert(ledger.closeButton.normalTexture.texture:match("JournalClose$") and ledger.settingsButton.normalTexture.texture:match("JournalSettings$"))
ledger.bookSurface:Hide()
click(ledger.closeButton)
assert(not ledger:IsShown(), "the close action must work independently of the illustrated background")
GL.ShowLedger(identity.key)
ledger.bookSurface:Show()
checkPage(ledger)
readable(ledger.detailText.color) readable(ledger.detailIdentity.color)
for _, relation in ipairs({ "friend", "warning", "enemy", "neutral" }) do
    GL.SetReaction(identity, relation)
    readable(ledger.detailTitle.color) readable(ledger.detailStatus.color)
    for key, control in pairs(ledger.reactions) do assert(control.selection:IsShown() == (key == relation)) end
    local row = ledger.rows[1]
    local names = { friend = "Ami", warning = "Méfiance", enemy = "Ennemi", neutral = "Neutre" }
    local icons = { friend = "RelationFriend", warning = "RelationWarning", enemy = "RelationEnemy", neutral = "RelationNeutral" }
    assert(row.relation:GetText() == names[relation] and row.relation.wordWrap == false and row.relation.maxLines == 1)
    assert(row.name:GetText() == GL.Get(identity.key).fullName, "no cryptic prefix in the player's name")
    assert(row.relationIcon:IsShown() and row.relationIcon.texture:find(icons[relation], 1, true))
    assert(ledger.detailIcon.texture:find(icons[relation], 1, true))
    assert(row.name.anchor[2] + row.name:GetWidth() < row.relationIcon.anchor[2])
    assert(row.identity.anchor[3] + row.identity:GetHeight() <= row.relation.anchor[3],
        "identity and relationship occupy separate lines")
    assert(row.identity.anchor[2] + row.identity:GetWidth() <= row:GetWidth())
    assert(row.relation.anchor[2] + row.relation:GetWidth() < row:GetWidth())
    assert(contrast(row.bg.color, row.name.color) >= 4.5 and contrast(row.bg.color, row.relation.color) >= 4.5,
        "selected index labels need readable light ink on leather")
end
for _, tab in ipairs({ "history", "notes", "summary" }) do
    click(ledger.detailTabs[tab])
    assert(ledger.detailTab == tab and ledger.counters:IsShown() == (tab == "summary"))
    for key, control in pairs(ledger.detailTabs) do assert(control.selection:IsShown() == (key == tab)) end
    if tab == "summary" then assert(ledger.detailText:GetText():find("Dernière rencontre",1,true))
    elseif tab == "history" then assert(ledger.historyPage:IsShown() and ledger.historyPage.rows[1].event)
    else assert(GrudgeLedgerNote:IsShown() and GrudgeLedgerNote.edit:GetText() ~= "") end
    assert(ledger.detailBody:GetHeight() >= ledger.detailScroll:GetHeight())
end
ledger.search:SetText("No matching person")
assert(ledger.actions[1].enabled, "typing does not commit search before validation")
ledger.search.scripts.OnEnterPressed(ledger.search)
assert(ledger.empty:IsShown())
for _, control in pairs(ledger.reactions) do assert(not control.selection:IsShown() and not control.enabled) end
local disabled = ledger.actions[1]
local tint = disabled.skin.vertexColor[1]
-- Median parchment face from JournalButtons.tga, tinted as it is in game.
assert(tint < 1 and contrast(disabled.caption.color, {234/255*tint, 198/255*tint, 147/255*tint}) >= 4.5,
    "disabled actions stay legible on the dimmed parchment")
click(ledger.reset)
assert(not ledger.empty:IsShown())
GL.ShowLedger(identity.key)
UIParent:SetSize(800, 600) ledger:Hide() ledger:Show()
assert(ledger:GetWidth() * ledger.scale <= 776 and ledger:GetHeight() * ledger.scale <= 576)
UIParent:SetSize(1920, 1080)
GL.EditNote(identity)
assert(GrudgeLedgerNote.edit.justifyV == "TOP" and ledger.search.justifyV == "MIDDLE")
readable(GrudgeLedgerNote.edit.color)
for _, region in ipairs(mock.frames) do
    if type(region.requestedTexture) == "string" and region.requestedTexture:find("JournalPaper", 1, true) then solidFallback(region) end
end
click(ledger.settingsButton)
local settings = GrudgeLedgerSettings
assert(settings:IsShown() and not ledger:IsShown())
for _, category in ipairs({ "appearance", "alerts", "relations", "shortcuts", "data" }) do
    click(settings.tabs[category])
    assert(settings.category == category)
    for key, page in pairs(settings.pages) do
        assert(page:IsShown() == (key == category) and settings.tabs[key].selection:IsShown() == (key == category))
    end
end
for key, control in pairs(settings.checks) do
    local old = GL.Settings()[key]
    control:SetChecked(not old) click(control)
    assert(GL.Settings()[key] == not old, "settings callback persists its checkbox")
    control:SetChecked(old) click(control)
end
click(settings.navigation.ledger)
assert(ledger:IsShown() and not settings:IsShown())
GL.ShowGuide()
assert(GrudgeLedgerGuide:IsShown() and GL.Settings().guideSeen)
SlashCmdList.GRUDGELEDGER("debug")
assert(GrudgeLedgerDiagnostic.edit.justifyV == "TOP")
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
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
GrudgeLedger.InitDB()
local modernButton = GrudgeLedgerMinimapButton
assert(modernButton:GetWidth() == 31 and modernButton.icon:GetWidth() == 20)
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
assert(missingPaperCount >= 1, "the note editor keeps its solid paper backing if its texture cannot load")
assert(not GrudgeLedgerWindow.bookSurface.texture and GrudgeLedgerWindow.paper.color and GrudgeLedgerWindow.indexPaper.color)
checkPage(GrudgeLedgerWindow)
assert(#GrudgeLedger.errors == 0)
print("PASS visual UI: native minimap frame with small borderless artwork (legacy/compartment), shape/size/scale-aware rim, unclipped parent, one drag commit, resize/visibility, navigation, tabs, explicit search, readable relationship states, settings and texture fallbacks.")
