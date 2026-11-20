-- Owner report (0.33.0): 37 minutes after a death, the killer's sheet had no data at all. The
-- reading was tried once, at the first blow, and the killer had no unit at that instant. A fight
-- now keeps trying once a second: statistics as soon as a unit exists, inspection once in range.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local now, requests, timers = 1000, 0, {}
GetServerTime = function() return now end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function elapse() -- every waiting timer fires once
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end
local guid = "Player-9-00CD"
mock.units.target = nil
UnitIsVisible = UnitExists
UnitHealthMax = function() return 2400 end
UnitPowerType = function() return 0, "MANA" end
UnitPowerMax = function() return 3100 end
local inRange = false
CanInspect = function() return inRange end
NotifyInspect = function(unit) assert(UnitGUID(unit) == guid) requests = requests + 1 end
-- The game describes a player from the GUID alone; a value it hides is left out without an error.
GetPlayerInfoByGUID = function(id)
    if id == guid then return "Voleur", "ROGUE", "Mort-vivant", "Scourge", 2, "Unseen", "" end
    return mock.secret, mock.secret, mock.secret, mock.secret, mock.secret
end
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
-- Never targeted, yet his sheet already says who he is: class, race, sex and faction come from the GUID.
assert(record.class == "ROGUE" and record.className == "Voleur" and record.race == "Scourge", tostring(record.class))
assert(record.raceName == "Mort-vivant" and record.sex == 2 and record.faction == "Horde")
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

-- A reading hidden by the game in combat is tried again two seconds later, not a minute later.
local second = "Player-9-00CE"
mock.units.target = { guid = second, name = "Hidden", surname = "Values", isPlayer = true }
elapse() -- the first request never got an answer: it is given up
local hidden = true
UnitHealthMax = function() return hidden and mock.secret or 3300 end
UnitPowerMax = function() return hidden and mock.secret or 2100 end
NotifyInspect = function() requests = requests + 1 end
inRange = false
local other = GL.RecordAggression(GL.IdentityFromName("Hidden", "Values", second), "confirmed", "Combat log", "watch-b")
GL.StepInspectionWatch()
assert(not other.inspection or not other.inspection.stats, "hidden values are not stored")
assert(other.class == nil and other.faction == nil, "a hidden description is left out")
hidden = false
now = now + 2
GL.StepInspectionWatch()
assert(other.inspection and other.inspection.stats.HEALTH == 3300, "readable two seconds later")

-- Forever accepts an inspection when the game allows it or when the player is close: one is enough.
local before = requests
CheckInteractDistance = function() return true end
now = now + 5
GL.StepInspectionWatch()
assert(requests == before + 1, "close enough is enough, even when CanInspect says no")
CheckInteractDistance = function() return false end
now = now + 40
elapse() -- three seconds without an answer: given up, and nothing leaves while neither rule holds
assert(requests == before + 1, "neither allowed nor close: no request")
inRange = true
now = now + 2
GL.StepInspectionWatch()
assert(requests == before + 2, "allowed by the game is enough, even beyond short range")
CheckInteractDistance = nil
now = now + 1
mock.Fire("INSPECT_READY", second)

-- /gl sonde reports what the client lets an addon read about the target, in plain lines, then what
-- the watch managed on the last opponents.
local shown = #mock.messages
GetInventoryItemID = function(_, slot) return slot <= 3 and 100 + slot or nil end
assert(GL.ReadingProbe() == true)
local report = table.concat(mock.messages, "\n", shown + 1)
assert(report:find("Sonde de lecture · cible amicale · vous êtes hors combat", 1, true), report)
assert(report:find("Vie maximale : lisible (3300) · niveau : lisible (42)", 1, true), report)
assert(report:find("Avant inspection : 3 pièces reconnues, 0 liens complets", 1, true), report)
assert(report:find("Le jeu autorise l’inspection : oui · à courte portée : sans réponse", 1, true), report)
assert(report:find("Suivi de Hidden Values : repéré après 0 s (target) · statistiques après 2 s · inspection demandée après 7 s"
    .. " · réponse après 50 s · 0 pièces · talents absents", 1, true), report)
assert(report:find("Suivi de Unseen Killer : repéré après 10 s (target) · statistiques après 10 s · inspection demandée après 12 s"
    .. " · sans réponse · 0 pièces · talents absents", 1, true), report)
assert(GrudgeLedgerProbe:IsShown() and GrudgeLedgerProbe.model, "the kept-model window opens")
-- The probe's own inspection answer is timed, and a value the game hides is named as such.
shown = #mock.messages
hidden = true
mock.Fire("INSPECT_READY", second)
assert(mock.messages[shown + 1]:find("Inspection : réponse en 0.0 s · 0 pièces · talents absents", 1, true), mock.messages[shown + 1])
GL.ReadingProbe()
report = table.concat(mock.messages, "\n", shown + 2)
assert(report:find("Vie maximale : caché par le jeu · niveau : lisible (42)", 1, true), report)
mock.units.target = nil
shown = #mock.messages
assert(GL.ReadingProbe() == false and mock.messages[shown + 1]:find("ciblez un autre joueur", 1, true))
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS inspection watch: a fight keeps trying once a second, statistics as soon as a unit exists, "
    .. "inspection once in range, expiry after three minutes, hidden values retried, either rule, reading probe")
