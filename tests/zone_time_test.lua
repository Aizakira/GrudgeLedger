local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local epoch = os.time({year = 2026, month = 12, day = 31, hour = 23, min = 59, sec = 30})
local now, zone, afk, online, instance, tick = epoch, "Port", false, true, "none", nil
GetServerTime = function() return now end
GetRealZoneText = function() return zone end
IsInInstance = function() return instance ~= "none", instance end
UnitIsAFK = function() return afk end
UnitIsConnected = function() return online end
date = os.date
C_Timer = {NewTicker = function(seconds, fn)
    assert(seconds == 60 and tick == nil)
    tick = fn
    return {Cancel = function() tick = nil end}
end}
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/ZoneTime.lua"))()
local GL = GrudgeLedger
GL.InitDB()
mock.Fire("PLAYER_ENTERING_WORLD")
assert(not tick and not GL.db.zoneExposure)
GL.SetSetting("zoneTime", true)
now = now + 60 tick()
assert(GL.ZoneTimes({period="year", year=2026}).Port == 30 and GL.ZoneTimes({period="year", year=2027}).Port == 30)
assert(table.concat(GL.JournalYears(), ",") == "2027,2026", "peaceful years remain selectable")
zone = "Quai" mock.Fire("ZONE_CHANGED_NEW_AREA")
now = now + 20 afk = true mock.Fire("PLAYER_FLAGS_CHANGED", "player")
now = now + 40 tick() afk = false mock.Fire("PLAYER_FLAGS_CHANGED", "player")
now = now + 10 instance = "pvp" mock.Fire("PLAYER_LEAVING_WORLD") mock.Fire("PLAYER_ENTERING_WORLD")
now = now + 80 tick() assert(GL.ZoneTimes().Quai == 30)
instance = "party" mock.Fire("PLAYER_ENTERING_WORLD")
now = now + 40 tick() assert(GL.ZoneTimes().Quai == 30)
instance = "none" mock.Fire("PLAYER_ENTERING_WORLD")
now = now + 400 tick() assert(GL.ZoneTimes().Quai == 30, "resume after a long clock gap cannot invent presence")
now = now + 5 online = false mock.Fire("UNIT_CONNECTION", "player")
now = now + 50 tick() assert(GL.ZoneTimes().Quai == 35)
online = true mock.Fire("UNIT_CONNECTION","player")
now = now + 15 GL.SetSetting("zoneTime",false)
assert(not tick and GL.ZoneTimes().Quai == 50)
now = epoch + 7 * 86400 + 20
assert(GL.ZoneTimes({period="week"}).Port == 40, "only the overlapping part of the visit is counted")
mock.units.player.guid = "Player-1-another"
assert(not next((GL.ZoneTimes({period="week"}))) and GL.ZoneTimes({scope="all",period="week"}).Port == 40)
assert(not next((GL.ZoneTimes({scope="legacy"}))))
GL.SetSetting("zoneTime", true)
for i = 1, 2200 do
    now = now + 1 zone = i % 2 == 1 and "A" or "B" mock.Fire("ZONE_CHANGED_NEW_AREA")
end
local rows, partial = GL.ZoneTimes({period="month"})
assert(partial and #GL.db.zoneExposure["Player-1-another"].recent <= 2048 and rows.A > 0)
rows, partial = GL.ZoneTimes()
assert(not partial and rows.A + rows.B == 2199, "rolling limits never reduce the annual ledger")
mock.Fire("PLAYER_LOGOUT")
assert(not tick and #GL.errors == 0)
local damaged = {years = {["2027"] = {Port = 20, Quai = "bad", [""] = 12}, ["2026"] = false},
    recent = {[1] = false, [2] = {"Quai", "bad", now}, [4] = {"Port", now - 20, now}, [6] = {"Quai", now + 10, now}},
    clippedAt = "bad"}
GL.db.zoneExposure = {["Player-1-another"] = damaged, broken = false, old = {years = "bad", recent = 5}}
rows, partial = GL.ZoneTimes({period="week",scope="all"})
assert(rows.Port == 20 and rows.Quai == nil and partial)
assert(GL.ZoneTimes({scope="all"}).Port == 20 and #damaged.recent == 1)
mock.Fire("PLAYER_ENTERING_WORLD")
zone = "Port" mock.Fire("ZONE_CHANGED_NEW_AREA")
now = now + 10 tick()
assert(GL.ZoneTimes().Port == 30 and #GL.errors == 0, "surviving records accept subsequent live measurements")
print("PASS optional zone time: outdoor intervals, AFK, clock gaps, scopes, year boundary, rolling windows and bounded archives")
