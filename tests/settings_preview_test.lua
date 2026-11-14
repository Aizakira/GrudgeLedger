-- Real controls and adjacent live PvP alert, with a synthetic identity.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local now, sounds, messages = 2000, {}, {}
time, GetServerTime = function() return now end, function() return now end
SOUNDKIT = { IG_QUEST_LOG_OPEN = 7, RAID_WARNING = 12 }
PlaySound = function(id) sounds[#sounds+1] = id end
SendChatMessage = function(message) messages[#messages+1] = message end
for _, module in ipairs({"Core", "Display", "UITheme", "UI"}) do
    assert(loadfile(TEST_ROOT .. "/" .. module .. ".lua"))("GrudgeLedger")
end
local GL = GrudgeLedger
GL.InitDB()
local function click(button) button:GetScript("OnClick")(button, "LeftButton") end
SlashCmdList.GRUDGELEDGER("settings")
local f = GrudgeLedgerSettings
local size, delay = f.sliders.iconSize, f.sliders.alertCooldown
local changes = 0
GL.On("SETTINGS", function() changes = changes + 1 end)
size:SetValue(26) size:SetValue(40)
assert(f.previewRows.friend.icon:GetWidth() == 40 and GL.Settings().iconSize == 20 and changes == 0,
    "drag previews locally without refreshing the journal and plates on every movement")
size:GetScript("OnMouseUp")(size)
assert(GL.Settings().iconSize == 40 and changes == 1)
local toggle = f.checks.markers
toggle:SetChecked(false) click(toggle)
assert(not f.previewRows.enemy.icon:IsShown())
toggle:SetChecked(true) click(toggle)
assert(f.previewRows.enemy.icon:IsShown() and f.previewRows.enemy.icon:GetWidth() == 40)
click(f.tabs.alerts)
delay:SetValue(15) delay:GetScript("OnMouseUp")(delay)
assert(GL.Settings().alertCooldown == 15)
click(f.testEnemy)
local preview = assert(GrudgeLedgerAlertPreview)
assert(preview:IsShown() and sounds[1] == 12 and not next(GL.db.players) and not GrudgeLedgerNearbyAlert)
click(f.testFriend)
assert(preview:IsShown() and sounds[2] == 7 and preview.name:GetText() == "Célestine Longuebrise")
GL.SetSetting("sounds", false)
click(f.testFriend)
assert(#sounds == 2 and not next(GL.db.detectionLog or {}) and not next(messages),
    "previews emit no diagnostic, ordinary chat or party warning")
local enemy = GL.SetReaction(GL.Identity("target"), "enemy")
GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
local real = assert(GrudgeLedgerNearbyAlert)
assert(real:IsShown() and real.key == enemy.key and not preview:IsShown(),
    "a real alert always replaces the preview")
click(f.testFriend)
assert(real:IsShown() and not preview:IsShown() and real.key == enemy.key)
real:Hide()
click(f.testEnemy)
now = now + 7
GrudgeLedgerDisplayEvents:GetScript("OnUpdate")(GrudgeLedgerDisplayEvents, .6)
assert(not preview:IsShown() and not next(messages))
local log = GL.db.detectionLog
assert(log and #log > 0)
click(f.tabs.data) click(f.clearAction)
assert(GL.db.detectionLog == log)
click(f.tabs.alerts) click(f.tabs.data)
assert(not f.clearAction.armed)
click(f.clearAction) click(f.clearAction)
assert(not next(GL.db.detectionLog) and GL.Get(enemy.key) == enemy)
click(f.experimental)
assert(f.experimentalText:IsShown())
GL.ShowLedger()
assert(GL.Settings().guideSeen and GrudgeLedgerGuide:IsShown())
click(GrudgeLedgerGuide.openJournal)
assert(GrudgeLedgerWindow:IsShown() and not GrudgeLedgerGuide:IsShown())
SlashCmdList.GRUDGELEDGER("settings") click(f.tabs.data) click(f.guide)
assert(GrudgeLedgerGuide:IsShown())
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS settings: live marker size, one saved update per drag, local alert samples, live priority, expiry, sound preference, trace clearing and returning to the guide")
