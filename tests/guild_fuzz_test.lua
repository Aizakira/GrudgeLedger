-- Security (25/11): a hostile or broken guild member sends tens of thousands of malformed messages,
-- built from every kind the guild exchanges and then damaged at random. Nothing may raise an error,
-- and what is kept stays within the bounds the protocol promises.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
mock.units.player.guild, mock.units.player.realm = "Guild", "Realm"
GetNormalizedRealmName = function() return "Realm" end
local me = mock.units.player.guid
local roster = { { "Testeur-Realm", me, true }, { "Hostile-Realm", "Player-1-hostile", true },
    { "Absent-Realm", "Player-1-absent", false }, { "Other-Realm", "Player-1-other", true } }
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return unpack({ [1] = roster[i][1], [9] = roster[i][3], [17] = roster[i][2] }, 1, 17) end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.SendAddonMessage = function() return 0 end
C_ChatInfo.InChatMessagingLockdown = function() return false end
local tick
C_Timer = { NewTicker = function(_, fn) tick = fn return { Cancel = function() end } end, After = function(_, fn) fn() end }
C_Map = { GetBestMapForUnit = function() return 1446 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end }
mock.Fire("PLAYER_LOGIN")
mock.Fire("GUILD_ROSTER_UPDATE")
GL.GuildMap.Enable(true)
local s = GL.Bounties.GuildScope()

-- Deterministic randomness: the same run every time.
local seed = 12345
-- The high bits of the generator: its low bits repeat in short cycles and would tie draws together.
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return math.floor(seed / 65536) % n + 1 end
local guids = { "Player-1-absent", "Player-1-hostile", "Player-1-other", me, "Player-1-target01", "Player-9-zzzzzz",
    "Player-1-" .. string.rep("a", 40), "Creature-0-1-2", "" }
