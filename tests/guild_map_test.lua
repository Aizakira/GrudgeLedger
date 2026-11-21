-- Guild vision of the map (0.49.0), with several real clients on a simulated wire.
-- One short message a fight; only members who ticked the box keep what they hear; a place is only
-- accepted from the member it is about; unticking makes the guild forget.
local clients, wire, now = {}, {}, 1800000000
local function client(i)
    local env = setmetatable({ _G = false }, { __index = _G })
    env._G = env
    env.loadfile = function(p) return setfenv(assert(loadfile(p)), env) end
    local mock = env.loadfile(TEST_WORK .. "/tests/addon_mock.lua")()
    local c = { env = env, GL = env.GrudgeLedger, m = mock, id = "Player-1-a" .. i, name = "Member" .. i .. "-Realm", guild = "Guild", log = {} }
    clients[i] = c
    mock.units.player = { guid = c.id, name = "Member" .. i, surname = "Example", guild = c.guild, realm = "Realm" }
    env.GetServerTime = function() return now end
    env.GetNormalizedRealmName = function() return "Realm" end
    env.GetNumGuildMembers = function() return #clients end
    env.GetGuildRosterInfo = function(index)
        local p = clients[index]
        local info = { [1] = p.name, [17] = p.id }
        return unpack(info, 1, 17)
    end
    env.IsInInstance = function() return c.instance == true end
    c.x, c.y = 0.5124, 0.2876
    env.C_Map = {
        GetBestMapForUnit = function() return 1446 end,
        GetPlayerMapPosition = function() return { GetXY = function() return c.x, c.y end } end,
    }
    env.C_ChatInfo.RegisterAddonMessagePrefix = function() end
    env.C_ChatInfo.InChatMessagingLockdown = function() return false end
    env.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel)
        assert(#msg <= 255, "addon message over 255 bytes")
        c.log[#c.log + 1] = msg
        wire[#wire + 1] = { prefix, msg, channel, c.name, c.guild }
        return 0
    end
    env.C_Timer = { NewTicker = function(delay, fn)
        if delay == 0.5 then c.tick = fn end
        return { Cancel = function() end }
    end }
    mock.Fire("PLAYER_LOGIN")
    for _, p in ipairs(clients) do p.m.Fire("GUILD_ROSTER_UPDATE") end
    return c
end
local function waiting()
    for _, p in ipairs(clients) do
        local urgent, bulk = p.GL.Transport.Pending(p.GL.Bounties.GuildScope())
        if urgent + bulk > 0 then return true end
    end
    return false
end
local function flush()
    for _ = 1, 3000 do
        now = now + 1
        for _, p in ipairs(clients) do p.tick() end
        local packets = wire
        wire = {}
        for _, m in ipairs(packets) do
            for _, p in ipairs(clients) do p.m.Fire("CHAT_MSG_ADDON", unpack(m, 1, 4)) end
        end
        if #wire == 0 and not waiting() then return end
    end
    error("guild traffic did not settle")
end
local function sentAbout(c, pattern)
    local count = 0
    for _, msg in ipairs(c.log) do
        if msg:find(pattern) then count = count + 1 end
    end
    return count
end
local a, b, intruder = client(1), client(2), client(3)
flush()
local A, B = a.GL.GuildMap, b.GL.GuildMap

-- Off by default: a fight sends nothing, and nothing is kept.
assert(select(1, A.Enabled()) == false and select(2, A.Enabled()) == true)
assert(A.Fight("k") == false and sentAbout(a, "^M") == 0 and #A.Points() == 0)

-- One member ticks the box: their fight goes out, but a member who did not tick keeps nothing.
assert(A.Enable(true) == true and A.Enabled() == true)
flush()
now = now + 10
assert(A.Fight("k") == true)
flush()
assert(sentAbout(a, "^M;1;Player%-1%-a1;%d+;1446;512;288;k$") == 1, a.log[#a.log])
assert(b.GL.Bounties.GuildScope().places == nil and #B.Points() == 0, "unticked: nothing kept")

-- The second member ticks it: they ask, the first answers with their latest places.
assert(B.Enable(true) == true)
flush()
local seen = B.Points()
assert(#seen == 1 and seen[1].actor == a.id and seen[1].kind == "kill" and seen[1].mapID == 1446, #seen)
assert(math.abs(seen[1].x - 0.512) < 0.0001 and math.abs(seen[1].y - 0.288) < 0.0001)
assert(#A.Points() == 0, "your own fights come from your journal, not from the guild")

-- A death of the second member reaches the first, through the real hook of a recorded death.
now = now + 20
b.x, b.y = 0.25, 0.75
b.GL.Bounties.Death("Player-1-enemy01", "Enemy")
flush()
seen = A.Points()
assert(#seen == 1 and seen[1].actor == b.id and seen[1].kind == "death" and math.abs(seen[1].x - 0.25) < 0.0001, #seen)
-- Nothing leaves from an instance.
b.instance = true
assert(B.Fight("k") == false)
b.instance = nil

-- A place is only accepted from the member it is about: a forged one, a relay and nonsense are refused.
local forged = intruder.GL.Bounties.GuildScope()
local T = intruder.GL.Transport
T.Send(forged, "M;1;" .. b.id .. ";" .. now .. ";1446;100;100;d")
T.Send(forged, "R;M;1;" .. intruder.id .. ";" .. now .. ";1446;100;100;d")
T.Send(forged, "M;1;" .. intruder.id .. ";" .. now .. ";1446;5000;100;d")
T.Send(forged, "M;1;" .. intruder.id .. ";" .. (now + 4000) .. ";1446;100;100;d")
T.Send(forged, "M;1;" .. intruder.id .. ";" .. (now - 40 * 86400) .. ";1446;100;100;d")
T.Send(forged, "M;2;" .. intruder.id .. ";" .. now .. ";1446;100;100;d")
T.Send(forged, "M;1;" .. intruder.id .. ";" .. now .. ";1446;100;100;x")
flush()
assert(#A.Points() == 1 and #B.Points() == 1, "forged places refused")
-- A well-formed one from a member who shares nothing themselves is still what that member chose to
-- send: it is kept, bounded like the rest.
T.Send(forged, "M;1;" .. intruder.id .. ";" .. now .. ";1446;100;100;d")
flush()
assert(#A.Points() == 2 and #B.Points() == 2)

-- Bounded: forty places a member, the latest.
for i = 1, 45 do
    now = now + 2
    a.x = 0.1 + i / 100
    assert(A.Fight("d") == true)
end
flush()
local fromA = 0
for _, point in ipairs(B.Points()) do
    if point.actor == a.id then fromA = fromA + 1 end
end
assert(fromA == 40 and #b.GL.Bounties.GuildScope().places[a.id] == 40, fromA)
assert(math.abs(B.Points()[1].x - 0.55) < 0.0001, "the latest first")

-- A member who logs in asks for a catch-up: each sharing member answers with fifteen places, no more.
local before = sentAbout(a, "^M;1;")
b.GL.Bounties.GuildScope().places = nil
b.GL.Transport.Send(b.GL.Bounties.GuildScope(), "MQ")
now = now + 40
flush()
assert(sentAbout(a, "^M;1;") - before == 15, sentAbout(a, "^M;1;") - before)
-- The same question twice in a row is answered once.
before = sentAbout(a, "^M;1;")
b.GL.Transport.Send(b.GL.Bounties.GuildScope(), "MQ")
flush()
b.GL.Transport.Send(b.GL.Bounties.GuildScope(), "Q")
flush()
assert(sentAbout(a, "^M;1;") - before == 15, "one answer to MQ, and the login catch-up carries them too")

-- Unticking: nothing is kept here, and the guild forgets your places.
assert(A.Enable(false) == true and A.Enabled() == false and a.GL.Bounties.GuildScope().places == nil)
flush()
for _, point in ipairs(B.Points()) do assert(point.actor ~= a.id, "forgotten by the guild") end
now = now + 5
assert(A.Fight("k") == false)
for _, c in ipairs(clients) do assert(#c.GL.errors == 0, (c.GL.errors[1] or {}).text) end
print("PASS guild map: off by default, one message a fight, kept only by members who share, forged places refused, "
    .. "forty a member, fifteen replayed, forgotten when unticked")
