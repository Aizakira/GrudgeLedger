-- Guild actions exercise the actual UI/Menu/Core against native-frame mocks.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
assert(loadfile(TEST_ROOT .. "/Menu.lua"))()
local GL, units = GrudgeLedger, mock.units
GL.InitDB()
assert(not GrudgeLedgerGuilds, "no guild window at login")

local function childButton(parent, text)
    for _, child in ipairs(parent.children) do if child.text == text and child.scripts.OnClick then return child end end
    error("missing button " .. text)
end
local function click(frame)
    assert(frame.enabled ~= false, "disabled button")
    frame.scripts.OnClick(frame, "LeftButton")
end
local function open(context)
    local root = mock.NewMenu()
    mock.menuHooks.MENU_UNIT_PLAYER(nil, root, context)
    local submenu = assert(root.children["Grudge Ledger"])
    assert(#root.entries == 2 and not next(root.buttons), "guilds must not expand the root menu")
    assert(not submenu.buttons["Guilde : ennemie"], "guild actions belong in their own nested submenu")
    return submenu.children.Guilde or submenu
end

assert(not open({ unit = "target" }).buttons["Guilde : ennemie"], "guild actions only when guild known")
units.target.guild = "Les Voyageurs Test"
local captured = open({ unit = "target" })
assert(captured.buttons["Guilde : amie"] and captured.buttons["Guilde : méfiance"] and captured.buttons["Guilde : ennemie"] and captured.buttons["Guilde : neutre"])
assert(not next(GL.db.guilds) and not next(GL.db.players), "opening menu must not create guild or person")
units.target = { name = "Megumin", surname = "Crimson", guid = "Player-1-megumin", guild = "Crimson Demons" }
captured.buttons["Guilde : ennemie"]()
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "enemy", "menu keeps original guild after target switch")
assert(not GL.GetGuildRule("Crimson Demons"), "switched target guild remains untouched")
captured.buttons["Guilde : gérer / ajouter une note"]()
local f = GrudgeLedgerGuilds
assert(f:IsShown() and f.name:GetText() == "Les Voyageurs Test")
local function selectedGuild(expected)
    for reaction, control in pairs(f.reactions) do
        assert(control.selection:IsShown() == (reaction == expected), "guild reaction selection must match the exact rule")
    end
end
selectedGuild("enemy")
f.note:SetText("Agression en groupe |cff00ff00")
click(childButton(f, "Enregistrer la note"))
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "enemy", "note edit preserves guild reaction")
assert(GL.GetGuildRule("Les Voyageurs Test").note == "Agression en groupe |cff00ff00")
click(childButton(f, "Amie"))
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "friend")
selectedGuild("friend")
click(childButton(f, "Méfiance"))
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "warning")
selectedGuild("warning")
click(childButton(f, "Neutre"))
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "neutral")
selectedGuild("neutral")
GL.SetGuildReaction("Les Voyageurs Test", "enemy")
selectedGuild("enemy")
assert(f.status:GetText() == "Avis actuel : Ennemi", "external rule changes update the status with the active choice")

-- Exact-name entry works without a target, including same-name guilds on another realm.
units.target = nil
f.name:SetText("Guildes lointaines")
f.realm:SetText("Forever")
selectedGuild(nil)
assert(f.status:GetText() == "Aucun avis sur cette guilde.", "typing another guild clears the previous guild's status")
f.note:SetText("Très bon groupe")
click(childButton(f, "Amie"))
assert(GL.GetGuildRule("Guildes lointaines").reaction == "friend")
assert(f.status:GetText() == "Avis enregistré : Ami", "ordinary refresh preserves save confirmation")
f.realm:SetText("Autre royaume")
selectedGuild(nil)
assert(f.status:GetText() == "Aucun avis sur cette guilde.", "changing realm updates the exact guild's status")
click(childButton(f, "Ennemie"))
assert(GL.GetGuildRule("Guildes lointaines", "Autre royaume").reaction == "enemy")
selectedGuild("enemy")
assert(GL.GetGuildRule("Guildes lointaines", "Forever").reaction == "friend", "realm remains part of guild identity")
local before = GL.GetGuildRule("Guildes lointaines", "Autre royaume").note
f.note:SetText(string.rep("é", 1001))
click(childButton(f, "Enregistrer la note"))
assert(GL.GetGuildRule("Guildes lointaines", "Autre royaume").note == before, "invalid long note preserves saved value")
assert(f.note:GetText() == string.rep("é", 1001), "invalid note draft remains editable")
local validationMessage = f.status:GetText()
GL.Emit("CHANGED")
assert(f.status:GetText() == validationMessage, "unrelated refresh must preserve actionable validation errors")
f.name:SetText("|cff00ff00Bad")
f.note:SetText("")
click(childButton(f, "Ennemie"))
assert(not GL.GetGuildRule("|cff00ff00Bad"), "invalid exact names rejected")
click(childButton(f, "Guilde de la cible"))
assert(f.status:GetText():find("Sélectionne", 1, true))

for i = 1, 12 do GL.SetGuildReaction("Test " .. i, "warning") end
assert(f.total:GetText():find("15 guilde(s)", 1, true))
click(f.next)
assert(f.offset == 9 and f.rows[1].rule, "guild list pages beyond nine entries")
local chosen = f.rows[1].rule
click(f.rows[1])
assert(f.name:GetText() == chosen.name and f.realm:GetText() == chosen.realm, "row opens exact rule")

