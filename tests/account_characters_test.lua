-- Audit 24/11: the book is the account's, shared by all its characters. Another character of the
-- account is never "another member": its opinions, fights and deaths are already the account's.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me = mock.units.player.guid
local alt, member = "Player-1-alt", "Player-1-member"
GL.db.characterFactions[alt] = "Alliance"
assert(GL.OwnCharacter(me) and GL.OwnCharacter(alt) and not GL.OwnCharacter(member))
local s = GL.Bounties.GuildScope()
assert(s, "a guild space")
local target = "Player-1-target"

-- 1. Opinions: the alt's testimony on a target is the account's own, not a second member's.
s.socialReports = {
    [alt .. ":" .. target] = { actor = alt, target = target, seq = 1, at = now, received = now, score = -15, relation = "enemy", events = {} },
    [member .. ":" .. target] = { actor = member, target = target, seq = 1, at = now, received = now, score = -4, relation = "warning", events = {} },
}
GL.SharedDossiers.RefreshOpinions()
local opinion = GL.GuildOpinion(target)
assert(opinion and opinion.count == 1 and opinion.score == -4, "only the real member counts: " .. tostring(opinion and opinion.score))

-- 2. Guild map: the alt's fights are in the account's journal, the map must not add them again.
s.places = {
    [alt] = { table.concat({ now - 60, 1448, 400, 600, "d", target, "Cible" }, ";") },
    [member] = { table.concat({ now - 30, 1448, 400, 600, "d", target, "Cible" }, ";") },
}
GL.GuildMap.Enable(true)
local others, all = 0, 0
for _, point in ipairs(GL.GuildMap.Points()) do if point.actor == alt then others = others + 1 end end
for _, point in ipairs(GL.GuildMap.Points(true)) do if point.actor == alt then all = all + 1 end end
assert(others == 0 and all == 1, "the alt's fights: left out of the guild's, kept in the guild journal")
local killer = GL.GuildMap.Killer(target)
assert(killer and killer.deaths == 1 and killer.actor == member, "a guild killer counts real members only")

-- 3. Automatic bounty: three deaths of one account's characters are one victim.
GL.Bounties.ShareDeaths(true)
for _, actor in ipairs({ alt, member }) do
    local seq = (now - 120) * 1000 + #actor
    s.events[actor .. ":" .. seq] = table.concat({ "D", actor, seq, now - 120, target, "", "Cible" }, ";")
end
GL.Bounties.Death(target, "Cible")
local auto = false
for _, o in pairs(GL.Bounties.List()) do if o.target == target and o.auto then auto = true end end
assert(not auto, "two members (the account counted once) do not post an automatic bounty")

-- 4. Merging a name-only sheet keeps its duels and assists.
-- The GUID sheet exists, and a name-only sheet was kept apart (seen before its GUID was known).
local withGuid = GL.IdentityFromName("Duel", "Partner", "Player-1-duel")
local merged = GL.Remember(withGuid)
GL.db.aliases["name:duel partner"] = nil
local named = GL.IdentityFromName("Duel", "Partner")
GL.RecordDuel(named, true)
GL.RecordAssist(named)
assert(GL.db.players["name:duel partner"], "a separate name-only sheet")
merged = GL.Remember(withGuid)
assert(not GL.db.players["name:duel partner"], "merged into the GUID sheet")
assert(merged.duels and merged.duels.wins == 1, "duel wins survive the merge")
assert((tonumber(merged.assists) or 0) == 1, "assists survive the merge")

-- 5. Two namesakes, one deleted: the other gets its name back.
local first = GL.Remember(GL.IdentityFromName("Same", "Name", "Player-1-same1"))
local second = GL.Remember(GL.IdentityFromName("Same", "Name", "Player-1-same2"))
assert(GL.db.aliases["name:same name"] == false)
assert(GL.DeleteProfile(second))
assert(GL.db.aliases["name:same name"] == first.key, "the remaining namesake owns its name again")

-- 6. A note, an opinion or a tag written from the book is not a sighting (owner, 24/11).
local seen = GL.Remember(GL.IdentityFromName("Absent", "Player", "Player-1-absent"))
local seenAt = seen.lastSeen
now = now + 3600
GL.AddNote(seen, "Une note écrite plus tard.")
GL.SetReaction(seen, "warning")
assert(seen.lastSeen == seenAt, "editing the sheet does not date a new sighting")
GL.Remember(GL.IdentityFromName("Absent", "Player", "Player-1-absent"))
assert(seen.lastSeen == now, "a real observation does")

assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS account characters: alts' opinions, map fights, guild killers and deaths count as the account's; merged duels and assists; namesake alias released")
