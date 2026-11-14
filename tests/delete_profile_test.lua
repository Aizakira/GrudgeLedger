local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
GL.SetSetting("guideSeen", true)
IsInInstance = function() return false, "none" end
local now = GL.Now()
GetServerTime = function() return now end
local id = GL.Identity("target")
local record = GL.SetReaction(id, "friend")
local other = GL.SetReaction(GL.IdentityFromName("Aqua", "Waters", "Player-1-waters"), "friend")
GL.AddNote(id, "Wrong contact")
GL.RecordPvP(id, "death", "confirmed", nil, "one")
GL.RecordHonor(id, 35)
GL.RecordHonor(other, 3)
assert(GL.PersonalStatistics().deaths == 1 and GL.PersonalStatistics().honor == 38)

local pending
function StaticPopup_Show(which, name, _, data)
    pending = {name=name, record=data, dialog=assert(StaticPopupDialogs[which])}
end
local function prompt()
    GL.ShowLedger(record.key)
    local f = GrudgeLedgerWindow
    f.tools:GetScript("OnClick")(f.tools)
    assert(f.toolsMenu:IsVisible())
    for _, control in ipairs(f.toolsMenu.children) do
        if control.text == "Supprimer la fiche…" then
            control:GetScript("OnClick")(control)
            assert(pending.name == record.fullName and pending.record == record and not f.toolsMenu:IsShown())
            assert(pending.dialog.button2 == "Annuler" and pending.dialog.hideOnEscape)
            assert(GL.Get(id) == record and #record.notes == 1)
            return
        end
    end
    error("missing delete profile action")
end
prompt()
pending = nil -- dismissed with the native Cancel button
assert(GL.Get(id) == record and GL.PersonalStatistics().honor == 38)
prompt()
GL.ShowLedger(other.key)
pending.dialog.OnAccept(nil, pending.record)
assert(GL.Get(id) == record and GL.Get(other) == other, "a stale confirmation cannot follow a new selection")

id.guild, id.guildKnown = "Nearby Guild", true
GL.Remember(id)
GL.SetGuildReaction(id.guild, "enemy")
assert(#GL.GuildMembers(id.guild) == 1)
assert(#GL.GuildStatistics() > 0)
GL.db.detectionLog = {{key=other.key}, {key=id.key}}
GL.db.tracker.groups = {char1={[id.key]="group-one", [other.key]="other"}}
prompt()
pending.dialog.OnAccept(nil, pending.record)
local stats = GL.PersonalStatistics()
assert(not GL.Get(id) and not GL.Get(id.alias) and GL.Get(other) == other)
assert(stats.honor == 3 and stats.deaths == 0)
assert(not GL.db.tracker.groups.char1[id.key] and GL.db.tracker.groups.char1[other.key] == "other")
for _, entry in ipairs(GL.db.detectionLog) do assert(entry.key ~= id.key) end
assert(GL.GetGuildRule(id) and #GL.GuildMembers(id.guild) == 0)
assert(not GL.RecordSeen(id, true), "a player's visible guild marker cannot immediately recreate the profile")
assert(GrudgeLedgerWindow.detailTitle:GetText() == other.fullName)
now = now + 601
local fresh = assert(GL.RecordSeen(id, true))
assert(fresh ~= record and #fresh.notes == 0 and #fresh.history == 0)
assert(not GL.DeleteProfile(record) and GL.Get(id) == fresh, "old confirmations cannot delete a recreated profile")
GL.InitDB()
assert(#GL.Get(id).notes == 0 and GL.Get(other) and GL.PersonalStatistics().deaths == 0)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS named profile deletion, cancellation, stale dialogs, scoped cleanup, totals and later guild sightings")
