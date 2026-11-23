local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local units, messages = mock.units, mock.messages
local now, size = GL.Now(), 0
GetServerTime = function() return now end
GetNumGroupMembers = function() return size end
local sends = 0
SendChatMessage = function() sends = sends + 1 end
C_ChatInfo.SendAddonMessage = SendChatMessage
GL.SetSetting("guideSeen", true)
GL.SetSetting("groupTracking", false)
local function click(b) return b:GetScript("OnClick")(b, "LeftButton") end

local aqua = GL.Identity("target")
local root = mock.NewMenu()
mock.menuHooks.MENU_UNIT_PARTY(nil, root, {unit="target"})
local menu = root.children["Grudge Ledger"].children["Étiquettes personnelles"]
assert(menu and not GL.Get(aqua), "opening a menu does not add a contact")
local originalUnit = units.target
units.target = {name="Aqua", surname="Rocks", guid="Player-1-other"}
menu.buttons["Butin ninja"]()
local record = assert(GL.Get(aqua))
assert(GL.HasTag(record, "ninja") and not GL.Get(GL.Identity("target")), "frozen menu identity")
assert(not GL.ToggleTag(aqua, "unknown"))
assert(GL.Relation(record) == "neutral" and GL.AutomaticBalance(record) == 0 and #record.history == 0)
GL.AddNote(aqua, "Donjon")
GL.EditNote(aqua)
local editor, ledger = GrudgeLedgerNote, GrudgeLedgerWindow
click(editor.tags)
click(editor.tagChoices.reliable)
assert(editor.tagChoices.ninja.active and editor.tagChoices.reliable.active)
editor.edit:SetText("Un brouillon")
click(editor.tagChoices.toxic)
assert(editor.edit:GetText() == "Un brouillon" and #record.notes == 1)
click(editor.tagChoices.toxic)
assert(GL.TagText(record) == "Butin ninja, Fiable")
local sameFirst = GL.Remember(GL.Identity("target"))
assert(not GL.HasTag(sameFirst))
GL.ShowLedger(record.key)
-- 0.33.0: one Filtres button opens the panel that holds every filter.
click(ledger.openFilters) assert(ledger.filterPanel:IsShown())
click(ledger.tagFilters.ninja)
click(ledger.notesOnly)
click(ledger.factions.Alliance)
assert(ledger.filterPanel:IsShown() and ledger.openFilters:GetText() == "Filtres · 3", ledger.openFilters:GetText())
assert(ledger.rows[1].key == record.key and not ledger.rows[2]:IsShown())
assert(GL.SearchPlayers({query="butin donjon",tag="reliable"})[1] == record)
assert(#GL.SearchPlayers({tag="ninja", faction="Horde"}) == 0)
click(ledger.detailTabs.notes) click(editor.tags) click(editor.tagChoices.ninja)
assert(not ledger.rows[1]:IsShown() and ledger.emptyPage:IsShown() and not editor:IsShown(), "removing the active filter's tag updates the page")
click(ledger.reset)
assert(ledger.tagFilters.all.active and not ledger.notesOnly.active and #GL.SearchPlayers() == 2)

GL.ShowLedger(record.key)
local function selectedRow()
    for _, row in ipairs(ledger.rows) do if row.key == record.key then return row end end
end
local row = assert(selectedRow())
local strip = ledger.tagStrip
assert(strip:IsShown() and strip.caption:GetText() == "Fiable" and strip.caption:IsShown())
assert(row.tagStrip.caption:GetText() == "Fiable" and row.tagStrip.caption:IsShown())
assert(table.concat(strip.icons[1].texCoord, ",") == "0.25,0.5,0.5,1" and GL.Relation(record) == "neutral")
for _, choice in ipairs(GL.TagChoices) do if choice[1] ~= "reliable" then GL.ToggleTag(aqua, choice[1]) end end
assert(strip.icons[6]:IsShown() and not strip.caption:IsShown() and row.tagStrip.caption:GetText() == "+3")
GL.SetSetting("compactMode", true)
GL.ShowLedger(record.key)
row = assert(selectedRow())
assert(row.tagStrip.icons[1]:IsShown() and not row.tagStrip.icons[2]:IsShown() and row.tagStrip.caption:GetText() == "+5")
GL.ShowLedger(sameFirst.key)
assert(not strip:IsShown(), "selecting an untagged contact clears the previous header")
GL.ShowLedger(record.key)
for _, choice in ipairs(GL.TagChoices) do GL.ToggleTag(aqua, choice[1]) end
assert(not strip:IsShown() and not selectedRow().tagStrip:IsShown() and selectedRow().name:GetWidth() == 195)
GL.ToggleTag(aqua, "reliable")
assert(strip.caption:GetText() == "Fiable" and not strip.icons[2]:IsShown())
GL.SetSetting("compactMode", false)

local provisional = GL.IdentityFromName("Forge", "Light")
local guidOnly = GL.IdentityFromName("Forge", nil, "Player-1-forge")
GL.ToggleTag(provisional, "leaver") GL.ToggleTag(guidOnly, "boosted")
GL.Get(provisional).tagRemindedAt = {["Player-1-former"] = now - 17}
local merged = GL.Remember(GL.IdentityFromName("Forge", "Light", guidOnly.guid))
assert(GL.HasTag(merged,"leaver") and GL.HasTag(merged,"boosted") and GL.Get(provisional) == merged)
assert(merged.tagRemindedAt["Player-1-former"] == now - 17)
GL.InitDB()
assert(GL.HasTag(GL.Get(aqua),"reliable") and GL.HasTag(GL.Get(guidOnly),"leaver"))

units.target = originalUnit
GameTooltip.lines, GameTooltip._grudgeLedgerKey = {}, nil
GL.SetSetting("compactTooltips", true)
GL.Display.Tooltip(GameTooltip)
assert(table.concat(GameTooltip.lines,"\n"):find("Étiquettes : Fiable",1,true))
local old = #messages
local function invite(name, guid)
    mock.Fire("PARTY_INVITE_REQUEST", name, false, false, false, true, false, false, guid)
end
invite("Aqua", nil)
invite("Aqua Water", sameFirst.guid)
assert(#messages == old, "ambiguous names and another GUID cannot claim the tagged identity")
invite("Aqua", aqua.guid) invite("Aqua Water", aqua.guid)
assert(#messages == old + 1 and messages[#messages]:find("Invitation de Aqua Water — Fiable",1,true))
units.party1 = originalUnit
units.party2 = {name="Forge",surname="Light",guid=guidOnly.guid}
size = 3
mock.Fire("GROUP_ROSTER_UPDATE") mock.Fire("GROUP_ROSTER_UPDATE")
assert(#messages == old + 2 and messages[#messages]:find("Forge Light",1,true) and not messages[#messages]:find("Aqua Water",1,true))
now = now + 601
mock.Fire("GROUP_ROSTER_UPDATE")
assert(#messages == old + 2, "continuously present members do not repeat after cooldown")
units.party1, units.party2, size = nil, nil, 0
mock.Fire("GROUP_ROSTER_UPDATE")
units.party1, units.party2, size = originalUnit, {name="Forge",surname="Light",guid=guidOnly.guid}, 3
mock.Fire("GROUP_ROSTER_UPDATE")
assert(#messages == old + 3 and messages[#messages]:find("Aqua Water",1,true) and messages[#messages]:find("Forge Light",1,true), "one summary for a whole group")
now = now + 601
mock.Fire("PLAYER_LEAVING_WORLD")
units.party1, units.party2 = nil, nil
mock.Fire("GROUP_ROSTER_UPDATE")
mock.Fire("PLAYER_ENTERING_WORLD", false, true)
units.party1, units.party2 = originalUnit, {name="Forge",surname="Light",guid=guidOnly.guid}
mock.Fire("GROUP_ROSTER_UPDATE")
assert(#messages == old + 3)
units.party1, units.party2, size = nil, nil, 0
mock.Fire("GROUP_ROSTER_UPDATE")
GL.SetSetting("tagReminders", false)
invite("Forge Light", guidOnly.guid)
units.party1, size = originalUnit, 2
mock.Fire("GROUP_ROSTER_UPDATE")
assert(#messages == old + 3 and sends == 0)
assert(GL.DeleteProfile(record) and GL.TagText(GL.Get(aqua)) == nil and GL.HasTag(merged,"boosted"))
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS private tags: identity, notes and journal filters, local tooltip, invitation and deduplicated roster, persistence and deletion")
