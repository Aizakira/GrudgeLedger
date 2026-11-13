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
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
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
local function text(tab)
    GL.ShowLedger(record.key)
    local control = GrudgeLedgerWindow.detailTabs[tab or "history"]
    control:GetScript("OnClick")(control)
    return GrudgeLedgerWindow.detailText:GetText()
end
local rendered = text()
for _, expected in ipairs({
    "Participation possible à votre mort", "coup fatal non identifié", "Vous l'avez vaincu",
    "Vous a infligé des dégâts", "Geste demandé : Bisou", "Geste demandé : Crachat",
    "Geste demandé : Bisou — avis +1", "Geste demandé : Crachat — avis -1", "Vous l'avez marqué : Ami", "Super donjon ||cff00ff00",
    "11/11/2026 12:00", "Quartier commerçant · Hurlevent", "Quête suivie : Les oreilles des trolls",
}) do assert(rendered:find(expected, 1, true), "missing readable fact: " .. expected) end
for _, hidden in ipairs({ "UNIT_DIED", "PARTY_KILL", "SPELL_DAMAGE", "Geste amical envoyé", "Guilde mémorisée : inconnue" }) do
    assert(not rendered:find(hidden, 1, true), "technical/noisy detail leaked: " .. hidden)
end
assert(first.evidence == "PRIVATE technical evidence: UNIT_DIED", "presentation must not destroy correction evidence")
assert(text("notes"):find("Mon souvenir personnel", 1, true), "notes have a dedicated readable view")
text("summary")
assert(GrudgeLedgerWindow.metrics.kills.value:GetText() == "1 fois"
    and GrudgeLedgerWindow.metrics.deaths.probable:GetText() == "1 probable"
    and GrudgeLedgerWindow.detailText:GetText():find("Agressions : 1 confirmée, 0 probable", 1, true), "summary keeps confidence counters separate")
assert(GrudgeLedgerWindow.balance:GetText() == "-10" and GrudgeLedgerWindow.scoreContext:GetText():find("Avis personnel", 1, true),
    "manual friendship does not overwrite the displayed automatic debt")
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
local display = text("history")
assert(#record.history == previous, "the 20-event display cap must not truncate the stored journal")
local _, count = display:gsub("11/11/2026 12:00", "")
assert(count == 20, "the history tab renders at most 20 dated events")
assert(text("notes"):find("Mon souvenir personnel", 1, true), "history cap never hides personal notes")
local longNote = "À revoir : à\n\t" .. string.rep("é", 90) .. " souvenir final"
GL.AddNote(record, longNote)
local summary = text("summary")
assert(summary:find("À revoir : à " .. string.rep("é", 67) .. "… (suite dans Notes)", 1, true), "summary folds ASCII whitespace and preserves accented characters under the Windows locale")
assert(GrudgeLedgerWindow.balance:GetText() ~= "" and summary:find("Dernière rencontre", 1, true) < summary:find("Dernière note", 1, true)
    and summary:find("Dernière note", 1, true) < summary:find("Agressions", 1, true), "summary gives encounters and notes priority over supporting details")
assert(text("notes"):find(longNote, 1, true) and record.notes[#record.notes].text == longNote,
    "preview never changes the complete note")
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS readable history: actions and participants, honest uncertainty, literal notes, retained evidence/corrections, immutable quest/subzone snapshots, old events, protected/missing quest APIs and bounded display")
