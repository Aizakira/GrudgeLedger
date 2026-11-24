-- Owner, 24/11: a payment mail that comes back to its payer unopened is owed again.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me, hunter = mock.units.player.guid, "Player-1-hunter"
local roster = { { "Testeur-Realm", me }, { "Hunter-Realm", hunter } }
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return unpack({ [1] = roster[i][1], [17] = roster[i][2] }, 1, 17) end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function() return 0 end
C_ChatInfo.InChatMessagingLockdown = function() return false end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
mock.Fire("GUILD_ROSTER_UPDATE")
local foe = GL.IdentityFromName("Target", "Example", "Player-1-target")
foe.faction = "Horde"
GL.Remember(foe)
local B = GL.Bounties
local order = assert(B.Post(foe.guid, foe.fullName, 50000))
now = now + 60
mock.Fire("CHAT_MSG_ADDON", "GLBounty1", table.concat({ "K", hunter, now * 1000, now, order, "", "" }, ";"), "GUILD", "Hunter-Realm")
local function owed() return B.Due(B.List()[order], me, hunter) end
assert(B.List()[order].winner and owed() == 50000, "the hunter won, the payer owes " .. tostring(owed()))
now = now + 60
assert(B.ConfirmPayment(order, hunter, 50000))
assert(owed() == 0, "the payment is on its way")
-- Thirty days later the mail comes back unopened.
now = now + 30 * 86400 - 3600
GetInboxNumItems = function() return 1 end
GetInboxHeaderInfo = function() return nil, nil, "Hunter", "[GL:" .. order .. "/0] Target Example", 50000, 0, nil, nil, nil, true end
mock.Fire("MAIL_INBOX_UPDATE")
assert(owed() == 50000, "a returned payment is owed again: " .. tostring(owed()))
mock.Fire("MAIL_INBOX_UPDATE")
assert(owed() == 50000, "the same returned mail is counted once")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS bounty returned mail: a payment returned unopened is owed again, once")
