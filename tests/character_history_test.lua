-- Dated history of a character and the build of both players at each fight.
local now = 1800000000
local function client(saved)
    local env=setmetatable({_G=false,GrudgeLedgerDB=saved},{__index=_G})
    env._G=env
    env.loadfile=function(p) return setfenv(assert(loadfile(p)),env) end
    local mock=env.loadfile(TEST_WORK.."/tests/addon_mock.lua")()
    env.GetServerTime=function() return now end
    env.UnitLevel=function(unit) return unit=="player" and 36 or 30 end
    env.UnitHealthMax=function(unit) return unit=="player" and 1500 or 1000 end
    env.GetAverageItemLevel=function() return 31, 30 end
    env.GetInventoryItemID=function(unit,slot) if unit=="player" and slot==1 then return 555 end end
    return {env=env,GL=env.GrudgeLedger,m=mock}
end
local c=client()
local GL=c.GL
local identity=GL.IdentityFromName("History","Target","Player-1-abcd")
local record=GL.Remember(identity)
local guid=identity.guid
local function snapshot(at,level,guild,head,points)
    c.env.GrudgeLedgerArmory=c.env.GrudgeLedgerArmory or {items={},profiles={}}
    local items=c.env.GrudgeLedgerArmory.items
    items[#items+1]={id=head,name="Helmet "..head,ref="item:"..head,icon=1}
    c.env.GrudgeLedgerArmory.profiles[guid]={updated=at,level=level,averageItemLevel=level-5,
        identity={name="History Target",guild=guild},gear={head=#items},
        trees={{name="Affliction",points=points[1]},{name="Démonologie",points=points[2]},{name="Destruction",points=points[3]}}}
end
local function changes(key)
    local out={}
    for _,change in ipairs(GL.db.characterHistory[guid].changes) do
        if change.key==key then out[#out+1]=change.value end
    end
    return out
end
local t1=now
snapshot(t1,32,"Old Guild",100,{0,31,0})
GL.CharacterHistory.Collect(guid)
now=now+3*86400
local t2=now
snapshot(t2,38,"New Guild",200,{31,0,20})
GL.CharacterHistory.Collect(guid)
local levels=changes("level")
assert(levels[1]==32 and levels[#levels]==38,"level history keeps both values in order")
local heads=changes("gear:head")
assert(#heads==2 and heads[1]==100 and heads[2]==200,"each piece keeps its own history")
assert(changes("guild")[1]=="Old Guild" and changes("guild")[2]=="New Guild")
assert(changes("spec")[2]=="31/0/20")
-- An older snapshot arriving late does not rewrite the history.
now=now+10
snapshot(t1-86400,30,"Ancient Guild",50,{0,0,31})
GL.CharacterHistory.Collect(guid)
assert(changes("level")[#changes("level")]==38 and #changes("gear:head")==2,"older data is ignored")
-- The same value only confirms it.
now=now+10
snapshot(t2+60,38,"New Guild",200,{31,0,20})
GL.CharacterHistory.Collect(guid)
assert(#changes("gear:head")==2)
-- The dossier shows what changed.
local evolution=table.concat(GL.CharacterEvolution(guid),"\n")
assert(evolution:find("de 32 à 38",1,true) and evolution:find("de Old Guild à New Guild",1,true),evolution)
assert(evolution:find("1 pièces changées",1,true) or evolution:find("pièces changées",1,true),evolution)
-- A fight records both builds as they were at that moment.
now=now+3600
local _,event=GL.RecordPvP(identity,"death","confirmed","fixture","history-death")
local build=assert(event.build,"the fight carries the builds")
assert(build.opponent.gear.head==200 and build.opponent.spec=="31/0/20" and build.opponent.at==t2+60,"opponent as known at the fight")
assert(build.opponent.source=="armory")
assert(build.me.level==36 and build.me.stats.HEALTH==1500 and build.me.gear.head==555 and build.me.ilvl==30,"our own build")
local text=GL.FightBuildText(event)
assert(text:find("Affliction 31/0/20",1,true) and text:find("vie 1500",1,true),text)
-- A later change of gear does not alter the fight's memory.
now=now+86400
snapshot(now,40,"New Guild",300,{31,0,20})
GL.CharacterHistory.Collect(guid)
assert(event.build.opponent.gear.head==200 and changes("gear:head")[3]==300)
-- Everything survives a reload.
local saved=GL.db
local d=client(saved)
assert(d.GL.db.characterHistory[guid] and #d.GL.db.characterHistory[guid].changes>=8)
local reloaded=d.GL.Get(identity)
local kept
for _,e in ipairs(reloaded.history) do if e.eventId=="history-death" then kept=e end end
assert(kept and kept.build and kept.build.opponent.gear.head==200)
-- Bounded: at most 120 changes per character. The reloaded client reads the same Armory data.
d.env.GrudgeLedgerArmory=c.env.GrudgeLedgerArmory
for i=1,140 do
    now=now+60
    snapshot(now,40,"New Guild",1000+i,{31,0,20})
    d.GL.CharacterHistory.Collect(guid)
end
assert(#d.GL.db.characterHistory[guid].changes==120,"history is bounded")
assert(#c.GL.errors==0 and #d.GL.errors==0,(c.GL.errors[1] or d.GL.errors[1] or {}).text)
print("PASS character history: dated changes per value and per piece, late data ignored, confirmations, "
    .."dossier evolution, builds of both players frozen at the fight, reload, bounded history")
