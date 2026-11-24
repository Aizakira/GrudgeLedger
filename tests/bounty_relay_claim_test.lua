-- Audit 24/11: a member relays, in a hunter's name, a claim backdated before the real one. Only a
-- claim heard from its own hunter may win: the issuer's client never crowns a relayed claim.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me, member, hunter = mock.units.player.guid, "Player-1-member", "Player-1-hunter"
local roster = { { "Testeur-Realm", me }, { "Member-Realm", member }, { "Hunter-Realm", hunter } }
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return unpack({ [1] = roster[i][1], [17] = roster[i][2] }, 1, 17) end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function() return 0 end
C_ChatInfo.InChatMessagingLockdown = function() return false end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
mock.Fire("GUILD_ROSTER_UPDATE")
local function hear(text, from) mock.Fire("CHAT_MSG_ADDON", "GLBounty1", text, "GUILD", from) end

local foe = GL.IdentityFromName("Target", "Example", "Player-1-target")
foe.faction = "Horde"
GL.Remember(foe)
local order = assert(GL.Bounties.Post(foe.guid, foe.fullName, 50000))
local function contract() return GL.Bounties.List()[order] end
assert(contract() and contract().state == "open")

-- The forged relay: a claim "by the hunter", dated ten seconds after the posting.
now = now + 100
local fakeSeq = (now - 90) * 1000 + 1
hear(table.concat({ "R;K", hunter, fakeSeq, now - 90, order, "", "" }, ";"), "Member-Realm")
local o = contract()
assert(o.state == "open" and not o.first and not o.winner, "a relayed claim alone counts for nothing")

-- The hunter's own claim, later than the forged one: it wins.
now = now + 10
local realSeq = now * 1000 + 2
hear(table.concat({ "K", hunter, realSeq, now, order, "", "" }, ";"), "Hunter-Realm")
o = contract()
assert(o.winner and o.winner.key == hunter .. ":" .. realSeq, "the claim heard from its hunter wins")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS bounty relay claim: a relayed claim cannot win a bounty, the hunter's own claim does")
