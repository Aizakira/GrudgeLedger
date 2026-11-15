local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local now = 1000
GetServerTime = function() return now end
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()

local function identity(name)
    return GL.IdentityFromName(name, "Example", "Player-1-" .. name)
end
local function marked(name, relation)
    local id = identity(name)
    return id, GL.SetReaction(id, relation)
end
local function ranking(metric, expected)
    local rows = GL.PlayerStatistics(metric)
    assert(#rows == #expected, metric .. ": unexpected rows")
    for i, wanted in ipairs(expected) do
        assert(rows[i].record == wanted[1] and rows[i].value == wanted[2], metric .. ": incorrect rank " .. i)
    end
    return rows
end
for _, metric in ipairs({ "friendsRecent", "enemiesRecent", "friendsGrouped" }) do ranking(metric, {}) end
assert(not GL.RecordGroup(identity("Unknown"), "session-unknown", "Hurlevent"), "a group must not introduce strangers")

local alpha, a = marked("Alpha", "friend")
local beta, b = marked("Beta", "friend")
local enemy, e = marked("Enemy", "enemy")
local warning, w = marked("Warning", "warning")
local unseen, u = marked("Unseen", "friend")
local neutral = identity("GroupOnly")
local n = GL.Remember(neutral)
GL.RecordGroup(neutral, "neutral-session", "Hurlevent")
GL.RecordSeen(neutral, true)
assert(GL.IsGroupOnly(n), "legacy neutral group records stay excluded from relationship rankings")
GL.RecordSeen(alpha, true)
now = 2000 GL.RecordSeen(beta, true)
now = 3000 GL.RecordSeen(enemy, true)
now = 4000 GL.RecordSeen(warning, true)
ranking("friendsRecent", { { b, 2000 }, { a, 1000 } })
ranking("enemiesRecent", { { w, 4000 }, { e, 3000 } })
ranking("friendsGrouped", {})

now = 5000
GL.AddNote(alpha, "A manual note is not a sighting")
GL.RecordGroup(alpha, "session-one", "Hurlevent")
GL.RecordGroup(alpha, "session-one", "Hurlevent")
GL.RecordGroup(beta, "session-one", "Hurlevent")
GL.RecordGroup(enemy, "session-one", "Hurlevent")
assert(a.lastSeen == now and a.groupCount == 1)
ranking("friendsRecent", { { b, 2000 }, { a, 1000 } })
ranking("enemiesRecent", { { w, 4000 }, { e, 3000 } })
ranking("friendsGrouped", { { a, 1 }, { b, 1 } })

-- Observation timestamps cover every character; equal scores use the persistent key.
mock.units.player.guid = "Player-1-alt"
now = 6000 GL.RecordSeen(alpha, true) GL.RecordSeen(beta, true)
assert(a.encounters.seen["Player-1-self"] == 1000 and a.encounters.seen["Player-1-alt"] == 6000)
now = 7000 GL.RecordGroup(alpha, "session-two", "Hurlevent")
for i = 1, 3 do
    ranking("friendsRecent", { { a, 6000 }, { b, 6000 } })
    ranking("friendsGrouped", { { a, 2 }, { b, 1 } })
end

-- Legacy counts do not invent observation dates, including incomplete or corrupt timestamps.
u.encounters = { count = 12, since = 1 }
ranking("friendsRecent", { { a, 6000 }, { b, 6000 } })
u.encounters.seen = { text = "9000", negative = -1, zero = 0, infinite = math.huge, nan = 0 / 0 }
ranking("friendsRecent", { { a, 6000 }, { b, 6000 } })
ranking("friendsSeen", { { u, 12 }, { a, 2 }, { b, 2 } })

GL.SetReaction(alpha, "enemy")
ranking("friendsRecent", { { b, 6000 } })
ranking("friendsGrouped", { { b, 1 } })
ranking("enemiesRecent", { { a, 6000 }, { w, 4000 }, { e, 3000 } })
GL.SetReaction(alpha, "friend")
ranking("friendsGrouped", { { a, 2 }, { b, 1 } })

-- Reading rankings must not refresh lastSeen, normalize/repair data, or alter history and reputation.
local records = { a, b, e, w, u, n }
local before = {}
for _, r in ipairs(records) do
    before[r] = { r.lastSeen, r.reputation, r.groupCount, #r.history, r.encounters, r.encounters and r.encounters.seen }
end
now = 8000
local rows = ranking("friendsRecent", { { a, 6000 }, { b, 6000 } })
rows[1].value = -100
rows[1] = nil
ranking("friendsRecent", { { a, 6000 }, { b, 6000 } })
ranking("friendsGrouped", { { a, 2 }, { b, 1 } })
ranking("enemiesRecent", { { w, 4000 }, { e, 3000 } })
for _, r in ipairs(records) do
    local saved = before[r]
    assert(r.lastSeen == saved[1] and r.reputation == saved[2] and r.groupCount == saved[3] and #r.history == saved[4])
    assert(r.encounters == saved[5] and (r.encounters and r.encounters.seen) == saved[6])
end
assert(u.encounters.seen.text == "9000" and u.encounters.seen.infinite == math.huge, "ranking does not repair stored data")
assert(a.encounters.seen["Player-1-self"] == 1000 and a.encounters.seen["Player-1-alt"] == 6000)
print("PASS meaningful rankings: true observations, group sessions, current relations, legacy records, stable sorting and read-only behavior")
