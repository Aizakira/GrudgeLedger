-- One book per faction (0.54.0). On a PvP realm (one faction) nothing moves. A book written by
-- characters of both factions is cut once, each fact going to its author's side, nothing lost.
-- Playing the other faction opens the other book; coming back opens the first one, unchanged.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local now = 1800000000
GetServerTime = function() return now end
local faction, me = "Alliance", "Player-1-A0000001"
UnitFactionGroup = function(unit) return unit == "player" and faction or nil end
local realGUID = UnitGUID
UnitGUID = function(unit)
    if unit == "player" then return me end
    return realGUID(unit)
end
local function fact(kind, actor, at, extra)
    local e = { kind = kind, actorGUID = actor, time = at, confidence = "confirmed", eventId = kind .. at }
    for key, value in pairs(extra or {}) do e[key] = value end
    return e
end
local function sheet(guid, name, side, history, notes, pvp)
    return { guid = guid, name = name, fullName = name, faction = side, history = history, notes = notes or {}, pvp = pvp or {} }
end
local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
local A1, A2, H1 = "Player-1-A0000001", "Player-1-A0000002", "Player-1-H0000001"

-- 1. A PvP realm: only Alliance characters, two of them. Nothing moves.
GrudgeLedgerDB = { schema = 2, players = {
    ["guid:Player-1-E0000001"] = sheet("Player-1-E0000001", "Grok", "Horde",
        { fact("death", A1, now - 100), fact("kill", A2, now - 50) }, nil, { deaths = 1, kills = 1 }),
    ["guid:Player-1-F0000001"] = sheet("Player-1-F0000001", "Amie", "Alliance", { fact("grouped", A2, now - 40) }),
}, aliases = {}, guilds = { ["forever:les ennemis"] = { key = "forever:les ennemis", reaction = "enemy" } } }
GL.InitDB()
assert(GL.db.book == "Alliance" and GL.db.migrations[5] and count(GL.db.players) == 2, count(GL.db.players))
assert(GL.db.books.Horde and count(GL.db.books.Horde.players) == 0 and GL.db.characterFactions[A1] == "Alliance")
local grok = GL.Get("guid:Player-1-E0000001")
assert(grok.pvp.deaths == 1 and grok.pvp.kills == 1 and #grok.history == 2, "a sheet of one side is never cut")
assert(GL.Get(GL.IdentityFromName("Amie", nil, "Player-1-F0000001")) ~= nil, "names still lead to their sheets")

-- 1b. The split waits for the player's own identifier (review 0.58.0): at ADDON_LOADED without it,
-- nothing moves; at login it runs.
local savedMe = me
me = nil
GrudgeLedgerDB = { schema = 2, players = {
    ["guid:Player-1-E0000002"] = sheet("Player-1-E0000002", "Lumi", "Alliance", { fact("death", H1, now - 90) }, nil, { deaths = 1 }),
}, aliases = {}, guilds = {} }
GL.InitDB()
assert(GL.db.book == nil and GL.Get("guid:Player-1-E0000002"), "no split without the player's identifier")
me = savedMe
mock.Fire("PLAYER_LOGIN")
assert(GL.db.book == "Alliance" and not GL.Get("guid:Player-1-E0000002") and GL.db.books.Horde.players["guid:Player-1-E0000002"])

-- 2. A PvE realm: an Alliance character and a Horde one wrote in the same book. The Horde
-- character's facts go to the Horde book, a sheet with facts on both sides is copied.
GrudgeLedgerDB = { schema = 2, players = {
    -- A Horde player the Alliance character fought: stays.
    ["guid:Player-1-E0000001"] = sheet("Player-1-E0000001", "Grok", "Horde", { fact("death", A1, now - 100) }, nil, { deaths = 1 }),
    -- An Alliance player who killed the Horde character: leaves for the Horde book.
    ["guid:Player-1-E0000002"] = sheet("Player-1-E0000002", "Lumi", "Alliance", { fact("death", H1, now - 90) },
        { { text = "Horde note", actorGUID = H1, time = now - 89 } }, { deaths = 1 }),
    -- A Horde player: killed by the Alliance character, then grouped with the Horde character.
    ["guid:Player-1-E0000003"] = sheet("Player-1-E0000003", "Zug", "Horde",
        { fact("kill", A1, now - 80), fact("grouped", H1, now - 70), fact("grouped", H1, now - 60) }, nil, { kills = 1 }),
    -- No author known: stays where it is.
    ["guid:Player-1-E0000004"] = sheet("Player-1-E0000004", "Vieux", "Horde", { { kind = "seen", time = now - 500 } }),
}, aliases = {}, guilds = { ["forever:les ennemis"] = { key = "forever:les ennemis", reaction = "enemy" } } }
GL.InitDB()
assert(GL.db.book == "Alliance" and GL.db.characterFactions[H1] == nil, "the Horde character was never seen: deduced")
local horde = GL.db.books.Horde.players
assert(GL.Get("guid:Player-1-E0000001") and not GL.Get("guid:Player-1-E0000002") and horde["guid:Player-1-E0000002"])
assert(#horde["guid:Player-1-E0000002"].notes == 1, "the note follows its author")
local zug, hordeZug = GL.Get("guid:Player-1-E0000003"), horde["guid:Player-1-E0000003"]
assert(zug and hordeZug and #zug.history == 1 and #hordeZug.history == 2, "a sheet with facts on both sides is copied")
assert(zug.pvp.kills == 1 and hordeZug.pvp.kills == 0 and hordeZug.groupCount == 2 and zug.groupCount == 0)
assert(GL.Get("guid:Player-1-E0000004") and GL.db.books.Horde.guilds["forever:les ennemis"], "opinions on guilds go to both books")
local total = count(GL.db.players) + count(horde)
assert(total == 5, total)

-- 3. Logging in with the Horde character opens the Horde book; the Alliance one waits, untouched.
faction, me = "Horde", H1
mock.Fire("PLAYER_LOGIN")
assert(GL.db.book == "Horde" and GL.db.characterFactions[H1] == "Horde")
assert(GL.Get("guid:Player-1-E0000002") and not GL.Get("guid:Player-1-E0000001") and GL.db.books.Alliance)
assert(GL.Relation(GL.Get("guid:Player-1-E0000002")) ~= "neutral", "the Horde character's enemy is still its enemy")
assert(GL.Get(GL.IdentityFromName("Lumi", nil, "Player-1-E0000002")), "names are indexed in the opened book")
-- A new fact lands in the Horde book only.
GL.RecordPvP(GL.IdentityFromName("Nouveau", "Venu", "Player-1-E0000009"), "death", "confirmed", "fixture", "h-new")
assert(GL.Get("guid:Player-1-E0000009") and not GL.db.books.Alliance.players["guid:Player-1-E0000009"])

-- 4. Back to the Alliance character: its book again, exactly as it was.
faction, me = "Alliance", A1
mock.Fire("PLAYER_LOGIN")
assert(GL.db.book == "Alliance" and GL.Get("guid:Player-1-E0000001") and not GL.Get("guid:Player-1-E0000009"))
assert(GL.db.books.Horde.players["guid:Player-1-E0000009"] and count(GL.db.players) == 3)
-- The same faction again: nothing happens.
assert(GL.SelectBook() == false)

-- 5. Your own guildmates are never enemies because of an opinion on their guild.
GetGuildInfo = function(unit) return "Les Ennemis", "Membre", 1, nil end
local mate = GL.Remember(GL.IdentityFromName("Camarade", nil, "Player-1-G0000001"))
mate.guild = "Les Ennemis"
assert(GL.Relation(mate) ~= "enemy", GL.Relation(mate))
GetGuildInfo = function(unit) if unit == "player" then return nil end return "Les Ennemis", "Membre", 1, nil end
assert(GL.Relation(mate) == "enemy", "outside the guild the opinion applies")
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS faction books: one faction untouched, a mixed book cut by author without loss, the other book opened at login and back, "
    .. "own guildmates never enemies")
