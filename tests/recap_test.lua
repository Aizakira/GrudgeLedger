-- The Bilan as five cards (0.53.0): who you are, your numbers, your two people, your territory,
-- your guild. Journal data only. One choice of period, turned like stories.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local R = GL.Recap
local now = GL.Now()
GetServerTime = function() return now end
local function click(b) b.scripts.OnClick(b, "LeftButton") end
local function person(first, last, id) return GL.IdentityFromName(first, last, "Player-9-" .. id) end

-- An empty journal: a wanderer, nothing to name, and every card says so plainly.
R.Open(1)
local f = GrudgeLedgerRecap
assert(f:IsShown() and f.period == "month" and f.periods.month.active and f.host.cards[1]:IsShown() and not f.host.cards[2]:IsShown())
local who = f.host.cards[1]
assert(who.archetype:GetText() == "Le Voyageur" and who.title:GetText() == "", who.archetype:GetText())
assert(f.scopeButton:GetText() == "Personnage : celui-ci")

-- Three deaths against the same player in Tanaris, three victories over another in Feralas.
GetRealZoneText = function() return "Tanaris" end
local noni, prey = person("Noni", "Vachementop", "0001"), person("Pist", "Qr", "0002")
for i = 1, 3 do
    now = now + 600
    GL.RecordPvP(noni, "death", "confirmed", "fixture", "d" .. i)
end
GetRealZoneText = function() return "Feralas" end
for i = 1, 3 do
    now = now + 600
    GL.RecordPvP(prey, "kill", "confirmed", "fixture", "k" .. i)
end
R.Refresh()
assert(who.archetype:GetText() == "Le Duelliste" and who.sentence:GetText() == "Combat après combat, l’équilibre : 3 victoires, 3 morts.")
assert(who.title:GetText() == "« Le Fléau de Feralas »", who.title:GetText())

-- The arrows and the dots turn the cards; the last card leads back to the first.
click(f.next)
local numbers = f.host.cards[2]
assert(f.card == 2 and numbers:IsShown() and not who:IsShown())
assert(numbers.values[1]:GetText() == "3" and numbers.values[2]:GetText() == "3" and numbers.ratio:GetText() == "1,0 victoire par mort.")
click(f.dots[3])
local people = f.host.cards[3]
assert(people.people[1].name:GetText() == "Noni Vachementop" and people.people[1].line:GetText() == "Vous a tué 3 fois")
assert(people.people[2].name:GetText() == "Pist Qr" and people.people[2].line:GetText() == "Vaincu 3 fois")
local opened
local realLedger = GL.ShowLedger
GL.ShowLedger = function(key) opened = key end
click(people.people[1])
assert(opened == GL.Get(noni).key)
GL.ShowLedger = realLedger
click(f.next)
local land = f.host.cards[4]
assert(land.deadly:GetText() == "Tanaris" and land.deadlyCounts:GetText() == "3 morts · 0 victoires")
assert(land.winning:GetText() == "Feralas" and land.winningCounts:GetText() == "3 victoires · 0 morts")
click(f.next)
local guild = f.host.cards[5]
assert(guild.note:IsShown() and guild.note:GetText():find("Pas de guilde", 1, true) and not guild.open:IsShown())
click(f.next)
assert(f.card == 1)
click(f.previous)
assert(f.card == 5)

-- More victories: you strike harder than you fall, the archetype follows.
GetRealZoneText = function() return "Feralas" end
for i = 4, 7 do
    now = now + 600
    GL.RecordPvP(prey, "kill", "confirmed", "fixture", "k" .. i)
end
click(f.dots[1])
assert(who.archetype:GetText() == "Le Prédateur", who.archetype:GetText())
assert(who.sentence:GetText() == "Vous frappez le premier, et vous gagnez : 7 victoires pour 3 morts.")

-- One zone for everything: the territory card never says the same name twice.
local facts = R.Facts("all", "character")
assert(facts.deadly.label == "Tanaris" and facts.winning.label == "Feralas" and facts.home.label == "Feralas")

-- The periods: older fights leave "this week" but stay "since the beginning".
now = now + 10 * 86400
click(f.periods.week)
assert(f.period == "week" and f.periods.week.active and who.archetype:GetText() == "Le Voyageur")
click(f.periods.all)
assert(who.archetype:GetText() == "Le Prédateur")
click(f.scopeButton)
assert(f.scope == "all" and f.scopeButton:GetText() == "Personnages : tout le compte" and who.name:GetText() == "Tous vos personnages")
click(f.scopeButton)

-- "Copier le bilan": the card as text, to paste in a chat; the box keeps nothing once closed.
click(f.copy)
assert(f.copyBox:IsShown())
local text = f.copyField:GetText()
assert(text:find("^Grudge Ledger · Bilan · Depuis le début\n"), text)
assert(text:find("Le Prédateur (Le Fléau de Feralas)", 1, true) and text:find("7 victoires · 3 morts", 1, true))
assert(text:find("Némésis : Noni Vachementop (3 morts)", 1, true) and text:find("Zone la plus dangereuse : Tanaris (3 morts)", 1, true))
click(f.copy)
assert(not f.copyBox:IsShown() and f.copyField:GetText() == "")

-- The Bilan tab opens these cards; the old tables stay one click away.
GL.ShowRelations()
click(GrudgeLedgerRelations.navigation.journal)
assert(f:IsShown())
click(f.details)
assert(GrudgeLedgerJournal and GrudgeLedgerJournal:IsShown())
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS bilan: five cards turned with arrows and dots, archetype and title from the journal, nemesis and prey, territory, "
    .. "periods and characters, copied text, Bilan tab and detailed tables")
