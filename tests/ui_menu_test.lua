-- Actual Core + UI + Menu under the shared deterministic WoW-frame fixture.
local addon = assert(TEST_ROOT, "Set TEST_ROOT to the GrudgeLedger addon directory")
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
getmetatable(UIParent).__index.HighlightText = function(self) self.highlighted = true end
local menuHooks, units, secret = mock.menuHooks, mock.units, mock.secret
local cvars = mock.cvars
assert(loadfile(addon .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(addon .. "/UITheme.lua"))()
assert(loadfile(addon .. "/UI.lua"))()
assert(loadfile(addon .. "/Menu.lua"))()
local GL = GrudgeLedger
GL.InitDB()
assert(GrudgeLedgerMinimapButton and not GrudgeLedgerWindow, "login must not open the journal")

local function open(context, tag)
    local root = mock.NewMenu()
    assert(menuHooks[tag or "MENU_UNIT_PLAYER"])(nil, root, context)
    local submenu = root.children["Grudge Ledger"]
    if submenu then
        assert(#root.entries == 2 and root.entries[1].kind == "divider", "one compact addon entry at the top level")
        assert(root.entries[2].text == "Grudge Ledger" and not root.entries[2].callback, "native hover submenu has no action on its parent")
        assert(not next(root.buttons), "all player actions belong inside the submenu")
    else assert(#root.entries == 0, "invalid contexts must not add empty menus") end
    return submenu or root
end
assert(not next(open(nil).buttons), "nil context")
assert(not next(open(secret).buttons), "secret context")
assert(not next(open({ unit = secret, name = secret }).buttons), "secret fields")
assert(not next(open({ unit = "npc" }).buttons), "no NPC records")
assert(not next(open({ unit = "player" }).buttons), "no self records")
assert(not next(open({ name = "Ambiguous" }).buttons), "no bare-name guesses")

local r = open({ unit = "target" })
assert(r.buttons.Ami and r.buttons.Ennemi and r.buttons.Automatique and not r.buttons.Neutre and r.buttons["Ajouter une note"])
assert(not next(GL.db.players), "opening a menu must not create a record")
units.target = { name = "Megumin", surname = "Crimson", guid = "Player-1-megumin" }
r.buttons.Ami()
local aqua = GL.Get("guid:Player-1-aqua")
assert(aqua and GL.Relation(aqua) == "friend", "menu action must use original target")
assert(not GL.Get("guid:Player-1-megumin"), "new target must be untouched")
r.buttons.Ennemi()
assert(GL.Relation(aqua) == "enemy", "direct enemy state, no arithmetic")
r.buttons.Automatique()
assert(GL.Relation(aqua) == "neutral" and aqua.reactionSource == "automatic", "automatic is neutral without debt")
assert(r.buttons["Méfiance"] and r.buttons["Avis positif (+1)"] and r.buttons["Avis négatif (-1)"])
r.buttons["Méfiance"]()
assert(GL.Relation(aqua) == "warning" and aqua.reputation == -1)
r.buttons["Avis positif (+1)"]()
assert(GL.Relation(aqua) == "neutral" and aqua.reputation == 0)
r.buttons["Avis négatif (-1)"]()
assert(GL.Relation(aqua) == "warning" and aqua.reputation == -1)
r.buttons.Ennemi()
r.buttons["Avis positif (+1)"]()
assert(GL.Relation(aqua) == "warning" and aqua.reputation == -9, "positive step can leave red tier")
r.buttons.Automatique()

open({ lineID = 10 }, "MENU_UNIT_CHAT_ROSTER").buttons.Ami()
assert(GL.Get("guid:Player-1-darkness").surname == "FordDustiness", "chat surname preserved")
open({ name = "Same", server = "SurnameOne" }).buttons.Ami()
open({ name = "Same", server = "SurnameTwo" }).buttons.Ennemi()
assert(GL.Relation(GL.Get("name:same surnameone")) == "friend")
assert(GL.Relation(GL.Get("name:same surnametwo")) == "enemy", "identical first names stay separate")

local function childButton(parent, text)
    for _, child in ipairs(parent.children) do if child.text == text and child.scripts.OnClick then return child end end
    error("missing button " .. text)
end
local function click(frame) assert(frame.enabled ~= false, "disabled button") frame.scripts.OnClick(frame, "LeftButton") end

r.buttons["Ajouter une note"]()
assert(GrudgeLedgerNote:IsShown())
GrudgeLedgerNote.edit:SetText("Super donjon, personne cool |cff00ff00")
click(childButton(GrudgeLedgerNote, "Enregistrer"))
assert(#aqua.notes == 1 and aqua.notes[1].text:find("Super donjon", 1, true))
assert(not GrudgeLedgerNote:IsShown() and not GL.Get("guid:Player-1-megumin"))
GL.EditNote(aqua)
GrudgeLedgerNote.edit:SetText("Brouillon conservé")
GrudgeLedgerNote:Hide()
GL.EditNote(aqua)
assert(GrudgeLedgerNote.edit:GetText() == "Brouillon conservé", "Escape/close keeps unsaved draft")
GrudgeLedgerNote.edit:SetText(string.rep("Ligne de note\n", 40))
assert(GrudgeLedgerNote.edit:GetHeight() > GrudgeLedgerNote.scroll:GetHeight(), "multiline editor child must grow beyond viewport")
GrudgeLedgerNote.edit.scripts.OnCursorChanged(GrudgeLedgerNote.edit, 0, -520, 1, 13)
assert(GrudgeLedgerNote.scroll:GetVerticalScroll() >= 393, "cursor follows down beyond viewport")
GrudgeLedgerNote.edit.scripts.OnCursorChanged(GrudgeLedgerNote.edit, 0, -2, 1, 13)
assert(GrudgeLedgerNote.scroll:GetVerticalScroll() == 2, "cursor follows back to top")
GrudgeLedgerNote.edit:SetText("Court")
assert(GrudgeLedgerNote.scroll:GetVerticalScroll() == 0, "shortening note clamps stale scroll offset")
GrudgeLedgerNote.edit:SetText(string.rep("é", 1001))
click(childButton(GrudgeLedgerNote, "Enregistrer"))
assert(GrudgeLedgerNote:IsShown() and #aqua.notes == 1, "over-byte-limit note rejected without losing editor")

r.buttons["Ouvrir la fiche"]()
assert(GrudgeLedgerWindow:IsShown())
assert(GrudgeLedgerWindow.detailText:GetText():find("||cff00ff00", 1, true), "notes rendered as literal text")
GL.RecordPvP(aqua, "death", "probable", "Déduction", "ui-test")
assert(GL.Relation(aqua) == "enemy" and aqua.reputation == -10, "automatic keeps new PvP debt visible")
assert(GrudgeLedgerWindow.metrics.deaths.value:GetText() == "0 fois" and GrudgeLedgerWindow.metrics.deaths.probable:GetText() == "1 probable", "summary separates the probable death from confirmed deaths")
assert(GrudgeLedgerWindow.balance:GetText() == "-10")
GL.RecordPvP(aqua, "kill", "confirmed", "Direct", "ui-repayment")
r.buttons.Automatique()
assert(GL.Relation(aqua) == "warning" and aqua.reputation == -9)
assert(GrudgeLedgerWindow.reactions.warning.selection:IsShown() and not GrudgeLedgerWindow.reactions.neutral.selection:IsShown(), "automatic selects the effective dangerous relation")
assert(GrudgeLedgerWindow.detailStatus:GetText():find("Méfiance", 1, true))
GL.SetReaction(aqua, "friend")
click(GrudgeLedgerWindow.reactions.neutral)
assert(GL.Relation(aqua) == "warning" and aqua.reputation == -9, "journal button shares the same automatic calculation")
click(GrudgeLedgerWindow.detailTabs.history)
assert(GrudgeLedgerWindow.detailText:GetText():find("Classement automatique réactivé", 1, true))
GL.SetReaction(aqua, "warning")
local status = GrudgeLedgerWindow.detailStatus
assert(status:GetText():find("Méfiance", 1, true) and status.color[1] > status.color[2] and status.color[2] > status.color[3], "warning uses readable orange ink and an explicit status label")
assert(not GrudgeLedgerWindow.detailText:GetText():find("Vous a infligé des dégâts", 1, true), "history does not invent aggression events")
click(GrudgeLedgerWindow.detailTabs.summary)
assert(GrudgeLedgerWindow.detailText:GetText():find("Agressions : 0 confirmée, 0 probable", 1, true))
click(GrudgeLedgerWindow.actions[1])
assert(GL.Relation(aqua) == "friend")
GrudgeLedgerWindow.search:SetText("%")
click(GrudgeLedgerWindow.searchButton)
assert(GrudgeLedgerWindow.total:GetText():find("0 personne", 1, true), "search is literal, no Lua pattern")
GrudgeLedgerWindow.search:SetText("")
click(GrudgeLedgerWindow.searchButton)

SlashCmdList.GRUDGELEDGER("options")
assert(GrudgeLedgerSettings:IsShown())
click(GrudgeLedgerSettings.tabs.alerts)
local check = GrudgeLedgerSettings.checks.sounds
check:SetChecked(false) click(check)
assert(GL.Settings().sounds == false)
click(GrudgeLedgerSettings.tabs.relations)
local socialCheck = GrudgeLedgerSettings.checks.socialTracking
socialCheck:SetChecked(false) click(socialCheck)
assert(GL.Settings().socialTracking == false)
assert(not next(cvars), "no automatic changes to nameplate settings")
mock.SetCombat(true)
click(GrudgeLedgerSettings.tabs.appearance)
local recognition = childButton(GrudgeLedgerSettings.pages.appearance, "Activer le repérage (icônes + couleurs)")
click(recognition)
SlashCmdList.GRUDGELEDGER("reperage")
assert(not next(cvars), "no restricted CVar changes in combat")
assert(not GL.Settings().nameColor, "combat rejection also preserves addon preferences")
mock.SetCombat(false)
local allowed = { nameplateShowFriendlyPlayers = true, nameplateShowEnemies = true, nameplateShowAll = true }
C_CVar = {
    SetCVar = function(key, value) assert(allowed[key], "obsolete or unrelated CVar") cvars[key] = value end,
    GetCVar = function(key) return cvars[key] and tostring(cvars[key]) or "0" end,
}
click(recognition)
assert(cvars.nameplateShowFriendlyPlayers == 1 and cvars.nameplateShowEnemies == 1 and cvars.nameplateShowAll == 1)
assert(not cvars.nameplateShowFriends, "use Forever's current friendly-player filter")
assert(GL.Settings().markers and GL.Settings().nameColor)
assert(GrudgeLedgerSettings.checks.nameColor:GetChecked())
assert(GrudgeLedgerSettings.plateStatus:GetText():find("Alliés : activées", 1, true))
GL.SetSetting("markers", false) GL.SetSetting("nameColor", false)
cvars.nameplateShowFriendlyPlayers = 0
SlashCmdList.GRUDGELEDGER("reperage")
assert(cvars.nameplateShowFriendlyPlayers == 1 and GL.Settings().markers and GL.Settings().nameColor,
    "command and button share the complete setup")
C_CVar.SetCVar = function() error("CVar refused") end
cvars.nameplateShowFriendlyPlayers = 0
SlashCmdList.GRUDGELEDGER("repérage")
assert(mock.messages[#mock.messages]:find("pas confirmé", 1, true), "do not claim success after a refused setting")
C_CVar = nil
SlashCmdList.GRUDGELEDGER("reperage")
assert(cvars.nameplateShowFriendlyPlayers == 1, "legacy global API fallback")
SlashCmdList.GRUDGELEDGER("+ Super donjon")
local megumin = GL.Get("guid:Player-1-megumin")
assert(megumin.reputation == 1 and GL.Relation(megumin) == "friend")
assert(megumin.history[#megumin.history].evidence == "Super donjon", "macro reason preserves text")
SlashCmdList.GRUDGELEDGER("- Mauvais souvenir")
assert(megumin.reputation == 0)
SlashCmdList.GRUDGELEDGER("mefiance")
assert(megumin.reputation == -1 and GL.Relation(megumin) == "warning")
SlashCmdList.GRUDGELEDGER("ennemi")
assert(megumin.reputation == -10 and GL.Relation(megumin) == "enemy")
SlashCmdList.GRUDGELEDGER("ami")
assert(GL.Relation(megumin) == "friend")
SlashCmdList.GRUDGELEDGER("neutre")
assert(GL.Relation(megumin) == "neutral")
GL.RecordPvP(megumin, "death", "probable", "Observed", "command-death")
GL.RecordPvP(megumin, "kill", "confirmed", "Direct", "command-repayment")
for _, command in ipairs({ "auto", "automatique", "neutre" }) do
    GL.SetReaction(megumin, "friend")
    SlashCmdList.GRUDGELEDGER(command)
    assert(megumin.reputation == -9 and GL.Relation(megumin) == "warning" and megumin.reactionSource == "automatic")
end
SlashCmdList.GRUDGELEDGER("note Très bon donjon avec cette personne !")
assert(megumin.notes[1].text == "Très bon donjon avec cette personne !")
SlashCmdList.GRUDGELEDGER("note")
assert(GrudgeLedgerNote:IsShown() and GrudgeLedgerNote.identity.guid == megumin.guid)
local beforeReputation = megumin.reputation
units.target = nil
SlashCmdList.GRUDGELEDGER("- Sans cible")
assert(megumin.reputation == beforeReputation, "missing target must not reuse old macro identity")
SlashCmdList.GRUDGELEDGER("debug")
for _, frame in ipairs({ GrudgeLedgerWindow, GrudgeLedgerNote, GrudgeLedgerSettings }) do
    assert(frame.topLevel and frame.raised > 0, "all windows must be top-level and raised on opening")
end
local raised = GrudgeLedgerNote.raised
GL.EditNote(aqua)
assert(GrudgeLedgerNote.raised > raised, "reopening visible note editor raises it")
raised = GrudgeLedgerWindow.raised
GL.ShowLedger(aqua.key)
assert(GrudgeLedgerWindow.raised > raised, "reopening visible ledger raises it")
raised = GrudgeLedgerSettings.raised
SlashCmdList.GRUDGELEDGER("settings")
assert(GrudgeLedgerSettings.raised > raised, "reopening visible settings raises it")
assert(#GL.errors == 0, "UI callbacks must not silently error")
print("PASS ui_menu: immutable click targets, context validation, exact identities, direct relations, notes/drafts, rendering, settings, no forced UI/CVars.")
