-- Guild contracts share the book's navigation, portraits and character dossier.
local GL = GrudgeLedger
local UI, B = GL.UITheme, GL.Bounties
local f, refresh, startForm, selectOrder
local t = UI.theme
local media="Interface\\AddOns\\GrudgeLedger\\Media\\"
local pageSize = 6
local english = GetLocale and GetLocale() ~= "frFR"
local function L(fr, en) return english and en or fr end
local function mine() return GL.Safe(UnitGUID, "player") end
local function contact(id) return id and GL.Get("guid:" .. id) end
local function who(id)
    local r = contact(id)
    local name=(r and r.fullName) or B.MemberName(id)
    if not name and id==mine() then
        local first,last=GL.Safe(UnitName,"player")
        if first then name=first..(last and last~="" and (" "..last) or "") end
    end
    return name or id
end
local function total(o)
    local n = 0
    for _, amount in pairs(o.pot) do n = n + amount end
    return n
end
local function money(n)
    if n % 10000 == 0 then return math.floor(n / 10000) .. L(" PO", " g") end
    return ("%d %s %d %s %d %s"):format(math.floor(n / 10000), L("po", "g"), math.floor(n / 100) % 100,
        L("pa", "s"), n % 100, L("pc", "c"))
end
local function copper(value)
    local whole, fraction = value:match("^%s*(%d+)[.,](%d+)%s*$")
    if not whole then whole, fraction = value:match("^%s*(%d+)%s*$"), "" end
    if whole and #fraction <= 4 and tonumber(whole) <= 1000 then
        local amount = tonumber(whole) * 10000 + tonumber((fraction .. "0000"):sub(1, 4))
        if amount <= 10000000 then return amount end
    end
