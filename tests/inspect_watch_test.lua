-- Owner report (0.33.0): 37 minutes after a death, the killer's sheet had no data at all. The
-- reading was tried once, at the first blow, and the killer had no unit at that instant. A fight
-- now keeps trying once a second: statistics as soon as a unit exists, inspection once in range.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local now, requests = 1000, 0
GetServerTime = function() return now end
C_Timer = { After = function() end }
local guid = "Player-9-00CD"
mock.units.target = nil
UnitIsVisible = UnitExists
UnitHealthMax = function() return 2400 end
UnitPowerType = function() return 0, "MANA" end
UnitPowerMax = function() return 3100 end
local inRange = false
CanInspect = function() return inRange end
NotifyInspect = function(unit) assert(UnitGUID(unit) == guid) requests = requests + 1 end
for _, name in ipairs({ "Core", "UITheme", "UI", "DossierEquipment", "DossierTalentData", "DossierTalents", "DossierInspect" }) do
    assert(loadfile(TEST_ROOT .. "/" .. name .. ".lua"))("GrudgeLedger")
end
local GL = GrudgeLedger
GL.InitDB()
GL.VisiblePortraitUnit = function(record)
    if UnitExists("target") and UnitGUID("target") == record.guid then return "target" end
end
-- The killer strikes from out of sight: no unit, nothing can be read yet.
local identity = GL.IdentityFromName("Unseen", "Killer", guid)
local record = GL.RecordAggression(identity, "confirmed", "Combat log", "watch-a")
assert(not record.inspection and requests == 0)
assert(GL.StepInspectionWatch() == 1, "the fight keeps the killer on the watch list")
-- Ten seconds later he is targeted, still too far to inspect: statistics are read at once.
now = now + 10
mock.units.target = { guid = guid, name = "Unseen", surname = "Killer", isPlayer = true }
GL.StepInspectionWatch()
assert(record.inspection and record.inspection.stats.HEALTH == 2400 and record.inspection.stats.MANA == 3100, "statistics as soon as a unit exists")
assert(requests == 0, "no inspection out of range")
-- He comes within range: the inspection leaves on the next step.
now = now + 2
inRange = true
GL.StepInspectionWatch()
assert(requests == 1, requests)
-- Three minutes after the fight the watch ends by itself.
now = now + 200
assert(GL.StepInspectionWatch() == 0, "the watch expires")
-- A player you never fought is not watched for three minutes, and battlegrounds are left alone.
assert(GL.WatchForInspection("Creature-1-wolf") == false and GL.WatchForInspection(nil) == false)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS inspection watch: a fight keeps trying once a second, statistics as soon as a unit exists, "
    .. "inspection once in range, expiry after three minutes")
