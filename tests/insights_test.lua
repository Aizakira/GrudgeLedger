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
assert(#GL.PlayerStatistics("friendsSeen") == 0, "a first meeting is not a repeat encounter")
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

local shared = {}
for i, confidence in ipairs({ "probable", "confirmed", "probable" }) do
    local record = GL.RecordPvP(identity("Shared" .. i, "Shared Guild"), "death", confidence, "fixture", "shared-death")
    shared[i] = { record, record.history[#record.history] }
end
assert(guild("Shared Guild").deaths == 1 and guild("Shared Guild").probableDeaths == 0,
    "one guild death, strongest evidence wins independently of participant order")
GL.RecordPvP(identity("OtherParticipant", "Other Guild"), "death", "probable", "fixture", "shared-death")
assert(guild("Other Guild").probableDeaths == 1, "each involved guild retains its own evidence")
GL.VoidPvP(unpack(shared[2]))
assert(guild("Shared Guild").deaths == 0 and guild("Shared Guild").probableDeaths == 1,
    "voided lethal attribution falls back to the other participants, counted once")
GL.VoidPvP(unpack(shared[1])) GL.VoidPvP(unpack(shared[3]))
assert(guild("Shared Guild").deaths == 0 and guild("Shared Guild").probableDeaths == 0)
for i = 1, 2 do GL.RecordPvP(identity("Legacy" .. i, "Legacy Guild"), "death", "probable", "fixture") end
assert(guild("Legacy Guild").probableDeaths == 2, "legacy events without IDs must not be guessed into one death")

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

assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
GL.ShowStatistics("guilds")
local f = GrudgeLedgerStatistics
assert(f:IsShown() and f.rows[1].item)
assert(f.selected == f.rows[1].item and f.guildDetail.name:GetText() == f.selected.name)
assert(f.tabs.guilds.selection:IsShown() and not f.tabs.players.selection:IsShown())
f.groups[2].scripts.OnClick()
assert(f.groups[3]:GetText() == "Mes règles" and f.choices[4].metric == "probableDeaths")
f.groups[3].scripts.OnClick()
assert(f.rows[1].item and not f.choices[2]:IsShown(), "rules page has its own single choice and works for guilds without combat")
for _, row in ipairs(f.rows) do
    if row:IsShown() then assert(GL.GetGuildRule(row.item.name, row.item.realm) and row.value:GetText() ~= "") end
end
f.groups[1].scripts.OnClick()
assert(f.scope:GetText() == "Compte · Relations actuelles")
f.rows[1].scripts.OnClick(f.rows[1])
local chosen = f.selected
f.guildActions[1].scripts.OnClick()
assert(GL.GetGuildRule(chosen.name, chosen.realm).reaction == "warning")
assert(f.guildDetail.name:GetText() == chosen.name and f.guildDetail.exceptionButton.enabled)
f.guildDetail.exceptionButton.scripts.OnClick()
assert(f.guildDetail.exceptionsOnly)
for _, row in ipairs(f.guildDetail.rows) do
    if row.record then assert(GL.Relation(row.record) ~= "warning" and row.record.guild == chosen.name and row.record.realm == chosen.realm) end
end
f.guildDetail.exceptionButton.scripts.OnClick()
assert(not f.guildDetail.exceptionsOnly and f.guildDetail.rows[1].record)
GL.ShowStatistics("players")
assert(f.tabs.players.selection:IsShown() and not f.tabs.guilds.selection:IsShown())
assert(f.rows[1].item.value >= 1 and not f.guildActions[1]:IsShown())
f.relationButton.scripts.OnClick()
for _, row in ipairs(f.rows) do if row:IsShown() then assert(GL.Relation(row.item.record) == "enemy") end end
f.relationButton.scripts.OnClick()
for _, row in ipairs(f.rows) do if row:IsShown() then assert(GL.Relation(row.item.record) == "warning") end end
f.relationButton.scripts.OnClick()
local selected = f.rows[1].item.record
f.rows[1].scripts.OnClick(f.rows[1])
assert(not f:IsShown() and GrudgeLedgerWindow:IsShown())
assert(GrudgeLedgerWindow.detailTitle:GetText():find(selected.fullName, 1, true))
GL.ShowStatistics("players") f.groups[2].scripts.OnClick()
assert(not f.rows[1]:IsShown() and f.empty:GetText():find("deuxième rencontre", 1, true))
now = now + 601 GL.RecordSeen(b, true) GL.RecordSeen(promoted, true)
GL.ShowStatistics("players")
assert(f.rows[1].item.record.key == b.key)
assert(f.rows[1].value:GetText() == "2" and f.rows[1].rank:GetText() == "1")
assert(f.columnExtra:GetText() == "Guilde connue" and f.rows[1].extra:GetText() == GL.Get(b).guild and not f.rows[1].icon:IsShown())
assert(f.columnValue:GetText() == "Rencontres" and f.scope:GetText():find("Toutes périodes", 1, true))
GL.Get(b).faction = "Alliance"
f.factionButton.scripts.OnClick()
assert(f.rows[1].item.record.key == b.key and not f.rows[2]:IsShown())
assert(f.total:GetText() == "1 personne")
f.factionButton.scripts.OnClick()
assert(not f.rows[1]:IsShown() and f.empty:GetText():find("Toutes les factions", 1, true))
f.factionButton.scripts.OnClick()
assert(f.rows[1].item.record.key == promoted.key, "unknown factions remain separately visible")
f.factionButton.scripts.OnClick()
for i = 1, 10 do GL.SetReaction(identity("Fixture" .. i, "Fixture " .. i), "enemy") end
local allGuilds = #GL.GuildStatistics()
GL.ShowStatistics("guilds")
local secondGuild = f.rows[2].item
assert(secondGuild and not GL.GetGuildRule(secondGuild.name, secondGuild.realm))
f.rows[2].scripts.OnClick(f.rows[2])
GL.Emit("CHANGED")
assert(f.selected.key == secondGuild.key and f.guildDetail.name:GetText() == secondGuild.name)
assert(not GL.GetGuildRule(secondGuild.name, secondGuild.realm), "previewing a guild never defines a rule")
f.next.scripts.OnClick()
assert(f.offset == #f.rows and f.rows[1].item and f.previous.enabled)
f.rows[1].scripts.OnClick(f.rows[1])
assert(f.guildActions[1].enabled)
f.previous.scripts.OnClick()
assert(f.selected == f.rows[1].item and f.guildDetail.name:GetText() == f.selected.name,
    "paging updates the highlighted guild, its sheet and its action target together")
f.manage.scripts.OnClick()
assert(GrudgeLedgerGuilds:IsShown() and f:IsShown(), "the guild editor must return to the rankings when closed")
GrudgeLedgerGuilds:Hide()
f.choices[2].scripts.OnClick()
assert(f.offset == 0)
if f.rows[1]:IsShown() then
    assert(f.selected == f.rows[1].item and f.guildActions[1].enabled and f.guildDetail.name:GetText() == f.selected.name,
        "the first visible guild opens when changing ranking")
else
    assert(not f.selected and not f.guildActions[1].enabled)
end
assert(#GL.GuildStatistics() == allGuilds, "UI filtering must not modify the cached guilds")
for _, row in ipairs(f.rows) do if row:IsShown() then assert(row.item.friends > 0) end end
assert(not f.factionButton:IsShown())
-- Exercise every navigation path and ensure each choice maps to a measured metric.
local metrics = {
    players = { {"grudge", "enemiesSeen", "enemiesRecent", "aggressions"}, {"friendsSeen", "reputation", "friendsRecent", "friendsGrouped"}, {"deaths", "kills", "probableDeaths", "probableKills"} },
    guilds = { {"grudges", "friends"}, {"deaths", "kills", "aggressions", "probableDeaths"} },
}
for mode, groups in pairs(metrics) do
    GL.ShowStatistics(mode)
    for i, choices in ipairs(groups) do
        f.groups[i].scripts.OnClick()
        for j, metric in ipairs(choices) do
            f.choices[j].scripts.OnClick()
            assert(f.choices[j].metric == metric and f.choices[j].selection:IsShown())
            assert(f.description:GetText() ~= "" and f.footnote:GetText() ~= "")
            for _, row in ipairs(f.rows) do
                if row:IsShown() then assert((mode == "guilds" and row.item[metric] or row.item.value) > 0) end
            end
        end
    end
end
GL.ShowStatistics("players") f.groups[3].scripts.OnClick() f.choices[2].scripts.OnClick()
assert(not f.rows[1]:IsShown() and f.empty:GetText() ~= "" and not f.next.enabled)
assert(f.selection:GetText() == "", "empty rankings must not invite selecting a missing row")
-- Commands use the same entry points as buttons: only one book may be visible.
GL.SetSetting("guideSeen", true)
GL.ShowJournal("summary")
assert(GrudgeLedgerJournal:IsShown() and not f:IsShown())
GL.ShowStatistics("players")
assert(f:IsShown() and not GrudgeLedgerJournal:IsShown())
GL.ShowLedger()
assert(GrudgeLedgerWindow:IsShown() and not f:IsShown())
GL.ShowJournal("history") GL.ShowLedger()
assert(GrudgeLedgerWindow:IsShown() and not GrudgeLedgerJournal:IsShown())
SlashCmdList.GRUDGELEDGER("traces")
assert(GrudgeLedgerDiagnostic.privacy:GetText():find("contient les noms", 1, true))
SlashCmdList.GRUDGELEDGER("debug")
assert(GrudgeLedgerDiagnostic.privacy:GetText():find("anonyme", 1, true))
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS insights: sliding observations, persistence, alt separation, no retrospective visits, rankings, realm/guild history, corrections, rule exceptions, bounded private/anonymized logs, clickable guild/player pages")
