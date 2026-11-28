-- Randomised guild vision (25/11): the box ticked and unticked, fights heard from their author or
-- relayed, members asking to be forgotten, time passing, members leaving, in an order drawn at
-- random. Rules that must always hold: unticked, nothing is shown nor saved; a forgotten member's
-- earlier fights never come back; nothing older than 38 days, nothing from outside the guild,
-- never your own characters, at most 40 fights a member. Synthetic guild only. Deterministic.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me = mock.units.player.guid
local mates = {}
for i = 1, 6 do mates[i] = { name = ("Mate%d-Realm"):format(i), id = ("Player-1-mate%04d"):format(i), member = true } end
local function roster()
    local list = { { "Testeur-Realm", me } }
    for _, m in ipairs(mates) do if m.member then list[#list + 1] = { m.name, m.id } end end
    return list
end
GetNumGuildMembers = function() return #roster() end
GetGuildRosterInfo = function(i)
    local row = roster()[i]
    return unpack({ [1] = row[1], [9] = true, [17] = row[2] }, 1, 17)
end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function() return 0 end
C_ChatInfo.InChatMessagingLockdown = function() return false end
C_Timer = { NewTicker = function() return { Cancel = function() end } end, After = function(_, fn) fn() end }
C_Map = { GetBestMapForUnit = function() return 1446 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end }
mock.Fire("PLAYER_LOGIN")
mock.Fire("GUILD_ROSTER_UPDATE")
local M = GL.GuildMap
M.Enable(true)
local seed = 77
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return math.floor(seed / 65536) % n + 1 end
local DAY = 86400
local on, forgotAt = true, {}
local function hear(sender, text) mock.Fire("CHAT_MSG_ADDON", "GLBounty1", text, "GUILD", sender) end
for step = 1, 6000 do
    now = now + rnd(4 * 3600)
    local m = mates[rnd(#mates)]
    local what = rnd(20)
    if what <= 9 then
        local at = now - rnd(45 * DAY)
        hear(m.name, ("M;1;%s;%d;%d;%d;%d;%s;;"):format(m.id, at, 1440 + rnd(9), rnd(1000) - 1, rnd(1000) - 1, rnd(2) == 1 and "d" or "k"))
        -- Heard from its author while the box is ticked, a member speaks again: what it says is kept.
        if on and m.member and at >= now - 38 * DAY then forgotAt[m.id] = nil end
    elseif what <= 15 then
        local other = mates[rnd(#mates)]
        local at = now - rnd(45 * DAY)
        hear(m.name, ("R;M;1;%s;%d;1446;%d;%d;k;;"):format(other.id, at, rnd(1000) - 1, rnd(1000) - 1))
    elseif what == 16 then
        hear(m.name, "MX")
        -- Only a member of the guild is heard.
        if m.member then forgotAt[m.id] = now end
    elseif what == 17 then
        on = not on
        M.Enable(on)
    elseif what == 18 then
        hear(m.name, "MQ")
    elseif what == 19 then
        m.member = not m.member
        mock.Fire("GUILD_ROSTER_UPDATE")
    else
        -- One of your own characters speaks: the map reads your journal, never this.
        hear("Testeur-Realm", ("M;1;%s;%d;1446;1;1;d;;"):format(me, now - 10))
    end
    local label = "step " .. step .. ": "
    assert(#GL.errors == 0, label .. tostring(GL.errors[1] and GL.errors[1].text))
    local s = GL.Bounties.GuildScope()
    local points = M.Points()
    if not on then
        assert(#points == 0 and s.places == nil, label .. "unticked: nothing shown nor saved")
    else
        local per = {}
        for _, p in ipairs(points) do
            per[p.actor] = (per[p.actor] or 0) + 1
            assert(p.actor ~= me and not GL.OwnCharacter(p.actor), label .. "your own character on the guild's map")
            assert(p.time >= now - 38 * DAY - 900 and p.time <= now + 60, label .. "a fight out of its 38 days (a quarter of an hour of cache)")
            assert(p.actor:match("^Player%-1%-mate%d%d%d%d$"), label .. "someone outside the guild")
            local member = false
            for _, m in ipairs(mates) do if m.id == p.actor then member = m.member end end
            assert(member, label .. "a member who left the guild is still on its map: " .. p.actor)
            assert(not forgotAt[p.actor] or p.time > forgotAt[p.actor], label .. "a forgotten fight came back: " .. p.actor)
        end
        for actor, n in pairs(per) do assert(n <= 40, label .. actor .. " has " .. n) end
    end
end
print("PASS random guild map: 6000 steps of ticks, fights, relays, forgetting and roster changes; the rules hold")
