-- Audit 24/11, protections decided by the owner:
-- 1. a relay in the name of a connected member is refused (it speaks for itself);
-- 2. relayed events do not use up the named member's room;
-- 4. your own events answer a catch-up once every thirty seconds at most;
-- 6. a member sending many inconsistent messages is told once in the chat.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me, relayer, connected, away = mock.units.player.guid, "Player-1-relayer", "Player-1-connected", "Player-1-away"
local roster = { { "Testeur-Realm", me, true }, { "Relayer-Realm", relayer, true }, { "Connected-Realm", connected, true },
    { "Away-Realm", away, false } }
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return unpack({ [1] = roster[i][1], [9] = roster[i][3], [17] = roster[i][2] }, 1, 17) end
local sent = {}
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function(_, text) sent[#sent + 1] = text return 0 end
C_ChatInfo.InChatMessagingLockdown = function() return false end
local tick
C_Timer = { NewTicker = function(_, fn) tick = fn return { Cancel = function() end } end, After = function(_, fn) fn() end }
mock.Fire("PLAYER_LOGIN")
mock.Fire("GUILD_ROSTER_UPDATE")
local B = GL.Bounties
assert(B.Online(connected) and not B.Online(away))
local s = B.GuildScope()
local function hear(text, from) mock.Fire("CHAT_MSG_ADDON", "GLBounty1", text, "GUILD", from) end
local function order(actor, n) return table.concat({ "O", actor, now * 1000 + n, now, ("Player-1-t%05d"):format(n), 10000, "Cible " .. n }, ";") end

-- 1. Connected: refused. Away: kept.
hear("R;" .. order(connected, 1), "Relayer-Realm")
hear("R;" .. order(away, 2), "Relayer-Realm")
local byConnected, byAway = 0, 0
for _, raw in pairs(s.events) do
    if raw:find(";" .. connected .. ";", 1, true) then byConnected = byConnected + 1 end
    if raw:find(";" .. away .. ";", 1, true) then byAway = byAway + 1 end
end
assert(byConnected == 0 and byAway == 1, "relays: connected refused, away kept")

-- 2. The relayed event is marked; when its author says it, it becomes theirs.
local relayedKey = away .. ":" .. (now * 1000 + 2)
assert(s.relayed and s.relayed[relayedKey], "a relayed event is marked")
roster[4][3] = true mock.Fire("GUILD_ROSTER_UPDATE")
hear(order(away, 2), "Away-Realm")
assert(not s.relayed[relayedKey], "the author's own word adopts it")

-- 6. Relays about connected members are refused silently: a catch-up answer holds them too, and an
-- honest member must not be accused (owner 25/11). Five messages sent straight in another
-- member's name (a forgery): one line in the chat, once.
local printed = #mock.messages
for i = 3, 9 do hear("R;" .. order(connected, i), "Relayer-Realm") end
for i = printed + 1, #mock.messages do
    assert(not mock.messages[i]:find("incohérents", 1, true), "no warning for a catch-up answer")
end
for i = 10, 16 do hear(order(connected, i), "Relayer-Realm") end
local told = 0
for i = printed + 1, #mock.messages do
    if mock.messages[i]:find("messages incohérents de Relayer", 1, true) then told = told + 1 end
end
assert(told == 1, "told once: " .. told)

-- 4. Two catch-up requests within thirty seconds: your own events leave once.
assert(B.Post("Player-1-target01", "Cible Exemple", 0))
for _ = 1, 20 do tick() end
sent = {}
local later = {}
local after = C_Timer.After
C_Timer.After = function(delay, fn) later[#later + 1] = fn end
hear("Q", "Relayer-Realm")
now = now + 11
hear("Q", "Connected-Realm")
now = now + 3
hear("Q", "Other-Realm")
for _ = 1, 200 do now = now + 1 tick() end
local function ownSent()
    local n = 0
    for _, text in ipairs(sent) do if text:find(";" .. me .. ";", 1, true) and text:find("Cible Exemple", 1, true) then n = n + 1 end end
    return n
end
assert(ownSent() == 1, "own events answered once in the window, not " .. ownSent())
-- The questions inside the window get one answer at its end (owner 25/11: nobody misses you).
assert(#later == 1, "one deferred answer for two late questions")
later[1]()
for _ = 1, 200 do now = now + 1 tick() end
C_Timer.After = after
assert(ownSent() == 2, "the late arrivals are answered at the end of the window")
-- 25/11: relayed events have a bound of their own, kept across sessions (1500 per relayer). A book
-- that already holds 1500 relays from one member (several sessions) takes no more from them.
roster[4][3] = false mock.Fire("GUILD_ROSTER_UPDATE")
for i = 1, 1500 do
    local key = away .. ":" .. (now * 1000 + 5000 + i)
    s.events[key] = table.concat({ "D", away, now * 1000 + 5000 + i, now, ("Player-1-w%05d"):format(i), "", "Victime" }, ";")
    s.relayed[key] = relayer
end
-- A new session: the guild space comes back from the saved file (a new table), counters start again.
local reloaded = {}
for k, v in pairs(s) do reloaded[k] = v end
GL.db.bountyGuilds[s.guildKey] = reloaded
s = reloaded
mock.Fire("GUILD_ROSTER_UPDATE")
now = now + 30
local extra = away .. ":" .. (now * 1000 + 9)
hear("R;" .. table.concat({ "D", away, now * 1000 + 9, now, "Player-1-extra01", "", "Victime" }, ";"), "Relayer-Realm")
assert(not s.events[extra], "a relayer past its bound adds nothing")
-- 25/11, "Membres actifs": a member whose addon speaks is listed by name with its version, kept in
-- the guild's space so that it is still listed after a reload.
GL.version = "0.62.1" -- the harness has no addon metadata
hear("GLV;0.58.11", "Relayer-Realm")
local listed
for _, m in ipairs(GL.GuildMap.Members()) do if m.id == relayer then listed = m end end
assert(listed and listed.version == "0.58.11" and not listed.current and listed.name == "Relayer-Realm", "the member is listed with an old version")
assert(GL.Bounties.GuildScope().addonMembers[relayer].v == "0.58.11", "kept in the guild's space")
assert(GL.GuildMap.Members()[1].you, "you come first")
-- Members heard before 0.62.1 were never written down: they are found in what their addon left,
-- here the bounty events of the absent member and a card of the connected one (owner report 25/11).
s.journal = s.journal or { cards = {} }
s.journal.cards = s.journal.cards or {}
s.journal.cards["synthetic"] = { key = "synthetic", owner = connected, time = now - 3 * 86400 }
local byId = {}
for i, m in ipairs(GL.GuildMap.Members()) do byId[m.id] = i end
assert(byId[away] and byId[connected], "found in the bounty events and the cards")
assert(GL.GuildMap.Members()[byId[away]].at <= now, "dated by their latest trace")
-- Nothing older than sixty days, nobody outside the guild.
s.journal.cards["synthetic"].time, s.journal.cards["stranger"] = now - 61 * 86400, { owner = "Player-1-stranger", time = now }
byId = {}
for i, m in ipairs(GL.GuildMap.Members()) do byId[m.id] = i end
assert(not byId["Player-1-stranger"], "only members of the guild")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS guild relay rules: connected members speak for themselves, relays outside their room, one answer, odd sender told once")