units.target = { name = "Joueur", surname = "Exemple", guid = "Player-1-guild-test", guild = "Les Voyageurs Test" }
SlashCmdList.GRUDGELEDGER("guilde ennemi")
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "enemy")
local gros = GL.Remember(GL.Identity("target"))
GL.ShowLedger(gros.key)
assert(GL.Relation(gros) == "enemy" and GL.RelationSource(gros) == "guild")
assert(GrudgeLedgerWindow.detailStatus:GetText():find("avis hérité de la guilde", 1, true))
assert(GrudgeLedgerWindow.reactions.enemy.selection:IsShown(), "guild inheritance selects the effective reaction")
assert(GrudgeLedgerWindow.detailText:GetText():find("Dernière guilde connue : Les Voyageurs Test", 1, true))
assert(GrudgeLedgerWindow.detailText:GetText():find("||cff00ff00", 1, true), "guild note is rendered literally")
click(GrudgeLedgerWindow.guildButton)
assert(f.name:GetText() == "Les Voyageurs Test")
GL.SetReaction(gros, "friend")
assert(GL.Relation(gros) == "friend", "individual opinion takes priority over guild")
assert(GrudgeLedgerWindow.detailStatus:GetText():find("choix personnel", 1, true))
assert(GrudgeLedgerWindow.reactions.friend.selection:IsShown() and not GrudgeLedgerWindow.reactions.enemy.selection:IsShown(),
    "manual override updates the selected reaction without hiding its provenance")
SlashCmdList.GRUDGELEDGER("guilde mefiance")
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "warning")
SlashCmdList.GRUDGELEDGER("guilde ami")
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "friend")
SlashCmdList.GRUDGELEDGER("guilde neutre")
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "neutral")
assert(open({ name = "Joueur Exemple", guid = gros.guid }).buttons["Guilde : ennemie"], "chat can use an exact known player's guild")
units.target.guild = nil
assert(open({ unit = "target" }).buttons["Guilde : ennemie"], "missing lookup retains last known guild")
GL.Remember({ name = gros.name, surname = gros.surname, guid = gros.guid, guildKnown = true })
assert(not open({ unit = "target" }).buttons["Guilde : ennemie"], "explicit cleared membership invalidates cached guild too")
units.target.guild = mock.secret
assert(not open({ unit = "target" }).buttons["Guilde : ennemie"], "secret guild must not be used")
units.target = nil
SlashCmdList.GRUDGELEDGER("guilde ennemi")
assert(GL.GetGuildRule("Les Voyageurs Test").reaction == "neutral", "macro cannot reuse stale target guild")
SlashCmdList.GRUDGELEDGER("guilde")
assert(f:IsShown())

local firstGuild = { guild = "Les Voyageurs Test", realm = "Forever" }
local otherGuild = { guild = "Guildes lointaines", realm = "Forever" }
GL.ShowGuilds(firstGuild)
f.note:SetText("Brouillon de la première guilde")
GL.ShowGuilds(otherGuild)
f.note:SetText("Brouillon de la seconde guilde")
GL.ShowGuilds(firstGuild)
assert(f.note:GetText() == "Brouillon de la première guilde", "changing guild and returning preserves unsaved note")
click(childButton(f, "Enregistrer la note"))
GL.ShowGuilds(otherGuild)
assert(f.note:GetText() == "Brouillon de la seconde guilde", "saving one guild must retain other guild drafts")
GL.SetGuildReaction(firstGuild, "neutral", "Note enregistrée plus récente")
GL.ShowGuilds(firstGuild)
assert(f.note:GetText() == "Note enregistrée plus récente", "saved draft must be cleared rather than mask newer saved note")

f.name:SetText("Guilde saisie manuellement")
f.realm:SetText("Forever")
f.note:SetText("Brouillon saisi sans règle")
GL.ShowGuilds(firstGuild)
assert(not GL.GetGuildRule("Guilde saisie manuellement"), "switching selection must not create a rule for typed name")
GL.ShowGuilds({ guild = "Guilde saisie manuellement", realm = "Forever" })
assert(f.note:GetText() == "Brouillon saisi sans règle", "exact typed name retains its unsaved draft")
GL.ShowGuilds({ guild = "Guilde saisie manuellement", realm = "Autre royaume" })
assert(f.note:GetText() == "", "same guild name on another realm has separate draft")
f.note:SetText("Brouillon autre serveur")
GL.ShowGuilds({ guild = "Guilde saisie manuellement", realm = "Forever" })
assert(f.note:GetText() == "Brouillon saisi sans règle")
GL.ShowGuilds({ guild = "Guilde saisie manuellement", realm = "Autre royaume" })
assert(f.note:GetText() == "Brouillon autre serveur")
local raised = f.raised
GL.ShowGuilds()
assert(f.topLevel and f.raised > raised, "reopening visible guild window raises it above later windows")
raised = f.raised
f.scripts.OnMouseDown(f)
assert(f.raised > raised and f.scripts.OnDragStart, "click raises window without removing dragging")
assert(#GL.errors == 0, "guild callbacks must not silently error")
print("PASS guild_ui: immutable menu guilds, exact names/realms, notes/validation/drafts, paged management, manual priority, macro safety, window stacking.")
