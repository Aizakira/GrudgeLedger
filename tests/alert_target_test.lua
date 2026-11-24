-- Owner, 24/11: clicking an alert targets the player, through a secure button, out of combat. A known
-- enemy then gets our reticle over its name (never a raid mark). In combat the game locks the button: the alert opens the sheet as before.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local methods = getmetatable(UIParent).__index
function methods:SetAttribute(key, value) self.attributes = self.attributes or {} self.attributes[key] = value end
function methods:GetAttribute(key) return self.attributes and self.attributes[key] end
function methods:HookScript(event, fn)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end fn(...) end
end
local lockdown, marked = false, nil
InCombatLockdown = function() return lockdown end
SetRaidTarget = function(unit, index) marked = { unit, index } end
IsInGroup = function() return false end
IsShiftKeyDown = function() return false end
GrudgeLedgerDB = nil
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/Display.lua"))()
local GL = GrudgeLedger
GL.InitDB()
local enemy = GL.SetReaction(GL.Identity("target"), "enemy")
GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
local alert = assert(GrudgeLedgerNearbyAlert)
local button = assert(GrudgeLedgerAlertTarget, "the secure targeting button exists")
assert(alert:IsShown() and button:IsShown(), "out of combat the alert can target")
assert(button.attributes.type1 == "macro" and button.attributes.macrotext1 == "/targetexact " .. enemy.fullName,
    tostring(button.attributes.macrotext1))
assert(alert.hint:GetText():find("cibler", 1, true), "the hint says a click targets")
-- The click targets (the secure action is the game's), then the prey's reticle and the alert closes.
local prey
local mark = GL.Display.MarkPrey
GL.Display.MarkPrey = function(guid) prey = guid end
button.scripts.PostClick(button, "LeftButton")
GL.Display.MarkPrey = mark
assert(prey == enemy.guid and not marked, "a known enemy gets our reticle, never a raid mark")
assert(not alert:IsShown() and not button:IsShown(), "the alert and its button close")

-- A second enemy, then combat starts: the button goes away before the lock, the plain hint comes back.
mock.units.target = { name = "Second", surname = "Ennemi", guid = "Player-1-second" }
GL.SetReaction(GL.Identity("target"), "enemy")
GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(alert:IsShown() and button:IsShown() and button.attributes.macrotext1 == "/targetexact Second Ennemi")
for _, f in ipairs(mock.frames) do
    if f.events and f.events.PLAYER_REGEN_DISABLED and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_REGEN_DISABLED") end
end
lockdown = true
assert(not button:IsShown(), "no secure button stays armed in combat")
assert(not alert.hint:GetText():find("cibler", 1, true), "in combat the alert says its plain click")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS alert target: a click targets the player out of combat, reticle on an enemy, plain click in combat")
