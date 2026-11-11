local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local tracked, questID, questTitle, questIndex = true, 123, "Les oreilles des trolls", 2
C_SuperTrack = {
    IsSuperTrackingQuest = function() return tracked end,
    GetSuperTrackedQuestID = function() return questID end,
}
C_QuestLog = {
    GetLogIndexForQuestID = function(id) assert(id == 123) return questIndex end,
    GetTitleForQuestID = function(id) assert(id == 123) return questTitle end,
}
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
local GL = GrudgeLedger
GL.InitDB()
local identity = GL.Identity("target")
local record = GL.RecordPvP(identity, "death", "probable", "PRIVATE technical evidence: UNIT_DIED", "death")
local first = record.history[1]
assert(first.questID == 123 and first.questTitle == questTitle and first.subzone == "Quartier commerçant")
GL.RecordPvP(identity, "kill", "confirmed", "PRIVATE technical evidence: PARTY_KILL", "kill")
GL.RecordAggression(identity, "confirmed", "PRIVATE technical evidence: SPELL_DAMAGE", "hit")
GL.AdjustReputation(identity, 1, "Geste amical envoyé : /kiss", "emote")
GL.AdjustReputation(identity, -1, "Geste négatif envoyé : /spit", "emote")
GL.AdjustReputation(identity, 1, "Super donjon |cff00ff00", "manual")
GL.SetReaction(identity, "friend")
GL.AddNote(identity, "Mon souvenir personnel")
local function text()
    GL.ShowLedger(record.key)
    return GrudgeLedgerWindow.detailText:GetText()
end
local rendered = text()
for _, expected in ipairs({
    "Participation possible à votre mort : 1 fois", "coup fatal non identifié", "Vous l'avez vaincu : 1 fois",
    "Vous a infligé des dégâts : 1 fois", "Geste demandé : Bisou", "Geste demandé : Crachat",
    "Geste demandé : Bisou — avis +1", "Geste demandé : Crachat — avis -1", "Vous l'avez marqué : Ami", "Super donjon ||cff00ff00", "Mon souvenir personnel",
    "11/11/2026 12:00", "Quartier commerçant · Hurlevent", "Quête suivie : Les oreilles des trolls",
}) do assert(rendered:find(expected, 1, true), "missing readable fact: " .. expected) end
for _, hidden in ipairs({ "UNIT_DIED", "PARTY_KILL", "SPELL_DAMAGE", "Geste amical envoyé", "Guilde mémorisée : inconnue" }) do
    assert(not rendered:find(hidden, 1, true), "technical/noisy detail leaked: " .. hidden)
end
assert(first.evidence == "PRIVATE technical evidence: UNIT_DIED", "presentation must not destroy correction evidence")
GL.RecordGroup(identity, "different-place", "Monastère écarlate")
local group = record.history[#record.history]
assert(group.kind == "grouped" and not group.subzone and not group.questTitle, "explicitly different locations must not inherit current context")
assert(GL.VoidPvP(record, first))
assert(text():find("annulé, non comptabilisé", 1, true) and record.pvp.probableDeaths == 0)

-- A newer quest/location cannot rewrite an old event, even after loading the DB again.
questTitle = "Une autre quête"
GetSubZoneText = function() return "Une autre sous-zone" end
GL.AdjustReputation(identity, 1, "Nouveau souvenir", "manual")
assert(record.history[#record.history].questTitle == questTitle)
GL.InitDB()
assert(first.questTitle == "Les oreilles des trolls" and first.subzone == "Quartier commerçant")
table.insert(record.history, { kind = "death", confidence = "confirmed", zone = "Ancien lieu", time = 1 })
local legacy = record.history[#record.history]
text()
assert(not legacy.questTitle and not legacy.subzone, "never invent context for legacy events")
assert(text():find("Vous a tué", 1, true))

local function withoutQuest()
    GL.AdjustReputation(identity, 1, "Contexte indisponible", "manual")
    local event = record.history[#record.history]
    assert(not event.questID and not event.questTitle, "invalid or untracked quests must not be guessed")
end
tracked = false withoutQuest() -- A waypoint with a remembered quest ID is not a tracked quest.
tracked = mock.secret withoutQuest()
tracked = true
questIndex = nil withoutQuest() -- Quest not in the log.
questIndex = 0 withoutQuest()
questIndex = mock.secret withoutQuest()
questIndex = 2
questTitle = mock.secret withoutQuest()
questTitle = "|Hquest:123|hunsafe|h" withoutQuest()
questTitle = "Public title"
for _, id in ipairs({ mock.secret, -1, 0, math.huge, 0/0, 1.5 }) do questID = id withoutQuest() end
questID = 123
C_QuestLog.GetTitleForQuestID = function() error("unavailable") end
withoutQuest()
C_QuestLog, C_SuperTrack = nil, nil
GetSubZoneText = function() return mock.secret end
withoutQuest()
assert(not record.history[#record.history].subzone)

local previous = #record.history
GL.ShowLedger(record.key)
local display = GrudgeLedgerWindow.detailText:GetText()
assert(#record.history == previous, "the 20-event display cap must not truncate the stored journal")
local _, count = display:gsub("11/11/2026 12:00", "")
assert(count == 21, "20 visible history entries plus the personal note date")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS readable history: actions and participants, honest uncertainty, literal notes, retained evidence/corrections, immutable quest/subzone snapshots, old events, protected/missing quest APIs and bounded display")
