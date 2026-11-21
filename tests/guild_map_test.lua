-- Guild vision (0.49.0, 0.50.0), with several real clients on a simulated wire.
-- One short message a fight, naming the opponent; only members who ticked the box keep what they
-- hear; a newcomer receives what the guild knows, absent members included; meeting a player who
-- killed a member raises the "Tueur de guilde" alert; unticking makes the guild forget.
local clients, wire, now = {}, {}, 1800000000
local function client(i)
    local env = setmetatable({ _G = false }, { __index = _G })
    env._G = env
    env.loadfile = function(p) return setfenv(assert(loadfile(p)), env) end
    env.GetAddOnMetadata = function() return "0.58.0" end
    local mock = env.loadfile(TEST_WORK .. "/tests/addon_mock.lua")()
    local c = { env = env, GL = env.GrudgeLedger, m = mock, id = "Player-1-a" .. i, name = "Member" .. i .. "-Realm", guild = "Guild",
        log = {}, online = true, sounds = {} }
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
    env.SOUNDKIT.PVP_THROUGH_QUEUE = 77
    env.PlaySound = function(id) c.sounds[#c.sounds + 1] = id end
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
    for _, p in ipairs(clients) do
        if p.online then p.m.Fire("GUILD_ROSTER_UPDATE") end
    end
    return c
end
local function waiting()
    for _, p in ipairs(clients) do
        if p.online then
            local urgent, bulk = p.GL.Transport.Pending(p.GL.Bounties.GuildScope())
            if urgent + bulk > 0 then return true end
        end
    end
    return false
end
local function flush()
    for _ = 1, 4000 do
        now = now + 1
        for _, p in ipairs(clients) do
            if p.online then p.tick() end
        end
        local packets = wire
        wire = {}
        for _, m in ipairs(packets) do
            for _, p in ipairs(clients) do
                if p.online then p.m.Fire("CHAT_MSG_ADDON", unpack(m, 1, 4)) end
            end
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
local function from(points, id)
    local count = 0
    for _, point in ipairs(points) do
        if point.actor == id then count = count + 1 end
    end
    return count
end
local enemy = "Player-1-enemy01"
local a, b, third = client(1), client(2), client(3)
flush()
local A, B, C = a.GL.GuildMap, b.GL.GuildMap, third.GL.GuildMap

-- On by default since 0.51.0, and the player is told once in the chat. Switched off: a fight sends
-- nothing, and nothing is kept.
assert(select(1, A.Enabled()) == true and select(2, A.Enabled()) == true and a.GL.Bounties.GuildScope().noticed)
for _, member in ipairs({ A, B, C }) do assert(member.Enable(false) == true) end
flush()
assert(select(1, A.Enabled()) == false)
assert(A.Fight("k", enemy, "Bad Guy") == false and sentAbout(a, "^M;") == 0 and #A.Points() == 0)

-- One member ticks the box: their fight goes out with its opponent, but a member who did not tick
-- keeps nothing.
assert(A.Enable(true) == true and A.Enabled() == true)
flush()
now = now + 10
assert(A.Fight("k", enemy, "Bad Guy") == true)
flush()
assert(sentAbout(a, "^M;1;Player%-1%-a1;%d+;1446;512;288;k;Player%-1%-enemy01;Bad Guy$") == 1, a.log[#a.log])
assert(b.GL.Bounties.GuildScope().places == nil and #B.Points() == 0, "unticked: nothing kept")

-- The second member ticks it: they ask, the first answers with their own fights.
assert(B.Enable(true) == true)
flush()
local seen = B.Points()
assert(#seen == 1 and seen[1].actor == a.id and seen[1].kind == "kill" and seen[1].mapID == 1446, #seen)
assert(seen[1].target == enemy and seen[1].name == "Bad Guy" and math.abs(seen[1].x - 0.512) < 0.0001 and math.abs(seen[1].y - 0.288) < 0.0001)
assert(#A.Points() == 0, "your own fights come from your journal, not from the guild")
assert(B.Killer(enemy) == nil, "a victory makes no guild killer")

-- A death of the second member reaches the first, through the real hook of a recorded death.
now = now + 20
b.x, b.y = 0.25, 0.75
b.GL.Bounties.Death(enemy, "Bad Guy")
flush()
seen = A.Points()
assert(#seen == 1 and seen[1].actor == b.id and seen[1].kind == "death" and math.abs(seen[1].x - 0.25) < 0.0001, #seen)
local killer = A.Killer(enemy)
assert(killer and killer.deaths == 1 and killer.actor == b.id and killer.name == "Bad Guy" and killer.mapID == 1446)
assert(B.Killer(enemy) == nil, "your own death is your journal's business")
-- Nothing leaves from an instance.
b.instance = true
assert(B.Fight("k", enemy) == false)
b.instance = nil

-- The first member meets that player, who is not in their journal: the "Tueur de guilde" alert,
-- with a sound of its own. Once per cooldown.
assert(a.GL.Get("guid:" .. enemy) == nil)
now = now + 600
a.m.units.target = { name = "Bad", surname = "Guy", guid = enemy }
a.GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
local toast = assert(a.env.GrudgeLedgerNearbyAlert, "the first member is alerted")
assert(toast:IsShown() and toast.title:GetText() == "Tueur de guilde" and toast.name:GetText() == "Bad Guy", toast.title:GetText())
assert(toast.note:GetText() == "A tué Member2-Realm il y a 10 min.", toast.note:GetText())
assert(#a.sounds == 1 and a.sounds[1] == 77, "its own sound")
toast:Hide()
a.GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(not toast:IsShown() and #a.sounds == 1 and a.GL.Get("guid:" .. enemy) == nil, "once per cooldown, nothing enters the journal")
-- The guild killer alert is orange and carries "Rechercher" (0.57.0): a free wanted notice in one click.
a.env.UnitFactionGroup = function(unit) return unit == "player" and "Alliance" or "Horde" end
a.env.SOUNDKIT.LOOT_WINDOW_COIN_SOUND = 88
now = now + 600
a.GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
assert(toast:IsShown() and toast.title:GetText() == "Tueur de guilde" and toast.accent[1] > 0.8 and toast.accent[2] < 0.5)
assert(toast.action:IsShown() and toast.action:GetText() == "Rechercher")
toast.action.scripts.OnClick(toast.action, "LeftButton")
local wanted = a.GL.Bounties.OpenFor(enemy)
assert(wanted and a.GL.BountyTotal(wanted) == 0, "a wanted notice without gold")
-- The player is still there: the alert turns at once into the wanted one, gold, with the sound of
-- coins and what the guild offers.
assert(toast:IsShown() and toast.bounty and toast.title:GetText() == "Cible de prime à proximité", toast.title:GetText())
assert(toast.note:GetText():find("Avis de recherche, sans or", 1, true) and toast.accent[2] > 0.6 and not toast.action:IsShown(), toast.note:GetText())
assert(a.sounds[#a.sounds] == 88, tostring(a.sounds[#a.sounds]))
toast:Hide()
-- The victim has their own journal and their own alert: no guild banner for them.
b.m.units.target = { name = "Bad", surname = "Guy", guid = enemy }
b.GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
local theirs = b.env.GrudgeLedgerNearbyAlert
assert(not (theirs and theirs:IsShown() and theirs.title:GetText() == "Tueur de guilde"))

-- A fight said by a member about another member, outside a relay, is refused; so is nonsense.
local forged = third.GL.Bounties.GuildScope()
local T = third.GL.Transport
T.Send(forged, "M;1;" .. b.id .. ";" .. now .. ";1446;100;100;d;;")
T.Send(forged, "M;1;" .. third.id .. ";" .. now .. ";1446;5000;100;d;;")
T.Send(forged, "M;1;" .. third.id .. ";" .. (now + 4000) .. ";1446;100;100;d;;")
T.Send(forged, "M;1;" .. third.id .. ";" .. (now - 40 * 86400) .. ";1446;100;100;d;;")
T.Send(forged, "M;2;" .. third.id .. ";" .. now .. ";1446;100;100;d;;")
T.Send(forged, "M;1;" .. third.id .. ";" .. now .. ";1446;100;100;x;;")
T.Send(forged, "M;1;" .. third.id .. ";" .. now .. ";1446;100;100;d;not-a-player;Name")
T.Send(forged, "M;1;" .. third.id .. ";" .. now .. ";1446;100;100;d;;" .. ("n"):rep(60))
T.Send(forged, "M;1;" .. third.id .. ";" .. now .. ";1446;100;100;d")
flush()
assert(#A.Points() == 1 and #B.Points() == 1, "malformed or borrowed fights refused")

-- Bounded: forty fights a member, the latest.
for i = 1, 45 do
    now = now + 2
    a.x = 0.1 + i / 100
    assert(A.Fight("d", enemy, "Bad Guy") == true)
end
flush()
assert(from(B.Points(), a.id) == 40 and #b.GL.Bounties.GuildScope().places[a.id] == 40)
assert(math.abs(B.Points()[1].x - 0.55) < 0.0001, "the latest first")
assert(B.Killer(enemy).deaths == 40)

-- The third member shares a fight, then goes offline. A fourth joins the guild with an empty
-- journal and ticks the box: they receive what the guild knows, the absent member's fights included.
assert(C.Enable(true) == true)
flush()
now = now + 5
third.x, third.y = 0.9, 0.1
assert(C.Fight("d", enemy, "Bad Guy") == true)
flush()
assert(from(A.Points(), third.id) == 1 and from(B.Points(), third.id) == 1)
third.online = false
local ownA, ownB = sentAbout(a, "^M;1;"), sentAbout(b, "^M;1;")
local relayA, relayB = sentAbout(a, "^R;M;1;"), sentAbout(b, "^R;M;1;")
local fourth = client(4)
flush()
-- A login (0.58.0): nobody resends their own fights; one relay, the relayer's own fights included,
-- gives the newcomer what the guild knows.
assert(sentAbout(a, "^M;1;") == ownA and sentAbout(b, "^M;1;") == ownB, "no member answers a login with its own fights")
local relayed = sentAbout(a, "^R;M;1;") - relayA + sentAbout(b, "^R;M;1;") - relayB
assert(relayed > 0 and relayed <= 2 * 120, relayed)
local known = fourth.GL.GuildMap.Points()
assert(from(known, a.id) == 40 and from(known, b.id) == 1 and from(known, third.id) == 1, #known)
-- The versions: each member announced its own at login and answered the newcomer.
assert(select(2, fourth.GL.GuildMap.Versions()) == 2 and select(1, fourth.GL.GuildMap.Versions()) == 2)
assert(sentAbout(fourth, "^GLV;") == 1 and sentAbout(a, "^GLV;") >= 1)
-- A member with an older version is named once in the chat; a newer one in the guild is told too.
local printed = #a.m.messages
fourth.GL.version = "0.10.0"
fourth.GL.GuildMap.Announce(fourth.GL.Bounties.GuildScope())
flush()
assert(#a.m.messages > printed and a.m.messages[#a.m.messages]:find("ancienne version", 1, true), tostring(a.m.messages[#a.m.messages]))
assert(select(1, a.GL.GuildMap.Versions()) < select(2, a.GL.GuildMap.Versions()))
fourth.GL.version = "9.0.0"
now = now + 61
printed = #b.m.messages
fourth.GL.GuildMap.Announce(fourth.GL.Bounties.GuildScope())
flush()
assert(b.m.messages[#b.m.messages]:find("plus récente", 1, true), tostring(b.m.messages[#b.m.messages]))
fourth.GL.version = a.GL.version
now = now + 60
assert(fourth.GL.GuildMap.Enable(true) == true)
flush()
known = fourth.GL.GuildMap.Points()
assert(from(known, a.id) == 40 and from(known, b.id) == 1 and from(known, third.id) == 1, #known)
assert(sentAbout(a, "^R;M;1;") + sentAbout(b, "^R;M;1;") >= 1, "someone passed on the absent member's fights")
assert(fourth.GL.GuildMap.Killer(enemy).deaths == 42, fourth.GL.GuildMap.Killer(enemy).deaths)
-- The same question twice in a row is answered once.
now = now + 60
local scopeA = a.GL.Bounties.GuildScope()
assert(A.Receive(scopeA, a.id, fourth.id, "MQ", false) == true)
local _, queued = a.GL.Transport.Pending(scopeA)
assert(queued >= 40, queued)
flush()
local before = sentAbout(a, "^M;1;")
now = now - 20
A.Receive(scopeA, a.id, fourth.id, "MQ", false)
local _, again = a.GL.Transport.Pending(scopeA)
now = now + 20
assert(again == 0 and sentAbout(a, "^M;1;") == before, "one answer every thirty seconds")

-- Unticking: nothing is kept here, the guild forgets your fights, and a relay cannot bring them back.
local old = "R;M;1;" .. a.id .. ";" .. (now - 100) .. ";1446;300;300;d;;"
assert(A.Enable(false) == true and A.Enabled() == false and a.GL.Bounties.GuildScope().places == nil)
flush()
assert(from(B.Points(), a.id) == 0 and from(fourth.GL.GuildMap.Points(), a.id) == 0, "forgotten by the guild")
fourth.GL.Transport.Send(fourth.GL.Bounties.GuildScope(), old)
flush()
assert(from(B.Points(), a.id) == 0, "a relay older than the request to forget is refused")
now = now + 5
assert(A.Fight("k", enemy) == false)
-- Ticking it again: their new fights are theirs again.
assert(A.Enable(true) == true)
now = now + 5
assert(A.Fight("k", enemy, "Bad Guy") == true)
flush()
assert(from(B.Points(), a.id) >= 1 and b.GL.Bounties.GuildScope().mapForgot[a.id] == nil)
for _, c in ipairs(clients) do assert(#c.GL.errors == 0, (c.GL.errors[1] or {}).text) end
print("PASS guild vision: off by default, one message a fight with its opponent, kept only by members who share, borrowed fights "
    .. "refused, forty a member, a newcomer receives the guild's fights, guild killer alert with its own sound, forgotten when unticked")
