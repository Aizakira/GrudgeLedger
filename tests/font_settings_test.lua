local mock = dofile(TEST_WORK .. "/tests/wow_mock.lua")
local methods = getmetatable(UIParent).__index
function methods:SetFontObject(name)
    self.fontObject = name
    self.font = {(name:find("Fancy") or name == "QuestFont_Large") and "Morpheus" or "Classic",
        tonumber(name:match("Fancy(%d+)Font")) or (name == "QuestFont_Large" and 15 or 12), ""}
    self.color, self.spacing = {1, 1, 1, 1}, 0
end
function methods:GetFont() return unpack(self.font or {"Classic", 12, ""}) end
function methods:GetTextColor() return unpack(self.color or {1, 1, 1, 1}) end
function methods:SetSpacing(value) self.spacing = value end
function methods:GetSpacing() return self.spacing or 0 end
function methods:GetNumLines()
    return math.ceil(#self:GetText() / (self.fontObject == "ChatFontNormal" and 50 or 30)) + 1
end
function methods:GetStringHeight() return self:GetNumLines() * (select(2, self:GetFont()) + self:GetSpacing()) end

assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
local GL = GrudgeLedger
local fontDir = "Interface\\AddOns\\GrudgeLedger\\Media\\Fonts\\Spectral-"
assert(GL.Settings().readableFont == false, "existing grimoire presentation is the default")
GrudgeLedgerDB = {settings = {readableFont = true}} -- preference saved by an earlier session
GL.InitDB()
local record = GL.SetReaction(GL.Identity("target"), "friend")
GL.AddNote(record, string.rep("Longue note lisible. ", 40))
GL.ShowLedger(record.key)
GrudgeLedgerWindow.detailTabs.notes:GetScript("OnClick")(GrudgeLedgerWindow.detailTabs.notes)
GL.EditNote(record)
local f, note = GrudgeLedgerWindow, GrudgeLedgerNote
note.edit:SetText(string.rep("Brouillon non enregistré. ", 40))
SlashCmdList.GRUDGELEDGER("settings")
local settings = GrudgeLedgerSettings
assert(settings.classic.active and f.title:GetFont() == fontDir .. "SemiBoldItalic.ttf" and note.edit.fontObject == "ChatFontNormal")
assert(select(2, f.title:GetFont()) == 34 and select(2, f.rows[1].name:GetFont()) == 16)
assert(select(2, f.detailText:GetFont()) == 15 and select(2, note.edit:GetFont()) == 15)
local draft, text, color = note.edit:GetText(), f.detailText:GetText(), {f.detailText:GetTextColor()}
local readableHeight = note.edit:GetHeight()
local function choose(value)
    local control = value and settings.classic or settings.grimoire
    control:GetScript("OnClick")(control)
    assert(GL.Settings().readableFont == value and GrudgeLedgerDB.settings.readableFont == value)
end
local setFont = methods.SetFont
function methods:SetFont(path, size, flags)
    setFont(self, path, size, flags) -- Forever's SetFont has no documented return values.
end
choose(false)
assert(f.title.fontObject == "GameFontNormalLarge" and f.detailTitle.fontObject == "GameFontNormalLarge")
assert(f.rows[1].name.fontObject == "GameFontNormalLarge" and note.edit.fontObject == "QuestFont_Large")
assert(settings.title.fontObject == "GameFontNormalLarge", "book section titles switch too")
assert(f.detailTitle:GetFont() == fontDir .. "SemiBold.ttf" and f.rows[1].name:GetFont() == fontDir .. "SemiBold.ttf")
assert(note.edit:GetFont() == fontDir .. "Regular.ttf" and f.total:GetFont() == fontDir .. "Regular.ttf")
assert(f.navigation.ledger.caption:GetFont() == fontDir .. "SemiBold.ttf")
local tab = f.navigation.ledger
assert(not tab.normalFont and not tab.highlightFont and not tab.disabledFont,
    "a native button state font would replace the themed caption on hover or disable")
tab:SetText("Journal") tab:SetEnabled(false) tab:SetEnabled(true)
assert(tab.caption:GetText() == "Journal" and tab.caption:GetFont() == fontDir .. "SemiBold.ttf")
local unavailable = f:CreateFontString()
function unavailable:SetFont(path, size, flags)
    if path:find("Spectral", 1, true) then error("Font asset unavailable") end
    setFont(self, path, size, flags)
end
GL.UITheme.journalFont(unavailable, "GameFontHighlight", 14)
assert(unavailable:GetFont() == "Classic" and select(2, unavailable:GetFont()) == 14)
assert(note.edit:GetHeight() > readableHeight, "wrapped text is measured again immediately")
f.detailScroll:SetVerticalScroll(100000)
note.scroll:SetVerticalScroll(100000)
choose(true)
assert(f.detailScroll:GetVerticalScroll() <= math.max(0, f.detailBody:GetHeight() - f.detailScroll:GetHeight()))
assert(note.scroll:GetVerticalScroll() <= math.max(0, note.edit:GetHeight() - note.scroll:GetHeight()))
assert(f.detailText:GetText() == text and note.edit:GetText() == draft, "switching fonts must not lose text or drafts")
assert(f.detailText.color[1] == color[1] and f.detailText.color[2] == color[2] and f.detailText:GetSpacing() == 4,
    "paper ink and line spacing survive font inheritance changes")
assert(f.rows[1].name.color[2] > f.rows[1].name.color[1], "friend name keeps its green ink")
assert(#record.notes == 1 and record.reputation == 1 and not next(mock.cvars))
note:Hide()
choose(false)
GL.EditNote(record)
assert(note.edit:GetText() == draft and note.edit.fontObject == "QuestFont_Large", "hidden editors update without discarding drafts")
choose(true)
GL.ShowGuilds(record)
assert(GrudgeLedgerGuilds.title.fontObject == "ChatFontNormal", "later-created windows use the saved choice")
assert(not GL.SetSetting("readableFont", "true"), "setting validates its type")
GL.InitDB()
assert(GL.Settings().readableFont and settings.classic.active, "choice survives database reload")
GL.SetSetting("readingScale", 1.25)
assert(select(2, f.detailText:GetFont()) == 18.75 and select(2, f.rows[1].name:GetFont()) == 20,
    "reading scale applies to content and index names")
assert(note.edit:GetText() == draft, "resizing text preserves an unsaved draft")
GL.SetSetting("compactMode", true)
assert(f.detailText:GetSpacing() == 2)
GL.SetSetting("compactMode", false)
assert(f.detailText:GetSpacing() == 4)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS font settings: persisted choice, immediate reversible native fonts, sizes/colors/spacing, scroll clamping, drafts, hidden and newly created windows")
