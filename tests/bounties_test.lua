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
    env.CreateFrame=function() return {RegisterEvent=function() end,SetScript=function(_,_,f) c.event=f end} end
    env.C_Timer={NewTicker=function(_,f) c.tick=f end}
    env.C_ChatInfo={RegisterAddonMessagePrefix=function() end,SendAddonMessage=function(p,t,ch)
        network[#network+1]={i,p,t,ch,c.name};return 0 end}
    local f=assert(loadfile(TEST_ROOT.."/Bounties.lua"));setfenv(f,env);f()
    c.env=env;c.b=env.GrudgeLedger.Bounties;c.hook=ev
    c.event(nil,"PLAYER_LOGIN")
    for _,p in ipairs(clients) do if p.online then p.event(nil,"GUILD_ROSTER_UPDATE") end end
    return c
end
local function flush()
    for _=1,200 do
        now=now+1
        for _,c in ipairs(clients) do if c.online then c.tick() end end
        if #network==0 then return end
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
local order=assert(a.b.Post(target,"Target",100000))
assert(not a.b.Post(target,"Target",0))
flush()
assert(b.b.Pledge(order,50000));flush()
now=now+100
assert(not b.b.Update(order,"not mine",true))
assert(a.b.Update(order,"Patrouille au rivage",true));flush()
local renewed=b.b.List()[order]
assert(renewed.note=="Patrouille au rivage" and renewed.expires>renewed.at+7*86400 and renewed.pot[b.id]==50000)
local notices=0
b.env.GrudgeLedger.Print=function() notices=notices+1 end
b.b.Observe(target);b.b.Observe(target);assert(notices==1)
a.online=false
local c=client(3);flush()
assert(c.b.List()[order].pot[b.id]==50000)
c.group=true
c.hook.BOUNTY_KILL(target);flush()
assert(c.b.List()[order].state=="claimed")
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
refill();b.event(nil,"MAIL_FAILED")
assert(b.b.Due(b.b.List()[order],b.id,c.id)==21000)
env.SendMailNameEditBox.v="";env.SendMailSubjectEditBox.v="";env.SendMailMoney.n=0
local button,clicks=nil,0
env.GetTime=function()return now end
env.MailFrame={IsShown=function()return true end}
env.CreateFrame=function()
 button=setmetatable({lastClick=false,SetScript=function(self,_,fn)self.click=fn end,
    GetFontString=function()return {GetStringWidth=function()return 100 end}end},
    {__index=function()return function()end end})
 return button
end
env.SendMailMailButton={IsEnabled=function()return true end,Click=function()
 clicks=clicks+1;send(env.SendMailNameEditBox.v,env.SendMailSubjectEditBox.v)
end}
b.event(nil,"MAIL_SHOW")
assert(button and clicks==0)
button:click();button:click()
assert(clicks==1 and env.SendMailNameEditBox.v==a.name and env.SendMailMoney.n==25000)
b.event(nil,"MAIL_FAILED")
refill();b.event(nil,"MAIL_SEND_SUCCESS");b.event(nil,"MAIL_SEND_SUCCESS");flush()
assert(a.b.Due(a.b.List()[order],b.id,c.id)==0)
assert(b.b.ConfirmPayment(order,a.id,25000));assert(a.b.ConfirmPayment(order,c.id,50000));flush()
assert(c.b.List()[order].state=="paid")
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
a.b.ShareFights(true);b.b.ShareFights(true)
a.b.Kill(target);b.b.Death(target,"Target");flush()
local wins,losses=c.b.GuildFights(target)
assert(wins==1 and losses==1)
local late=client(4);flush()
wins,losses=late.b.GuildFights(target)
assert(wins==1 and losses==1)
c.guild="Other";c.event(nil,"PLAYER_GUILD_UPDATE");assert(not next(c.b.List()))
print("PASS guild bounties: offline relay, duplicate messages, owner resolution, split, partial payments, expiration, withdrawal, automatic order, guild isolation.")
