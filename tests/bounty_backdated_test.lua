-- Security (25/11): a member posts a bounty dated a little before a real one on the same target.
-- A real bounty that other members put gold on keeps its target and its pledges.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me, cheat = mock.units.player.guid, "Player-1-cheat"
local roster = { { "Testeur-Realm", me, true }, { "Issuer-Realm", "Player-1-issuer", true }, { "Cheat-Realm", cheat, true } }
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return unpack({ [1] = roster[i][1], [9] = roster[i][3], [17] = roster[i][2] }, 1, 17) end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function() return 0 end
C_ChatInfo.InChatMessagingLockdown = function() return false end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
mock.Fire("GUILD_ROSTER_UPDATE")
local function hear(text, from) mock.Fire("CHAT_MSG_ADDON", "GLBounty1", text, "GUILD", from) end
local target = "Player-1-target01"
local realSeq = now * 1000 + 1
hear(table.concat({ "O", "Player-1-issuer", realSeq, now, target, 100000, "Cible" }, ";"), "Issuer-Realm")
local real = "Player-1-issuer:" .. realSeq
now = now + 30
-- You put gold on it.
assert(GL.Bounties.Pledge(real, 50000))
now = now + 30
-- The cheat's publication, dated five seconds before the real one.
hear(table.concat({ "O", cheat, (now - 65) * 1000 + 2, now - 65, target, 0, "Cible" }, ";"), "Cheat-Realm")
local list = GL.Bounties.List()
local fake = list[cheat .. ":" .. ((now - 65) * 1000 + 2)]
assert(list[real].state == "open" and not list[real].supersededBy, "the backed bounty keeps its target")
assert(fake and fake.supersededBy == real, "the backdated one is the one set aside")
assert(GL.Bounties.OpenFor(target).id == real)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS bounty backdated: a bounty backed by other members keeps its target against a backdated one")
