-- Unticking then ticking "Vision de guilde" again (owner report 25/11): the guild's fights came
-- back only if a member answered, and members who had just answered stay silent thirty seconds.
-- Now they wait in memory while the box is unticked; nothing new is kept meanwhile, and a member
-- who asks to be forgotten is forgotten there too. Synthetic guild only.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me = mock.units.player.guid
local roster = { { "Testeur-Realm", me, true }, { "Mate-Realm", "Player-1-mate0001", true }, { "Other-Realm", "Player-1-mate0002", true } }
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return unpack({ [1] = roster[i][1], [9] = roster[i][3], [17] = roster[i][2] }, 1, 17) end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end

C_ChatInfo.SendAddonMessage = function() return 0 end
C_ChatInfo.InChatMessagingLockdown = function() return false end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
C_Map = { GetBestMapForUnit = function() return 1446 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end }
mock.Fire("PLAYER_LOGIN")
mock.Fire("GUILD_ROSTER_UPDATE")
local M = GL.GuildMap
M.Enable(true)
local function hear(sender, text) mock.Fire("CHAT_MSG_ADDON", "GLBounty1", text, "GUILD", sender) end
local function fight(actor, at, kind) return ("M;1;%s;%d;1446;500;500;%s;;"):format(actor, at, kind) end
hear("Mate-Realm", fight("Player-1-mate0001", now - 100, "d"))
hear("Mate-Realm", fight("Player-1-mate0001", now - 50, "k"))
hear("Other-Realm", fight("Player-1-mate0002", now - 30, "d"))
assert(#M.Points() == 3, #M.Points())

-- Unticked: nothing shows, nothing is saved, nothing heard is kept.
M.Enable(false)
local s = GL.Bounties.GuildScope()
assert(#M.Points() == 0 and s.places == nil)
hear("Mate-Realm", fight("Player-1-mate0001", now - 10, "d"))
-- The other member asks to be forgotten while the box is unticked.
hear("Other-Realm", "MX")
-- Ticked again: the fights held are back at once, without waiting for an answer.
M.Enable(true)
local points = M.Points()
assert(#points == 2, #points)
for _, point in ipairs(points) do
    assert(point.actor == "Player-1-mate0001" and point.time ~= now - 10, "heard while unticked: not kept")
end
-- Ticking twice changes nothing.
M.Enable(true)
assert(#M.Points() == 2)

-- At login a member answers with the guild's latest fights, as a relay (owner report 25/11: no
-- guild fight at all on the map). The fights of the members connected right now are in it, the
-- relayer's own included: they are kept, since those members only send their own when a box is ticked.
now = now + 100
hear("Mate-Realm", "R;" .. fight("Player-1-mate0001", now - 5, "k"))
hear("Mate-Realm", "R;" .. fight("Player-1-mate0002", now - 4, "k"))
assert(#M.Points() == 4, #M.Points())
-- A member who asked to be forgotten stays forgotten: its older fights are not brought back.
hear("Mate-Realm", "R;" .. fight("Player-1-mate0002", now - 200, "d"))
assert(#M.Points() == 4, #M.Points())
-- Someone outside the guild is never relayed in.
hear("Mate-Realm", "R;" .. fight("Player-1-stranger", now - 3, "k"))
assert(#M.Points() == 4)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS guild map toggle: unticking then ticking keeps the guild's fights in memory, nothing heard meanwhile, forgetting honoured")