end
local states = {
    open=L("En cours","Open"), claimed=L("En attente de synchronisation","Awaiting sync"),
    fulfilled=L("Prime faite · règlement en attente","Bounty complete · payment pending"),
    paid=L("Prime réglée","Paid"), withdrawn=L("Retirée","Withdrawn"), expired=L("Expirée","Expired")
}
local souvenirs = { none=L("Aucun","None"), screenshot=L("Capture souvenir","Screenshot"), video=L("Vidéo souvenir","Video") }
local filterLists = {
    active={{"all",L("Toutes les primes","All bounties")},{"pinned",L("Épinglées","Pinned")},
        {"issued",L("Mes contrats","Issued by me")},{"solo",L("Hors groupe","Solo only")},{"party",L("Groupe autorisé","Groups allowed")}},
    history={{"all",L("Tout mon historique","All my history")},{"hunted",L("Réalisées","Completed by me")},
        {"issued",L("Commanditées","Issued by me")},{"due",L("À régler","I owe gold")},{"paid",L("Réglées","Paid")}}
}
local function members(o)
    if not o.winner then return {} end
    local result = {o.winner.actor}
    for id in (o.winner.detail or ""):gmatch("[^,]+") do result[#result+1] = id end
    return result
end
local function pins(create)
    local me = mine()
    if not me or not GL.db then return {} end
    if create then
        GL.db.bountyPins = GL.db.bountyPins or {}
        GL.db.bountyPins[me] = GL.db.bountyPins[me] or {}
    end
    return GL.db.bountyPins and GL.db.bountyPins[me] or {}
end
local function isOpen(o) return o.state == "open" or o.state == "claimed" end
local function passFilter(o, filter, me, pinned)
    if filter == "issued" then return o.owner == me end
    if filter == "pinned" then return pinned[o.id] end
    if filter == "party" or filter == "solo" then return o.group == filter end
    if filter == "paid" then return o.state == "paid" end
    if filter == "due" or filter == "hunted" then
        for _, h in ipairs(members(o)) do
            if (filter == "hunted" and h == me) or (filter == "due" and B.Due(o, me, h) > 0) then return true end
        end
        return false
    end
    return true
end
local function visible(region, yes) if yes then region:Show() else region:Hide() end end
local function tip(button, text)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(text); GameTooltip:Show() end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
local function text(parent, x, y, w, h, size, color, value)
    local s = UI.label(parent,value or "",nil,x,-y,w)
    s:SetHeight(h)
    UI.journalFont(s, "GameFontHighlight", size)
    s:SetTextColor(unpack(color or t.ink))
    return s
end
local function input(parent,x,y,w,max,paper)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetPoint("TOPLEFT",x,-y); e:SetSize(w,28); e:SetAutoFocus(false); e:SetMaxLetters(max)
    UI.styleInput(e,false,paper)
    e:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
    return e
end
local function button(parent, title, x,y,w,fn,paper)
    return UI.button(parent,title,x,-y,w,fn,nil,paper)
end
local function message(msg) f.feedback:SetText(msg or "") end
local function showDossier(id,name)
    if id then GL.OpenPlayerDossier(id, function() GL.ShowBookPage(f); refresh() end, name) end
end
local function resetList()
    f.offset = 0
    f.search:SetText("")
end
local function chooseTab(tab)
    f.tab, f.filterKey, f.selected, f.editing, f.origin = tab,"all",nil,nil,nil
    f.form:Hide(); f.filters:Hide(); resetList(); message(); refresh()
end
local function actionResult(id,err)
    if id then f.cachedOrders=nil; return true end
    local errors = {
        duplicate=L("Une prime est déjà ouverte sur ce joueur.","This player already has an open bounty."),
        guild=L("Une guilde est nécessaire pour publier.","Join a guild to publish a bounty."),
        limit=L("Limite de contrats, de montant ou de renouvellement atteinte.","Contract, amount or renewal limit reached."),
        invalid=L("Opération refusée. Vérifiez le contrat, le montant et la consigne (100 octets).","Rejected. Check contract, amount and instructions (100 bytes).")
    }
    message(errors[err] or L("Opération refusée. Actualisez le contrat.","Action rejected. Refresh the contract."))
    return false
end
local function compactDate(ts)
    return (ts and GL.Safe(date,"%d/%m/%Y %H:%M",ts)) or "—"
end
local function showEditor(kind)
    local o = f.order
    if not o then return end
    f.editing = kind
    f.tools:Hide(); f.editor:Show()
    local titles = {pledge=L("Votre contribution en PO (jusqu’à 1 000)","Your contribution in gold (up to 1,000)"),
        note=L("Consigne libre (100 octets)","Free instructions (100 bytes)"),
        withdraw=L("Retirer ce contrat de la guilde ?","Withdraw this guild contract?")}
    f.editor.title:SetText(titles[kind]); visible(f.editor.field,kind ~= "withdraw")
    f.editor.field:SetText(kind == "note" and (o.note or "") or "")
    f.editor.ok:SetText(kind=="withdraw" and L("Confirmer le retrait","Confirm withdrawal") or L("Valider","Save"))
    if kind ~= "withdraw" then f.editor.field:SetFocus() end
    message()
end
local function commitEdit()
    local o, kind = f.order, f.editing
    if not o or not kind then return end
    local id,err
    if kind=="pledge" then
        local amount = copper(f.editor.field:GetText())
        if not amount or amount <= 0 then return message(L("Saisissez une contribution supérieure à zéro.","Enter a positive contribution.")) end
        id,err=B.Pledge(o.id,amount)
    elseif kind=="note" then id,err=B.Update(o.id,f.editor.field:GetText(),false)
    elseif kind=="withdraw" then id,err=B.Withdraw(o.id) end
    if actionResult(id,err) then
        f.editing=nil
        if kind=="withdraw" then chooseTab("history"); selectOrder(o.id) else refresh() end
        message(L("Modification enregistrée.","Change saved."))
    end
end
local function setTarget(record)
    f.target = record
    f.form.target:SetText(record and UI.plain(record.fullName or record.name) or L("Sélectionnez un joueur à gauche","Select a player on the left"))
    f.form.publish:SetEnabled(record ~= nil)
end
local function syncOptions()
    for _, pair in ipairs(f.form.options) do UI.selectButton(pair.control, f.draft[pair.key]==pair.value) end
    f.form.equal:SetEnabled(f.draft.group=="party")
end
startForm = function(record, origin)
    f.editing, f.origin, f.tab = nil, origin, "active"
    f.draftGuild=GL.Safe(GetGuildInfo,"player")
    f.filters:Hide(); f.form:Show(); f.detail:Hide()
    f.draft={group="solo",split="winner",souvenir="none"}
    f.form.gold:SetText(""); f.form.quota:SetText("1"); f.form.note:SetText("")
    setTarget(record); syncOptions(); resetList(); message(); refresh()
end
local function cancelForm()
    local origin = f.origin
    chooseTab("active")
    if origin then GL.ShowLedger("guid:" .. origin) end
end
local function publish()
    if not f.target then return end
    local guild=GL.Safe(GetGuildInfo,"player")
    if not guild then return message(L("Rejoignez une guilde pour publier la prime.","Join a guild to publish this bounty.")) end
    if f.draftGuild and guild~=f.draftGuild then
        return message(L("Vous avez changé de guilde. Rouvrez la création pour la nouvelle guilde.","Your guild changed. Reopen the form to post to your new guild."))
    end
    local amount, q = copper(f.form.gold:GetText()), f.form.quota:GetText():match("^%d+$")
    q = tonumber(q)
    if not amount then return message(L("La récompense doit être comprise entre 0 et 1 000 PO.","Enter a reward from 0 to 1,000 gold.")) end
    if not q or q < 1 or q > 99 then return message(L("Choisissez entre 1 et 99 victoires.","Choose from 1 to 99 wins.")) end
    local note = f.form.note:GetText()
    if #note>100 or GL.ContainsControlOrMarkup(note) or note:find(";",1,true) then
        return message(L("Consigne limitée à 100 octets, sans point-virgule ni code de couleur.","Use up to 100 bytes, without semicolons or color codes."))
    end
    local options = {quota=q,group=f.draft.group,split=f.draft.split,souvenir=f.draft.souvenir,note=note}
    local id,err = B.Post(f.target.guid,f.target.fullName or f.target.name,amount,options)
    if actionResult(id,err) then chooseTab("active"); selectOrder(id); message(L("Prime publiée à la guilde.","Bounty posted to your guild.")) end
end
local function makeForm()
    local form=CreateFrame("Frame",nil,f); f.form=form; form:SetAllPoints(f); form.options={}
    text(form,358,163,525,26,20,nil,L("Créer une prime de guilde","Create a guild bounty"))
    form.target=text(form,358,201,545,30,18)
    text(form,358,251,250,24,14,nil,L("Récompense totale (PO)","Total reward (gold)"))
    text(form,642,251,250,24,14,nil,L("Victoires requises","Wins required"))
    form.gold=input(form,358,277,243,12,true); form.quota=input(form,642,277,195,2,true)
    local function choice(key, value, label, x, y, w)
        local c=button(form,label,x,y,w,function()
            f.draft[key]=value
            if f.draft.group=="solo" then f.draft.split="winner" end
            syncOptions()
        end,true)
        form.options[#form.options+1]={key=key,value=value,control=c}
        return c
    end
    text(form,358,332,135,25,14,nil,L("Chasse","Hunt"))
    choice("group","solo",L("Hors groupe","Solo only"),489,324,180)
    choice("group","party",L("Groupe autorisé","Groups allowed"),682,324,196)
    text(form,358,372,135,24,14,nil,L("Répartition","Payout"))
    choice("split","winner",L("Au vainqueur","Winner takes all"),489,364,180)
    form.equal=choice("split","equal",L("Parts égales","Equal shares"),682,364,196)
    tip(form.equal,L("Entre le vainqueur et les membres de guilde de son groupe présents à proximité de la dernière victoire.","Split with nearby guild party members at the final win."))
    text(form,358,414,135,24,14,nil,L("Souvenir","Keepsake"))
    choice("souvenir","none",souvenirs.none,489,406,108)
    choice("souvenir","screenshot",L("Capture","Screenshot"),606,406,140)
    choice("souvenir","video",L("Vidéo","Video"),755,406,123)
    text(form,358,455,540,22,14,nil,L("Consigne libre · facultative","Special instructions · optional"))
    form.note=input(form,358,482,520,100,true)
    text(form,358,526,535,56,13,t.inkMuted,L("Les victoires sont comptées automatiquement. Les souvenirs et les consignes libres sont facultatifs.","Wins count automatically. Keepsakes and free instructions are optional."))
    form.cancel=button(form,L("Annuler","Cancel"),358,597,148,cancelForm,true)
    form.publish=button(form,L("Créer la prime","Post bounty"),606,597,272,publish,true)
    UI.selectButton(form.publish,true); form:Hide()
end

local function makeDetail()
    local p=CreateFrame("Frame",nil,f); f.detail=p; p:SetAllPoints(f)
    p.kicker=text(p,358,161,535,31,22,t.red)
    local face=CreateFrame("Button",nil,p); p.face=face; face:SetPoint("TOPLEFT",358,-200); face:SetSize(100,100)
    UI.surface(face,t.gold); face.raceIcon=face:CreateTexture(nil,"ARTWORK")
    face.raceIcon:SetPoint("TOPLEFT",3,-3); face.raceIcon:SetPoint("BOTTOMRIGHT",-3,3)
    local rim=face:CreateTexture(nil,"OVERLAY"); rim:SetAllPoints(face); rim:SetTexture(media.."PortraitBezel")
    face.classIcon=face:CreateTexture(nil,"OVERLAY"); face.classIcon:SetSize(19,19); face.classIcon:SetPoint("BOTTOMRIGHT",-3,3)
    p.level=CreateFrame("Frame",nil,face); p.level:SetPoint("BOTTOMLEFT",-3,-3); p.level:SetSize(28,28)
    local medallion=p.level:CreateTexture(nil,"ARTWORK"); medallion:SetAllPoints(p.level); medallion:SetTexture(media.."LevelMedallion")
    p.level.caption=text(p.level,0,0,28,28,14,t.paper); p.level.caption:SetJustifyH("CENTER")
    GL.Safe(p.level.caption.SetJustifyV,p.level.caption,"MIDDLE")
    face:SetScript("OnClick",function() if f.order then showDossier(f.order.target,f.order.name) end end)
    tip(face,L("Ouvrir la fiche du joueur","Open player dossier"))
    p.name=button(p,"",470,201,428,function() if f.order then showDossier(f.order.target,f.order.name) end end,true)
    p.name:SetHeight(34); p.name.caption:SetHeight(28); UI.journalFont(p.name.caption,"GameFontNormalLarge",18)
    p.identity=text(p,474,243,427,25,14,t.inkMuted)
    p.price=text(p,474,268,427,31,21)
    for _,y in ipairs({305,376,479}) do
        local rule=p:CreateTexture(nil,"ARTWORK"); rule:SetPoint("TOPLEFT",358,-y)
        rule:SetSize(540,1); rule:SetColorTexture(unpack(t.gold)); rule:SetAlpha(.6)
    end
    p.progress=text(p,358,313,544,26,18,t.red)
    p.rules=text(p,358,342,548,40,13,t.inkMuted)
    p.owner=button(p,"",358,383,305,function() if f.order then showDossier(f.order.owner,who(f.order.owner)) end end,true)
    p.deadline=text(p,670,385,228,32,12,t.inkMuted)
    p.note=text(p,358,423,540,64,14)
    p.payment=text(p,358,487,547,26,14)
    p.people={}
    for i=1,5 do
        local c=button(p,"",358+((i-1)%2)*271,514+math.floor((i-1)/2)*29,262,
            function(self) if self.guid then showDossier(self.guid,who(self.guid)) end end,true)
        p.people[i]=c
    end
    local bar=CreateFrame("Frame",nil,p); f.tools=bar; bar:SetAllPoints(p)
    bar.pin=button(bar,"",358,522,145,function()
        local o=f.order
        if o then local saved=pins(true); saved[o.id]=not saved[o.id] or nil; refresh() end
    end,true)
    bar.pledge=button(bar,L("Contribuer","Contribute"),512,522,160,function() showEditor("pledge") end,true)
    bar.note=button(bar,L("Modifier la consigne","Edit instructions"),358,563,193,function() showEditor("note") end,true)
    bar.renew=button(bar,L("Renouveler","Renew"),557,563,138,function()
        if f.order and actionResult(B.Update(f.order.id,nil,true)) then refresh(); message(L("Contrat renouvelé.","Contract renewed.")) end
    end,true)
    bar.withdraw=button(bar,L("Retirer la prime","Withdraw bounty"),701,563,194,function() showEditor("withdraw") end,true)
    p.dossier=button(p,L("Fiche du joueur","Player dossier"),358,614,178,function() if f.order then showDossier(f.order.target,f.order.name) end end,true)
    local edit=CreateFrame("Frame",nil,p); f.editor=edit; edit:SetAllPoints(p)
    edit.title=text(edit,358,495,540,20,14); edit.field=input(edit,358,520,532,100,true)
    edit.ok=button(edit,"",358,565,235,commitEdit,true)
    edit.cancel=button(edit,L("Annuler","Cancel"),606,565,160,function() f.editing=nil; refresh() end,true)
    edit:Hide()
end
local function renderDetail(o)
    local p=f.detail
    visible(p,o~=nil)
    if not o then return end
    local record=contact(o.target) or {guid=o.target,fullName=o.name}
    GL.PaintBookPortrait(p.face,record)
    local faction,race,class=GL.IdentityLabels(record)
    local lvl=GL.ValidLevel(record.level)
    p.name:SetText(UI.plain(o.name).."  ›")
    visible(p.level,lvl~=nil); if lvl then p.level.caption:SetText(tostring(lvl)) end
    p.identity:SetText(UI.plain(table.concat({race,class,faction}," · ")))
    p.price:SetText(L("Récompense totale  ","Total reward  ")..money(total(o)))
    local due,winner=0,o.winner and o.winner.actor
    for i,c in ipairs(p.people) do c.guid=nil; c:Hide() end
    if winner then
        p.kicker:SetText(states[o.state])
        local me,myShare=mine(),0
        local hunters=members(o)
        for i,h in ipairs(hunters) do
            local c=p.people[i]
            local outstanding=B.Due(o,me,h)
            due=due+outstanding
            if c then
                c.guid=h
                local share=0
                for payer in pairs(o.pot) do
                    local transferred,retained=B.Share(o,payer,h)
                    share=share+transferred+retained
                end
                if h==me then myShare=share end
                local label=UI.plain(who(h)).." · "..money(share)
                if o.pot[me] and o.pot[me]>0 then label=UI.plain(who(h)).." · "..L("dû ","owed ")..money(outstanding) end
                c:SetText(label); c:Show()
            end
        end
        p.payment:SetText(due>0 and (L("À envoyer à la boîte aux lettres : ","Send at a mailbox: ")..money(due))
            or myShare>0 and (L("Votre part : ","Your share: ")..money(myShare)) or L("Bénéficiaires","Beneficiaries"))
        p.progress:SetText(L("Prime faite · ","Bounty complete · ")..(o.quota or 1).."/"..(o.quota or 1)..L(" victoires"," wins"))
    else
        p.kicker:SetText(isOpen(o) and L("MISE À PRIX","WANTED") or states[o.state])
        p.progress:SetText(L("Vos victoires : ","Your wins: ")..B.Progress(o).."/"..(o.quota or 1).."   ·   "..(states[o.state] or ""))
        p.payment:SetText("")
    end
    p.rules:SetText((o.group=="solo" and L("Chasse hors groupe","Solo only") or L("Groupe autorisé","Groups allowed"))
        .."   ·   "..(o.split=="equal" and L("Or partagé à parts égales","Gold split equally") or L("Or au vainqueur","Winner takes all"))
        .."\n"..L("Souvenir : ","Keepsake: ")..(souvenirs[o.souvenir] or souvenirs.none))
    p.owner:SetText(L("Commanditaire : ","Issuer: ")..UI.plain(who(o.owner)).."  ›")
    p.deadline:SetText(winner and L("Terminée : ","Completed: ")..compactDate(o.winner.time)
        or L("Échéance : ","Expires: ")..compactDate(o.expires))
    p.note:SetText(o.note and o.note~="" and UI.plain(o.note) or L("Aucune consigne particulière.","No special instructions."))
    if o.state~="open" then f.editing=nil end
    visible(f.tools,isOpen(o) and not f.editing); visible(f.editor,f.editing~=nil)
    f.tools.pin:SetText(pins()[o.id] and L("Désépingler","Unpin") or L("Épingler","Pin"))
    f.tools.pledge:SetEnabled(o.state=="open")
    local owner=o.state=="open" and o.owner==mine()
    visible(f.tools.note,owner); visible(f.tools.renew,owner); visible(f.tools.withdraw,owner)
end
selectOrder=function(id)
    f.selected, f.editing, f.reveal = id,nil,true
    f.filters:Hide(); message(); refresh()
end
local function filteredContacts(query)
    local list, seen={},{}
    local current=GL.Identity("target")
    if current and current.guid and (current.fullName or ""):lower():find(query:lower(),1,true) then
        list[#list+1]=current; seen[current.guid]=true
    end
    for _,record in ipairs(GL.SearchPlayers({query=query,sort="name"})) do
        if record.guid and record.guid~=mine() and not seen[record.guid] then list[#list+1]=record end
    end
    return list
end
local function currentOrders()
    -- The engine replays the guild log. Scrolling or typing must only filter its current result.
    if f.cachedTab~=f.tab or not f.cachedOrders or (f.nextExpiry and GL.Now()>f.nextExpiry) then
        f.cachedTab,f.cachedOrders,f.nextExpiry=f.tab,f.tab=="history" and B.History() or B.List(),nil
        for _,o in pairs(f.cachedOrders) do
            if o.state=="open" and o.expires and (not f.nextExpiry or o.expires<f.nextExpiry) then f.nextExpiry=o.expires end
        end
    end
    return f.cachedOrders
end
refresh=function()
    if not f or not f:IsShown() then return end
    local creating=f.form:IsShown()
    local query=f.search:GetText():lower()
    local list,selected={},nil
    if creating then
        list=filteredContacts(query)
    else
        local me,pinned=mine(),pins()
        for _,o in pairs(currentOrders()) do
            if (f.tab=="history" or isOpen(o)) and passFilter(o,f.filterKey,me,pinned)
                and o.name:lower():find(query,1,true) then
                list[#list+1]=o
            end
        end
        table.sort(list,function(a,b)
            local at,bt=(a.winner and a.winner.time) or a.at,(b.winner and b.winner.time) or b.at
            if at~=bt then return at>bt end
            return a.id>b.id
        end)
        for index,o in ipairs(list) do
            if o.id==f.selected then
                selected=o
                if f.reveal and (index<=f.offset or index>f.offset+pageSize) then f.offset=index-1 end
                break
            end
        end
        f.reveal=nil
        selected=selected or list[1]
        if not selected or f.selected~=selected.id then f.editing=nil end
        f.selected=selected and selected.id
    end
    f.order=selected; f.offset=math.max(0,math.min(f.offset,#list-pageSize)); f.count=#list
    f.heading:SetText(creating and L("Choisir la cible","Choose a target") or f.tab=="history" and L("Mon historique","My history") or L("Primes en cours","Open bounties"))
    UI.selectButton(f.activeTab,not creating and f.tab=="active"); UI.selectButton(f.historyTab,not creating and f.tab=="history")
    visible(f.filter,not creating); visible(f.new,not creating)
    if not creating then
        for _,entry in ipairs(filterLists[f.tab]) do if entry[1]==f.filterKey then f.filter:SetText(L("Filtre : ","Filter: ")..entry[2]) end end
    end
    for i,row in ipairs(f.rows) do
        local e=list[i+f.offset]; row.entry=e; visible(row,e~=nil)
        if e then
            local id=creating and e.guid or e.target
            row.player:SetText(UI.plain(e.fullName or e.name))
            local label=creating and L("Choisir","Choose") or f.tab=="active" and money(total(e)) or states[e.state]
            if not creating and f.tab=="history" and e.state=="fulfilled" then label=L("À régler","Pending") end
            row.select:SetText(label.." ›")
            UI.selectButton(row.select,creating and f.target and f.target.guid==id or not creating and f.selected==e.id)
        end
    end
    f.prev:SetEnabled(f.offset>0); f.next:SetEnabled(f.offset+pageSize<#list)
    f.page:SetText(#list==0 and "0" or (f.offset+1).."–"..math.min(f.offset+pageSize,#list).." / "..#list)
    f.empty:SetText(#list==0 and (query~="" and L("Aucun résultat pour cette recherche.","No results for your search.")
        or creating and L("Aucun contact identifié. Ciblez un personnage en jeu.","No known contact. Target a player in game.")
        or f.tab=="active" and not GL.Safe(GetGuildInfo,"player") and L("Rejoignez une guilde pour utiliser les primes.","Join a guild to use bounties.")
        or L("Aucune prime dans cette sélection.","No bounties in this selection.")) or "")
    if not creating then renderDetail(selected) end
end

local function build()
    f=UI.bookWindow("GrudgeLedgerBounties", "Grudge Ledger")
    f.tab,f.filterKey,f.offset="active","all",0
    GL.SetupBookNavigation(f,"bounties")
    f.activeTab=button(f,L("En cours","Open"),35,162,122,function() chooseTab("active") end)
    f.historyTab=button(f,L("Mon historique","My history"),160,162,145,function() chooseTab("history") end)
    f.heading=text(f,36,203,268,26,18,t.paper)
    f.search=input(f,36,236,269,64,false)
    f.placeholder=text(f.search,9,5,250,19,12,t.muted,L("Rechercher un joueur…","Search players…"))
    f.filter=button(f,"",36,270,269,function()
        if f.filters:IsShown() then return f.filters:Hide() end
        for n,c in ipairs(f.filterChoices) do
            local entry=filterLists[f.tab][n]
            c.key=entry and entry[1]
            visible(c,entry~=nil)
            if entry then c:SetText(entry[2]); UI.selectButton(c,f.filterKey==entry[1]) end
        end
        f.filters:Show()
    end)
    f.rows={}
    for i=1,pageSize do
        local row=CreateFrame("Button",nil,f); row:SetPoint("TOPLEFT",35,-(309+(i-1)*40)); row:SetSize(272,39)
        UI.surface(row,t.panel,1)
        local function select()
            if not row.entry then return end
            if f.form:IsShown() then setTarget(row.entry); message(); refresh() else selectOrder(row.entry.id) end
        end
        row:SetScript("OnClick",select)
        row.player=button(row,"",2,5,166,function()
            local e=row.entry
            if e then showDossier(e.target or e.guid,e.fullName or e.name) end
        end)
        tip(row.player,L("Ouvrir la fiche du joueur","Open player dossier"))
        row.select=button(row,"",169,5,100,select)
        f.rows[i]=row
    end
    f.empty=text(f,36,313,267,82,15,t.brass)
    local function shift(n) f.offset=math.max(0,f.offset+n); refresh() end
    f.prev=button(f,"<",36,562,66,function() shift(-pageSize) end)
    f.next=button(f,">",239,562,66,function() shift(pageSize) end)
    f.page=text(f,101,568,137,18,12,t.paper); f.page:SetJustifyH("CENTER")
    f.new=button(f,L("Créer une prime","Create bounty"),36,609,269,function() startForm(nil) end)
    local listArea=CreateFrame("Frame",nil,f)
    listArea:SetPoint("TOPLEFT",33,-305); listArea:SetSize(275,pageSize*40+8)
    if listArea.EnableMouseWheel then
        listArea:EnableMouseWheel(true)
        listArea:SetScript("OnMouseWheel",function(_,delta) shift(delta>0 and -1 or 1) end)
        for _,r in ipairs(f.rows) do
            for _,control in ipairs({r,r.player,r.select}) do
                control:EnableMouseWheel(true); control:SetScript("OnMouseWheel",listArea:GetScript("OnMouseWheel"))
            end
        end
    end
    f.filters=CreateFrame("Frame",nil,f)
    f.filters:SetPoint("TOPLEFT",36,-296); f.filters:SetSize(269,142); f.filters:EnableMouse(true)
    if f.filters.SetFrameLevel then f.filters:SetFrameLevel(f:GetFrameLevel()+8) end
    UI.surface(f.filters,t.gold); UI.surface(f.filters,t.panel,1,1)
    f.filterChoices={}
    for i=1,5 do
        f.filterChoices[i]=button(f.filters,"",4,3+(i-1)*27,261,function(self)
            f.filterKey=self.key; f.selected=nil; f.offset=0; f.editing=nil
            f.filters:Hide(); message(); refresh()
        end)
    end
    f.filters:Hide()
    makeForm(); makeDetail()
    f.feedback=text(f,351,649,555,21,12,t.ink)
    f.search:SetScript("OnTextChanged",function(self)
        visible(f.placeholder,self:GetText()==""); f.offset=0; f.filters:Hide(); refresh()
    end)
    f:HookScript("OnHide",function() f.filters:Hide(); f.search:ClearFocus() end)
    f:RegisterEvent("PLAYER_GUILD_UPDATE")
    f:SetScript("OnEvent",function() f.cachedOrders=nil; f.dirty=true end)
    local elapsed=0
    f:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+(dt or 0)
        if not f.dirty and elapsed<1 then return end
        elapsed=0
        if f.dirty or (f.nextExpiry and GL.Now()>f.nextExpiry) then
            f.dirty,f.cachedOrders,f.nextExpiry=nil,nil,nil; refresh()
        end
    end)
end

function GL.OpenBounties(guid,mode)
    if not f then build() end
    GL.ShowBookPage(f)
    f.cachedOrders=nil
    chooseTab("active")
    if mode=="create" then
        local r=contact(guid)
        if guid and not r then
            local live=GL.Identity("target")
            if live and live.guid==guid then r=live end
        end
        startForm(r,r and r.guid)
    elseif guid then
        for _,o in pairs(currentOrders()) do
            if o.target==guid and isOpen(o) then selectOrder(o.id); return f end
        end
        chooseTab("history")
        for _,o in pairs(currentOrders()) do
            if o.target==guid then selectOrder(o.id); return f end
        end
        chooseTab("active"); message(L("Aucune prime pour ce joueur.","No bounty for this player."))
    end
    return f
end

-- A burst of sync events repaints the visible panel only once on the next frame.
GL.On("BOUNTIES_CHANGED",function() if f then f.dirty=true end end)
