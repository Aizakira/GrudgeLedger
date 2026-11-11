-- Real Core + Display: absence is refreshed by sightings, never by editing a
-- note or retaining a remote target/group member. No wall-clock sleeps needed.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local units, now, shown, raid = mock.units, 10000, 0, false
units.target = nil
function GetServerTime() return now end
function UnitIsVisible(unit) return units[unit] and units[unit].visible ~= false or false end
function GetNumGroupMembers() return raid and (units.raid2 and 2 or 0) or (units.party1 and 2 or 0) end
function IsInRaid() return raid end
function UnitInParty(unit) return not raid and UnitIsUnit(unit, "party1") end
function UnitInRaid(unit) return raid and UnitIsUnit(unit, "raid2") and 2 or nil end
local methods = getmetatable(UIParent).__index
function methods:SetVertexColor(...) self.vertex = { ... } end
function methods:GetFrameLevel() return 1 end
function methods:SetFrameLevel() end
function methods:SetIgnoreParentAlpha() end
function methods:SetIgnoreParentScale() end
function methods:SetTexture(value) self.texture = value end
function methods:AddLine() end
local originalShow = methods.Show
function methods:Show()
    if self == GrudgeLedgerNearbyAlert then shown = shown + 1 end
    originalShow(self)
end
local plates = {}
C_NamePlate = {
    GetNamePlateForUnit = function(unit) return plates[unit] end,
    GetNamePlates = function() local result = {} for _, plate in pairs(plates) do result[#result + 1] = plate end return result end,
}
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/Display.lua"))()
local GL, D = GrudgeLedger, GrudgeLedger.Display
GL.InitDB()
local function friend(name)
    local person = { name = name, surname = "Example", guid = "Player-1-" .. name }
    local id = GL.IdentityFromName(person.name, person.surname, person.guid)
    GL.SetReaction(id, "friend")
    return person, GL.Get(id)
end
local function see(person)
    units.target = person
    person.visible = true
    D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
end
local function tick(seconds)
    now = now + seconds
    GrudgeLedgerDisplayEvents.scripts.OnUpdate(GrudgeLedgerDisplayEvents, 1)
end
local person, record = friend("Companion")
see(person)
assert(shown == 1, "first encounter alerts once")
local expires = GrudgeLedgerNearbyAlert.expires
for i = 1, 300 do tick(60) end
assert(shown == 1 and GrudgeLedgerNearbyAlert.expires == expires,
    "five hours together must neither repeat nor extend the popup")
units.target = nil
for i = 1, 30 do
    now = now + 600
    see(person)
    units.target = nil
end
assert(shown == 1, "meeting every ten minutes for five hours is one continuous encounter")
now = now + 1800
see(person)
assert(shown == 2, "a friend returning after thirty minutes alerts again")
person.visible = false -- still selected, but physically gone
local lastPhysical = record.friendPresence[units.player.guid]
tick(1800)
assert(record.friendPresence[units.player.guid] == lastPhysical, "a remote selected unit does not renew presence")
see(person)
assert(shown == 3)

-- Plate and mouseover observation work without selecting the friend.
local plate = CreateFrame("Frame", "PresencePlate", UIParent)
plate.namePlateUnitToken = "nameplate1"
plate.UnitFrame = CreateFrame("Frame", nil, plate)
plate.UnitFrame.name = plate.UnitFrame:CreateFontString()
units.target, units.nameplate1, plates.nameplate1 = nil, person, plate
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
for i = 1, 30 do tick(60) end
D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
units.nameplate1, plates.nameplate1 = nil, nil
see(person)
assert(shown == 3, "continuous nameplates renew presence without repeating")
units.target, units.mouseover = nil, person
for i = 1, 30 do tick(60) end
see(person)
units.mouseover = nil
assert(shown == 3, "continuous visible mouseover also renews presence")

-- Group membership suppresses and closes friend alerts, even with history off.
GL.SetSetting("groupTracking", false)
units.party1 = person
D.OnEvent(nil, "GROUP_ROSTER_UPDATE")
assert(not GrudgeLedgerNearbyAlert:IsShown())
person.visible = false
tick(1800)
see(person)
assert(shown == 3, "no proximity alert for a current party member")
units.target = nil
for i = 1, 30 do tick(60) end
assert(record.friendPresence[units.player.guid] == now, "a physically visible party-only unit renews presence")
units.party1 = nil
D.OnEvent(nil, "GROUP_ROSTER_UPDATE")
see(person)
assert(shown == 3, "leaving the group does not rearm a physically present friend")
raid, units.raid1, units.raid2 = true, units.player, person
person.visible = false
tick(1800)
see(person)
assert(shown == 3, "raid friends are suppressed too")
units.target = nil
for i = 1, 30 do tick(60) end
assert(record.friendPresence[units.player.guid] == now, "a physically visible raid-only unit renews presence")
person.visible = false
lastPhysical = record.friendPresence[units.player.guid]
tick(1800)
assert(record.friendPresence[units.player.guid] == lastPhysical, "a remote roster entry is not physical presence")
raid, units.raid1, units.raid2 = false, nil, nil
D.OnEvent(nil, "GROUP_ROSTER_UPDATE")
see(person)
assert(shown == 4, "a former groupmate can return after a genuine absence")
units.party1 = person
D.OnEvent(nil, "GROUP_ROSTER_UPDATE")
assert(not GrudgeLedgerNearbyAlert:IsShown(), "joining the group closes an already open friend popup")
units.party1 = nil

-- Disabled alerts still observe presence; unrelated edits never do.
units.target = nil
local muted, mutedRecord = friend("Muted")
GL.SetSetting("friendAlerts", false)
see(muted)
for i = 1, 30 do tick(60) end
GL.SetSetting("friendAlerts", true)
see(muted)
assert(shown == 4, "reenabling alerts must not announce a companion already observed")
units.target = nil
now = now + 601
GL.AddNote(mutedRecord, "An edited note is not a sighting")
GL.SetSetting("alertCooldown", 99999)
see(muted)
assert(shown == 5, "friend absence is independent of the enemy cooldown and note timestamps")

-- Persisted per-character presence survives reload and world transitions.
D.OnEvent(nil, "PLAYER_ENTERING_WORLD")
see(muted)
assert(shown == 5)
GrudgeLedgerCoreEvents, GrudgeLedgerDisplayEvents, GrudgeLedgerNearbyAlert = nil, nil, nil
-- Core's event frame is unnamed; retain only the saved database when reloading.
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/Display.lua"))()
GL, D = GrudgeLedger, GrudgeLedger.Display
GL.InitDB()
see(muted)
assert(shown == 5, "reload must not repeat a recent encounter")
units.player.guid = "Player-1-other-character"
see(muted)
assert(shown == 6, "another character has its own encounter clock")

-- Merging a provisional name record into a known GUID keeps the newest trace.
units.target = nil
local provisional = GL.Remember(GL.IdentityFromName("Merged", "Friend"))
provisional.friendPresence = { [units.player.guid] = now, older = now - 20, corrupt = "invalid" }
local known = GL.Remember(GL.IdentityFromName("Merged", nil, "Player-1-merged"))
known.friendPresence = { [units.player.guid] = now - 10, older = now + 10 }
local merged = GL.Remember(GL.IdentityFromName("Merged", "Friend", "Player-1-merged"))
assert(merged.friendPresence[units.player.guid] == now and merged.friendPresence.older == now + 10)
assert(merged.friendPresence.corrupt == nil)

-- A removed plate may disappear from the API before its REMOVED event arrives.
units.nameplate7, plates.nameplate7 = person, plate
plate.namePlateUnitToken = "nameplate7"
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate7")
record = GL.Get(GL.Identity("nameplate7"))
local before = shown
lastPhysical = record.friendPresence[units.player.guid]
units.nameplate7, plates.nameplate7 = nil, nil
now = now + 1800
D.Refresh(record)
assert(shown == before and record.friendPresence[units.player.guid] == lastPhysical,
    "a stale cached plate identity must not announce or renew an absent friend")
D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", "nameplate7")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS friend presence: five-hour sessions, exact ten-minute recrossings, thirty-minute absence, plates/target/mouseover, party/raid, hidden targets, toggles, reload, character isolation and identity merge")
