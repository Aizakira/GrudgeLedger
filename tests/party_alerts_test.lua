-- Real observation paths; no timers, sleeps or network calls in this check.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local units, now, raid, instanceType = mock.units, 10000, false, "none"
local sent, attempts, plates = {}, 0, {}
units.target = nil
units.party1 = { name = "Companion", surname = "Example", guid = "Player-1-party" }
function GetServerTime() return now end
function IsInInstance() return instanceType ~= "none", instanceType end
function IsInRaid() return raid end
function GetNumGroupMembers() return units.party1 and 2 or 0 end
function UnitInParty(unit) return UnitIsUnit(unit, "party1") end
function UnitInRaid() return nil end
function UnitIsVisible(unit) return units[unit] and units[unit].visible ~= false or false end
local function send(message, channel)
    attempts = attempts + 1
    assert(channel == "PARTY" and #message <= 255)
    assert(not message:find("[|%c{}]"), "never send links, control characters or raid-icon markup")
    sent[#sent + 1] = message
end
C_ChatInfo.SendChatMessage = send
local methods = getmetatable(UIParent).__index
function methods:SetVertexColor() end
function methods:GetFrameLevel() return 1 end
function methods:SetFrameLevel() end
function methods:SetIgnoreParentAlpha() end
function methods:SetIgnoreParentScale() end
function methods:AddLine() end
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
C_NamePlate = {
    GetNamePlateForUnit = function(unit) return plates[unit] end,
    GetNamePlates = function() return {} end,
}
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/Display.lua"))()
local GL, D = GrudgeLedger, GrudgeLedger.Display
GL.InitDB()
GL.Settings().enemyAlerts, GL.Settings().friendAlerts = false, false
local serial = 0
local function person(confidence, kind)
    serial = serial + 1
    local p = { name = "Rival" .. serial, surname = "Example", guid = "Player-1-rival" .. serial }
    local id = GL.IdentityFromName(p.name, p.surname, p.guid)
    local record = GL.Remember(id)
    if confidence then
        if kind == "aggression" then GL.RecordAggression(id, confidence, "test", "event" .. serial)
        else GL.RecordPvP(id, "death", confidence, "test", "event" .. serial) end
    else GL.SetReaction(id, "enemy") end
    return p, record
end
local function see(p)
    units.target = p
    D.OnEvent(nil, "PLAYER_TARGET_CHANGED")
end
local function resetView()
    units.target, units.mouseover = nil, nil
    for unit in pairs(plates) do D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", unit) units[unit] = nil end
    plates = {}
    now = now + 10000
end
local function tick(seconds)
    now = now + seconds
    D.Refresh()
end
local rival, record = person("confirmed")
assert(GL.Settings().partyWarnings == false, "sharing must be off by default")
see(rival)
assert(#sent == 0 and not record.partyPresence)
GL.Settings().partyWarnings = true
see(rival)
assert(#sent == 1 and sent[1]:find("agression PvP enregistrée", 1, true))
assert(not sent[1]:find("m'a", 1, true), "legacy/account data must not become a claim by this character")
for _ = 1, 300 do tick(60) end
assert(#sent == 1, "five hours of continued presence must not repeat a party warning")
for _ = 1, 30 do now = now + 600 see(rival) end
assert(#sent == 1, "exactly ten-minute recrossings remain one encounter")
rival.visible = false
local seenAt = record.partyPresence[units.player.guid].seenAt
tick(1800)
assert(record.partyPresence[units.player.guid].seenAt == seenAt, "remote selected target is not a sighting")
rival.visible = true
see(rival)
assert(#sent == 2, "a genuine return after 30 minutes is announced")
units.target = nil
now = now + 601
see(rival)
assert(#sent == 2, "new encounter still respects the 30-minute per-person cooldown")

resetView()
local before = #sent
local unsupported, unsupportedRecord = person()
see(unsupported)
assert(#sent == before, "a manual enemy without PvP evidence is not called a past aggressor")
local positive, positiveRecord = person("confirmed")
GL.SetReaction(positiveRecord, "friend")
see(positive)
assert(#sent == before, "a forgiven friend must not be announced as dangerous")
local neutral, neutralRecord = person()
GL.SetReaction(neutralRecord, "neutral")
see(neutral)
see(units.player)
assert(#sent == before, "neutral records and self do not warn")
local partner = units.party1
local teammate = person("confirmed")
units.party1 = teammate
see(teammate)
assert(#sent == before, "current party members are excluded")
units.party1 = nil
see(rival)
assert(#sent == before, "solo sends nothing")
units.party1 = partner
raid = true
see(rival)
raid = false
for _, kind in ipairs({ "pvp", "arena", "raid", "scenario" }) do instanceType = kind see(rival) end
assert(#sent == before, "raids, battlegrounds and arenas never send")
instanceType = "none"
local savedInstance = IsInInstance
IsInInstance = function() error("protected") end
see(rival)
IsInInstance = nil
see(rival)
IsInInstance = savedInstance
local savedRaid = IsInRaid
IsInRaid = function() return mock.secret end
see(rival)
IsInRaid = savedRaid
assert(#sent == before, "unknown/protected party context fails closed")

resetView()
local probable = person("probable")
see(probable)
assert(#sent == before + 1 and sent[#sent]:find("probable", 1, true) and sent[#sent]:find("à confirmer", 1, true))
units.target = nil
local aggression = person("confirmed", "aggression")
now = now + 60
see(aggression)
assert(#sent == before + 2, "confirmed aggression alone is eligible after global cooldown")
units.target = nil
local crowd = {}
for i = 1, 40 do crowd[i] = person("confirmed") see(crowd[i]) end
assert(#sent == before + 2, "global cap suppresses a burst of different players")
now = now + 60
for _, p in ipairs(crowd) do see(p) end
assert(#sent == before + 2, "suppressed sightings do not become a delayed chat backlog")

-- The physical nameplate and tooltip paths maintain the same encounter clock.
resetView()
local p, plateRecord = person("confirmed")
local plate = CreateFrame("Frame", nil, UIParent)
plate.UnitFrame = CreateFrame("Frame", nil, plate)
plate.UnitFrame.name = plate.UnitFrame:CreateFontString()
units.nameplate1, plates.nameplate1 = p, plate
D.OnEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
before = #sent
for _ = 1, 40 do tick(60) end
assert(#sent == before and plateRecord.partyPresence[units.player.guid].seenAt == now)
D.OnEvent(nil, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
units.nameplate1, plates.nameplate1 = nil, nil
units.mouseover = p
for _ = 1, 40 do tick(60) end
assert(#sent == before and plateRecord.partyPresence[units.player.guid].seenAt == now)
units.mouseover = nil
now = now + 1801
units.target = p
function GameTooltip:GetUnit() return p.name, "target" end
D.Tooltip(GameTooltip)
assert(#sent == before + 1, "physical tooltip sightings can start an encounter")

-- A reload, a setting toggle, and a backward clock cannot reset antispam.
before = #sent
GrudgeLedgerDisplayEvents, GrudgeLedgerNearbyAlert = nil, nil
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/Display.lua"))()
GL, D = GrudgeLedger, GrudgeLedger.Display
GL.InitDB()
see(p)
GL.SetSetting("partyWarnings", false)
GL.SetSetting("partyWarnings", true)
assert(#sent == before)
now = now - 1000
see(p)
local other = person("confirmed")
see(other)
assert(#sent == before, "clock rollback must not reopen global or per-player cooldowns")

-- Missing native API is recoverable at a later encounter; never bypass a refusal.
resetView()
local missing = person("confirmed")
C_ChatInfo.SendChatMessage = nil
see(missing)
assert(#sent == before)
C_ChatInfo.SendChatMessage = send
see(missing)
assert(#sent == before, "no burst of retries on the same encounter")
now = now + 601
see(missing)
assert(#sent == before + 1, "available API retries on a new encounter")
resetView()
local blocked = person("confirmed")
local blockedAttempts = 0
C_ChatInfo.SendChatMessage = function() blockedAttempts = blockedAttempts + 1 error("protected") end
SendChatMessage = function() error("must not bypass modern API refusal") end
see(blocked)
for _ = 1, 100 do tick(1) end
assert(blockedAttempts == 1, "a protected send is attempted once, never every refresh")
now = now + 601
see(blocked)
assert(blockedAttempts == 1)
now = now + 1800
see(blocked)
assert(blockedAttempts == 2, "a later encounter may retry once after long cooldown")
C_ChatInfo.SendChatMessage = nil
SendChatMessage = send
resetView()
see(person("confirmed"))
assert(#sent == before + 2, "legacy native API is supported when modern API is absent")

resetView()
before = #sent
local unsafe, unsafeRecord = person("confirmed")
for _, name in ipairs({ "Player|Hlink", "Player\nInjected", "Player{rt1}", string.rep("A", 121) }) do
    -- Live identity cleaning rejects controls; the saved-record path also rejects
    -- markup and oversized names without ever forwarding notes or arbitrary data.
    unsafe.name, unsafe.surname = name, "Example"
    unsafeRecord.fullName = name
    see(unsafe)
end
assert(#sent == before)
assert(#GL.errors == 2, "only the two deliberate native refusals should be logged")
print("PASS party warnings: opt-in, evidence wording, party-only, presence/cooldowns, flood suppression, reload/clock rollback, protected APIs, bounded retries and safe names")
