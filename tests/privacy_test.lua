-- Distribution remains empty and never imports another addon's personal database.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
WorthRememberingDB = { players = { private = { name = "Private", notes = { "Private note" } } } }
GrudgebookDB = { people = { private = { name = "Private", guild = "Private guild" } } }
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
assert(next(GL.db.players) == nil and next(GL.db.guilds) == nil)
assert(GL.db == GrudgeLedgerDB and GL.db ~= WorthRememberingDB and GL.db ~= GrudgebookDB)
assert(WorthRememberingDB.players.private.notes[1] == "Private note")
local identity = GL.IdentityFromName("Example", "Player", "Player-1-example")
GL.SetReaction(identity, "friend")
GL.AddNote(identity, "My own journal")
local saved = GrudgeLedgerDB
GL.InitDB()
assert(GL.Get(identity).notes[1].text == "My own journal" and GL.db == saved)
-- A different account with no saved variable starts blank, using identical code.
GrudgeLedgerDB = nil
GL.InitDB()
assert(next(GL.db.players) == nil and next(GL.db.guilds) == nil)
assert(saved.players[identity.key].notes[1].text == "My own journal")
local function serializable(value, seen)
    local kind = type(value)
    assert(kind == "table" or kind == "string" or kind == "number" or kind == "boolean" or kind == "nil")
    if kind ~= "table" then return end
    assert(not seen[value], "saved data contains a reference cycle")
    seen[value] = true
    for key, item in pairs(value) do serializable(key, seen) serializable(item, seen) end
    seen[value] = nil
end
serializable(saved, {})
-- Guild realm is supplied by GetGuildInfo, not assumed to be the local realm.
GetRealmName = function() return "Local Realm" end
GetGuildInfo = function() return "Shared Name", "Member", 5, "Other Realm" end
local foreign = GL.Identity("target")
assert(foreign.realm == "Other Realm")
GL.SetGuildReaction("Shared Name", "enemy", nil, "Local Realm")
assert(GL.RecordSeen(foreign) == nil)
GL.SetGuildReaction("Shared Name", "warning", nil, "Other Realm")
assert(GL.Relation(GL.RecordSeen(foreign)) == "warning")
GetGuildInfo = function() return mock.secret end
local hidden = GL.Identity("target")
assert(not hidden.guildKnown and hidden.realm == "Other Realm" and hidden.guild == "Shared Name",
    "only the earlier public observation is reused, never the hidden response")
local record = GL.RecordSeen(hidden)
assert(record.guild == "Shared Name" and record.realm == "Other Realm")
print("PASS privacy: empty new accounts, separate SavedVariables, no legacy import, serializable data, exact guild realm and hidden-membership preservation")
