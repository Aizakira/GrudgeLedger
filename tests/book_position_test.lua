assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local methods = getmetatable(UIParent).__index
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if relative == nil then relative = self.parent end
    self.point = { point, relative, relativePoint or point, x or 0, y or 0 }
end
local moving
function methods:StartMoving() assert(not moving); moving = self end
function methods:StopMovingOrSizing() assert(moving == self); moving = nil end
local function center(frame)
    if frame == UIParent then return 0, 0 end
    local p = assert(frame.point)
    assert(p[1] == "CENTER" and p[3] == "CENTER")
    local x, y = center(p[2])
    return x + p[4], y + p[5]
end
local function at(frame, x, y)
    local actualX, actualY = center(frame)
    assert(frame:IsVisible() and actualX == x and actualY == y, tostring(frame.name) .. " lost the book position")
end
local function click(button) button:GetScript("OnClick")(button, "LeftButton") end
local function drag(frame, x, y)
    frame:GetScript("OnDragStart")(frame)
    moving:SetPoint("CENTER", UIParent, "CENTER", x, y)
    frame:GetScript("OnDragStop")(frame)
    at(frame, x, y)
end
for _, file in ipairs({"Core", "UITheme", "UI", "Transport", "Bounties", "DossierEquipment", "DossierPanels", "PlayerDossier", "BountyUI"}) do
    assert(loadfile(TEST_ROOT .. "/" .. file .. ".lua"))("GrudgeLedger")
end
local GL = GrudgeLedger
GL.InitDB()
GL.SetSetting("guideSeen", true)
GL.ShowLedger()
local ledger = GrudgeLedgerWindow
-- Same window as the other pages; the 720 painting overflows it by 10 units above and below.
assert(ledger:GetWidth() == 960 and ledger:GetHeight() == 700)
assert(ledger.bookSurface:GetWidth() == 960 and ledger.bookSurface:GetHeight() == 720)
assert(ledger.bookSurface.point[1] == "TOPLEFT" and ledger.bookSurface.point[#ledger.bookSurface.point] == 10,
    "the painting starts 10 units above the window")
at(ledger, 0, 0)
drag(ledger, 110, -48)
click(ledger.navigation.players)
local stats = GrudgeLedgerStatistics
assert(stats:GetHeight() == 700, "opening the reference journal must not stretch another page")
at(stats, 110, -48)
click(stats.sections[4])
at(stats, 110, -48)
click(stats.navigation.bounties)
local primes = GrudgeLedgerBounties
at(primes, 110, -48)
drag(primes, -40, 32)
-- The third tab is the guild's book (0.55.0); without Relations.lua it falls back to the rankings.
click(primes.navigation.guild)
at(stats, -40, 32)
GL.ShowJournal("summary")
at(GrudgeLedgerJournal, -40, 32)
click(GrudgeLedgerJournal.navigation.ledger)
at(ledger, -40, 32)
GL.ShowGuide()
drag(GrudgeLedgerGuide, 60, 20)
GrudgeLedgerGuide:Hide()
at(ledger, 60, 20)
GL.ShowGuilds()
drag(GrudgeLedgerGuilds, -10, -10)
at(ledger, 60, 20)
ledger:Hide()
GL.OpenBounties()
at(primes, 60, 20)
primes:GetScript("OnDragStart")(primes)
assert(GL.OpenPlayerDossier("Player-1-target", nil, "Test"))
assert(not moving, "changing pages during a drag must release the book")
at(GrudgeLedgerPlayerDossier, 60, 20)
UIParent:SetSize(800, 600)
UIParent:GetScript("OnSizeChanged")(UIParent, 800, 600)
local anchor = GrudgeLedgerPlayerDossier.parent
assert(anchor:GetWidth() * anchor:GetScale() <= 776 and anchor:GetHeight() * anchor:GetScale() <= 576)
assert(anchor:GetHeight() == 720, "screen fitting includes the ribbon footer even while another page is open")
assert(anchor.clamped, "dragging must clamp the complete painting and its ribbon footer")
GL.ShowLedger()
assert(ledger.parent == anchor)
assert(anchor:GetHeight() == 720 and anchor:GetHeight() * anchor:GetScale() <= 576,
    "small screens fit the whole journal, including the suspended bookmarks")
at(ledger, 60, 20)
local ledgerScale = anchor:GetScale()
GL.ShowGuide()
assert(GrudgeLedgerGuide:IsShown() and ledger:IsShown(), "the guide overlays the journal")
GrudgeLedgerGuide:Hide()
assert(anchor:GetScale() == ledgerScale and anchor:GetHeight() == 720,
    "closing a shorter overlay must keep the underlying journal fitted to the screen")
at(ledger, 60, 20)
print("PASS shared book position across tabs, overlay, reopen, interrupted drag, resize and independent dialog")
