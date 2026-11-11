local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local methods = getmetatable(UIParent).__index
local control, moving, sent, now = false, false, 0, 1000
local restricted, afterPerform
local recipients = {}
IsControlKeyDown = function() return control end
GetTimePreciseSec = function() return now end
GetServerTime = function() return now end
function methods:StartMoving() moving = true end
function methods:StopMovingOrSizing() moving = false end
function methods:GetLeft() return 200 end
function methods:GetBottom() return 300 end
C_ChatInfo.PerformEmote = function(token, target)
    assert(token == "KISS" or token == "SPIT")
    sent = sent + 1
    -- Native targetName semantics: an empty argument selects the actual unit;
    -- any nonempty string is a character name, never a unit token.
    local unit = mock.units.target
    local named = unit and unit.name .. " " .. (unit.surname or "")
    if not restricted and unit and (target == "" or target == named) then
        recipients[#recipients + 1] = { token = token, guid = unit.guid, faction = UnitFactionGroup("target") }
    end
    if afterPerform then afterPerform() end
    return restricted
end
hooksecurefunc = function(owner, key, callback)
    if type(owner) == "string" then callback, key, owner = key, owner, _G end
    local original = owner[key]
    owner[key] = function(...) local result = original(...) callback(...) return result end
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
assert(recipients[1].guid == mock.units.target.guid and recipients[1].token == "KISS", "kiss addresses the selected player's full identity")
click(kiss) assert(r.reputation == 1 and sent == 2, "post-hook/fallback and repeated click deduplicated")
click(spit) assert(r.reputation == 0)
assert(recipients[3].guid == r.guid and recipients[3].token == "SPIT", "spit request also uses the selected player, though the engine controls its text")
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
restricted = true
click(spit) assert(not GL.Get(GL.Identity("target")), "native restricted return cannot add an opinion, even through post-hooks")
restricted = mock.secret
click(kiss) assert(not GL.Get(GL.Identity("target")), "unreadable result cannot be claimed as accepted")
restricted = false
UnitFactionGroup = function(unit) return mock.units[unit] and mock.units[unit].faction or "Alliance" end
for _, faction in ipairs({ "Horde", "Alliance" }) do
    mock.units.target = { name = "Same", surname = faction, guid = "Player-1-" .. faction, faction = faction }
    click(kiss) click(spit)
    local record = GL.Get(GL.Identity("target"))
    assert(record.reputation == 0 and #record.history == 2)
    assert(recipients[#recipients].guid == record.guid and recipients[#recipients - 1].guid == record.guid)
    assert(recipients[#recipients].faction == faction, "neither faction is filtered out of native routing")
end
local clicked = { name = "Original", surname = "Target", guid = "Player-1-original" }
mock.units.target = clicked
local clickedIdentity = GL.Identity("target")
afterPerform = function() mock.units.target = { name = "Changed", surname = "Target", guid = "Player-1-changed" } end
click(kiss)
assert(GL.Get(clickedIdentity).reputation == 1 and not GL.Get(GL.Identity("target")), "a callback cannot redirect the recorded gesture")
afterPerform = nil
C_ChatInfo.PerformEmote = function() error("blocked") end
click(spit) assert(not GL.Get(GL.Identity("target")), "failed call cannot add an opinion")
C_ChatInfo.PerformEmote = nil
DoEmote = function(token, target) assert(token == "SPIT" and target == "") return true end
click(spit) assert(GL.Get(GL.Identity("target")).reputation == -1, "legacy API return is not the modern restricted flag")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS quick gestures: selected-player routing for both factions and both native gestures, rejection/post-hook safety, captured identity, legacy API, cooldown, Ctrl drag and target/opt-out guards; recipient display still requires the real client")
