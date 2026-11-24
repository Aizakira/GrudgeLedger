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

-- 6. Five inconsistent messages: one line in the chat, once.
local printed = #mock.messages
for i = 3, 9 do hear("R;" .. order(connected, i), "Relayer-Realm") end
local told = 0
for i = printed + 1, #mock.messages do
    if mock.messages[i]:find("messages incohérents de Relayer", 1, true) then told = told + 1 end
end
assert(told == 1, "told once: " .. told)

-- 4. Two catch-up requests within thirty seconds: your own events leave once.
assert(B.Post("Player-1-target01", "Cible Exemple", 0))
for _ = 1, 20 do tick() end
sent = {}
hear("Q", "Relayer-Realm")
now = now + 11
hear("Q", "Connected-Realm")
for _ = 1, 400 do now = now + 1 tick() end
local own = 0
for _, text in ipairs(sent) do if text:find(";" .. me .. ";", 1, true) and text:find("Cible Exemple", 1, true) then own = own + 1 end end
assert(own == 1, "own events answered once, not " .. own)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS guild relay rules: connected members speak for themselves, relays outside their room, one answer, odd sender told once")
