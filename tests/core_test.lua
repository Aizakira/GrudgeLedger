local now = 1000
time = function() return now end
GetRealZoneText = function() return "Hurlevent" end
CreateFrame = function() return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end } end
local secret = setmetatable({}, { __eq = function() error("secret compared") end, __tostring = function() error("secret printed") end })
issecretvalue = function(v) return rawequal(v, secret) end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
assert(GL.Clean(secret) == nil)
assert(GL.Safe(function() return secret, "safe" end) == nil)
assert(GL.IdentityFromName("Dupont", nil, nil) == nil, "unknown surnames must not merge")
assert(GL.IdentityFromName("|Hplayer:bad", "Name") == nil)
local a = GL.IdentityFromName("Alex", "One")
local b = GL.IdentityFromName("Alex", "Two", "Player-1-222")
assert(a.key ~= b.key)
GL.SetReaction(a, "friend")
assert(GL.AddNote(a, "Super donjon, personne sympa."))
local liveA = GL.IdentityFromName("Alex", "One", "Player-1-111")
local promoted = GL.Remember(liveA)
assert(promoted.reaction == "friend" and #promoted.notes == 1)
assert(GL.db.players[a.key] == nil and GL.Get(a) == promoted)
GL.SetReaction(b, "enemy")
assert(GL.Get(b) ~= promoted)
local clone = GL.IdentityFromName("Alex", "One", "Player-1-333")
GL.Remember(clone)
assert(GL.Get(clone) ~= promoted and GL.Get(a) == nil, "ambiguous full names must not resolve arbitrarily")
assert(GL.SetReaction(a, "enemy") == nil, "an ambiguous chat identity must not mark the wrong player")
assert(GL.Relation(promoted) == "friend")
assert(GL.RecordPvP(liveA, "death", "confirmed", "recent target", "fight-1"))
assert(GL.RecordPvP(liveA, "death", "confirmed", "duplicate", "fight-1") == nil)
assert(promoted.pvp.deaths == 1)
assert(GL.Relation(promoted) == "friend", "manual friend survives PvP inference")
local c = GL.IdentityFromName("Enemy", "Surname", "Player-1-444")
GL.RecordPvP(c, "death", "confirmed", "targeting player", "fight-2")
assert(GL.Relation(GL.Get(c)) == "enemy")
GL.SetReaction(c, "neutral")
GL.RecordPvP(c, "death", "confirmed", "combat log", "fight-3")
assert(GL.Relation(GL.Get(c)) == "enemy" and GL.Get(c).reputation == -20)
assert(GL.Get(c).pvp.deaths == 2)
assert(GL.RecordPvP(c, "kill", "certain", "bad") == nil)
assert(GL.SetReaction(c, "bad") == nil)
assert(not GL.AddNote(c, "   ") and not GL.AddNote(c, string.rep("a", 2001)))
GL.RecordGroup(b, "session-1", "Donjon")
GL.RecordGroup(b, "session-1", "Donjon")
assert(GL.Get(b).groupCount == 1)
GL.RecordGroup(b, "session-2", "Donjon")
assert(GL.Get(b).groupCount == 2)
local rosterOnly = GL.Remember(GL.IdentityFromName("Old", "Roster", "Player-1-oldroster"))
rosterOnly.groupCount, rosterOnly.history = 2, { { kind = "grouped", sessionId = "old-session" } }
assert(GL.IsGroupOnly(rosterOnly) and not GL.IsGroupOnly(GL.Get(b)))
for field, value in pairs({ reaction = "neutral", reputation = 1, notes = { { text = "Keep this note" } },
    pvp = { kills = 1 }, history = { { kind = "death", voided = true } } }) do
    local old = rosterOnly[field]
    rosterOnly[field] = value
    assert(not GL.IsGroupOnly(rosterOnly), "meaningful data must survive the group-only filter: " .. field)
    rosterOnly[field] = old
end
rosterOnly.guild, rosterOnly.realm = "Marked Guild", "Forever"
GL.SetGuildReaction("Marked Guild", "enemy", nil, "Forever")
assert(not GL.IsGroupOnly(rosterOnly), "guild opinions also qualify for the journal")
rosterOnly.guild = nil
GL.InitDB()
assert(GL.IsGroupOnly(GL.Get(rosterOnly)) and GL.Get(rosterOnly).groupCount == 2,
    "legacy group-only entries remain stored without losing history")
assert(not GL.SetSetting("sounds", "true"))
assert(GL.SetSetting("alertCooldown", 0) and GL.Settings().alertCooldown == 15)
assert(GL.SetSetting("minimapAngle", 370) and GL.Settings().minimapAngle == 10)
assert(not GL.SetSetting("iconSize", 0/0))
local saved = GrudgeLedgerDB
now = 2000
GL.InitDB()
assert(GrudgeLedgerDB == saved and GL.Get(liveA).notes[1].text == "Super donjon, personne sympa.")
assert(GL.Get(c).pvp.deaths == 2 and GL.Relation(GL.Get(c)) == "enemy" and GL.Get(c).reputation == -20)
GL.On("BROKEN", function() error("test callback") end)
GL.Emit("BROKEN")
assert(#GL.errors == 1 and GL.errors[1].text:find("test callback"))
local changed = 0
GL.On("CHANGED", function() changed = changed + 1 end)
GL.RecordSeen(liveA)
assert(changed == 0 and GL.Get(liveA).lastSeen == 2000, "sighting must not cause change loops")
local chat = GL.IdentityFromName("Chat", "Friend")
GL.AddNote(chat, "Rencontré dans le chat.")
local sighting = GL.IdentityFromName("Chat", "Friend", "Player-1-555")
sighting.class = "MAGE"
local found = GL.RecordSeen(sighting)
assert(found.guid == sighting.guid and found.class == "MAGE" and #found.notes == 1)
assert(GL.db.players[chat.key] == nil and GL.Get(chat) == found)
GL.Remember(GL.IdentityFromName("Chat", nil, "Player-1-555"))
assert(found.fullName == "Chat Friend" and found.surname == "Friend", "partial identity must not erase known surname")
assert(GL.RecordSeen(GL.IdentityFromName("Unknown", "Stranger", "Player-1-666")) == nil)
GL.db.players.invalid = 42
GL.InitDB()
assert(GL.db.players.invalid == nil and GL.db.quarantine.invalid == 42)
local aggressor = GL.IdentityFromName("Aggressor", "Enemy", "Player-1-777")
GL.RecordAggression(aggressor, "confirmed", "Health drop during duel-free hostile encounter", "attack-1")
GL.RecordAggression(aggressor, "confirmed", "duplicate", "attack-1")
local ra = GL.Get(aggressor)
assert(ra.pvp.aggressions == 1 and GL.Relation(ra) == "enemy")
GL.RecordPvP(aggressor, "death", "confirmed", "Targeting victim", "death-777")
assert(GL.Relation(ra) == "enemy" and ra.reputation <= -10)
GL.SetReaction(aggressor, "friend")
GL.RecordAggression(aggressor, "confirmed", "damage", "attack-2")
assert(GL.Relation(ra) == "friend" and ra.reputation == 1)
GL.AdjustReputation(aggressor, -1, "Avis personnel", "manual")
assert(GL.Relation(ra) == "neutral" and ra.reputation == 0)
GL.AdjustReputation(aggressor, -1, "Avis personnel", "manual")
assert(GL.Relation(ra) == "warning" and ra.reputation == -1)
GL.AdjustReputation(aggressor, -9, "Mauvais comportement", "manual")
assert(GL.Relation(ra) == "enemy" and ra.reputation == -10)
local hordeFriend = GL.IdentityFromName("Nice", "Horde", "Player-1-888")
GL.AdjustReputation(hordeFriend, 1, "Emote KISS", "emote")
assert(GL.Relation(GL.Get(hordeFriend)) == "friend")
GL.AdjustReputation(hordeFriend, 1000, "Bounded", "manual")
assert(GL.Get(hordeFriend).reputation == 100)
assert(GL.AdjustReputation(hordeFriend, 0/0) == nil)
local serialKiller = GL.IdentityFromName("Repeated", "Enemy", "Player-1-999")
for i = 1, 11 do GL.RecordPvP(serialKiller, "death", "confirmed", "Observed", "repeat-" .. i) end
assert(GL.Get(serialKiller).reputation == -100)
GL.AdjustReputation(serialKiller, 1, "One positive", "manual")
assert(GL.Get(serialKiller).reputation == -99)
local guildMember = GL.IdentityFromName("Guild", "Member", "Player-1-guild")
guildMember.guild, guildMember.realm, guildMember.guildKnown = "Test Guild", "Realm One", true
GL.SetGuildReaction("Test Guild", "warning", "Guilde à éviter.", "Realm One")
local member = GL.RecordSeen(guildMember)
assert(member and GL.Relation(member) == "warning" and GL.RelationSource(member) == "guild")
assert(GL.GetGuildRule("Test Guild", "Realm Two") == nil, "guilds are realm-scoped")
GL.SetGuildReaction(guildMember, "enemy")
assert(GL.Relation(member) == "enemy")
GL.SetReaction(guildMember, "friend")
assert(GL.Relation(member) == "friend" and GL.RelationSource(member) == "manual")
member.reaction = nil
guildMember.guild = nil
GL.RecordSeen(guildMember)
assert(member.guild == nil and GL.Relation(member) == "neutral", "leaving guild clears inherited marker")
guildMember.guild = "Test Guild"
GL.RecordSeen(guildMember)
GL.InitDB()
assert(GL.Relation(member) == "enemy" and GL.GetGuildRule("test guild", "Realm One").note == "Guilde à éviter.")
print("PASS guild and scoring: shared rules, realm isolation, manual exceptions, membership changes, persistence, bounded score")

local guildAlias = GL.IdentityFromName("GuildMerge", "Example")
guildAlias.guild, guildAlias.realm = "Historic Guild", "Other Realm"
local guildProvisional = GL.RecordPvP(guildAlias, "death", "confirmed", "Observed", "guild-merge-death")
local guildGuid = GL.IdentityFromName("GuildMerge", nil, "Player-1-guildmerge")
GL.Remember(guildGuid)
guildGuid = GL.IdentityFromName("GuildMerge", "Example", "Player-1-guildmerge")
local guildMerged = GL.Remember(guildGuid)
assert(guildMerged.guild == "Historic Guild" and guildMerged.realm == "Other Realm")
assert(guildMerged.history[1].guild == "Historic Guild" and guildMerged.history[1].guildObservedAt == now)
assert(GL.VoidPvP(guildMerged, guildMerged.history[1]) and guildMerged.history[1].guild == "Historic Guild")
assert(GL.RecordPvP(guildGuid, "death", "confirmed", "Duplicate", "guild-merge-death") == nil)
GL.InitDB()
assert(GL.Get(guildGuid).history[1].voided and GL.Get(guildGuid).guild == "Historic Guild")
print("PASS core: identity collisions, promotion, notes, persistence, manual priority, counters, dedup, settings and secrets")

-- Correcting an attribution removes its effects, not its history or dedup identity.
local correction = GL.IdentityFromName("Correction", "Example", "Player-1-correction")
local r = GL.RecordAggression(correction, "confirmed", "Observed health drop", "correction-a")
local attack = r.history[#r.history]
assert(GL.RelationConfidence(r) == "confirmed")
GL.RecordAggression(correction, "confirmed", "Damage log", "correction-b")
local confirmedAttack = r.history[#r.history]
assert(GL.RelationConfidence(r) == "confirmed")
GL.RecordPvP(correction, "death", "confirmed", "Recent enemy", "correction-c")
local death = r.history[#r.history]
assert(GL.Relation(r) == "enemy" and GL.RelationConfidence(r) == "confirmed", "confirmed aggression is not a confirmed killer")
GL.RecordPvP(correction, "death", "confirmed", "Fatal log", "correction-d")
local confirmedDeath = r.history[#r.history]
assert(GL.RelationConfidence(r) == "confirmed")
local countBefore, lastSeen = #r.history, r.lastSeen
now = now + 10
changed = 0
assert(GL.VoidPvP(correction, confirmedDeath))
assert(changed == 1 and r.lastSeen == lastSeen, "correction refreshes views, never records a sighting")
assert(confirmedDeath.voided and confirmedDeath.voidedAt == now and confirmedDeath.evidence == "Fatal log")
assert(r.pvp.deaths == 1 and #r.history == countBefore and r.reputation == -12)
assert(GL.RelationConfidence(r) == "confirmed")
assert(not GL.VoidPvP(correction, confirmedDeath) and not GL.VoidPvP(b, death))
assert(not GL.VoidPvP(correction, {kind = "death", confidence = "confirmed"}))
assert(not GL.VoidPvP(correction, "wrong type"))
assert(GL.RecordPvP(correction, "death", "confirmed", "repeat", "correction-d") == nil)
assert(GL.VoidPvP(correction, death) and GL.Relation(r) == "enemy" and r.reputation == -2)
assert(GL.VoidPvP(correction, confirmedAttack) and GL.RelationConfidence(r) == "confirmed")
assert(GL.VoidPvP(correction, attack) and GL.Relation(r) == "neutral" and r.reputation == 0)
assert(GL.RelationConfidence(r) == nil)
assert(GL.RecordAggression(correction, "confirmed", "repeat", "correction-a") == nil)
GL.RecordPvP(correction, "kill", "confirmed", "Target died", "correction-kill")
local victory = r.history[#r.history]
assert(GL.VoidPvP(correction, victory) and r.pvp.probableKills == nil)
GL.RecordPvP(correction, "kill", "confirmed", "PARTY_KILL", "correction-confirmed-kill")
assert(GL.VoidPvP(correction, r.history[#r.history]) and r.pvp.kills == 0)
GL.SetReaction(correction, "friend")
assert(GL.RelationConfidence(r) == nil)
local manual = r.history[#r.history]
assert(not GL.VoidPvP(correction, manual))
GL.RecordPvP(correction, "death", "confirmed", "Ambiguous", "correction-manual")
assert(GL.VoidPvP(correction, r.history[#r.history]) and r.reputation == 1 and GL.Relation(r) == "friend")
-- On 0.1.0 databases events lack new metadata; they are still correctable after reload.
r.reaction = nil
r.guild, r.realm = "Test Guild", "Realm One"
GL.RecordPvP(correction, "death", "confirmed", "Wrong enemy", "correction-guild")
assert(GL.RelationSource(r) == "pvp")
assert(GL.VoidPvP(correction, r.history[#r.history]))
assert(GL.RelationSource(r) == "guild" and GL.RelationConfidence(r) == nil)
GL.InitDB()
assert(confirmedDeath.voided and r.pvp.deaths == 0)
-- Recompute from active counters instead of adding 10 back to a saturated score.
serialKiller = GL.IdentityFromName("Capped", "Enemy", "Player-1-capped")
for i = 1, 11 do GL.RecordPvP(serialKiller, "death", "confirmed", "Observed", "capped-" .. i) end
local capped = GL.Get(serialKiller)
assert(GL.VoidPvP(serialKiller, capped.history[1]) and capped.reputation == -100)
assert(GL.VoidPvP(serialKiller, capped.history[2]) and capped.reputation == -90)
-- A gesture changes camaraderie but cannot pin a killer to orange forever.
local spit = GL.IdentityFromName("Gesture", "Enemy", "Player-1-gesture")
local gesture = GL.AdjustReputation(spit, -1, "SPIT", "emote")
assert(GL.Relation(gesture) == "warning" and GL.RelationSource(gesture) == "emote")
GL.RecordAggression(spit, "confirmed", "Damage", "gesture-attack")
local gestureAttack = gesture.history[#gesture.history]
GL.RecordPvP(spit, "death", "confirmed", "Participation", "gesture-death")
assert(GL.Relation(gesture) == "enemy" and GL.RelationConfidence(gesture) == "confirmed")
assert(GL.VoidPvP(spit, gesture.history[#gesture.history]))
assert(GL.Relation(gesture) == "enemy" and GL.RelationSource(gesture) == "pvp")
assert(GL.VoidPvP(spit, gestureAttack))
assert(GL.RelationSource(gesture) == "emote" and gesture.reputation == -1)
-- An identical explicit choice still pins the relationship intentionally.
GL.SetReaction(spit, "warning")
GL.RecordPvP(spit, "death", "confirmed", "Damage", "gesture-manual-death")
assert(GL.Relation(gesture) == "warning" and GL.RelationSource(gesture) == "manual")
local legacy = GL.IdentityFromName("Legacy", "Gesture", "Player-1-legacy-gesture")
local legacyGesture = GL.AdjustReputation(legacy, -1, "SPIT", "emote")
legacyGesture.reactionSource = nil -- pre-0.2.7 database
GL.AddNote(legacy, "Keep this note")
GL.InitDB()
assert(legacyGesture.reactionSource == "emote" and legacyGesture.notes[1].text == "Keep this note")
GL.RecordPvP(legacy, "death", "confirmed", "Lethal", "legacy-death")
assert(GL.Relation(legacyGesture) == "enemy")
local explicit = GL.SetReaction(GL.IdentityFromName("Legacy", "Manual", "Player-1-legacy-manual"), "neutral")
explicit.reactionSource, explicit.history = nil, {}
GL.InitDB()
GL.RecordPvP(explicit, "death", "confirmed", "Participation", "legacy-manual-death")
assert(GL.Relation(explicit) == "enemy" and explicit.reactionSource == "automatic")
local aliasGesture = GL.IdentityFromName("Merge", "Gesture")
GL.AdjustReputation(aliasGesture, 1, "KISS", "emote")
local fullGesture = GL.IdentityFromName("Merge", "Gesture", "Player-1-merge-gesture")
GL.Remember(GL.IdentityFromName("Merge", nil, fullGesture.guid))
local mergedGesture = GL.Remember(fullGesture)
assert(mergedGesture.reactionSource == "emote" and GL.Relation(mergedGesture) == "friend")
GL.RecordAggression(fullGesture, "confirmed", "Damage", "merge-attack")
assert(GL.Relation(mergedGesture) == "enemy")
local pinned = GL.IdentityFromName("Pinned", "Friend", "Player-1-pinned-friend")
local pinnedFriend = GL.SetReaction(pinned, "friend")
GL.AdjustReputation(pinned, 1, "KISS", "emote")
GL.RecordPvP(pinned, "death", "confirmed", "Damage", "pinned-death")
assert(GL.Relation(pinnedFriend) == "friend" and pinnedFriend.reactionSource == "manual")
-- Legacy manual pins survive migration even when an emote was sent later.
pinnedFriend.reactionSource = nil
GL.InitDB()
assert(GL.Relation(pinnedFriend) == "friend" and pinnedFriend.reactionSource == "manual")
local aliasManual = GL.IdentityFromName("Merge", "Pinned")
GL.SetReaction(aliasManual, "friend")
local guidManual = GL.IdentityFromName("Merge", "Pinned", "Player-1-merge-pinned")
GL.AdjustReputation(GL.IdentityFromName("Merge", nil, guidManual.guid), -1, "SPIT", "emote")
local mergedManual = GL.Remember(guidManual)
assert(mergedManual.reactionSource == "manual" and GL.Relation(mergedManual) == "friend" and mergedManual.reputation == 1)
GL.RecordPvP(guidManual, "death", "confirmed", "Damage", "merged-manual-death")
assert(GL.Relation(mergedManual) == "friend")
local function serialize(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local fields = {}
    for key, item in pairs(value) do fields[#fields + 1] = "[" .. serialize(key) .. "]=" .. serialize(item) end
    return "{" .. table.concat(fields, ",") .. "}"
end
local savedText = serialize(GrudgeLedgerDB)
GrudgeLedgerDB = assert(loadstring("return " .. savedText))()
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local reloaded = GrudgeLedger
reloaded.InitDB()
local restored = reloaded.Get(correction)
assert(restored ~= r and restored.history[1].voided and restored.history[1].evidence == "Observed health drop")
assert(restored.pvp.probableAggressions == nil and restored.pvp.probableDeaths == nil)
assert(reloaded.RecordAggression(correction, "confirmed", "Duplicate after reload", "correction-a") == nil)
assert(reloaded.Get(serialKiller).reputation == -90)
assert(reloaded.Get(legacy).reactionSource == "emote" and reloaded.Relation(reloaded.Get(legacy)) == "enemy")
assert(reloaded.Relation(reloaded.Get(spit)) == "warning" and reloaded.Get(spit).reactionSource == "manual")
print("PASS PvP corrections: confidence, six counters, immutable evidence, dedup, ownership, manual/guild precedence, persistence and saturation")
