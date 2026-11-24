-- Audit 24/11: a member cannot fill the guild's books. Guild cards are bounded per member, and a
-- full fight-score table makes room for a real target instead of refusing every new one.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me, member = mock.units.player.guid, "Player-1-member"
local roster = { { "Testeur-Realm", me }, { "Member-Realm", member } }
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return unpack({ [1] = roster[i][1], [17] = roster[i][2] }, 1, 17) end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function() return 0 end
C_ChatInfo.InChatMessagingLockdown = function() return false end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
mock.Fire("GUILD_ROSTER_UPDATE")
local s = GL.Bounties.GuildScope()
local G = GL.GuildProfiles

-- 310 cards from one member: 300 kept.
for i = 1, 310 do
    local target = ("Player-1-%06x"):format(i)
    G.Receive(s, me, member, table.concat({ "C", target, ("%032x"):format(i), now, ("%016x"):format(7), "Fiche " .. i }, ";"))
end
local cards = 0
for key in pairs(s.journal.cards) do if key:find("^Player%-1%-member:") then cards = cards + 1 end end
assert(cards == 300, "cards kept for one member: " .. cards)

-- A full score table still takes a target your book knows.
s.scores = {}
for i = 1, 1500 do s.scores[("Player-9-%06x"):format(i)] = { [member] = { 1, 0 } } end
local real = GL.Remember(GL.IdentityFromName("Real", "Target", "Player-1-realtgt"))
mock.Fire("CHAT_MSG_ADDON", "GLBounty1", table.concat({ "G", member, real.guid, 2, 1 }, ";"), "GUILD", "Member-Realm")
assert(s.scores[real.guid] and s.scores[real.guid][member][1] == 2, "a known target enters a full table")
local n = 0
for _ in pairs(s.scores) do n = n + 1 end
assert(n == 1500, "the table stays bounded: " .. n)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS guild bounds: cards bounded per member, a full score table makes room for a known target")
