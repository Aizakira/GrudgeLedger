-- Security (25/11): a guild card dated 1970 used to take any player, and its name then blocked the
-- honest shared dossiers. A card naming a known player by another name is refused; among cards, the
-- right name and the most accounts voting come before the first published.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function() return 0 end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
local s = GL.Bounties.GuildScope()
local G = GL.GuildProfiles
local me = mock.units.player.guid
local function card(sender, target, digest, at, name)
    G.Receive(s, me, sender, table.concat({ "C", target, digest, at, ("%016x"):format(#sender), name }, ";"))
end
local function vote(sender, owner, target, digest, account)
    G.Receive(s, me, sender, table.concat({ "T", owner, target, digest, 1, now, account, "reliable", "1" }, ";"))
end
-- A player you know.
local known = GL.Remember(GL.IdentityFromName("Vrai", "Nom", "Player-1-known01"))
card("Player-1-honest", known.guid, ("%032x"):format(1), now, "Vrai Nom")
card("Player-1-cheat", known.guid, ("%032x"):format(2), 1, "Faux Nom")
local picked = G.ForTarget(known.guid)
assert(picked and picked.name == "Vrai Nom", "a card naming a known player by another name is refused")
-- A player you do not know: the voted card beats the backdated one.
local stranger = "Player-1-strang01"
card("Player-1-honest", stranger, ("%032x"):format(3), now, "Inconnu Reel")
vote("Player-1-honest", "Player-1-honest", stranger, ("%032x"):format(3), ("%016x"):format(1))
vote("Player-1-voter", "Player-1-honest", stranger, ("%032x"):format(3), ("%016x"):format(2))
card("Player-1-cheat", stranger, ("%032x"):format(4), 1, "Squat")
picked = G.ForTarget(stranger)
assert(picked and picked.name == "Inconnu Reel", "the card more accounts voted on wins: " .. tostring(picked and picked.name))
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS guild card backdated: wrong names refused, the voted card before the first published")
