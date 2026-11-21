-- One real client, two guild peers, and repeated/out-of-order addon messages.
local owner,hunter,partner,enemy="Player-1-a","Player-1-b","Player-1-c","Player-2-d"
local now,party,raid=1800000000,0,false
local event,notices,changed
local names={[owner]="Issuer",[hunter]="Hunter",[partner]="Friend"}
local ids={owner,hunter,partner}
local env=setmetatable({}, {__index=_G})
local gl={db={},Safe=function(f,...) return f(...) end,Now=function() return now end,
    RequestArmory=function() end,
    Clean=function(v,k) if type(v)==k then return v end end,ContainsControlOrMarkup=function(s) return s:find("[|%c]") end,
    On=function() end,Emit=function(k) if k=="BOUNTIES_CHANGED" then changed=(changed or 0)+1 end end,
    Print=function() notices=(notices or 0)+1 end}
env.GrudgeLedger=gl
env.SlashCmdList={}
env.GetGuildInfo=function() return "Guild" end
env.GetNormalizedRealmName=function() return "Realm" end
env.GetNumGuildMembers=function() return #ids end
env.GetGuildRosterInfo=function(i) return unpack({[1]=names[ids[i]],[17]=ids[i]},1,17) end
env.UnitGUID=function(u) return u=="player" and owner or u=="party1" and hunter or "Player-9-outsider" end
env.UnitExists=function(u) return u=="party1" or u=="party2" end
env.UnitIsUnit=function() return false end
env.UnitIsVisible=function() return true end
env.GetNumGroupMembers=function() return party end
env.IsInRaid=function() return raid end
-- Each frame receives only the events it registered, as in the game.
local frames={}
env.CreateFrame=function()
    local frame={events={}}
    frame.RegisterEvent=function(self,name) self.events[name]=true end
    frame.SetScript=function(self,_,fn) self.handler=fn end
    frames[#frames+1]=frame
    return frame
end
event=function(_,name,...)
    for _,frame in ipairs(frames) do
        if frame.events[name] and frame.handler then frame.handler(frame,name,...) end
    end
end
env.C_ChatInfo={RegisterAddonMessagePrefix=function() end,SendAddonMessage=function() end}
env.C_Timer={NewTicker=function() end}
for _,name in ipairs({"Transport.lua","Bounties.lua"}) do
    local file=assert(loadfile(TEST_ROOT.."/"..name));setfenv(file,env);file()
end
event(nil,"PLAYER_LOGIN")
local b=gl.Bounties
local function receive(kind,actor,seq,id,value,detail)
    local msg=table.concat({kind,actor,seq,now,id,value,detail},";")
    for j=1,2 do event(nil,"CHAT_MSG_ADDON","GLBounty1",msg,"GUILD",names[actor]) end
end

local third={quota=3,group="party",split="equal",souvenir="video",note="Un souvenir pour la guilde."}
assert(not b.Post(enemy,"Enemy",100,{quota=100}))
assert(not b.Post(enemy,"Enemy",100,{quota=1.5}))
assert(not b.Post(enemy,"Enemy",100,{group="solo",split="equal"}))
assert(not b.Post(enemy,"Enemy",100,{souvenir="invalid"}))
local id=assert(b.Post(enemy,"Enemy",120001,third))
local o=assert(b.OpenFor(enemy))
assert(o.quota==3 and o.group=="party" and o.split=="equal" and o.souvenir=="video" and o.note==third.note)
receive("K",hunter,1,id,"","") -- legacy claim must never close this order
receive("H",hunter,2,id,"0","")
receive("H",partner,3,id,"0","")
-- A second win of the same hunter in the same minute does not count (0.58.5): a forged burst
-- cannot fill a quota.
receive("H",hunter,21,id,"0","")
o=b.List()[id]
assert(b.Progress(o,hunter)==1, b.Progress(o,hunter))
now=now+60
receive("H",hunter,4,id,"0","")
o=b.List()[id]
assert(o.state=="open" and b.Progress(o,hunter)==2 and b.Progress(o,partner)==1)
now=now+60
receive("H",hunter,5,id,"1,40,53",partner)
o=b.List()[id]
assert(o.state=="fulfilled" and o.winner.actor==hunter and o.winner.opponentLevel==53 and o.winner.playerLevel==40)
assert(b.Due(o,owner,hunter)==60001 and b.Due(o,owner,partner)==60000)
assert(not b.OpenFor(enemy) and b.History()[id].winner.time==now and notices==1 and changed>0)
receive("H",partner,6,id,"0","")
assert(b.List()[id].winner.actor==hunter and notices==1)
assert(b.ConfirmPayment(id,hunter,60001) and b.ConfirmPayment(id,partner,60000))
assert(b.History()[id].state=="sent" and notices==1)
receive("V",partner,11,id,"0,60001",owner) -- exceeds this hunter's exact share
receive("V",hunter,12,id,"0,40000",owner)
receive("V",hunter,13,id,"20000,40001",owner)
assert(select(3,b.Payment(b.List()[id],owner,hunter))==60001 and b.History()[id].state=="sent")
receive("V",partner,14,id,"0,60000",owner)
assert(b.History()[id].state=="paid")

local another="Player-2-e"
local solo=assert(b.Post(another,"Solo",120000,{group="solo",split="winner"}))
party=3
b.Kill(another)
receive("H",hunter,7,solo,"1","")
assert(b.Progress(b.List()[solo],owner)==0 and b.List()[solo].state=="open")
party=0
b.Kill(another)
assert(b.List()[solo].winner.actor==owner and b.List()[solo].winner.detail=="")
local grouped=assert(b.Post(enemy,"Enemy",120000,{group="party",split="equal"}))
party,raid=10,true
b.Kill(enemy)
assert(b.List()[grouped].state=="open")
party,raid=3,false
b.Kill(enemy,{playerLevel=50,opponentLevel=48})
o=b.List()[grouped]
assert(o.winner.actor==owner and o.winner.detail==hunter and b.Due(o,owner,hunter)==60000)
local send,keep=b.Share(o,owner,owner)
assert(send==0 and keep==60000 and b.Due(o,owner,owner)==0)
send,keep=b.Share(o,owner,hunter)
assert(send==60000 and keep==0)
local plain=assert(b.Post(another,"Winner",1000,{group="party",split="winner"}))
b.Kill(another)
assert(b.List()[plain].winner.detail=="")
now=now+39*86400
assert(not b.List()[id] and b.History()[id].state=="paid" and b.History()[id].winner.opponentLevel==53)
assert(b.ConfirmPayment(grouped,hunter,10000))
assert(b.Due(b.List()[grouped],owner,hunter)==50000)
assert(b.Share(b.List()[grouped],owner,hunter)==60000)
assert(b.Due(b.List()[grouped],owner,hunter)==50000 and b.ConfirmPayment(grouped,hunter,50000))
assert(b.History()[grouped].state=="sent" and not b.ConfirmPayment(grouped,hunter,1))
receive("V",hunter,15,grouped,"0,60000",owner)
assert(b.History()[grouped].state=="paid")
local sameSecond="Player-8-second"
receive("O",partner,41,sameSecond,"123","Previous")
receive("X",partner,42,partner..":41","","")
local noticesBefore=notices
local successor=assert(b.Post(sameSecond,"Successor",400))
assert(b.OpenFor(sameSecond).id==successor and b.List()[partner..":41"].state=="withdrawn")
assert(notices==noticesBefore,"publishing after an observed same-second close must not send a replacement warning")
env.SlashCmdList.GLBOUNTY("nota "..successor.." nueva")
assert(b.OpenFor(sameSecond).note=="nueva")
env.SlashCmdList.GLBOUNTY("renew "..successor.." updated")
assert(b.OpenFor(sameSecond).note=="updated")
now=now+7*86400+1
local later=assert(b.CanRepost(b.List()[successor]) and b.Post(sameSecond,"Later",100))
-- 0.58.5: a relay speaks only of a member of the guild. A pledge in the name of someone unknown
-- is refused; one in your own name that you never made is refused and told, once per member.
local function relayed(kind,actor,seq,id,value,detail)
    local msg="R;"..table.concat({kind,actor,seq,now,id,value,detail},";")
    event(nil,"CHAT_MSG_ADDON","GLBounty1",msg,"GUILD",names[hunter])
end
relayed("P","Player-5-ghost",77,later,"5000","")
assert(b.List()[later].pot["Player-5-ghost"]==nil, "a made-up member pledges nothing")
local beforeForgery=notices
relayed("P",owner,78,later,"5000","")
relayed("P",owner,79,later,"7000","")
assert(b.List()[later].pot[owner]==100 and notices==beforeForgery+1, "told once, and the pot is yours")
relayed("P",partner,80,later,"5000","")
assert(b.List()[later].pot[partner]==5000, "a real member's pledge still travels")
-- 0.58.7: nothing is cancelled for the guild in your name (the same character on another computer,
-- or a crash, would lose real bounties): the message is only ignored here.
for _,raw in pairs(b.GuildScope().events) do assert(raw:sub(1,2)~="Z;", "no automatic cancellation") end
-- A relay from another member cancels yours, even when you knew what it says.
local scopeNow=b.GuildScope()
assert(gl.Transport.SendBatch(scopeNow,{"R;x"},{key="bounty:relay",delay=100}))
relayed("P",partner,80,later,"5000","")
assert(gl.Transport.State(scopeNow,"bounty:relay")==nil, "the other relay cancels yours")
local function stamped(stamp,kind,actor,seq,id,value,detail)
    local msg=table.concat({kind,actor,seq,stamp,id,value,detail},";")
    event(nil,"CHAT_MSG_ADDON","GLBounty1",msg,"GUILD",names[actor])
end
-- A claim heard two hours after its own date is not confirmed by itself: the issuer confirms it.
now=now+3*3600
stamped(now-7200,"K",hunter,81,later,"","")
o=b.List()[later]
assert(o.state=="claimed" and b.LateClaim(o), o.state)
assert(b.Award(later) and b.List()[later].state~="claimed" and b.List()[later].winner.actor==hunter)
-- A claim naming a helper outside the guild still counts (0.58.7): that share is only never asked.
local withFriend=assert(b.Post("Player-2-friendly","Friendly",100))
stamped(now,"K",hunter,84,withFriend,"","Player-9-outsider")
assert(b.List()[withFriend].winner and b.List()[withFriend].winner.actor==hunter, b.List()[withFriend].state)
-- A bounty back-dated by an hour never replaces the one heard in time.
local contested="Player-2-contested"
stamped(now,"O",partner,82,contested,"100","Contested")
stamped(now-7200,"O",hunter,83,contested,"100","Contested")
assert(b.OpenFor(contested).id==partner..":82", b.OpenFor(contested).id)
print("PASS guild alpha rules: personal quota, replay, legacy claims, solo/group, split, notification and durable history")
