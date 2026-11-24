-- Owner, 24/11: tags belong to the account, guild votes count once per account. Removing a tag from
-- a second character withdraws the account's vote: the guild stops counting it.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function() return 0 end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
local G = GL.GuildProfiles
local main = mock.units.player.guid
local record = GL.Remember(GL.IdentityFromName("Tagged", "Player", "Player-1-tagged"))
local card = assert(G.Publish(record), "a guild card")
assert(G.SetTag(card, "toxic", true))
local _, counts = G.View(card)
assert(counts.toxic == 1, "the main's vote counts")
-- The alt, same account and guild, removes the tag.
now = now + 60
GL.db.characterFactions[main] = "Alliance"
mock.units.player.guid, mock.units.player.name = "Player-1-alt", "Second"
assert(G.SetTag(card, "toxic", false), "the alt can withdraw the account's vote")
_, counts = G.View(card)
assert((counts.toxic or 0) == 0, "the account's latest vote decides: " .. tostring(counts.toxic))
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS guild tags and alts: the account's latest vote decides, from any of its characters")
