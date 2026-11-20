-- Dated facts on the sheet (study, sections 3 and 6): who opens the fights, level gap, his spells,
-- his companions, streaks, recent fights, hours, days and zones. No score, every fact is listed.
local mock=assert(loadfile(TEST_WORK.."/tests/addon_mock.lua"))()
local GL=GrudgeLedger
local T0=1794400000 -- 12:26 UTC
local now=T0
time=function() return now end
GetServerTime=function() return now end
local I=GL.CharacterInsights
local HOUR=3600
local me=mock.units.player.guid
local identity=GL.IdentityFromName("Habit","Rogue","Player-9-00AA")
local record=GL.Remember(identity)
local guid=identity.guid

-- Four visits: two evenings, one more evening the next day, one morning. A second sighting
-- within ten minutes is the same visit.
I.RecordVisit(guid,T0+9*HOUR,"Elwynn")
I.RecordVisit(guid,T0+9*HOUR+60,"Elwynn")
I.RecordVisit(guid,T0+10*HOUR,"Elwynn")
I.RecordVisit(guid,T0+33*HOUR,"Elwynn")
I.RecordVisit(guid,T0+45*HOUR,"Baie")

-- Fights recorded after visits started, so they are not counted twice as sightings.
local function fight(kind,at,his,mine,rows)
    local e={kind=kind,time=at,zone="Elwynn",confidence="confirmed",actorGUID=me,actorName="Testeur",
        combat={opponentLevel=his,playerLevel=mine},report=rows and {live=rows}}
    record.history[#record.history+1]=e
    return e
end
local function opening(at,opener)
    record.history[#record.history+1]={kind="opening",time=at,opener=opener,actorGUID=me,zone="Elwynn"}
end
opening(T0+20*HOUR,"opponent")
opening(T0+30*HOUR,"opponent")
opening(T0+40*HOUR,"player")
fight("death",T0+20*HOUR+30,42,38,{
    {src=guid,dst=me,spell="Corruption",amount=50,at=1},{src=guid,dst=me,spell="Corruption",amount=50,at=2},
    {src=guid,dst=me,spell="Peur",at=3},{src="Player-1-friend",dst=me,from="Complice",spell="Frappe",amount=20,at=4}})
fight("kill",T0+30*HOUR+30,41,38)
fight("kill",T0+40*HOUR+30,42,39)
fight("kill",T0+41*HOUR,40,39).voided=true
now=T0+48*HOUR

local facts=I.Facts(record,guid)
local byKey,texts={},{}
for _,item in ipairs(facts) do
    byKey[item.key]=item
    texts[#texts+1]=item.text
end
local all=table.concat(texts,"\n")
assert(byKey.opening and byKey.opening.text=="Il ouvre le combat 2 fois sur 3" and #byKey.opening.facts==3,all)
assert(byKey.levels.text=="Écart de niveau moyen avec vous : +3 (3 combats)",all)
assert(byKey.spells.text=="Ses sorts contre vous : Corruption (2), Peur (1)",all)
assert(byKey.helpers.text=="Combats avec complices : 1 sur 1 · Complice (1)",all)
assert(byKey.streak.text=="Vous l’avez vaincu 2 fois de suite" and #byKey.streak.facts==2,all)
assert(byKey.recent.text=="3 combats ces 7 derniers jours",all)
assert(byKey.hours.text:find("(3 sur 4 apparitions)",1,true) and #byKey.hours.facts==3,all)
assert(byKey.days.text=="Vu 3 jours sur les 14 derniers",all)
assert(byKey.opening.facts[1].at==T0+40*HOUR,"facts are listed most recent first")
local presence=I.Presence(record,guid)
assert(presence.total==4 and presence.max==1 and I.Zones(presence)=="Elwynn (3), Baie (1)")

-- A journal from before this version: its dated events count as sightings.
local old=GL.Remember(GL.IdentityFromName("Old","Contact","Player-9-00BB"))
old.history[#old.history+1]={kind="kill",time=T0-86400,zone="Strangleronce",confidence="confirmed",actorGUID=me}
old.history[#old.history+1]={kind="grouped",time=T0-86400+60,zone="Strangleronce",actorGUID=me}
old.history[#old.history+1]={kind="trade",time=T0-3600,zone="Hurlevent",actorGUID=me}
local oldPresence=I.Presence(old,old.guid)
assert(oldPresence.total==2 and I.Zones(oldPresence)=="Hurlevent (1), Strangleronce (1)","events closer than ten minutes are one sighting")

-- A real sighting from the journal records a visit.
record.lastZone="Baie"
now=T0+50*HOUR
GL.Emit("CONTACT_SEEN",record)
assert(I.Presence(record,guid).total==5)
local saved=GL.db.characterHistory[guid].presence
assert(#saved.visits==5 and saved.zones.Baie==2)

-- The sheet: facts with their count, expandable to the dated events, and the presence grid.
local function click(b) b.scripts.OnClick(b,"LeftButton") end
assert(GL.OpenPlayerDossier(guid))
local f=GrudgeLedgerPlayerDossier
-- The sheet has pages instead of a scroll bar: walk them all, from the first.
local function eachRow(visit)
    while f.pagePrev:IsShown() and f.pagePrev:IsEnabled() do click(f.pagePrev) end
    repeat
        for _,r in ipairs(f.rows) do
            if r:IsVisible() and visit(r) then return r end
        end
        local more=f.pageNext:IsShown() and f.pageNext:IsEnabled()
        if more then click(f.pageNext) end
    until not more
end
local function all()
    local visible={}
    eachRow(function(r) visible[#visible+1]=r.caption:GetText().." "..r.amount:GetText() end)
    while f.pagePrev:IsShown() and f.pagePrev:IsEnabled() do click(f.pagePrev) end
    return table.concat(visible,"\n")
end
local function rows()
    local visible={}
    eachRow(function(r) visible[#visible+1]=r end)
    return visible
end
-- Leaves the sheet on the page that holds the row, so it can be clicked.
local function find(caption)
    return eachRow(function(r) return r.caption:GetText()==caption end)
end
-- The overview is one page: the first facts as cards, the full list one click away.
local o=f.overview
assert(o:IsVisible() and not f.body:IsVisible() and not f.pageNext:IsShown(),"the overview needs no page turning")
assert(o.cards[1]:IsShown() and o.cards[1].value:GetText()=="2 / 3" and o.cards[1].caption:GetText()=="ouvre le combat lui-même")
assert(o.factsLink:GetText()=="Tous les faits (8)",o.factsLink:GetText())
click(o.cards[1])
assert(f.factsMode and f.body:IsVisible() and not o:IsVisible())
local row=assert(find("Il ouvre le combat 2 fois sur 3"))
assert(row.amount:GetText()=="Masquer","the card opens its own facts")
local before=#rows()
click(row)
assert(#rows()==before-3 and find("Il ouvre le combat 2 fois sur 3").amount:GetText()=="Faits (3)","the facts close")
click(find("Vous l’avez vaincu 2 fois de suite"))
local detail=eachRow(function(r)
    return r.amount:GetText()=="Détail" and r.caption:GetText():find("Vous l'avez vaincu",1,true)
end)
assert(detail,"a fight fact opens its fight detail")
click(detail)
assert(GrudgeLedgerCorrections:IsShown())
GrudgeLedgerCorrections:Hide()
click(assert(find("Tous les faits")))
assert(not f.factsMode and o:IsVisible(),"back to the overview")
-- The twelve-month strip: one square per week.
local seen=0
for _,cell in ipairs(o.strip.cells) do seen=seen+(tonumber(cell.detail and cell.detail:match("^(%d+)")) or 0) end
assert(seen==5,"five visits on the strip: "..seen)
-- Habits: levels with tooltips, tiles, zones as a list that turns its own pages.
click(f.tabs.habits)
local h=f.habits
assert(h:IsVisible() and h.tiles[1].value:GetText()=="5" and h.tiles[2].value:GetText()=="3")
local evening=h.grid.cells[((math.floor((T0+9*HOUR)/86400)+3)%7)*24+21]
assert(evening.count==1 and math.abs(evening.fill.color[4]-.3)<.01,"one visit is level 1")
assert(h.grid.cells[0].count==0 and h.grid.cells[0].fill.color[4]<.11)
GameTooltip.SetOwner=function(self,owner) self.owner,self.lines=owner,{} end
evening.scripts.OnEnter(evening)
assert(GameTooltip.owner==evening and GameTooltip:GetText():find("de 21 h à 22 h",1,true) and GameTooltip.lines[1]=="1 apparition",GameTooltip:GetText())
evening.scripts.OnLeave(evening)
-- Five visits in the same hour reach the darkest level.
for k=1,4 do I.RecordVisit(guid,T0+9*HOUR-k*7*86400,"Elwynn") end
click(f.tabs.overview)
click(f.tabs.habits)
assert(evening.count==5 and evening.fill.color[4]==1,"five visits are level 4")
assert(h.zones.title:GetText()=="Zones · 2" and h.zones.rows[1].label:GetText()=="Elwynn" and h.zones.rows[1].value:GetText()=="7")
-- Thirty zones: the list turns its own pages, four lines at a time, without a scroll bar.
for k=1,30 do I.RecordVisit(guid,T0+60*HOUR+k*HOUR,"Zone "..k) end
click(f.tabs.overview)
click(f.tabs.habits)
assert(h.zones.turner:IsShown() and h.zones.turner.label:GetText():find("^1 / "),"long lists have pages")
click(h.zones.turner.next)
assert(h.zones.page==2 and h.zones.rows[1]:IsShown())
click(f.tabs.combat)
assert(not h:IsVisible())
assert(#GL.errors==0,(GL.errors[1] or {}).text)
print("PASS character insights: openings, level gap, spells, companions, streak, recent fights, hours, days, zones, "
    .."older journals, visit recording, expandable facts and presence grid")
