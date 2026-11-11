local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local methods = getmetatable(UIParent).__index
function methods:HighlightText() self.highlighted = true end
local now = 1000
GetServerTime = function() return now end
GetTimePreciseSec = GetServerTime
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
local function identity(name, guild, realm)
    local id = GL.IdentityFromName(name, "Example", "Player-1-" .. name)
    id.guild, id.realm = guild, realm or "Forever"
    return id
end
local a = identity("Alpha", "Old Guild")
assert(not GL.RecordSeen(a, true), "unmarked passersby must not create records")
local r = GL.RecordPvP(a, "death", "confirmed", "fixture", "d1")
assert(not r.encounters, "PvP records and menu actions are not observations")
for i = 1, 50 do GL.RecordSeen(a, true) end
assert(r.encounters.count == 1)
now = now + 600 GL.RecordSeen(a, true)
assert(r.encounters.count == 1, "exact ten minutes stays the same encounter")
now = now + 601 GL.RecordSeen(a, true)
assert(r.encounters.count == 2)
GL.InitDB() GL.RecordSeen(a, true)
assert(r.encounters.count == 2, "reload does not invent encounters")
now = now + 900 GL.RecordSeen(a)
assert(r.encounters.count == 2, "group metadata without visibility is not a visit")
GL.RecordSeen(a, true) assert(r.encounters.count == 3)
mock.units.player.guid = "Player-1-alt"
GL.RecordSeen(a, true) assert(r.encounters.count == 4, "different character is a different encounter")
assert(GL.PlayerStatistics("enemiesSeen")[1].value == 4)
local b = identity("Beta", "New Guild")
GL.AdjustReputation(b, 3, "good group", "manual")
GL.RecordSeen(b, true)
assert(GL.PlayerStatistics("reputation")[1].record.key == b.key)
assert(GL.PlayerStatistics("friendsSeen")[1].value == 1)
assert(#GL.PlayerStatistics("kills") == 0, "no invented zero-value champions")
assert(GL.PlayerStatistics("deaths")[1].value == 1)
local provisional = GL.IdentityFromName("Promoted", "Example")
GL.SetReaction(provisional, "friend") GL.RecordSeen(provisional, true)
local promoted = GL.IdentityFromName("Promoted", "Example", "Player-1-promoted")
GL.RecordSeen(promoted, true)
assert(GL.Get(promoted).encounters.count == 1, "name-to-GUID promotion preserves the encounter")
GL.RecordPvP(a, "death", "probable", "fixture", "d2")
local probable = r.history[#r.history]
assert(GL.PlayerStatistics("probableDeaths")[1].value == 1)
a.guild = "New Guild" GL.Remember(a)
local function guild(name, realm)
    for _, row in ipairs(GL.GuildStatistics()) do if row.name == name and row.realm == (realm or "Forever") then return row end end
end
assert(guild("Old Guild").deaths == 1 and guild("Old Guild").probableDeaths == 1)
assert(guild("New Guild").deaths == 0 and guild("New Guild").grudges == 1 and guild("New Guild").friends == 1)
GL.VoidPvP(r, probable)
assert(guild("Old Guild").probableDeaths == 0, "corrections update historical guild attribution")
GL.SetGuildReaction("New Guild", "warning")
local c = identity("Gamma", "New Guild")
assert(GL.Relation(GL.RecordSeen(c, true)) == "warning")
assert(guild("New Guild").grudges == 1, "rule does not manufacture personal grudges for ranking")
GL.SetGuildReaction("New Guild", "enemy", nil, "Another realm")
assert(guild("New Guild", "Another realm").grudges == 0)
assert(GL.Relation(GL.Get(b)) == "friend", "personal friends remain explicit exceptions")
local noGuild = identity("Unknown")
GL.RecordPvP(noGuild, "death", "confirmed", "fixture", "d3")
assert(guild("New Guild").deaths == 0, "missing historical guild is not guessed")

GL.ClearDetectionLog()
GL.Trace("observed", a, "nameplate1") GL.Trace("observed", a, "nameplate2")
assert(#GL.db.detectionLog == 1, "recycled unit tokens do not flood logs")
GL.Trace("cooldown", a, "target")
assert(#GL.db.detectionLog == 2)
assert(not GL.DetectionReport(false):find("Alpha", 1, true))
assert(GL.DetectionReport(true):find("Alpha", 1, true))
GL.SetSetting("detectionLog", false) now = now + 40 GL.Trace("shown", a, "target")
assert(#GL.db.detectionLog == 2)
GL.SetSetting("detectionLog", true)
for i = 1, 240 do now = now + 31 GL.Trace("shown", a, "target") end
assert(#GL.db.detectionLog == 200)
GL.InitDB() assert(#GL.db.detectionLog == 200, "diagnostic survives reload")
GL.ClearDetectionLog() assert(#GL.db.detectionLog == 0)

assert(loadfile(TEST_ROOT .. "/UI.lua"))()
GL.ShowStatistics("guilds")
local f = GrudgeLedgerStatistics
assert(f:IsShown() and f.rows[1].item)
f.rows[1].scripts.OnClick(f.rows[1])
local chosen = f.selected
f.guildActions[1].scripts.OnClick()
assert(GL.GetGuildRule(chosen.name, chosen.realm).reaction == "warning")
GL.ShowStatistics("players")
assert(f.rows[1].item.value >= 1 and not f.guildActions[1]:IsShown())
local selected = f.rows[1].item.record
f.rows[1].scripts.OnClick(f.rows[1])
assert(not f:IsShown() and GrudgeLedgerWindow:IsShown())
assert(GrudgeLedgerWindow.detailTitle:GetText():find(selected.fullName, 1, true))
GL.ShowStatistics("players") f.choices[6].scripts.OnClick()
assert(f.rows[1].item.record.key == b.key)
for i = 1, 10 do GL.SetGuildReaction("Fixture " .. i, "warning") end
GL.ShowStatistics("guilds") f.next.scripts.OnClick()
assert(f.offset == 8 and f.rows[1].item and f.previous.enabled)
GL.ShowStatistics("players") f.choices[2].scripts.OnClick()
assert(not f.rows[1]:IsShown() and f.empty:GetText() ~= "" and not f.next.enabled)
SlashCmdList.GRUDGELEDGER("traces")
assert(GrudgeLedgerDiagnostic.privacy:GetText():find("contient les noms", 1, true))
SlashCmdList.GRUDGELEDGER("debug")
assert(GrudgeLedgerDiagnostic.privacy:GetText():find("anonyme", 1, true))
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS insights: sliding observations, persistence, alt separation, no retrospective visits, rankings, realm/guild history, corrections, rule exceptions, bounded private/anonymized logs, clickable guild/player pages")
