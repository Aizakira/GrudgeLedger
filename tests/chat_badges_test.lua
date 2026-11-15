local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
ChatFrameUtil = nil
assert(loadfile(TEST_ROOT .. "/ChatBadges.lua"))()
local GL = GrudgeLedger
GL.InitDB()
local changes, filter = 0, nil
-- Forever's GetDecoratedSenderName passes (event, decorated name, raw fields...).
-- Returning nil preserves the already decorated name, including RGB and links.
ChatFrameUtil = {
    AddSenderNameFilter = function(f) assert(not filter) filter, changes = f, changes + 1 end,
    RemoveSenderNameFilter = function(f) assert(filter == f) filter, changes = nil, changes + 1 end,
}
local sent = 0
function SendChatMessage() sent = sent + 1 end
C_ChatInfo.SendChatMessage = SendChatMessage
local id = GL.Identity("target")
local record = GL.SetReaction(id, "enemy")
assert(GL.AddNote(record, "private note"))
local name = "|cffFFAA00|Hplayer:Aqua|h[Aqua]|h|r"
local function chat(event, guid, decorated, field11)
    return filter(event, decorated, mock.secret, "other sender name", nil,nil,nil,nil,nil,nil,nil,nil,field11,guid)
end
assert(not GL.Settings().chatBadges and not filter and changes == 0)
GL.SetSetting("chatBadges", true)
GL.Emit("SETTINGS")
assert(filter and changes == 1)
local events = #record.history
for _, event in ipairs({"CHAT_MSG_CHANNEL", "CHAT_MSG_PARTY", "CHAT_MSG_WHISPER", "CHAT_MSG_INSTANCE_CHAT"}) do
    local text = chat(event, id.guid, name)
    assert(text == "|TInterface\\AddOns\\GrudgeLedger\\Media\\RelationEnemy:14:14|t " .. name)
    assert(not text:find("private", 1, true))
end
assert(#record.history == events and not record.encounters and not record.friendPresence)
assert(not chat("CHAT_MSG_CHANNEL", mock.secret, name, id.guid))
assert(not chat("CHAT_MSG_CHANNEL", id.guid, mock.secret))
assert(not chat("CHAT_MSG_CHANNEL", nil, name, id.guid))
assert(not chat("CHAT_MSG_WHISPER_INFORM", id.guid, name))
local before = 0
for _ in pairs(GL.db.players) do before = before + 1 end
assert(not chat("CHAT_MSG_SAY", "Player-1-unknown", name))
local after = 0
for _ in pairs(GL.db.players) do after = after + 1 end
assert(before == after and sent == 0)
local formerPartyMember = GL.Remember(GL.IdentityFromName("Unmarked", "Companion", "Player-1-unmarked"))
formerPartyMember.groupCount = 1
assert(not chat("CHAT_MSG_PARTY", formerPartyMember.guid, name))
GL.SetReaction(record, "friend")
assert(chat("CHAT_MSG_GUILD", id.guid, name):find("RelationFriend",1,true))
GL.SetReaction(record, "warning")
assert(chat("CHAT_MSG_GUILD", id.guid, name):find("RelationWarning",1,true))
GL.SetReaction(record, "neutral")
assert(chat("CHAT_MSG_GUILD", id.guid, name):find("RelationNeutral",1,true))
IsInInstance = function() return true, "pvp" end
assert(not chat("CHAT_MSG_INSTANCE_CHAT", id.guid, name))
GL.SetSetting("chatBadges", false)
GL.Emit("SETTINGS")
assert(not filter and changes == 2 and #GL.errors == 0 and sent == 0)
print("PASS chat badges: native filter lifecycle, trusted sender GUID, unchanged name/colors, private notes, no writes or sends, BG and opt-out")
