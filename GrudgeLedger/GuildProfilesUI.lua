local GL, UI = GrudgeLedger, GrudgeLedger.UITheme
local G, L = GL.GuildProfiles, GL.L
local f, seed, selected, hidden, page, logPage, guild
local names={}
for _,v in ipairs(G.choices) do names[v[1]]=L(v[2]) end
local function show(widget,visible) if visible then widget:Show() else widget:Hide() end end
local function stamp(at) return date("%d/%m/%Y %H:%M",at) end

local function refresh()
    if not f or not f:IsShown() then return end
    local scope,me=GL.Bounties.GuildScope()
    if guild~=scope then seed,selected,hidden,page,logPage,guild=nil,nil,false,1,1,scope end
    if seed and not hidden then
        local shared=G.ForTarget(seed.guid)
        if shared then selected,seed,logPage=shared.key,nil,1 end
    end
    local cards=G.List(hidden)
    page=math.max(1,math.min(page,math.ceil(#cards/#f.rows)))
    local active
    for _,c in ipairs(cards) do if c.key==selected then active=c break end end
    if not active and not seed then active=cards[(page-1)*#f.rows+1] end
    selected=active and active.key
    for i,row in ipairs(f.rows) do
        local c=cards[(page-1)*#f.rows+i]
        row.card=c
        show(row,c)
        if c then row:SetText(c.name); UI.selectButton(row,c==active) end
    end
    f.back:SetEnabled(page>1)
    f.forward:SetEnabled(page*#f.rows<#cards)
    f.pages:SetText(("%d / %d"):format(page,math.max(1,math.ceil(#cards/#f.rows))))
    f.mode:SetText(hidden and L("Fiches visibles") or L("Fiches masquées"))
    f.auto:SetEnabled(scope~=nil)
    UI.selectButton(f.auto,G.Auto())
    f.auto:SetText(G.Auto() and L("Partage auto activé") or L("Activer le partage auto"))
    f.subject:SetText(active and active.name or (seed and seed.fullName) or L("Fiches de guilde"))
    f.target=active and active.target or (seed and seed.guid)
    f.dossier:SetEnabled(f.target~=nil)
    f.author:SetText(active and L("Publiée par %s · %s"):format(active.authorName,stamp(active.time))
        or (scope and (seed and L("Cette fiche est personnelle.") or L("Aucune fiche dans cette vue.")) or L("Guilde indisponible.")))
    f.account:SetText(active and L("Compte du registre · %s"):format(active.account) or "")
    local masked=scope and scope.journal and seed and scope.journal.hidden[seed.guid]
    if masked then f.author:SetText(L("Cette fiche est masquée pour vous.")) end
    f.publish:SetText(masked and L("Réafficher pour moi") or L("Publier cette fiche"))
    show(f.publish,scope and not active and seed and seed.guid and not G.ForTarget(seed.guid))
    show(f.hide,active~=nil)
    f.hide:SetText(hidden and L("Réafficher pour moi") or L("Masquer pour moi"))
    show(f.remove,active and G.Owns(active))
    local history,counts,latest=G.View(active)
    local summary={}
    for _,choice in ipairs(G.choices) do
        local n=counts[choice[1]]
        if n then summary[#summary+1]=names[choice[1]].." ×"..n end
    end
    f.summary:SetText(active and (#summary>0 and table.concat(summary,"   ·   ") or L("Aucun avis de guilde.")) or "")
    f.opinion:SetText(active and L("Mon avis de guilde") or "")
    for i,b in ipairs(f.tags) do
        local e=latest[(me or "")..":"..G.choices[i][1]]
        show(b,active and not hidden)
        UI.selectButton(b,e and e.on or false)
        b.nextValue=not(e and e.on)
    end
    f.historyTitle:SetText(active and L("Historique des avis") or "")
    logPage=math.max(1,math.min(logPage,math.ceil(#history/#f.history)))
    for i,line in ipairs(f.history) do
        local e=history[(logPage-1)*#f.history+i]
        line:SetText(e and ("%s   %s   %s %s"):format(stamp(e.time),e.authorName,e.on and "+" or "−",names[e.tag]) or "")
        line.event=e
    end
    show(f.older,logPage*#f.history<#history)
    show(f.newer,logPage>1)
end

local function build()
    f=UI.window("GrudgeLedgerGuildProfiles",L("Fiches de guilde"),850,550)
    f.rows,f.history,f.tags={},{},{}
    local function button(text,x,y,width,fn,choice) return UI.button(f,text,x,-y,width,fn,choice) end
    local function label(text,x,y,width,size) return UI.label(f,text,size,x,-y,width) end
    f.mode=button("",24,57,208,function() hidden=not hidden; seed,selected,page,logPage=nil,nil,1,1; refresh() end)
    for i=1,9 do
        local row
        row=button("",24,94+(i-1)*33,208,function()
            selected,seed,logPage=row.card.key,nil,1
            refresh()
        end,true)
        f.rows[i]=row
    end
    f.back=button("‹",24,400,42,function() page=page-1; refresh() end)
    f.pages=label("",89,405,78)
    f.forward=button("›",190,400,42,function() page=page+1; refresh() end)
    f.auto=button("",24,493,208,function() G.SetAuto(not G.Auto()) end,true)
    f.auto:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine(L("Partage les nouvelles fiches et vos prochaines modifications d’étiquettes avec cette guilde."),1,1,1,true)
        GameTooltip:Show()
    end)
    f.auto:SetScript("OnLeave",function() GameTooltip:Hide() end)
    f.subject=label("",254,67,392,"large")
    local function openDossier()
        if f.target and GL.OpenPlayerDossier(f.target,function() f:Show(); refresh() end,f.subject:GetText()) then f:Hide() end
    end
    f.dossier=button(L("Fiche complète"),662,60,156,openDossier)
    f.subjectLink=CreateFrame("Button",nil,f); f.subjectLink:SetAllPoints(f.subject)
    f.subjectLink:SetScript("OnClick",openDossier)
    f.author=label("",254,94,564)
    f.account=label("",254,115,564)
    f.summary=label("",254,148,560)
    f.opinion=label("",254,187,565,"large")
    for i,choice in ipairs(G.choices) do
        local tag=choice[1]
        local b
        b=button(names[tag],254+((i-1)%3)*192,215+math.floor((i-1)/3)*31,187,function()
            local s=GL.Bounties.GuildScope()
            local c=s and s.journal and s.journal.cards[selected]
            if c then G.SetTag(c,tag,b.nextValue) end
        end,true)
        f.tags[i]=b
    end
    f.historyTitle=label("",254,317,556,"large")
    for i=1,5 do
        local line=label("",254,344+(i-1)*23,564)
        f.history[i]=line
        local hit=CreateFrame("Frame",nil,f)
        hit:SetPoint("TOPLEFT",line,"TOPLEFT"); hit:SetSize(563,21); hit:EnableMouse(true)
        hit:SetScript("OnEnter",function(self)
            if not line.event then return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:AddLine(line.event.authorName)
            GameTooltip:AddLine(L("Compte du registre · %s"):format(line.event.account))
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    f.newer=button("‹",709,311,47,function() logPage=logPage-1; refresh() end)
    f.older=button("›",766,311,47,function() logPage=logPage+1; refresh() end)
    f.publish=button(L("Publier cette fiche"),254,493,245,function()
        if not seed or GL.Get(seed.key)~=seed then return end
        local scope=GL.Bounties.GuildScope()
        if scope and scope.journal and scope.journal.hidden[seed.guid] then
            local contact=seed
            G.HideTarget(contact.guid,true)
            GL.OpenGuildProfiles(contact)
            return
        end
        local c=G.Publish(seed)
        if c then G.HideTarget(c.target,true); seed,selected,hidden=nil,c.key,false; refresh() end
    end)
    f.hide=button("",254,493,212,function()
        local s=GL.Bounties.GuildScope()
        local c=s and s.journal and s.journal.cards[selected]
        if c then seed,selected=nil,nil; G.HideTarget(c.target,hidden) end
    end)
    local dialog="GRUDGE_LEDGER_WITHDRAW_GUILD_CARD"
    StaticPopupDialogs[dialog]={
        text=L("Retirer la fiche de %s et ses avis pour toute la guilde ? Les journaux personnels seront conservés."),
        button1=L("Retirer pour la guilde"),button2=L("Annuler"),timeout=0,whileDead=true,hideOnEscape=true,
        OnAccept=function(_,c) G.Withdraw(c) end,
    }
    f.remove=button(L("Retirer pour la guilde"),576,493,237,function()
        local s=GL.Bounties.GuildScope()
        local c=s and s.journal and s.journal.cards[selected]
        if c and G.Owns(c) then StaticPopup_Show(dialog,c.name,nil,c) end
    end)
    f:HookScript("OnHide",function() StaticPopup_Hide(dialog) end)
end
function GL.OpenGuildProfiles(record)
    if not f then build() end
    local c=record and G.ForTarget(record.guid)
    guild=GL.Bounties.GuildScope()
    seed,selected,hidden,page,logPage=not c and record or nil,c and c.key,false,1,1
    f:Show(); f:Raise(); refresh()
end
GL.On("GUILD_PROFILES",refresh)
local membership=CreateFrame("Frame")
membership:RegisterEvent("PLAYER_GUILD_UPDATE")
membership:SetScript("OnEvent",refresh)
