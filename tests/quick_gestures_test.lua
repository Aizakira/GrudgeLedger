local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local methods = getmetatable(UIParent).__index
local control, moving, sent, now = false, false, 0, 1000
IsControlKeyDown = function() return control end
GetTimePreciseSec = function() return now end
GetServerTime = function() return now end
function methods:StartMoving() moving = true end
function methods:StopMovingOrSizing() moving = false end
function methods:GetLeft() return 200 end
function methods:GetBottom() return 300 end
C_ChatInfo.PerformEmote = function(token, target)
    assert((token == "KISS" or token == "SPIT") and target == "target") sent = sent + 1
end
hooksecurefunc = function(owner, key, callback)
    if type(owner) == "string" then callback, key, owner = key, owner, _G end
    local original = owner[key]
    owner[key] = function(...) original(...) callback(...) end
end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/Social.lua"))()
assert(loadfile(TEST_ROOT .. "/QuickGestures.lua"))()
local GL = GrudgeLedger
GL.InitDB()
local bar = GrudgeLedgerGestures
assert(bar and bar:IsShown() and sent == 0)
local kiss, spit = bar.buttons.KISS, bar.buttons.SPIT
local function click(button) button.scripts.OnClick(button) end
click(kiss)
local r = GL.Get(GL.Identity("target"))
assert(r.reputation == 1 and sent == 1, "one explicit click, one native emote, one opinion")
click(kiss) assert(r.reputation == 1 and sent == 2, "post-hook/fallback and repeated click deduplicated")
click(spit) assert(r.reputation == 0)
now = now + 30 click(spit) assert(r.reputation == -1)
kiss.scripts.OnDragStart(kiss) assert(not moving, "unmodified click cannot move toolbar")
control = true kiss.scripts.OnDragStart(kiss) assert(moving)
kiss.scripts.OnDragStop(kiss) assert(not moving and GL.db.gesturePosition.x > 0)
control = false local before = sent click(kiss)
assert(sent == before, "releasing Ctrl after a drag must not send a gesture")
GL.SetSetting("quickGestures", false) assert(not bar:IsShown())
GL.SetSetting("quickGestures", true) assert(bar:IsShown())
GL.InitDB() assert(GL.db.gesturePosition.y > 0 and GrudgeLedgerGestures == bar)
GL.ResetGesturePosition() assert(GL.db.gesturePosition == nil)
mock.units.target = mock.units.npc click(kiss) assert(sent == before)
mock.units.target = mock.units.player click(kiss) assert(sent == before)
mock.units.target = nil click(spit) assert(sent == before)
mock.units.target = { name = "Other", surname = "Player", guid = "Player-1-other" }
GL.SetSetting("socialTracking", false) click(kiss) assert(sent == before)
GL.SetSetting("socialTracking", true)
C_ChatInfo.PerformEmote = function() error("blocked") end
click(spit) assert(not GL.Get(GL.Identity("target")), "failed action cannot add an opinion")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS quick gestures: native click actions, existing score/cooldown, no unsolicited emotes, Ctrl drag/save/reset, no click after drag, NPC/self/empty guards, opt-out and rejected API")
