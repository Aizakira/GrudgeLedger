-- Relations told as a story (0.40.0): the overview with its three portraits, the ledger of debts
-- with struck lines, and nicknames drawn from the facts. Journal data only, nothing from outside.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local I, R = GL.CharacterInsights, GL.RelationsPages
local now = GL.Now()
GetServerTime = function() return now end
local function click(b) b.scripts.OnClick(b, "LeftButton") end
local function person(first, last, id) return GL.IdentityFromName(first, last, "Player-9-" .. id) end

-- An empty book opens on the Bilan (0.55.0): every portrait says how it is earned.
GL.ShowRelations()
local f = GrudgeLedgerRelations
local overview, ledger = f.host.pages.recap, f.host.pages.debts
assert(R.page == "recap" and overview:IsShown() and not ledger:IsShown() and f.tabs.recap.active)
-- The book has the sheet's format: a narrow column with the five entries, the page on the sheet.
-- The guild's pages live in their own book, under the Guilde tab.
assert(f.tabs.rankings and f.host:GetWidth() > 600 and f.tabs.debts:GetWidth() < 200 and not f.tabs.guilds and not f.tabs.guildlog)
local people = overview.cards[3]
overview.card = 3
R.Refresh()
assert(people:IsShown() and people.people[1].line:GetText() == "Personne ne vous a tué sur cette période.")
assert(people.people[2].line:GetText() == "Un ami avec qui vous groupez, ou trois groupes cette semaine.")

-- A nemesis who killed you twice in the same zone, a prey beaten three times, a debt already avenged.
GetRealZoneText = function() return "Tanaris" end
local noni, prey, avenged = person("Noni", "Vachementop", "0001"), person("Pist", "Qr", "0002"), person("Siro", "Siro", "0003")
GL.RecordPvP(noni, "death", "confirmed", "fixture", "n1")
now = now + 600
GL.RecordPvP(noni, "death", "confirmed", "fixture", "n2")
now = now + 600
GL.RecordPvP(noni, "death", "confirmed", "fixture", "n3")
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
-- 0.59.0: the nickname is drawn from a pool for its kind; here, the zone where you fell.
assert(I.NicknameKind(nemesis) == "zone" and I.Nickname(nemesis):sub(-11) == " de Tanaris", tostring(I.Nickname(nemesis)))
assert(I.NicknameKind(GL.Get(prey)) == "prey" and GL.Epithets.Known("prey", I.Nickname(GL.Get(prey))) and R.Prey() == GL.Get(prey))
assert(I.Nickname(GL.Get(person("Sans", "Histoire", "0009")) or {}) == nil, "no nickname without facts")

GL.ShowRelations()
assert(people.people[1].record == nemesis and people.people[1].line:GetText() == "Vous a tué 3 fois", people.people[1].line:GetText())
assert(people.people[2].record == nil and people.people[3].record == GL.Get(avenged), "the period's most beaten opponent")

