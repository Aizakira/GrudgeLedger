-- The Bilan (0.53.0), first page of Relations since 0.55.0: nine cards turned like stories. Who you
-- are, your numbers, your three people, your territory, the classes and races that kill you, who
-- strikes first, your honor, your guild. Journal data only. Above the card, the period and the
-- characters, the copy and the old tables.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local R = GL.Recap
local now = GL.Now()
GetServerTime = function() return now end
local function click(b) b.scripts.OnClick(b, "LeftButton") end
local function person(first, last, id, class, className)
    local identity = GL.IdentityFromName(first, last, "Player-9-" .. id)
    identity.class, identity.className = class, className
    return identity
end

-- An empty journal: a wanderer, nothing to name, and every card says so plainly.
local f = R.Open(1)
local page = f.host.pages.recap
assert(f == GrudgeLedgerRelations and GL.RelationsPages.page == "recap" and f.tabs.recap.active)
assert(page.period == "month" and page.periodButton:GetText() == "Ce mois-ci" and page.scopeButton:GetText() == "Ce personnage")
assert(page.cards[1]:IsShown() and not page.cards[2]:IsShown() and #page.dots == 9)
local who = page.cards[1]
assert(who.archetype:GetText() == "Le Voyageur" and who.title:GetText() == "", who.archetype:GetText())

-- Three deaths against a rogue in Tanaris, three victories over a mage in Feralas.
GetRealZoneText = function() return "Tanaris" end
local noni, prey = person("Noni", "Vachementop", "0001", "ROGUE", "Voleur"), person("Pist", "Qr", "0002", "MAGE", "Mage")
for i = 1, 3 do
    now = now + 600
    GL.RecordPvP(noni, "death", "confirmed", "fixture", "d" .. i)
end
GetRealZoneText = function() return "Feralas" end
for i = 1, 3 do
    now = now + 600
    GL.RecordPvP(prey, "kill", "confirmed", "fixture", "k" .. i)
end
GL.RelationsPages.Refresh()
assert(who.archetype:GetText() == "Le Duelliste" and who.sentence:GetText() == "Combat après combat, l’équilibre : 3 victoires, 3 morts.")
assert(who.title:GetText() == "« Le Fléau de Feralas »", who.title:GetText())

-- The arrows and the dots turn the cards; the last card leads back to the first.
click(page.next)
local numbers = page.cards[2]
assert(page.card == 2 and numbers:IsShown() and not who:IsShown())
assert(numbers.values[1]:GetText() == "3" and numbers.values[2]:GetText() == "3" and numbers.ratio:GetText() == "1,0 victoire par mort.")
click(page.dots[3])
local people = page.cards[3]
assert(people.heading:GetText() == "Vos trois personnes")
assert(people.people[1].name:GetText() == "Noni Vachementop" and people.people[1].line:GetText() == "Vous a tué 3 fois")
assert(people.people[2].record == nil and people.people[3].name:GetText() == "Pist Qr" and people.people[3].line:GetText() == "Vaincu 3 fois")
local opened
local realLedger = GL.ShowLedger
GL.ShowLedger = function(key) opened = key end
click(people.people[1])
assert(opened == GL.Get(noni).key)
GL.ShowLedger = realLedger
click(page.next)
local land = page.cards[4]
assert(land.deadly:GetText() == "Tanaris" and land.deadlyCounts:GetText() == "3 morts · 0 victoires")
assert(land.winning:GetText() == "Feralas" and land.winningCounts:GetText() == "3 victoires · 0 morts")
-- The classes that kill you: the deadliest first, in red; the races card says when nothing is known.
click(page.next)
local classes = page.cards[5]
assert(classes.heading:GetText() == "Les classes qui vous tuent" and classes.rows[1].label:GetText() == "Voleur")
assert(classes.rows[1].counts:GetText() == "3 morts · 0 victoires" and classes.rows[2].label:GetText() == "Mage" and not classes.rows[3]:IsShown())
click(page.next)
local races = page.cards[6]
assert(races.heading:GetText() == "Les races qui vous tuent" and races.empty:GetText() == "Aucun combat sur cette période.")
click(page.next)
assert(page.cards[7].heading:GetText() == "Qui frappe le premier" and page.cards[7].value:GetText() == "—")
click(page.next)
assert(page.cards[8].heading:GetText() == "Votre honneur" and page.cards[8].value:GetText() == "0")
click(page.next)
local guild = page.cards[9]
assert(guild.note:IsShown() and guild.note:GetText():find("Pas de guilde", 1, true) and not guild.open:IsShown())
click(page.next)
assert(page.card == 1)
click(page.previous)
assert(page.card == 9)

-- More victories: you strike harder than you fall, the archetype follows.
for i = 4, 7 do
    now = now + 600
    GL.RecordPvP(prey, "kill", "confirmed", "fixture", "k" .. i)
end
click(page.dots[1])
assert(who.archetype:GetText() == "Le Prédateur", who.archetype:GetText())

-- The period: one button, a click shows the next one. Older fights leave "this week".
now = now + 10 * 86400
click(page.periodButton)
assert(page.period == "year" and page.periodButton:GetText() == "Cette année")
click(page.periodButton)
assert(page.period == "all" and who.archetype:GetText() == "Le Prédateur")
click(page.periodButton)
assert(page.period == "week" and who.archetype:GetText() == "Le Voyageur")
click(page.periodButton)
click(page.periodButton)
click(page.periodButton)
assert(page.period == "all")
click(page.scopeButton)
assert(page.scope == "all" and page.scopeButton:GetText() == "Tout le compte" and who.name:GetText() == "Tous vos personnages")
click(page.scopeButton)

-- "Copier": the card as text, to paste in a chat; the box keeps nothing once closed.
click(page.copy)
assert(page.copyBox:IsShown())
local text = page.copyField:GetText()
assert(text:find("^Grudge Ledger · Bilan · Depuis le début\n"), text)
assert(text:find("Le Prédateur (Le Fléau de Feralas)", 1, true) and text:find("7 victoires · 3 morts", 1, true))
assert(text:find("Némésis : Noni Vachementop (3 morts)", 1, true) and text:find("Zone la plus dangereuse : Tanaris (3 morts)", 1, true))
click(page.copy)
assert(not page.copyBox:IsShown() and page.copyField:GetText() == "")

-- The top tabs: Journal, Relations (which opens on the Bilan), Guilde, Primes. The old tables stay
-- one click away.
GL.ShowLedger()
click(GrudgeLedgerWindow.navigation.players)
assert(f:IsShown() and GL.RelationsPages.page == "recap")
click(f.navigation.guild)
assert(GrudgeLedgerGuild:IsShown() and GL.RelationsPages.page == "guildlog")
GL.ShowRelations()
click(page.details)
assert(GrudgeLedgerJournal and GrudgeLedgerJournal:IsShown())
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS bilan: nine cards in Relations, arrows and dots, archetype and title, three people, territory, classes and races, "
    .. "initiative and honor, period and characters above the card, copied text, Relations and Guilde tabs, detailed tables")
