-- Relations told as a story (0.40.0): the overview with its three portraits, the ledger of debts
-- with struck lines, and nicknames drawn from the facts. Journal data only, nothing from outside.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local I, R = GL.CharacterInsights, GL.RelationsPages
local now = GL.Now()
GetServerTime = function() return now end
local function click(b) b.scripts.OnClick(b, "LeftButton") end
local function person(first, last, id) return GL.IdentityFromName(first, last, "Player-9-" .. id) end

-- An empty book: every portrait says how it is earned, and nobody owes anything.
GL.ShowRelations()
local f = GrudgeLedgerStatistics
local overview, ledger = f.storyHost.pages.overview, f.storyHost.pages.debts
assert(f.story == "overview" and overview:IsShown() and not ledger:IsShown() and f.storyTabs.overview.active)
assert(overview.cards[2].name:GetText() == "Personne pour l’instant" and overview.cards[2].line:GetText() == "Deux morts face au même joueur.")
assert(overview.noDebt:GetText() == "Personne ne vous doit rien." and overview.week:GetText() == "Rien de notable ces sept derniers jours.")

-- A nemesis who killed you twice in the same zone, a prey beaten three times, a debt already avenged.
GetRealZoneText = function() return "Tanaris" end
local noni, prey, avenged = person("Noni", "Vachementop", "0001"), person("Pist", "Qr", "0002"), person("Siro", "Siro", "0003")
GL.RecordPvP(noni, "death", "confirmed", "fixture", "n1")
now = now + 600
GL.RecordPvP(noni, "death", "confirmed", "fixture", "n2")
for i = 1, 3 do
    now = now + 600
    GL.RecordPvP(prey, "kill", "confirmed", "fixture", "p" .. i)
end
now = now + 600
GL.RecordPvP(avenged, "death", "confirmed", "fixture", "s1")
for i = 1, 6 do
    now = now + 600
    GL.RecordPvP(avenged, "kill", "confirmed", "fixture", "s" .. (i + 1))
end
local nemesis = GL.Get(noni)
assert(I.Nickname(nemesis) == "Le Fléau de Tanaris", tostring(I.Nickname(nemesis)))
assert(I.Nickname(GL.Get(prey)) == "Votre proie favorite" and R.Prey() == GL.Get(prey))
assert(I.Nickname(GL.Get(person("Sans", "Histoire", "0009")) or {}) == nil, "no nickname without facts")

GL.ShowRelations()
assert(overview.cards[2].record == nemesis and overview.cards[2].nick:GetText() == "« Le Fléau de Tanaris »")
assert(overview.cards[2].line:GetText() == "Vous a tué 2 fois · vous doit " .. GL.Debt(nemesis), overview.cards[2].line:GetText())
assert(overview.cards[3].record == GL.Get(prey) and overview.cards[1].record == nil)
assert(overview.debts[1].record == nemesis and overview.debts[1].amount:GetText() == tostring(GL.Debt(nemesis)) and not overview.debts[2]:IsShown())
assert(overview.week:GetText():find("nouvel ennemi", 1, true) or overview.week:GetText():find("nouveaux ennemis", 1, true), overview.week:GetText())
assert(overview.week:GetText():find("1 dette réglée.", 1, true), overview.week:GetText())

-- The ledger: the open debt first with its amount and buttons, the avenged one struck through.
click(f.storyTabs.debts)
assert(f.story == "debts" and ledger:IsShown() and not overview:IsShown())
local open, settled, total = R.Debts()
assert(#open == 1 and #settled == 1 and settled[1].record == GL.Get(avenged) and total == GL.Debt(nemesis))
assert(ledger.total:GetText() == tostring(total) and ledger.count:GetText() == "1 dettes ouvertes · 1 réglées ce mois-ci")
local first, second = ledger.rows[1], ledger.rows[2]
assert(first.record == nemesis and first.amount:GetText() == tostring(total) and first.bounty:IsShown() and not first.strike:IsShown())
assert(first.detail:GetText() == "2 morts · « Le Fléau de Tanaris »", first.detail:GetText())
assert(second.record == GL.Get(avenged) and second.strike:IsShown() and second.state:GetText() == "Réglée" and not second.bounty:IsShown())
assert(second.detail:GetText():find("^Vengé le "), second.detail:GetText())
assert(not ledger.rows[3]:IsShown() and not ledger.previous:IsEnabled() and not ledger.next:IsEnabled())

-- Rivalries: the most fought first, the score, the debt and the dated thread, oldest to newest.
click(f.storyTabs.rivals)
local rivals = f.storyHost.pages.rivals
assert(f.story == "rivals" and rivals:IsShown() and #R.Rivals() == 3 and R.Rivals()[1].record == GL.Get(avenged))
assert(rivals.record == GL.Get(avenged) and rivals.count:GetText() == "1 / 3" and not rivals.previous:IsEnabled())
assert(rivals.score:GetText():find("6", 1, true) and rivals.facts[2]:GetText() == "Comptes réglés", rivals.score:GetText())
assert(rivals.steps[1]:IsShown() and rivals.steps[1].story:GetText():find("Tanaris", 1, true), rivals.steps[1].story:GetText())
click(rivals.next)
assert(rivals.record == GL.Get(prey) and rivals.nick:GetText() == "« Votre proie favorite »" and rivals.count:GetText() == "2 / 3")
click(rivals.next)
assert(rivals.record == nemesis and rivals.facts[2]:GetText() == "Il vous doit encore " .. GL.Debt(nemesis) and not rivals.next:IsEnabled())

-- Dangerous lands: one line per zone, deaths first, with who killed you there.
click(f.storyTabs.lands)
local lands = f.storyHost.pages.lands
assert(lands:IsShown() and #R.Lands() == 1 and R.Lands()[1].zone == "Tanaris" and R.Lands()[1].deaths == 3 and R.Lands()[1].kills == 9)
assert(lands.rows[1].zone:GetText() == "Tanaris" and lands.rows[1].counts:GetText() == "3 morts · 9 victoires" and not lands.rows[2]:IsShown())
assert(lands.rows[1].who:GetText() == "Noni Vachementop ×2, Siro Siro", lands.rows[1].who:GetText())

-- Guilds: without any guild known the page says so; "En guerre" needs your own rule.
click(f.storyTabs.guilds)
local crests = f.storyHost.pages.guilds
assert(crests:IsShown() and #R.Guilds() == 0 and crests.empty:GetText():find("Aucune guilde", 1, true) and not crests.cards[1]:IsShown())
local seen = person("Noni", "Vachementop", "0001")
seen.guild, seen.guildSeenAt = "Ok Bodycount", now
GL.Remember(seen)
local known = R.Guilds()
assert(#known == 1 and known[1].stance == "hostile" and not known[1].ruled, known[1] and known[1].stance)
GL.SetGuildReaction("Ok Bodycount", "enemy")
known = R.Guilds()
assert(known[1].stance == "enemy" and known[1].ruled)
R.Refresh()
assert(crests.cards[1]:IsShown() and crests.cards[1].stance:GetText() == "En guerre · votre règle", crests.cards[1].stance:GetText())

-- "Classements" opens the fourteen rankings with a way back; the way back returns to the overview.
click(f.storyTabs.rankings)
assert(f.story == nil and not f.storyHost:IsShown() and not f.storyTabs.debts:IsShown() and f.backToStory:IsShown())
click(f.backToStory)
assert(f.story == "overview" and f.storyHost:IsShown())
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS relations story: empty book, nicknames, three portraits, week, ledger with struck debts, rivalries, lands, guild crests, rankings one click away")