-- The ledger: the open debt first with its amount and buttons, the avenged one struck through.
click(f.tabs.debts)
assert(R.page == "debts" and ledger:IsShown() and not overview:IsShown())
-- The key figures of the left column, like the player sheet's; each line opens its page.
assert(f.keyHeading:GetText() == "Chiffres clés" and f.tally[1].label:GetText() == "Reste dû")
assert(tonumber(f.tally[1].value:GetText()) >= GL.Debt(nemesis) and f.tally[4].label:GetText() == "Rivalités", f.tally[1].value:GetText())
click(f.tally[4])
assert(R.page == "rivals")
click(f.tally[1])
assert(R.page == "debts")
click(f.tabs.recap)
local open, settled, total = R.Debts()
assert(#open == 1 and #settled == 1 and settled[1].record == GL.Get(avenged) and total == GL.Debt(nemesis))
assert(ledger.total:GetText() == tostring(total) and ledger.count:GetText() == "1 dette ouverte · 1 réglée ce mois-ci")
local first, second = ledger.rows[1], ledger.rows[2]
assert(first.record == nemesis and first.amount:GetText() == tostring(total) and first.bounty:IsShown() and not first.strike:IsShown())
assert(first.detail:GetText() == "3 morts · « " .. I.Nickname(nemesis) .. " »", first.detail:GetText())
assert(second.record == GL.Get(avenged) and second.strike:IsShown() and second.state:GetText() == "Réglée" and not second.bounty:IsShown())
assert(second.detail:GetText():find("^Vengé le "), second.detail:GetText())
assert(not ledger.rows[3]:IsShown() and not ledger.previous:IsEnabled() and not ledger.next:IsEnabled())

-- Rivalries (owner's brief, 25/11): strips ranked by what stands out, a click unfolds the sheet.
-- Siro: a death, then six victories; the prey: three victories; Noni: three deaths. All this week.
click(f.tabs.rivals)
local rivals = f.host.pages.rivals
assert(R.page == "rivals" and rivals:IsShown() and #R.Rivals() == 3)
local strips = rivals.strips
assert(strips[1].key == GL.Get(avenged).key and strips[2].key == GL.Get(prey).key and strips[3].key == nemesis.key and not strips[4]:IsShown())
-- Each strip says why it matters (RivalryLines.lua): six victories for a death, three deaths in twenty minutes.
assert(strips[1].motif:GetText() == "6 victoires, il vous craint" and strips[3].motif:GetText() == "Vous a tué 3 fois en 20 minutes", strips[3].motif:GetText())
assert(strips[1].score.kills:GetText() == "6 V" and strips[1].score.deaths:GetText() == "1 M" and strips[1].when:GetText():find("Tanaris", 1, true), strips[1].when:GetText())
assert(rivals.count:GetText() == "Page 1 sur 1" and not rivals.previous:IsEnabled() and not rivals.next:IsEnabled() and not rivals.sheet:IsShown())
-- Unfolded: you and the rival, the sentence, the debt, the latest five fights from oldest to newest.
click(strips[1])
local sheet = rivals.sheet
assert(rivals.open == GL.Get(avenged).key and sheet:IsShown() and sheet.debt:GetText() == "Comptes réglés")
-- The fact that names it, then a line that pushes: you lead, so it gloats.
local told = sheet.story:GetText()
assert(told:find("Siro", 1, true) and told:find("Tanaris", 1, true) and told:find("sixième", 1, true) and #told > 60 and not told:find("{", 1, true), told)
assert(sheet.steps[5]:IsShown() and sheet.steps[5].word:GetText() == "Victoire" and sheet.threadWhen:GetText():find("Tanaris", 1, true))
assert(sheet.youName:GetText() == "Vous" and sheet.rivalName:GetText() == "Siro Siro" and strips[2]:GetHeight() == 36)
-- The sheet takes the strip's place: the strip itself steps aside (owner, 25/11).
assert(not strips[1]:IsShown() and strips[2]:IsShown(), "no strip shown twice")
-- A click on the rival opens their sheet; the bounty sits under the debt.
assert(sheet.rivalHit and sheet.rivalHit.scripts.OnClick and sheet.fold and not sheet.open, "the name opens the sheet")
-- You wear the same frame as your rival, with your own live head when the game shows it (owner, 25/11).
assert(sheet.self and sheet.self.guid == UnitGUID("player") and sheet.you.portraitRim and sheet.rival.portraitRim, "the same frame for both")
-- Edge to edge: the sheet as wide as the strips, on the same left edge.
assert(sheet:GetWidth() == strips[1]:GetWidth(), "the sheet as wide as the strips")
-- The band where you face your rival: Alliance blue on your side, Horde red on theirs, whatever
-- your faction (owner, 25/11), and never turned around.
do
    local nativeFaction = UnitFactionGroup
    for _, side in ipairs({ "Alliance", "Horde", "Neutral" }) do
        UnitFactionGroup = function() return side end
        R.Refresh()
        assert(sheet.band.texture == GL.Art.RivalDuel and (not sheet.band.texCoord or table.concat(sheet.band.texCoord, ",") == "0,1,0,1"), side)
    end
    UnitFactionGroup = nativeFaction
end
-- The strips and the sheet stay above the worn bottom of the page (the last 32 of its 510 units).
assert(rivals.bottom >= -478, "the unfolded page ends at " .. rivals.bottom)
click(strips[3])
assert(rivals.open == nemesis.key and sheet.debt:GetText() == ("Noni vous doit %d points"):format(GL.Debt(nemesis)), sheet.debt:GetText())
assert(sheet.story:GetText():find("20 minutes", 1, true) and sheet.steps[1].word:GetText() == "Mort", sheet.story:GetText())
assert(sheet.steps[1].mark.texture == GL.Art.DeathSeal, "the seal of the kit, from the one list of pictures")
assert(sheet.steps[3]:IsShown() and not sheet.steps[4]:IsShown(), "three fights, three steps")
click(sheet.fold)
assert(not rivals.open and not sheet:IsShown() and strips[1]:GetHeight() == 62 and strips[3]:IsShown(), "the arrow folds it")
-- The search reads every name and guild, any case or accents; nothing found offers to clear it.
local function search(text)
    rivals.search:SetText(text)
    rivals.search.scripts.OnTextChanged(rivals.search)
end
search("NONI")
assert(strips[1].key == nemesis.key and not strips[2]:IsShown())
search("zzz")
assert(not strips[1]:IsShown() and rivals.empty:GetText():find("zzz", 1, true) and rivals.clear:IsShown())
click(rivals.clear)
assert(strips[3]:IsShown() and not rivals.clear:IsShown() and rivals.search:GetText() == "")

-- Dangerous lands: one line per zone, deaths first, with who killed you there.
click(f.tabs.lands)
local lands = f.host.pages.lands
assert(lands:IsShown() and #R.Lands() == 1 and R.Lands()[1].zone == "Tanaris" and R.Lands()[1].deaths == 4 and R.Lands()[1].kills == 9)
assert(lands.rows[1].zone:GetText() == "Tanaris" and lands.rows[1].counts:GetText() == "4 morts · 9 victoires" and not lands.rows[2]:IsShown())
assert(lands.rows[1].who:GetText() == "Noni Vachementop ×3, Siro Siro", lands.rows[1].who:GetText())

-- Guilds, in the guild's book: without any guild known the page says so; "En guerre" needs your rule.
local g = R.OpenGuild("guilds")
assert(g == GrudgeLedgerGuild and g.tabs.guilds.active and g.tabs.guildlog and g.tabs.enemies and not g.tabs.debts)
local crests = g.host.pages.guilds
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
assert(crests.cards[1].initials:GetText() == "OB" and R.Initials("ducks") == "D" and R.Initials("Éclats d’Ombre") == "ÉD", R.Initials("Éclats d’Ombre"))
-- A stranger grouped with three times nine days ago is not "your companion"; a friend grouped with is.
GL.Remember(person("Valf", "Gank", "0010"))
GL.RecordGroup(person("Valf", "Gank", "0010"), "g1", "Tanaris")
GL.RecordGroup(person("Valf", "Gank", "0010"), "g2", "Tanaris")
GL.RecordGroup(person("Valf", "Gank", "0010"), "g3", "Tanaris")
for _, e in ipairs(GL.Get(person("Valf", "Gank", "0010")).history) do
    if e.kind == "grouped" then e.time = now - 9 * 86400 end
end
local _, companion = GL.Titles()
assert(companion == nil, "an old group with a stranger is not a companion")
GL.SetReaction(person("Valf", "Gank", "0010"), "friend")
_, companion = GL.Titles()
assert(companion == GL.Get(person("Valf", "Gank", "0010")).key, "a friend you grouped with is")

-- The Registre (owner, 25/11): one entry for the detailed tables, the debts and the rankings, its
-- five sections under it while one is open. Four entries in the menu.
assert(f.tabs.registry and #f.sections == 5 and not f.tabs.rankings.icon, "the Registre and its five sections")
click(f.tabs.registry)
-- It opens on the section left last (here the debts, read above).
assert(R.page == "debts" and f.tabs.registry.active and f.sections[1]:IsShown() and f.sections[2].active, "the Registre opens where it was left")
click(f.tabs.rivals)
assert(not f.sections[1]:IsShown(), "the sections leave with the Registre")
-- "Menaces": the rankings on their first group; the lists of the group as chips, a click opens the sheet.
click(f.sections[3])
local rankings = f.host.pages.rankings
assert(R.page == "rankings" and rankings:IsShown() and f.tabs.registry.active and f.sections[3].active and #rankings.groups == 3)
assert(rankings.title:GetText() == "Rancunes les plus fortes" and rankings.tabs[1].active and rankings.chips[4]:IsShown() and not rankings.chips[5]:IsShown())
assert(rankings.rows[1].item.record == nemesis and rankings.rows[1].value:GetText() == "−" .. GL.Debt(nemesis), rankings.rows[1].value:GetText())
assert(rankings.rows[1].meta:GetText():find(I.Nickname(nemesis), 1, true), rankings.rows[1].meta:GetText())
-- "Amis": the second group. The old "Combats" group repeated the Adversaires table: it left.
click(f.sections[4])
assert(rankings.group == 2 and f.sections[4].active and not f.sections[3].active)
for _, group in ipairs(rankings.groups) do
    for _, entry in ipairs(group.entries) do assert(entry[2] ~= "Adversaires les plus vaincus", "no repeat of the Adversaires") end
end
-- The crests lead to the guild tab; a guild line shows its initials and your rule.
click(g.tabs.guilds)
click(crests.cards[1])
assert(R.page == "rankings" and rankings.group == 3 and f.sections[5].active and rankings.rows[1].item.name == "Ok Bodycount"
    and rankings.rows[1].initials:GetText() == "OB")
click(rankings.chips[6])
assert(rankings.title:GetText() == "Mes règles de guilde" and rankings.rows[1].value:GetText() == "Ennemi", rankings.rows[1].value:GetText())
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS relations story: the Bilan first, nicknames, three people, ledger with struck debts, rivalries, lands, guild crests in the guild's book, "
    .. "rankings one click away")

-- /gl carte measures what the client allows with maps, and a fight keeps its position (0.45.0).
do
    local shown = #mock.messages
    C_Map = nil
    assert(R.MapProbe() == false and mock.messages[shown + 1]:find("fonctions de carte", 1, true))
    C_Map = {
        GetBestMapForUnit = function() return 1446 end,
        GetMapInfo = function(id) return id == 1446 and { name = "Tanaris", mapType = 3, parentMapID = 1414 } or { name = "Kalimdor", mapType = 2 } end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.5124, 0.2876 end } end,
        GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end,
        GetMapArtLayerTextures = function() return { 11, 12, 13, 14, 21, 22, 23, 24, 31, 32, 33, 34 } end,
        GetMapChildrenInfo = function() return { {}, {}, {} } end,
        GetMapRectOnMap = function() return 0.4, 0.6, 0.5, 0.7 end,
    }
    shown = #mock.messages
    assert(R.MapProbe() == true)
    local report = table.concat(mock.messages, "\n", shown + 1)
    assert(report:find("zone n° 1446 · Tanaris · type 3 · dans Kalimdor", 1, true), report)
    assert(report:find("Position : 0.512 ; 0.288", 1, true) and report:find("12 morceaux · 1002 × 668 · morceau de 256", 1, true), report)
    assert(report:find("3 zones · rectangle de cette zone : 0.4", 1, true), report)
    assert(GrudgeLedgerMapProbe:IsShown() and #GrudgeLedgerMapProbe.pieces == 12)
    -- A fight recorded now keeps where it happened; the guild message format does not carry it.
    local placed = GL.RecordPvP(person("Carte", "Test", "0042"), "death", "confirmed", "fixture", "map-1")
    local event = placed.history[#placed.history]
    assert(event.mapID == 1446 and event.mapX == 0.512 and event.mapY == 0.288, tostring(event.mapX))
    C_Map.GetPlayerMapPosition = function() return nil end
    GL.RecordPvP(person("Carte", "Test", "0042"), "death", "confirmed", "fixture", "map-2")
    assert(placed.history[#placed.history].mapID == nil, "no position, nothing stored")
    -- The map of dangerous lands, in the Terres page (0.47.0): free zoom and drag, zones tinted in
    -- the shape the game itself uses to light them up, fights placed when you close in.
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5124, 0.2876 end } end
    C_Map.GetMapInfo = function(id)
        if id == 1446 then return { mapID = 1446, name = "Tanaris", mapType = 3, parentMapID = 1414 } end
        if id == 1444 then return { mapID = 1444, name = "Feralas", mapType = 3, parentMapID = 1414 } end
        if id == 1414 then return { mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 947 } end
        if id == 947 then return { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 } end
    end
    C_Map.GetMapChildrenInfo = function(id, kind)
        if id == 1414 and kind == 3 then return { { mapID = 1446, name = "Tanaris", mapType = 3 }, { mapID = 1444, name = "Feralas", mapType = 3 } } end
        if id == 947 and kind == 2 then return { { mapID = 1414, name = "Kalimdor", mapType = 2 } } end
        return {}
    end
    C_Map.GetMapRectOnMap = function(child, parent)
        if child == 1446 and parent == 1414 then return 0.4, 0.6, 0.6, 0.8 end
        if child == 1444 and parent == 1414 then return 0.1, 0.3, 0.5, 0.7 end
        if child == 1414 and parent == 947 then return 0.1, 0.5, 0.2, 0.8 end
    end
    C_Map.GetMapInfoAtPosition = function(id, x, y)
        if id ~= 1414 then return nil end
        if x >= 0.4 and x <= 0.6 and y >= 0.6 and y <= 0.8 then return { mapID = 1446 } end
        if x >= 0.1 and x <= 0.3 and y >= 0.5 and y <= 0.7 then return { mapID = 1444 } end
        return { mapID = 1414 }
    end
    C_Map.GetMapHighlightInfoAtPosition = function(id, x, y)
        if id == 1414 and x >= 0.4 and x <= 0.6 and y >= 0.6 then return 9001, nil, 0.8, 0.9, 0.22, 0.21, 0.39, 0.6 end
        return 0
    end
    local methods = getmetatable(UIParent).__index
    function methods:GetLeft() return 100 end
    function methods:GetTop() return 600 end
    function methods:SetVertexColor(...) self.vertex = { ... } end
    function methods:SetAlpha(value) self.alpha = value end
    local cursorX, cursorY = 400, 400
    GetCursorPosition = function() return cursorX, cursorY end
    C_MapExplorationInfo = { GetExploredMapTextures = function(id)
        if id ~= 1446 then return {} end
        return { { textureWidth = 300, textureHeight = 200, offsetX = 100, offsetY = 50, fileDataIDs = { 501, 502 } },
            { textureWidth = 64, textureHeight = 64, offsetX = 0, offsetY = 0, fileDataIDs = { 503 }, isShownByMouseOver = true } }
    end }
    click(f.tabs.lands)
    local landsPage = f.host.pages.lands
    local view = landsPage.map
    local function settle() view.canvas.scripts.OnUpdate(view.canvas, 1) end
    -- One canvas for the whole world (0.48.0). It opens on your continent, whole.
    assert(landsPage.mode == "map" and view:IsShown() and view.root == 947 and not landsPage.rows[1]:IsShown())
    assert(math.abs(view.zoom - 1 / 0.6) < 0.001 and math.abs(view.cx - 0.3) < 0.001 and view.cy == 0.5, view.zoom)
    local continent = view.world.continents[1]
    assert(#view.world.continents == 1 and #continent.art.textures == 12 and continent.art.mask, "the continent's picture, feathered")
    assert(continent.art.textures[1].alpha > 0.3 and continent.art.textures[1].alpha < 0.7 and view.world.art.textures[1].alpha == 1)
    -- One region for the zone you fought in, in the game's shape, added to the map like the game
    -- does (never a black square); the worst zone is bright red. Zones of every continent, no total.
    assert(#view.tallies == 1 and view.tallies[1].zone.name == "Tanaris" and #view.shapes == 1 and view.regions[1]:IsShown())
    -- The owner's rule (25/11): the colour follows the ratio of victories to deaths, none when even,
    -- full at four to one. Here 9 victories for 6 deaths: a light green, and the fraction 9 over 6.
    local lit = math.log(9 / 6) / math.log(4)
    assert(view.shapes[1].zone.shape.file == 9001 and math.abs(view.shapes[1].alpha - lit) < 0.001 and view.regions[1].blendMode == "ADD")
    assert(view.regions[1].vertex[2] > 0.5 and view.labels[1].kills:GetText() == "9" and view.labels[1].deaths:GetText() == "6")
    assert(math.abs(view.tallies[1].zone.rect.left - 0.26) < 0.001 and math.abs(view.shapes[1].zone.shape.width - 0.088) < 0.001)
    assert(view.caption:GetText():find("^Azeroth "), view.caption:GetText())
    -- The owner's kit (25/11): a brass frame over the map, an icon on each entry, the legend under
    -- the key figures while the map shows, the counts under the title.
    assert(view.frame and view.frame.pieces["cadre-hg"] and f.tabs.lands.icon and f.tabs.recap.icon and f.legend:IsShown(), "map kit")
    assert(f.legend.heading:GetText() == "Légende" and f.legend.lines[1]:IsShown() and not f.legend.lines[3]:IsShown())
    assert(not landsPage.lead:IsShown() and view.caption:GetText():find("6 morts", 1, true))
    -- The line under the map stays on the sound part of the sheet (owner report 25/11: it fell on the
    -- worn bottom edge, about the last 32 units of the 510-unit page): map top 70, map, 12, buttons 26.
    assert(70 + view.height + 12 + 26 <= 510 - 30, "the bottom line is above the sheet's curl: " .. view.height)
    assert(view.hint.color and view.hint.color[1] < 0.3 and view.hint.font[2] == 12, "the hint reads: dark ink, 12")
    assert(landsPage.rule.texture and landsPage.rule.texture:find("separateur-carte", 1, true), "the owner's separator")
    -- Zoomed out the fights are hidden; they are placed through the zone's rectangle on the world.
    assert(#view.placed == 1 and view.placed[1].event == event and not view.points[1]:IsShown() and not next(view.live))
    assert(math.abs(view.placed[1].x - (0.26 + 0.512 * 0.08)) < 0.001 and math.abs(view.placed[1].y - (0.56 + 0.288 * 0.12)) < 0.001)
    -- You: an arrow where you stand.
    assert(view.me:IsShown() and math.abs(view.here.x - (0.26 + 0.5124 * 0.08)) < 0.001 and view.mine:IsShown())
    -- The wheel sets where the view goes and the view glides there, the point under the pointer
    -- staying under it. The fights appear, the region fades, the explored pieces of the zone come in.
    local wheel = view.canvas.scripts.OnMouseWheel
    wheel(view.canvas, 1)
    assert(view.goal and math.abs(view.zoom - 1 / 0.6) < 0.001, "nothing jumps")
    view.canvas.scripts.OnUpdate(view.canvas, 0.02)
    assert(view.goal and view.zoom > 1 / 0.6 and view.zoom < view.goal.zoom, view.zoom)
    settle()
    assert(not view.goal and math.abs(view.zoom - 1.3 / 0.6) < 0.001 and math.abs(view.cx - 0.3) < 0.01, view.zoom .. " " .. view.cx)
    for _ = 1, 2 do
        wheel(view.canvas, 1)
        settle()
    end
    assert(view.zoom > 3.6 and view.points[1]:IsShown() and view.regions[1].alpha < view.shapes[1].alpha, view.zoom)
    local live = view.live[1446]
    -- The zone's own map first (25/11: without it, what was never explored showed the continent blown
    -- up into blurred squares), under the explored pieces; never the hover one.
    local base, explored = {}, {}
    for i, tile in ipairs(live and live.tiles or {}) do
        if tile.base then base[#base + 1] = live.textures[i] else explored[#explored + 1] = live.textures[i] end
    end
    assert(#base == 12 and #explored == 2 and explored[1].alpha > 0 and explored[1].alpha < 1, "zone map and explored pieces, not the hover one")
    assert(base[1].drawLayer == nil or base[1].drawSublevel == nil or base[1].drawSublevel < (explored[1].drawSublevel or 1), "the map under the pieces")
    assert(math.abs(explored[2].texCoord[2] - 44 / 64) < 0.001 and math.abs(explored[2].texCoord[4] - 200 / 256) < 0.001)
    -- Holding the button and moving drags the map; the view never leaves it.
    local before = view.cx
    view.canvas.scripts.OnMouseDown(view.canvas, "LeftButton")
    cursorX = cursorX + 60
    view.canvas.scripts.OnUpdate(view.canvas, 0.1)
    view.canvas.scripts.OnMouseUp(view.canvas, "LeftButton")
    assert(view.cx < before and view.cx >= 0.5 / view.zoom - 0.0001, view.cx)
    -- The wheel goes all the way down without ever switching maps.
    for _ = 1, 20 do
        wheel(view.canvas, 1)
        settle()
    end
    assert(view.root == 947 and view.zoom == 40 and R.MapWheel(1) == false, view.zoom)
    -- A click on a count glides to its zone: it fills the view, and the caption names it.
    click(view.labels[1])
    settle()
    assert(math.abs(view.zoom - 0.85 / 0.12) < 0.001 and math.abs(view.cx - 0.3) < 0.001 and math.abs(view.cy - 0.62) < 0.001, view.zoom)
    assert(view.caption:GetText():find("^Tanaris "), view.caption:GetText())
    assert(view.live[1446].textures[#view.live[1446].textures].alpha == 1 and view.out:IsShown())
    -- "Monde" backs out to the whole world; "Ma position" returns to your zone.
    assert(R.MapOut() == true)
    settle()
    assert(view.zoom == 1 and view.cx == 0.5 and not view.out:IsShown() and R.MapOut() == false and R.MapWheel(-1) == false)
    assert(not view.live[1446].textures[1]:IsShown() and continent.art.hidden, "detail and continents step back")
    click(view.mine)
    settle()
    assert(view.zoom > 7 and view.caption:GetText():find("^Tanaris "))
    -- Only finished fights are drawn: an attack without an outcome was a brown square (owner report).
    event.kind = "aggression"
    assert(#R.MapPoints(947, view.world.zones) == 0)
    event.kind = "death"
    -- While the regions speak the map under them is dimmed, so a lit zone stands out; every count
    -- sits on a tinted plate.
    R.MapOut()
    settle()
    assert(view.world.art.textures[1].vertex[1] < 0.5 and view.labels[1].fill.color[4] == 0, "no plate under the number")
    assert(view.labels[1].kills.color[2] == 1 and view.labels[1].deaths.color[1] == 1 and view.labels[1].kills.font[3] == "OUTLINE")
    assert(view.regions[1].boost:IsShown() and view.regions[1].boost.vertex[2] > 0.9, "a won zone is lit twice, green, like a lost one in red")
    -- Guild vision (0.49.0): one box on the page; the guild's fights are counted and drawn with yours.
    local realEnabled, realPoints, realEnable = GL.GuildMap.Enabled, GL.GuildMap.Points, GL.GuildMap.Enable
    local ticked = false
    GL.GuildMap.Enabled = function() return ticked, true end
    GL.GuildMap.Enable = function(value) ticked = value end
    GL.GuildMap.Points = function()
        if not ticked then return {} end
        return { { actor = "Player-1-Mate0001", time = 1700000300, mapID = 1444, x = 0.5, y = 0.5, kind = "death" },
            { actor = "Player-1-Mate0001", time = 1700000200, mapID = 1444, x = 0.2, y = 0.4, kind = "kill" },
            { actor = "Player-1-Mate0002", time = 1700000100, mapID = 99999, x = 0.2, y = 0.4, kind = "death" } }
    end
    R.Refresh()
    assert(landsPage.guild:IsShown() and not landsPage.guild:GetChecked() and #view.tallies == 1 and #view.placed == 1)
    landsPage.guild:SetChecked(true)
    landsPage.guild.scripts.OnClick(landsPage.guild)
    assert(ticked == true and landsPage.guild:GetChecked() and landsPage.lead:GetText() == "Vos combats et ceux de la guilde.")
    assert(#view.tallies == 2 and view.tallyOf[1444].deaths == 1 and view.tallyOf[1444].kills == 1, #view.tallies)
    assert(#view.placed == 3 and view.placed[2].guild == "Player-1-Mate0001" and view.hint:GetText():find("guilde : 2", 1, true), view.hint:GetText())
    assert(math.abs(view.placed[2].x - (0.1 + 0.2 * 0.4)) < 0.001, "placed through the zone's rectangle; an unknown map is left out")
    landsPage.guild:SetChecked(false)
    landsPage.guild.scripts.OnClick(landsPage.guild)
    assert(#view.tallies == 1 and #view.placed == 1)
    -- The guild's journal (0.51.0): one line a fight, yours included, a click opens the opponent's sheet.
    ticked = true
    GL.GuildMap.Points = function(withMine)
        assert(withMine == true, "the journal asks for your own fights too")
        local list = {}
        for i = 1, 9 do
            list[i] = { actor = "Player-1-Mate0001", time = GL.Now() - i * 3600, mapID = 1444, kind = i % 2 == 0 and "kill" or "death",
                target = i < 9 and "Player-1-Foe0001" or nil, name = i < 9 and "Bad Guy" or nil }
        end
        list[1].mine, list[1].actor = true, "Player-1-Me000001"
        return list
    end
    local gb = R.OpenGuild("guildlog")
    local log = gb.host.pages.guildlog
    assert(log:IsShown() and log.title:GetText() == "Journal de guilde" and log.rows[1].story:GetText() == "Vous avez été tué par Bad Guy")
    assert(log.rows[2].story:GetText() == "Un membre de la guilde a tué Bad Guy" and log.rows[2].where:GetText() == "Feralas · il y a 2 h")
    assert(log.rows[6]:IsShown() and log.count:GetText() == "9 combats · 5 morts" and log.next:IsEnabled() and not log.previous:IsEnabled())
    -- The Journal's three controls: search, the list button with its count, "Filtres".
    assert(log.viewCycle:GetText() == "Tous · 9" and log.openFilters:GetText() == "Filtres" and not log.filterPanel:IsShown())
    local opened
    local realDossier = GL.OpenPlayerDossier
    GL.OpenPlayerDossier = function(id, _, known) opened = id .. "/" .. tostring(known) end
    click(log.rows[2])
    assert(opened == "Player-1-Foe0001/Bad Guy", opened)
    -- "Rechercher": a wanted notice without gold, in one click; the button leaves once one runs.
    local posted
    local realPost, realOpen = GL.Bounties.Post, GL.Bounties.OpenFor
    GL.Bounties.Post = function(target, known, copper)
        posted = target .. "/" .. known .. "/" .. copper
        return "order-1"
    end
    GL.Bounties.OpenFor = function(target) return posted and target == "Player-1-Foe0001" and { state = "open" } or nil end
    assert(log.rows[2].wanted:IsShown())
    click(log.rows[2].wanted)
    assert(posted == "Player-1-Foe0001/Bad Guy/0" and not log.rows[2].wanted:IsShown(), posted)
    GL.Bounties.Post, GL.Bounties.OpenFor = realPost, realOpen
    click(log.next)
    assert(log.rows[3].story:GetText() == "Un membre de la guilde a été tué par un joueur inconnu" and not log.rows[3].sheet:IsShown())
    assert(not log.rows[3].wanted:IsShown() and not log.rows[4]:IsShown() and not log.next:IsEnabled())
    -- The list button: Tous, Morts, Victoires, Mes combats, each with its count; a new list starts clean.
    click(log.viewCycle)
    assert(log.viewCycle:GetText() == "Morts · 5" and log.count:GetText() == "5 combats · 5 morts" and log.offset == 0)
    click(log.viewCycle)
    assert(log.viewCycle:GetText() == "Victoires · 4")
    click(log.viewCycle)
    assert(log.viewCycle:GetText() == "Mes combats · 1" and log.rows[1].story:GetText() == "Vous avez été tué par Bad Guy")
    click(log.viewCycle)
    assert(log.viewCycle:GetText() == "Tous · 9")
    -- The search finds a member or an opponent by part of the name.
    log.search:SetText("bad")
    log.search.scripts.OnEnterPressed(log.search)
    assert(log.count:GetText() == "8 combats · 4 morts", log.count:GetText())
    log.search:SetText("")
    log.search.scripts.OnTextChanged(log.search)
    assert(log.count:GetText() == "9 combats · 5 morts")
    -- "Filtres" opens the Journal's panel: period, member, enemy; the button counts what is chosen.
    click(log.openFilters)
    local panel = log.filterPanel
    assert(panel:IsShown() and panel.periodCaption:GetText() == "Période : Toujours" and panel.whoCaption:GetText() == "Membre : Tous les membres")
    assert(panel.who[1]:GetText() == "Tous les membres" and panel.who[2]:GetText() == "Vous · 1" and panel.who[3]:GetText() == "Un membre de l… · 8")
    assert(panel.foe[2]:GetText() == "Bad Guy · 8" and not panel.foe[3]:IsShown(), "an unnamed opponent is not offered")
    click(panel.who[3])
    assert(panel:IsShown() and log.count:GetText() == "8 combats · 4 morts" and log.openFilters:GetText() == "Filtres · 1")
    assert(panel.whoCaption:GetText() == "Membre : Un membre de la guilde")
    click(panel.periods[3])
    assert(panel.periodCaption:GetText() == "Période : 7 jours" and log.openFilters:GetText() == "Filtres · 2")
    click(panel.foe[2])
    assert(log.count:GetText() == "7 combats · 3 morts" and log.openFilters:GetText() == "Filtres · 3")
    -- Nothing left: the page says how to get everything back, and "Effacer" does it.
    log.filter.who = "Player-1-Nobody01"
    R.Refresh()
    assert(not log.rows[1]:IsShown() and log.empty:GetText():find("Effacer", 1, true))
    click(panel.clear)
    assert(log.count:GetText() == "9 combats · 5 morts" and log.openFilters:GetText() == "Filtres" and log.viewCycle:GetText() == "Tous · 9")
    click(panel.close)
    assert(not panel:IsShown())
    -- The guild's book (0.55.0): the guild vision's box, the guild's week as key figures, and the
    -- guild's enemies, the deadliest first.
    assert(gb.vision:IsShown() and gb.vision:GetChecked() and gb.keyHeading:GetText() == "Chiffres clés")
    assert(gb.tally[1].label:GetText() == "Morts · 7 j" and gb.tally[1].value:GetText() == "5" and gb.tally[4].value:GetText() == "2")
    click(gb.tally[3])
    local enemies = gb.host.pages.enemies
    assert(R.page == "enemies" and enemies:IsShown() and enemies.viewCycle:GetText() == "Toujours · 1")
    assert(enemies.rows[1].story:GetText() == "Bad Guy" and enemies.rows[1].deaths:GetText() == "4" and not enemies.rows[2]:IsShown())
    assert(enemies.rows[1].where:GetText() == "2 membres tués · vaincu 4 fois par la guilde · Feralas, il y a 1 h", enemies.rows[1].where:GetText())
    click(enemies.rows[1])
    assert(opened == "Player-1-Foe0001/Bad Guy")
    click(gb.tabs.guildlog)
    GL.OpenPlayerDossier = realDossier
    ticked = false
    R.Refresh()
    assert(not log.rows[1]:IsShown() and log.empty:GetText():find("décochée", 1, true))
    click(f.tabs.lands)
    GL.GuildMap.Enabled, GL.GuildMap.Points, GL.GuildMap.Enable = realEnabled, realPoints, realEnable
    -- "Voir la liste" gives the list back; a client without map pictures only has the list.
    click(landsPage.toggle)
    assert(landsPage.mode == "list" and not view:IsShown() and landsPage.rows[1]:IsShown() and landsPage.toggle:GetText() == "Voir la carte")
    click(landsPage.toggle)
    C_Map.GetMapArtLayerTextures = function() return {} end
    view.worlds, view.root = {}, nil
    R.Refresh()
    assert(not view:IsShown() and landsPage.rows[1]:IsShown(), "no picture: the list")
    assert(#GL.errors == 0, (GL.errors[1] or {}).text)
    print("PASS map: probe facts, position kept on fights, one continuous canvas from world to zone, lit regions, explored detail, arrow, glide, list fallback")
end