local function guid() return guids[rnd(#guids)] end
local nasty = { "", "0", "-1", "nan", "inf", "-inf", "1e309", "99999999999999999999", "4294967296", "0x10", "1.5", " 7",
    ";", ";;", "|", "|cffff0000x|r", "|Hitem:1|h", "\n", "\0", "\127", "é", string.rep("x", 300), "%s%d", "Player-1-absent",
    "Player-1-absent:1", "1,2,3", "pwn", "sse", "1", "true" }
local function value() return nasty[rnd(#nasty)] end
local function stamp() return tostring(now - rnd(4000000) + 200) end
local function id() return tostring(now * 1000 + rnd(99999)) end
local kinds = { "O", "N", "A", "P", "K", "H", "F", "X", "U", "S", "Y", "Z", "V", "D", "Q", "?" }
-- One message close to a valid one, of any kind the guild exchanges.
-- Orders this run has seen, so that later events can name a real one.
local known = {}
local function message(author)
    local family = rnd(6)
    if family == 1 then
        local kind = kinds[rnd(#kinds)]
        local actor = rnd(2) == 1 and author or guid()
        local seq, at = id(), tostring(now - rnd(3600))
        local order = (kind == "O" or kind == "N" or kind == "A" or kind == "D") and guid()
            or (#known > 0 and rnd(3) > 1 and known[rnd(#known)]) or (guid() .. ":" .. id())
        local value = kind == "N" and "300000," .. rnd(4) .. "," .. ({ "pwn", "swn", "pen", "pes" })[rnd(4)]
            or kind == "P" and tostring(rnd(200000)) or kind == "Y" and tostring(rnd(200000)) or kind == "Z" and tostring(rnd(200000))
            or kind == "U" and "0" or kind == "H" and ({ "0", "1", "1,40,42" })[rnd(3)] or kind == "F" and (#known > 0 and known[rnd(#known)] or "")
            or kind == "S" and (#known > 0 and known[rnd(#known)] or "") or kind == "V" and "0," .. rnd(50000)
            or (kind == "O" or kind == "A") and tostring(rnd(3) == 1 and 0 or rnd(500000)) or ""
        local detail = (kind == "O" or kind == "N" or kind == "A" or kind == "D") and "Cible " .. rnd(50)
            or (kind == "Y" or kind == "Z" or kind == "V") and guid() or kind == "U" and "note" or ""
        if kind == "O" or kind == "N" or kind == "A" then known[#known + 1] = actor .. ":" .. seq end
        return table.concat({ kind, actor, seq, at, order, value, detail }, ";")
    elseif family == 2 then
        return table.concat({ "G", rnd(2) == 1 and author or guid(), ("Player-1-s%05d"):format(rnd(3000)), tostring(rnd(3000)), tostring(rnd(3000)) }, ";")
    elseif family == 3 then
        return table.concat({ "M", "1", guid(), stamp(), tostring(rnd(2000)), tostring(rnd(1100)), tostring(rnd(1100)),
            rnd(2) == 1 and "d" or "k", guid(), "Nom" }, ";")
    elseif family == 4 then
        local sub = rnd(4)
        if sub == 1 then return table.concat({ "J", "C", guid(), ("%032x"):format(rnd(99999)), stamp(), ("%016x"):format(rnd(99)), "Fiche" }, ";") end
        if sub == 2 then return table.concat({ "J", "T", guid(), guid(), ("%032x"):format(rnd(99)), id(), stamp(), ("%016x"):format(rnd(9)), "toxic", "1" }, ";") end
        if sub == 3 then return table.concat({ "J", "D", guid(), guid(), ("%032x"):format(rnd(99999)) }, ";") end
        return "J;V;" .. guid() .. ":" .. guid() .. ":" .. ("%032x"):format(rnd(99))
    elseif family == 5 then
        local sub = rnd(4)
        if sub == 1 then return "J;S2;V;" .. guid() .. ";" .. rnd(2000) .. ";" .. ({ "e", "w", "b", "h" })[rnd(4)] .. ";Nom%0A;Zone%00" end
        if sub == 2 then return "J;S2;W;" .. id() end
        if sub == 3 then return "J;S2;Q;" .. guid() .. ";" .. stamp() .. "," .. stamp() end
        return "J;S2;P;" .. guid() .. ";" .. id() .. ";" .. (rnd(2) == 1 and "r" or "t") .. ";1;" .. rnd(3) .. ";" .. value()
    end
    return ({ "Q", "MQ", "MX", "GLV;0.62.0", "GLVR;99.0", "GLP;deadbeef", "GLV;" .. value() })[rnd(7)]
end
-- Damages it: a field replaced, cut short, doubled, or wrapped as a relay.
local function damage(text)
    local fields = {}
    for v in (text .. ";"):gmatch("(.-);") do fields[#fields + 1] = v end
    local how = rnd(5)
    if how == 1 and #fields > 0 then fields[rnd(#fields)] = value()
    elseif how == 2 and #fields > 1 then fields[#fields] = nil
    elseif how == 3 then fields[#fields + 1] = value() end
    local out = table.concat(fields, ";")
    if rnd(3) == 1 then out = "R;" .. out end
    return out:sub(1, 255)
end
for i = 1, 30000 do
    now = now + 1
    local hostile = rnd(3) > 1
    local author = hostile and "Player-1-hostile" or "Player-1-other"
    local text = rnd(2) == 1 and message(author) or damage(message(author))
    -- A quarter: relays in the absent member's name, valid or damaged.
    if rnd(4) == 1 then text = "R;" .. (rnd(2) == 1 and message("Player-1-absent") or damage(message("Player-1-absent"))) end
    mock.Fire("CHAT_MSG_ADDON", "GLBounty1", text, "GUILD", hostile and "Hostile-Realm" or "Other-Realm")
    if i % 50 == 0 and tick then tick() end
    if i % 500 == 0 then mock.Fire("GUILD_ROSTER_UPDATE") end
end
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)

-- What is kept stays bounded.
local function count(map) local n = 0 for _ in pairs(type(map) == "table" and map or {}) do n = n + 1 end return n end
local events, relayed = count(s.events), count(s.relayed)
local cards = count(s.journal and s.journal.cards)
local withdrawn = count(s.journal and s.journal.withdrawn)
local scores = count(s.scores)
local places = 0
for _, list in pairs(type(s.places) == "table" and s.places or {}) do places = places + #list end
local reports = count(s.socialReports)
assert(relayed <= 3000, "relayed " .. relayed)
assert(events <= 600 * 4 + 3000 + 50, "events " .. events)
assert(cards <= 3000 and withdrawn <= 3000, "cards " .. cards .. " withdrawn " .. withdrawn)
assert(scores <= 1500, "scores " .. scores)
assert(places <= 150 * 40, "map lines " .. places)
assert(reports <= 256, "testimonies " .. reports)
-- And the views still work on what was kept.
GL.Bounties.List()
GL.Bounties.History()
GL.GuildMap.Points(true)
for _, card in ipairs(GL.GuildProfiles.List()) do GL.GuildProfiles.View(card) end
GL.SharedDossiers.RefreshOpinions()
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print(("PASS guild fuzz: 30000 damaged messages, no error; kept events %d, relayed %d, cards %d, scores %d, map lines %d"):format(
    events, relayed, cards, scores, places))
