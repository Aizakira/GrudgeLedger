-- Damaged guild space in the saved file (25/11): the guild's part of the save (shared fights,
-- bounties, cards, active members) filled by real messages, then copies damaged at random and the
-- addon loaded on each, in the guild. Loading, the guild's views and its pages must raise no error,
-- and the addon must catch none. Synthetic guild only. Deterministic.
local now = 1800000000
local function load(saved)
    local env = setmetatable({ _G = false, GrudgeLedgerDB = saved }, { __index = _G })
    env._G = env
    env.loadfile = function(p) return setfenv(assert(loadfile(p)), env) end
    local mock = env.loadfile(TEST_WORK .. "/tests/addon_mock.lua")()
    env.GetServerTime = function() return now end
    mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
    env.GetNormalizedRealmName = function() return "Realm" end
    local roster = { { "Testeur-Realm", mock.units.player.guid }, { "Mate-Realm", "Player-1-mate0001" }, { "Other-Realm", "Player-1-mate0002" } }
    env.GetNumGuildMembers = function() return #roster end
    env.GetGuildRosterInfo = function(i) return unpack({ [1] = roster[i][1], [9] = true, [17] = roster[i][2] }, 1, 17) end
    env.C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
    env.C_ChatInfo.SendAddonMessage = function() return 0 end
    env.C_ChatInfo.InChatMessagingLockdown = function() return false end
    env.C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
    env.C_Map = { GetBestMapForUnit = function() return 1446 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end }
    mock.Fire("PLAYER_LOGIN")
    mock.Fire("GUILD_ROSTER_UPDATE")
    return env.GrudgeLedger, env, mock
end
local seed = 2026
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return math.floor(seed / 65536) % n + 1 end
local GL, env, mock = load(nil)
local function hear(sender, text) mock.Fire("CHAT_MSG_ADDON", "GLBounty1", text, "GUILD", sender) end
GL.GuildMap.Enable(true)
for i = 1, 30 do
    now = now + 300
    hear("Mate-Realm", ("M;1;Player-1-mate0001;%d;1446;%d;%d;%s;Player-1-foe%05d;Ennemi"):format(now - 60, 100 + i, 200 + i, i % 2 == 0 and "d" or "k", i))
    hear("Other-Realm", "GLV;0.62.1")
    hear("Other-Realm", ("O;Player-1-mate0002;%d;%d;Player-1-foe%05d;%d;Cible %d"):format(now * 1000 + i, now - 10, i, 5000 * i, i))
    hear("Mate-Realm", ("P;Player-1-mate0001;%d;%d;Player-1-mate0002:%d;%d;"):format(now * 1000 + 500 + i, now - 5, now * 1000 + i, 1000))
end
GL.Bounties.Post("Player-1-foe99999", "Proie", 20000)
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    return out
end
local pristine = copy(GL.db)
assert(type(pristine.bountyGuilds) == "table" and next(pristine.bountyGuilds), "the guild space was filled")
-- A sound save loses nothing: the repair sets nothing aside and every list keeps its length.
do
    local G = load(copy(pristine))
    local s = G.Bounties.GuildScope()
    assert(not (G.db.quarantine and G.db.quarantine.guild), "a sound guild space was changed")
    local before, after = 0, 0
    for _, v in pairs(pristine.bountyGuilds) do for _ in pairs(v.events or {}) do before = before + 1 end end
    for _ in pairs(s.events) do after = after + 1 end
    assert(before == after and #G.GuildMap.Points() > 0 and #G.GuildProfiles.List() >= 0, "events kept: " .. before .. " / " .. after)
end
local function places(root)
    local list, seen = {}, {}
    local function walk(t, depth)
        if seen[t] or depth > 8 then return end
        seen[t] = true
        for k, v in pairs(t) do
            list[#list + 1] = { t, k }
            if type(v) == "table" then walk(v, depth + 1) end
        end
    end
    walk(root, 0)
    table.sort(list, function(a, b) return tostring(a[2]) < tostring(b[2]) end)
    return list
end
local BAD = { "nil", "", "x", 0, -1, 1e309, 2 ^ 53, 3.5, true, {}, { 1, 2 }, { x = "y" }, string.rep("z", 300) }
local function bad()
    local v = BAD[rnd(#BAD)]
    if v == "nil" then return nil end
    return type(v) == "table" and copy(v) or v
end
local failures = {}
local function try(label, run, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = ("run %d, %s: %s"):format(run, label, tostring(err)) end
    return ok
end
local RUNS = 480
for run = 1, RUNS do
    local saved = copy(pristine)
    local where = places(saved.bountyGuilds)
    local changed = {}
    for _ = 1, rnd(4) do
        local spot = where[rnd(#where)]
        spot[1][spot[2]] = bad()
        changed[#changed + 1] = tostring(spot[2])
    end
    local label = "damaged " .. table.concat(changed, ",")
    local G, E, M
    if try(label .. " / load", run, function() G, E, M = load(saved) end) then
        try(label .. " / guild views", run, function()
            G.GuildMap.Points()
            G.GuildMap.Points(true)
            G.GuildMap.Members()
            G.GuildMap.Killer("Player-1-foe00002")
            G.Bounties.List()
            G.Bounties.History()
            for _, card in ipairs(G.GuildProfiles.List()) do G.GuildProfiles.View(card) end
        end)
        try(label .. " / guild pages", run, function()
            local R = G.RelationsPages
            for _, page in ipairs({ "guildlog", "enemies", "guilds", "members", "lands" }) do
                R.Open(page)
                R.Refresh()
            end
            if G.ShowBounties then G.ShowBounties() end
        end)
        try(label .. " / messages after", run, function()
            M.Fire("CHAT_MSG_ADDON", "GLBounty1", ("M;1;Player-1-mate0001;%d;1446;5;5;d;;"):format(now - 1), "GUILD", "Mate-Realm")
            M.Fire("CHAT_MSG_ADDON", "GLBounty1", "Q", "GUILD", "Other-Realm")
        end)
        for _, e in ipairs(G.errors or {}) do
            if not tostring(e.text):find("quarantine", 1, true) then
                failures[#failures + 1] = ("run %d, %s / caught: %s"):format(run, label, tostring(e.text))
            end
        end
    end
end
table.sort(failures)
assert(#failures == 0, #failures .. " failures on damaged guild spaces:\n" .. table.concat(failures, "\n", 1, math.min(#failures, 20)))
print(("PASS damaged guild spaces: %d damaged copies load and show the guild's views and pages without error"):format(RUNS))
