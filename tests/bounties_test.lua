-- Full message exchange through the addon's registered events, with separate saved variables.
local clients, now, network = {}, 1800000000, {}
local target="Player-9-dead"
local function client(i)
    local id="Player-1-"..i
    local c={id=id,name="Member"..i.."-Realm",online=true,guild="Guild",db={}}
    clients[i]=c
    local env=setmetatable({}, {__index=_G})
    local ev={}
    env.GrudgeLedger={db=c.db,Safe=function(f,...) return f(...) end,Clean=function(v,k) if type(v)==k then return v end end,Now=function() return now end,
        RequestArmory=function(key,name,guid) c.request={key,name,guid} end,
        ContainsControlOrMarkup=function(v) return v:find("[|%c]") end,
        On=function(k,v) ev[k]=v end}
    env.GetGuildInfo=function() return c.guild,nil,nil,"Realm" end
    env.GetNormalizedRealmName=function() return "Realm" end
    env.UnitGUID=function(u) return u=="player" and id or clients[1].id end
    env.GetNumGuildMembers=function() return #clients end
    env.GetGuildRosterInfo=function(n)
        local a={[1]=clients[n].name,[17]=clients[n].id};return unpack(a,1,17)
    end
    env.IsInRaid=function() return false end
    env.GetNumGroupMembers=function() return c.group and 2 or 0 end
    env.UnitExists=function(u) return u=="party1" end
    env.UnitIsUnit=function() return false end
    env.UnitIsVisible=function() return true end
    -- Each frame receives only the events it registered, as in the game.
    local frames={}
    env.CreateFrame=function()
        local frame={events={}}
        frame.RegisterEvent=function(self,name) self.events[name]=true end
        frame.SetScript=function(self,_,fn) self.handler=fn end
        frames[#frames+1]=frame
        return frame
    end
    c.event=function(_,name,...)
        for _,frame in ipairs(frames) do
            if frame.events[name] and frame.handler then frame.handler(frame,name,...) end
        end
    end
    env.C_Timer={NewTicker=function(_,f) c.tick=f end}
    env.C_ChatInfo={RegisterAddonMessagePrefix=function() end,SendAddonMessage=function(p,t,ch)
        network[#network+1]={i,p,t,ch,c.name};return 0 end}
    for _,name in ipairs({"Transport.lua","Bounties.lua"}) do
        local f=assert(loadfile(TEST_ROOT.."/"..name));setfenv(f,env);f()
    end
    c.env=env;c.b=env.GrudgeLedger.Bounties;c.hook=ev
    c.event(nil,"PLAYER_LOGIN")
    for _,p in ipairs(clients) do if p.online then p.event(nil,"GUILD_ROSTER_UPDATE") end end
    return c
end
-- Messages may wait in a client's queue (the login relay leaves after a random delay): the network
-- is quiet only when nothing is in flight and nothing is queued.
local function queued()
    for _,c in ipairs(clients) do
        local s=c.online and c.b.GuildScope()
        if s then
            local urgent,bulk=c.env.GrudgeLedger.Transport.Pending(s)
            if urgent+bulk>0 then return true end
        end
    end
    return false
end
local function flush()
    for _=1,400 do
        now=now+1
        for _,c in ipairs(clients) do if c.online then c.tick() end end
        if #network==0 and not queued() then return end
        local batch=network;network={}
        for _,m in ipairs(batch) do
            for _,c in ipairs(clients) do
                if c.online and c.guild==clients[m[1]].guild then
                    for j=1,2 do c.event(nil,"CHAT_MSG_ADDON",m[2],m[3],m[4],m[5]) end
                end
            end
        end
    end
    error("message loop")
end
local a,b=client(1),client(2)
local order=assert(a.b.Post(target,"Target Player",100000))
assert(not a.b.Post(target,"Target",0))
flush()
assert(b.request[1]=="guid:"..target and b.request[2]=="Target Player" and b.request[3]==target)
assert(b.b.Pledge(order,50000));flush()
now=now+100
assert(not b.b.Update(order,"not mine",true))
assert(a.b.Update(order,"Patrouille au rivage",true));flush()
local renewed=b.b.List()[order]
assert(renewed.note=="Patrouille au rivage" and renewed.expires>renewed.at+7*86400 and renewed.pot[b.id]==50000)
assert(b.b.OpenFor(target).id==order and b.b.OpenFor(target).state=="open")
b.env.GrudgeLedger.Print=function() end
a.online=false
local c=client(3);flush()
assert(c.b.List()[order].pot[b.id]==50000)
c.group=true
c.hook.BOUNTY_KILL(target);flush()
assert(c.b.List()[order].state=="claimed")
assert(c.b.History()[order].state=="claimed")
now=now+12; a.online=true;a.event(nil,"PLAYER_LOGIN");flush()
for _,p in ipairs(clients) do
 local o=p.b.List()[order];assert(o.state=="fulfilled" and o.winner.actor==c.id)
 assert(p.b.Due(o,b.id,c.id)==25000 and p.b.Due(o,b.id,a.id)==25000)
end
assert(not c.b.Withdraw(order))
assert(b.b.ConfirmPayment(order,c.id,4000));flush()
assert(a.b.Due(a.b.List()[order],b.id,c.id)==21000)
assert(not b.b.ConfirmPayment(order,c.id,22000))
local env=b.env
local function field()
    return {v="",GetText=function(self)return self.v end,SetText=function(self,v) self.v=v end}
end
env.SendMailFrame={IsShown=function()return true end}
env.SendMailNameEditBox,env.SendMailSubjectEditBox,env.SendMailBodyEditBox=field(),field(),field()
env.SendMailMoney={n=0}
env.MoneyInputFrame_GetCopper=function(f)return f.n end
env.MoneyInputFrame_SetCopper=function(f,n) f.n=n end
env.SendMailSendMoneyButton={GetChecked=function()return true end}
env.SendMailRadioButton_OnClick=function()end
env.GetSendMailItem=function()end
env.SendMail=function()error("must not auto-send")end
local send
env.hooksecurefunc=function(name,f)assert(name=="SendMail");send=f end
env.HasSendMailItem=function(i)return i==1 end
assert(not b.b.PrepareMail(order,c.id) and env.SendMailMoney.n==0)
env.HasSendMailItem=nil
assert(b.b.PrepareMail(order,c.id))
assert(env.SendMailNameEditBox.v==c.name and env.SendMailMoney.n==21000)
assert(not b.b.PrepareMail(order,c.id))
b.event(nil,"MAIL_SEND_SUCCESS")
assert(b.b.Due(b.b.List()[order],b.id,c.id)==21000)
send("Other",env.SendMailSubjectEditBox.v);b.event(nil,"MAIL_SEND_SUCCESS")
assert(b.b.Due(b.b.List()[order],b.id,c.id)==21000)
local function refill()
 env.SendMailNameEditBox.v="";env.SendMailSubjectEditBox.v="";env.SendMailMoney.n=0
 assert(b.b.PrepareMail(order,c.id));send(c.name,env.SendMailSubjectEditBox.v)
end
refill();b.event(nil,"MAIL_CLOSED")
assert(not b.b.PrepareMail(order,c.id))
assert(b.b.ReconcileMail(false) and b.b.Due(b.b.List()[order],b.id,c.id)==21000)
refill();b.event(nil,"MAIL_FAILED")
assert(b.b.Due(b.b.List()[order],b.id,c.id)==21000)
env.SendMailNameEditBox.v="";env.SendMailSubjectEditBox.v="";env.SendMailMoney.n=0
local button,clicks=nil,0
env.GetTime=function()return now end
env.MailFrame={IsShown=function()return true end}
env.CreateFrame=function()
 button=setmetatable({SetText=function(self,v)self.text=v end,SetScript=function(self,_,fn)self.click=fn end,
    GetFontString=function()return {GetStringWidth=function()return 100 end}end},
    {__index=function()return function()end end})
 return button
end
env.SendMailMailButton={IsEnabled=function()return true end,Click=function()
 clicks=clicks+1;send(env.SendMailNameEditBox.v,env.SendMailSubjectEditBox.v)
end}
b.event(nil,"MAIL_SHOW")
assert(button and clicks==0 and button.text:find("Target",1,true) and not button.text:find(a.name,1,true))
button:click();button:click()
assert(clicks==0 and env.SendMailNameEditBox.v==a.name and env.SendMailMoney.n==25000)
local firstSubject=env.SendMailSubjectEditBox.v
env.SendMailMailButton:Click()
b.event(nil,"MAIL_FAILED") -- retain the user's prepared draft; retry only by native click
assert(b.b.Due(b.b.List()[order],b.id,a.id)==25000 and clicks==1)
env.SendMailMailButton:Click()
env.SendMailNameEditBox.v="";env.SendMailSubjectEditBox.v="";env.SendMailMoney.n=0
b.event(nil,"MAIL_SEND_SUCCESS")
assert(clicks==2 and env.SendMailNameEditBox.v==c.name and env.SendMailMoney.n==21000)
local secondSubject=env.SendMailSubjectEditBox.v
assert(b.b.Due(b.b.List()[order],b.id,a.id)==0 and b.b.Due(b.b.List()[order],b.id,c.id)==21000)
b.event(nil,"MAIL_SEND_SUCCESS") -- second draft was only prepared; repeated event cannot pay it
assert(b.b.Due(b.b.List()[order],b.id,c.id)==21000)
env.SendMailMailButton:Click()
b.event(nil,"MAIL_SEND_SUCCESS");b.event(nil,"MAIL_SEND_SUCCESS");flush()
assert(a.b.Due(a.b.List()[order],b.id,c.id)==0)
assert(clicks==3 and not b.b.ConfirmPayment(order,a.id,25000))
assert(a.b.ConfirmPayment(order,c.id,50000));flush()
assert(c.b.List()[order].state=="sent")
local function inbox(p,sender,subject,amount,cod,returned)
    p.env.GetInboxNumItems=function() return 1 end
    p.env.GetInboxHeaderInfo=function() return nil,nil,sender,subject,amount,cod or 0,30,0,false,returned end
    p.event(nil,"MAIL_INBOX_UPDATE")
end
inbox(a,"Stranger",firstSubject,25000)
inbox(a,b.name,"Prime : Target",25000)
inbox(a,b.name,firstSubject,25000,100)
inbox(a,b.name,firstSubject,25000,0,true)
assert(select(2,a.b.Payment(a.b.List()[order],b.id,a.id))==25000)
inbox(a,"Member2",firstSubject,25000)
inbox(a,b.name,firstSubject,25000); flush()
assert(select(2,a.b.Payment(a.b.History()[order],b.id,a.id))==0)
assert(select(2,c.b.Payment(c.b.History()[order],b.id,c.id))==25000)
inbox(c,b.name,secondSubject,21000)
inbox(c,b.name,secondSubject,21000); flush()
assert(select(2,b.b.Payment(b.b.History()[order],b.id,c.id))==4000 and b.b.History()[order].state=="sent")
inbox(c,b.name,firstSubject,4000); flush()
inbox(c,a.name,firstSubject,50000); flush()
assert(c.b.History()[order].state=="paid" and a.b.History()[order].state=="paid" and b.b.History()[order].state=="paid")
local other=assert(a.b.Post("Player-3-b","Other",0));assert(a.b.Withdraw(other));flush()
assert(c.b.List()[other].state=="withdrawn")
local expired=assert(a.b.Post("Player-3-c","Old",0));flush();now=now+7*86400+1
assert(c.b.List()[expired].state=="expired")
a.b.ShareDeaths(true)
for j=1,3 do now=now+1; a.hook.BOUNTY_DEATH(target,"Target") end
flush()
local count=0
for _,o in pairs(b.b.List()) do if o.auto then count=count+1;assert(o.state=="open" and o.expires-o.at==3*86400) end end
assert(count==1)
local rampage="Player-8-ccc"
b.b.ShareDeaths(true);c.b.ShareDeaths(true)
a.hook.BOUNTY_DEATH(rampage,"Enemy");flush()
b.hook.BOUNTY_DEATH(rampage,"Enemy");flush()
c.hook.BOUNTY_DEATH(rampage,"Enemy");flush()
local n=0
for _,o in pairs(a.b.List()) do if o.target==rampage then n=n+1 end end
assert(n==1)
-- Shared by default since 0.51.0: the totals of every member already count.
local wins0,losses0=c.b.GuildFights(target)
a.b.Kill(target);b.b.Death(target,"Target");flush()
local wins,losses=c.b.GuildFights(target)
assert(wins==wins0+1 and losses==losses0+1)
local late=client(4);flush()
assert(not late.b.History()[order])
wins,losses=late.b.GuildFights(target)
assert(wins==wins0+1 and losses==losses0+1)
c.guild="Other";c.event(nil,"PLAYER_GUILD_UPDATE");assert(not next(c.b.List()))
-- The hunter can collect mail before their local guild history has synchronized.
local soloTarget="Player-8-solo"
local delayed=assert(b.b.Post(soloTarget,"Target",120000,{group="solo"}))
inbox(a,b.name,"[GL:"..delayed.."/0] Target",120000)
a.env.GetInboxNumItems=function() return 0 end
flush(); a.b.Kill(soloTarget); flush()
assert(a.b.History()[delayed].state=="paid" and b.b.History()[delayed].state=="paid")

-- A returning issuer still learns about delivery after the guild log rotates.
local archived=assert(b.b.Post(soloTarget,"Target",120000,{group="solo"}))
flush(); a.b.Kill(soloTarget); flush()
assert(b.b.ConfirmPayment(archived,a.id,120000)); flush()
b.online=false
inbox(a,b.name,"[GL:"..archived.."/0] Target",120000); flush()
now=now+39*86400
a.event(nil,"PLAYER_LOGIN"); flush()
b.online=true; b.event(nil,"PLAYER_LOGIN"); flush()
assert(a.b.History()[archived].state=="paid" and b.b.History()[archived].state=="paid")
-- Two publishers cannot see each other before the first exchange. All clients
-- choose the same target contract, and replaying each packet emits only one debt.
local simultaneous="Player-8-overlap"
local replacementNotices={}
for _,p in ipairs({a,b,late}) do
    local who=p.id
    p.env.GrudgeLedger.Print=function(text)
        if text:find("Prime remplacée",1,true) then replacementNotices[who]=(replacementNotices[who] or 0)+1 end
    end
end
local one=assert(a.b.Post(simultaneous,"Overlap",120000))
local two=assert(b.b.Post(simultaneous,"Overlap",240000))
flush()
local canonical=a.b.OpenFor(simultaneous).id
local replaced=canonical==one and two or one
for _,p in ipairs({a,b,late}) do
    assert(p.b.OpenFor(simultaneous).id==canonical)
    local other=p.b.List()[replaced]
    assert(other.state=="superseded" and other.supersededBy==canonical and not p.b.Pledge(replaced,1))
end
late.b.Kill(simultaneous);flush()
local issuer=canonical==one and a or b
local otherIssuer=canonical==one and b or a
assert(replacementNotices[otherIssuer.id]==1 and not replacementNotices[issuer.id] and not replacementNotices[late.id])
for _,p in ipairs({a,b,late}) do
    local all=p.b.List()
    assert(all[canonical].winner.actor==late.id and p.b.Due(all[canonical],issuer.id,late.id)==all[canonical].pot[issuer.id])
    assert(not all[replaced].winner and p.b.Progress(all[replaced],late.id)==0 and p.b.Due(all[replaced],b.id,late.id)==0)
end

-- An already-dispatched installment and the rest of its contract survive an
-- older, overlapping publication arriving late. The inbox still settles it.
local targetLate="Player-8-late"
local owed=assert(b.b.Post(targetLate,"Late",1000));flush()
a.b.Kill(targetLate);flush()
assert(b.b.ConfirmPayment(owed,a.id,400));flush()
local olderStamp=b.b.List()[owed].at-1
local oldRaw=table.concat({"O",late.id,77,olderStamp,targetLate,999,"Late"},";")
for _,p in ipairs({a,b}) do
    p.event(nil,"CHAT_MSG_ADDON","GLBounty1",oldRaw,"GUILD",late.name)
    local all=p.b.List()
    assert(all[late.id..":77"].supersededBy==owed and p.b.Due(all[owed],b.id,a.id)==600)
end
inbox(a,b.name,"[GL:"..owed.."/0] Late",400);flush()
assert(select(3,b.b.Payment(b.b.List()[owed],b.id,a.id))==400)

-- A real native send is already in flight on a partition when an overlapping
-- contract that has also been paid arrives. Neither contract can charge twice.
local overlapMail="Player-8-inflight"
local inFlight=assert(b.b.Post(overlapMail,"Mail",700));flush()
a.b.Kill(overlapMail);flush()
env.SendMailNameEditBox.v="";env.SendMailSubjectEditBox.v="";env.SendMailMoney.n=0
assert(b.b.PrepareMail(inFlight,a.id))
local subject=env.SendMailSubjectEditBox.v
send(a.name,subject)
local otherOrder,claim=late.id..":101",a.id..":102"
local function raw(p,actor,kind,seq,stamp,order,value,detail)
    local message=table.concat({kind,actor.id,seq,stamp,order,value,detail},";")
    p.event(nil,"CHAT_MSG_ADDON","GLBounty1",message,"GUILD",actor.name)
end
raw(b,late,"O",101,now-300,overlapMail,500,"Mail")
raw(b,a,"K",102,now,otherOrder,"","")
raw(b,late,"F",103,now,otherOrder,claim,"")
raw(b,late,"Y",104,now,otherOrder,500,a.id)
assert(b.b.List()[inFlight].state=="superseded")
b.event(nil,"MAIL_SEND_SUCCESS");b.event(nil,"MAIL_SEND_SUCCESS")
local historical=b.b.History()[inFlight]
assert(historical.state=="superseded" and historical.paid[b.id.."/"..a.id]==700)
assert(b.b.Due(historical,b.id,a.id)==0 and select(2,b.b.Payment(historical,b.id,a.id))==700)
raw(b,a,"V",105,now,inFlight,"0,700",b.id)
assert(select(3,b.b.Payment(b.b.History()[inFlight],b.id,a.id))==700)

local guildTarget="Player-8-friend"
a.env.UnitFactionGroup=function() return "Alliance" end
a.env.GrudgeLedger.Get=function() return {guid=guildTarget,faction="Alliance"} end
assert(not a.env.GrudgeLedger.BountyTargetEligible({guid=guildTarget,faction="Alliance"}))
local rejected,reason=a.b.Post(guildTarget,"Friend",1)
assert(not rejected and reason=="ally" and not a.b.OpenFor(guildTarget))
a.env.GrudgeLedger.Get=function() return {guid=guildTarget,faction="Horde"} end
assert(a.b.Post(guildTarget,"Opponent",1))
assert(a.b.ShareFights(false) and a.b.ShareDeaths(true))
local fights,deaths=a.b.Sharing()
assert(fights==false and deaths==true)
-- Without a readable realm name (owner's client, 0.47.1), the roster and the mailbox still work, and
-- a payment from a same-realm sender (no realm in the mail) is recognised (0.58.2).
a.env.GetNormalizedRealmName,a.env.GetRealmName=nil,nil
a.event(nil,"GUILD_ROSTER_UPDATE")
local noRealm=assert(b.b.Post("Player-8-norealm","Nameless",30000,{group="solo"}));flush()
a.b.Kill("Player-8-norealm");flush()
assert(select(2,a.b.Payment(a.b.List()[noRealm],b.id,a.id))==30000)
inbox(a,"Member2","[GL:"..noRealm.."/0] Nameless",30000); flush()
assert(select(2,a.b.Payment(a.b.History()[noRealm] or a.b.List()[noRealm],b.id,a.id))==0, "a same-realm payment is recognised")
-- A payment whose sending was not confirmed: two buttons on the mailbox settle it (0.58.2).
local uncertainOrder=assert(b.b.Post("Player-8-uncertain","Doubt",9000,{group="solo"}));flush()
a.b.Kill("Player-8-uncertain");flush()
env.SendMailNameEditBox.v="";env.SendMailSubjectEditBox.v="";env.SendMailMoney.n=0
assert(b.b.PrepareMail(uncertainOrder,a.id))
send(a.name,env.SendMailSubjectEditBox.v);b.event(nil,"MAIL_CLOSED")
now=now+61
local created={}
env.CreateFrame=function()
    local frame=setmetatable({SetText=function(self,v) self.text=v end,SetScript=function(self,_,fn) self.click=fn end,
        GetFontString=function() return {GetStringWidth=function() return 100 end} end,Show=function(self) self.shown=true end,
        Hide=function(self) self.shown=false end},{__index=function() return function() end end})
    created[#created+1]=frame
    return frame
end
env.GrudgeLedger.Print=function() end
b.event(nil,"MAIL_SHOW")
local yes,no
-- The pay button was made by the earlier mailbox visit; the second one may be new.
table.insert(created,button)
for _,frame in ipairs(created) do
    if frame.text=="Le dernier règlement est parti" then yes=frame elseif frame.text=="Il n’est pas parti" then no=frame end
end
assert(yes and no, "two buttons settle an uncertain payment: "..tostring(button and button.text))
yes:click()
assert(b.b.Due(b.b.List()[uncertainOrder] or b.b.History()[uncertainOrder],b.id,a.id)==0, "the payment is recorded")
print("PASS guild bounties: offline relay, duplicate messages, owner resolution, split, partial payments, expiration, withdrawal, automatic order, "
    .."guild isolation, no readable realm, uncertain mail settled by buttons.")
