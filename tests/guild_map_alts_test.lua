-- Owner report (24/11): the journal is the account's, and an alt that joined the guild vision
-- announced the main's fights as hers ("Megumin a été tué par ..." in a zone she never visited).
-- Two sessions on one saved book: the main fights, then the alt logs in.
local now = 1800000000
local function session(player, saved)
    local env = setmetatable({ _G = false }, { __index = _G })
    env._G = env
    env.loadfile = function(p) return setfenv(assert(loadfile(p)), env) end
    env.GrudgeLedgerDB = saved
    local mock = env.loadfile(TEST_WORK .. "/tests/addon_mock.lua")()
    local s = { env = env, GL = env.GrudgeLedger, m = mock, sent = {} }
    mock.units.player = { guid = player, name = player == "Player-1-main" and "Principal" or "Megumin", surname = "Example",
        guild = "Guild", realm = "Realm" }
    env.GetServerTime = function() return now end
    env.GetNormalizedRealmName = function() return "Realm" end
    env.GetNumGuildMembers = function() return 1 end
    env.GetGuildRosterInfo = function() return unpack({ [1] = "Member-Realm", [17] = "Player-1-member" }, 1, 17) end
    env.C_Map = {
        GetBestMapForUnit = function() return 1448 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.6 end } end,
    }
    env.C_ChatInfo.RegisterAddonMessagePrefix = function() end
    env.C_ChatInfo.InChatMessagingLockdown = function() return false end
    env.C_ChatInfo.SendAddonMessage = function(_, msg) s.sent[#s.sent + 1] = msg return 0 end
    env.C_Timer = { NewTicker = function(delay, fn) if delay == 0.5 then s.tick = fn end return { Cancel = function() end } end,
        After = function(_, fn) fn() end }
    mock.Fire("PLAYER_LOGIN")
    mock.Fire("GUILD_ROSTER_UPDATE")
    s.GL.GuildMap.Join()
    return s
end
local function drain(s) for _ = 1, 200 do now = now + 1 if s.tick then s.tick() end end end

-- The main: two fights in Gangrebois, kept in the account's journal and on the guild map.
local main = session("Player-1-main", nil)
local GL = main.GL
assert(GL.GuildMap.Enabled() == true)
local foe = GL.IdentityFromName("Fy", "Rion", "Player-1-fyrion")
local _, death = GL.RecordPvP(foe, "death", "confirmed", "test", "main-death")
now = now + 60
local _, kill = GL.RecordPvP(foe, "kill", "confirmed", "test", "main-kill")
for _, e in ipairs({ death, kill }) do e.mapID, e.mapX, e.mapY = 1448, 0.4, 0.6 end
-- The map keeps one fight a second: each line carries the time of its journal event.
death.time = now - 1
assert(GL.GuildMap.Fight("k", foe.guid, "Fy Rion"))
local saved = now
now = death.time
assert(GL.GuildMap.Fight("d", foe.guid, "Fy Rion"))
now = saved
local book = GrudgeLedgerDB or main.env.GrudgeLedgerDB
local scope = GL.Bounties.GuildScope()
assert(#scope.places["Player-1-main"] >= 2)
-- What 0.61.2 did when the alt logged in: the main's fights under her name.
book.characterFactions["Player-1-alt"] = "Alliance"
scope.places["Player-1-alt"] = {}
for i, text in ipairs(scope.places["Player-1-main"]) do scope.places["Player-1-alt"][i] = text end

-- The alt logs in on the same book.
now = now + 3600
local alt = session("Player-1-alt", book)
local altScope = alt.GL.Bounties.GuildScope()
assert(altScope == book.bountyGuilds[scope.guildKey], "both characters share the guild's space")
assert(#(altScope.places["Player-1-alt"] or {}) == 0, "the alt keeps none of the main's fights")
assert(#altScope.places["Player-1-main"] >= 2, "the main keeps its own")
drain(alt)
local forgot, wrong = false, false
for _, msg in ipairs(alt.sent) do
    if msg == "MX" then forgot = true end
    if msg:find("^M;1;Player%-1%-alt;") then wrong = true end
end
assert(forgot, "the guild is asked to forget the alt's wrong fights")
assert(not wrong, "the alt never announces a fight of the main")
-- Seen from the alt, the guild journal shows the main's fights once, under the main.
local points = alt.GL.GuildMap.Points(true)
local byAlt = 0
for _, point in ipairs(points) do if point.actor == "Player-1-alt" then byAlt = byAlt + 1 end end
assert(byAlt == 0, "no fight of the main under the alt's name")
for _, c in ipairs({ main, alt }) do assert(#c.GL.errors == 0, (c.GL.errors[1] or {}).text) end
print("PASS guild map and alts: a character seeds only its own fights, wrong lines removed, the guild asked to forget them")
