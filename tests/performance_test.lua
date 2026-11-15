-- Operation counts, not wall-clock thresholds: deterministic on slow/fast CI hosts.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local clock, reads = 100, 0
GetTime = function() return clock end
local unitName = UnitName
UnitName = function(unit) reads = reads + 1 return unitName(unit) end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
local target = mock.units.target
local first = GL.Identity("target", true)
for i = 1, 100 do assert(GL.Identity("target", true) == first) end
assert(reads == 1, "polls reuse metadata within half a second")
mock.units.nameplate1 = target
assert(GL.Identity("nameplate1", true) == first and reads == 1, "aliases share a live GUID")
target.guild = "New Guild"
assert(GL.Identity("target").guild == "New Guild" and reads == 2, "actions bypass the polling cache")
clock = 100.499
GL.Identity("target", true) assert(reads == 2)
clock = 100.5
GL.Identity("target", true) assert(reads == 3, "exact expiry reads fresh metadata")
clock = 90
GL.Identity("target", true) assert(reads == 4, "a backward clock cannot prolong stale data")
mock.units.target = {name="Other", surname="Example", guid="Player-1-other"}
assert(GL.Identity("target", true).name == "Other" and reads == 5, "recycled token must not reuse previous player")
mock.units.target = nil
assert(GL.Identity("target", true) == nil and reads == 5, "disappeared unit cannot reappear from cache")
mock.units.target = target
target.guid = mock.secret
assert(not GL.Identity("target", true).guid and reads == 6, "unreadable GUID cannot hit cache")
target.guid = "Player-1-aqua"
clock = 101
target.name = mock.secret
assert(GL.Identity("target", true) == nil)
target.name = "Aqua"
assert(GL.Identity("target", true).name == "Aqua", "a failed fresh read must be retryable")
GL.InitDB()
local before = reads
GL.Identity("target", true) assert(reads == before + 1, "reload invalidates session metadata")
for i = 1, 256 do
    mock.units.other = {name="Visitor" .. i, surname="Example", guid="Player-1-visitor" .. i}
    GL.Identity("other", true)
end
before = reads
GL.Identity("target", true)
assert(reads == before + 1, "metadata cache is bounded even when the clock does not advance")
for _, value in ipairs({mock.secret, -1, math.huge, 0/0}) do
    GetTime = function() return value end
    before = reads
    GL.Identity("target", true) GL.Identity("target", true)
    assert(reads == before + 2, "invalid/protected clocks fall back to fresh reads")
end
GetTime = nil
before = reads
GL.Identity("target", true) GL.Identity("target", true)
assert(reads == before + 2, "missing clock preserves uncached operation")

-- Cached guild aggregates must reflect every supported mutation, without replay on a sighting.
local function identity(name, guild)
    local id = GL.IdentityFromName(name, "Example", "Player-1-" .. name)
    id.guild, id.realm = guild, "Forever"
    return id
end
local function guild(name)
    for _, row in ipairs(GL.GuildStatistics()) do if row.name == name then return row end end
end
local id = identity("GuildMember", "First Guild")
local record = GL.RecordPvP(id, "death", "confirmed", "test", "death1")
assert(guild("First Guild").deaths == 1)
local scans, nativeIpairs = 0, ipairs
ipairs = function(value)
    if value == record.history then scans = scans + 1 end
    return nativeIpairs(value)
end
for i = 1, 30 do GL.RecordSeen(id, true) assert(guild("First Guild").deaths == 1) end
assert(scans == 0, "unchanged guild totals must not replay PvP history")
ipairs = nativeIpairs
local copy = guild("First Guild")
copy.deaths, copy.name = 999, "Modified"
assert(guild("First Guild").deaths == 1, "callers cannot mutate cached rows")
GL.SetReaction(id, "friend") assert(guild("First Guild").friends == 1)
GL.AdjustReputation(id, -20, "opinion", "manual") assert(guild("First Guild").grudges == 1)
GL.VoidPvP(id, record.history[1], true) assert(guild("First Guild").deaths == 0)
GL.RecordAggression(id, "confirmed", "test", "aggression1") assert(guild("First Guild").aggressions == 1)
GL.RecordPvP(id, "kill", "confirmed", "test", "kill1") assert(guild("First Guild").kills == 1)
id.guild = "Second Guild"
GL.Remember(id)
assert(guild("Second Guild").members == 1 and guild("First Guild").members == 0)
id.guild, id.guildKnown = nil, true
GL.Remember(id) assert(guild("Second Guild") == nil, "explicit departure invalidates guild membership")
local groupId = identity("GroupOnly", "Group Guild")
local group = GL.Remember(groupId)
group.groupCount, group.history = 1, {{kind="group"}}
assert(guild("Group Guild") == nil)
GL.AddNote(groupId, "Worth remembering")
assert(guild("Group Guild").members == 1, "a note makes group-only records personal")
GL.SetGuildReaction("Rule Only", "warning") assert(guild("Rule Only").members == 0)
GL.InitDB() assert(guild("First Guild").kills == 1, "reload reconstructs derived statistics")

local alias = GL.IdentityFromName("Merged", "Example")
alias.guild, alias.realm = "Merge Guild", "Forever"
GL.AdjustReputation(alias, -1, "SPIT", "emote")
local live = GL.IdentityFromName("Short", nil, "Player-1-merged")
live.guild, live.realm = alias.guild, alias.realm
GL.RecordPvP(live, "death", "confirmed", "test", "merge-death")
assert(guild("Merge Guild").members == 2)
live.name, live.surname = "Merged", "Example"
local merged = GL.Remember(live)
assert(merged.reputation == -11 and guild("Merge Guild").members == 1
    and guild("Merge Guild").deaths == 1, "identity merge invalidates both cached totals")

-- Large social history: new opinions scan only the new tail, not old events.
local socialId = identity("Social", nil)
local social = GL.Remember(socialId)
social.reactionSource = "emote"
local eventReads = 0
for i = 1, 1000 do
    social.history[i] = setmetatable({}, {__index=function(_, key)
        eventReads = eventReads + 1
        return ({kind="reputation", source="emote", delta=1})[key]
    end})
end
GL.AdjustReputation(socialId, -1, "SPIT", "emote")
assert(eventReads > 0 and social.reputation == 100)
eventReads = 0
GL.AdjustReputation(socialId, -1, "SPIT", "emote")
assert(eventReads == 0, "appending an opinion must not reread the old social history")
social.history = {{kind="reputation", source="emote", delta=-3}}
GL.AdjustReputation(socialId, 1, "KISS", "emote")
assert(social.reputation == -2, "replacing history cannot reuse an unrelated subtotal")
table.remove(social.history)
GL.SetReaction(socialId, "neutral")
assert(social.reputation == -3, "truncated history is rebuilt")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS performance contracts: bounded GUID cache, fresh actions, expiry, secret/missing APIs, guild invalidation/copies and incremental social totals")
