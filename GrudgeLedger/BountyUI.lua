-- Guild contracts share the book's navigation, portraits and character dossier. Since 0.56.0 the
-- page has the narrow format of Relations and Guilde: the lists and the key figures on the left,
-- the list, a bounty or the creation on the right.
local GL = GrudgeLedger
local UI, B = GL.UITheme, GL.Bounties
local f, refresh, startForm, selectOrder
local t = UI.theme
local media="Interface\\AddOns\\GrudgeLedger\\Media\\"
local pageSize = 6
local L = GL.L
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
local function targetInfo(record)
    local profile=GL.ArmoryProfile(record) or {}
    local a=profile.identity or {}
    local faction,race,class=GL.IdentityLabels(record)
    return (record.race or record.raceName) and race or a.race or race,
        (record.class or record.className) and class or a.class or class,
        record.faction and faction or a.faction or faction, GL.ValidLevel(record.level) or GL.ValidLevel(profile.level)
end
local function total(o)
    local n = 0
    for _, amount in pairs(o.pot) do n = n + amount end
    return n
end
local function money(n)
    if n % 10000 == 0 then return math.floor(n / 10000) .. L(" PO") end
    return ("%d %s %d %s %d %s"):format(math.floor(n / 10000), L("po"), math.floor(n / 100) % 100,
        L("pa"), n % 100, L("pc"))
end
GL.BountyMoney, GL.BountyTotal = money, total
local function copper(value)
    local whole, fraction = value:match("^%s*(%d+)[.,](%d+)%s*$")
    if not whole then whole, fraction = value:match("^%s*(%d+)%s*$"), "" end
    if whole and #fraction <= 4 and tonumber(whole) <= 1000 then
        local amount = tonumber(whole) * 10000 + tonumber((fraction .. "0000"):sub(1, 4))
        if amount <= 10000000 then return amount end
    end
end
local states = {
    open=L("En cours"), claimed=L("Objectif atteint · en attente du commanditaire"),
    superseded=L("Prime remplacée"),
    fulfilled=L("Prime faite · règlement en attente"),
    sent=L("Courrier en transit"), paid=L("Payée"),
    withdrawn=L("Retirée"), expired=L("Expirée")
}
local souvenirs = { none=L("Aucun"), screenshot=L("Capture d’écran"), video=L("Vidéo") }
-- The lists the list button shows in turn, as in the Journal; the other choices are in "Filtres".
local filterLists = {
    active={{"all",L("En cours")},{"pinned",L("Épinglées")},{"issued",L("Mes contrats")}},
    history={{"all",L("Tout")},{"incoming",L("Or à recevoir")},{"due",L("Or à envoyer")},
        {"transit",L("Courrier en transit")},{"paid",L("Payées")}}
}
local function members(o)
    local w=o.winner or o.priorWinner or o.first
    if not w then return {} end
    local result = {w.actor}
    for id in (w.detail or ""):gmatch("[^,]+") do result[#result+1] = id end
    return result
end
local function account(o,me)
    local a={due=0,incoming=0,received=0,transit=0,amount=0,remaining=0}
    -- Once the guild roster is read, what is still to send to someone gone from the guild is set
    -- aside: the mailbox no longer offers it. Mail already sent and what they received stay counted.
    local roster=B.IsMember(me)
    for _,h in ipairs(members(o)) do
        if h==me then a.hunted=true end
        local gone=roster and not B.IsMember(h)
        for payer in pairs(o.pot) do
            local send,waiting,received=B.Payment(o,payer,h)
            if gone then
                waiting=waiting-send
                send=0
            end
            if payer==me then a.due=a.due+send end
            if h==me then a.incoming=a.incoming+waiting; a.received=a.received+received end
            if payer==me or h==me or o.owner==me then
                a.transit=a.transit+waiting-send
                a.amount=a.amount+waiting+received
                a.remaining=a.remaining+waiting
            end
        end
    end
    a.role=o.owner==me and (a.hunted and L("Chasse et contrat") or L("Commanditaire"))
        or a.hunted and L("Chasseur") or (o.pot[me] and L("Contributeur") or L("Participant"))
    a.status=states[o.state]
    if o.winner and not o.supersededBy then
        a.status=a.amount==0 and L("Terminée") or a.remaining==0 and states.paid
            or a.due>0 and L("À envoyer") or a.incoming>0 and L("À recevoir")
            or a.transit==a.remaining and states.sent or L("Paiement en attente")
    end
    return a
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
local function isOpen(o) return o.state == "open" end
local function passFilter(o, filter, me, pinned, a)
    if filter == "issued" then return o.owner == me end
    if filter == "pinned" then return pinned[o.id] end
    if filter == "party" or filter == "solo" then return o.group == filter end
    if filter=="paid" then return a.amount>0 and a.remaining==0 end
    if filter=="due" or filter=="incoming" or filter=="transit" then return a[filter]>0 end
    return true
end
local function visible(region, yes) if yes then region:Show() else region:Hide() end end
local function goldStars(parent,x,y,size)
    local mark=CreateFrame("Frame",nil,parent)
    mark:SetPoint("TOPLEFT",x,-y); mark:SetSize(size*2,size+3)
    for i=0,1 do
        local star=mark:CreateTexture(nil,"OVERLAY")
        star:SetPoint("TOPLEFT",i*size,-i*3); star:SetSize(size-i*3,size-i*3)
        star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    end
    mark:Hide()
    return mark
end
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
    f.tab, f.filterKey, f.role, f.selected, f.editing, f.origin = tab,"all","all",nil,nil,nil
    f.kind, f.group, f.viewing, f.choosing, f.creating = "all","all",nil,nil,nil
    f.form:Hide()
    f.filters:Hide()
    resetList()
    message()
    refresh()
end
local function actionResult(id,err,why)
    if id then f.cachedOrders=nil; return true end
    -- A refusal names its cause: "check the contract" alone left the player with nothing to do.
    local causes = {
        scope=L("Guilde ou royaume illisible pour l’instant. Réessayez dans un instant, ou après un /reload."),
        target=L("Ce joueur n’a pas encore d’identifiant dans votre livre. Ciblez-le une fois, puis recommencez."),
        self=L("Vous ne pouvez pas poser une prime sur vous-même."),
        name=L("Le nom de ce joueur ne peut pas être envoyé à la guilde."),
    }
    local part=type(why)=="string" and why:match("^scope:(%a+)$")
    if part then
        if part=="noguild" then
            message(L("Vous n’êtes dans aucune guilde. Une prime se dépose dans une guilde : ses membres la voient et la chassent."))
            return false
        end
        local parts={guild=L("Le nom de votre guilde n’est pas encore arrivé. Réessayez dans quelques secondes."),
            realm=L("Le royaume ne peut pas être lu."),
            player=L("Votre propre identifiant ne peut pas être lu.")}
        message((parts[part] or causes.scope)..(part=="guild" and "" or " "..L("Faites une capture de ce message.")))
        return false
    end
    if err=="invalid" and causes[why] then
        message(causes[why])
        return false
    end
    local errors = {
        ally=L("Cet allié peut recevoir des étiquettes dans le Journal."),
        duplicate=L("Une prime est déjà ouverte sur ce joueur."),
        guild=L("Une guilde est nécessaire pour publier."),
        limit=L("Limite de contrats, de montant ou de renouvellement atteinte."),
        invalid=L("Vérifiez le contrat, le montant et la consigne.")
    }
    message(errors[err] or L("Opération refusée. Actualisez le contrat."))
    return false
end
local function compactDate(ts)
    return (ts and GL.Safe(date,"%d/%m/%Y %H:%M",ts)) or "—"
end
local function noteError(value)
    if #value>100 then return L("Raccourcissez la consigne. Les caractères accentués occupent plus de place.") end
    if GL.ContainsControlOrMarkup(value) or value:find(";",1,true) then
        return L("Retirez les points-virgules et les codes de mise en forme.")
    end
end
local function showNoteBudget(edit,label)
    label:SetText(L("Espace utilisé : %d %%"):format(#edit:GetText()))
end
local function huntRules(group,split)
    local rule=L("Les coups fatals doivent venir du même chasseur ou de son familier.")
    if group=="solo" then return rule.." "..L("Chasse en solo.") end
    if split=="equal" then
        return rule.." "..L("Groupe de 5 maximum. Parts égales entre le vainqueur et ses équipiers de guilde visibles à la dernière victoire.")
    end
    return rule.." "..L("Groupe de 5 maximum. Toute la prime revient au vainqueur.")
end
local function showEditor(kind)
    local o = f.order
    if not o then return end
    f.editing = kind
    f.tools:Hide(); f.editor:Show()
    local titles = {pledge=L("Votre contribution en PO (jusqu’à 1 000)"),
        note=L("Consigne libre"),
        withdraw=L("Retirer ce contrat de la guilde ?")}
    visible(f.editor.budget,kind=="note")
    f.editor.title:SetText(titles[kind]); visible(f.editor.field,kind ~= "withdraw")
    f.editor.field:SetText(kind == "note" and (o.note or "") or "")
    f.editor.ok:SetText(kind=="withdraw" and L("Confirmer le retrait") or L("Valider"))
    if kind ~= "withdraw" then f.editor.field:SetFocus() end
    message()
end
local function commitEdit()
    local o, kind = f.order, f.editing
    if not o or not kind then return end
    local id,err
    if kind=="pledge" then
        local amount = copper(f.editor.field:GetText())
        if not amount or amount <= 0 then return message(L("Saisissez une contribution supérieure à zéro.")) end
        id,err=B.Pledge(o.id,amount)
    elseif kind=="note" then
        local value=f.editor.field:GetText()
        local problem=noteError(value)
        if problem then return message(problem) end
        id,err=B.Update(o.id,value,false)
    elseif kind=="withdraw" then id,err=B.Withdraw(o.id) end
    if actionResult(id,err) then
        f.editing=nil
        if kind=="withdraw" then chooseTab("history"); selectOrder(o.id) else refresh() end
        message(L("Modification enregistrée."))
    end
end
local function setTarget(record)
    f.target = GL.BountyTargetEligible(record) and record or nil
    record = f.target
    f.form.target:SetText(record and UI.plain(record.fullName or record.name) or L("Aucune cible choisie"))
    if record and record.faction~="Alliance" and record.faction~="Horde" then
        f.form.target:SetText(UI.plain(record.fullName or record.name).." · "..L("Faction inconnue"))
    end
    f.form.change:SetText(record and L("Changer") or L("Choisir"))
end
-- The form shows only what the chosen kind needs: no gold for a wanted notice, no split without a
-- group. The rules sum up in one line.
local function syncOptions()
    local gold=f.draft.kind=="gold"
    if f.draft.group=="solo" or not gold then f.draft.split="winner" end
    for _, pair in ipairs(f.form.options) do UI.selectButton(pair.control, f.draft[pair.key]==pair.value) end
    UI.selectButton(f.form.free,not gold)
    UI.selectButton(f.form.gift,gold)
    visible(f.form.goldLabel,gold)
    visible(f.form.gold,gold)
    local split=gold and f.draft.group=="party"
    visible(f.form.splitLabel,split)
    for _, pair in ipairs(f.form.options) do
        if pair.key=="split" then visible(pair.control,split) end
    end
    f.form.equal:SetEnabled(split)
    f.form.rules:SetText(huntRules(f.draft.group,f.draft.split).." "..L("Souvenir facultatif."))
    f.form.publish:SetText(gold and L("Publier la prime") or L("Publier l’avis"))
    f.form.publish:SetEnabled(f.target~=nil)
end
startForm = function(record, origin)
    f.editing, f.origin, f.tab, f.repostFrom, f.viewing, f.creating = nil, origin, "active", nil, nil, true
    f.draftGuild=GL.Safe(GetGuildInfo,"player")
    f.filters:Hide()
    f.detail:Hide()
    f.form:Show()
    f.draft={kind="free",group="solo",split="winner",souvenir="none"}
    f.form.gold:SetText("")
    f.form.quota:SetText("1")
    f.form.note:SetText("")
    setTarget(record)
    -- Without a target the page first lists the players of the book: a click chooses one.
    f.choosing=f.target==nil
    syncOptions()
    resetList()
    message()
    refresh()
    if record and not f.target then actionResult(nil,"ally") end
end
local function cancelForm()
    local origin,previous=f.origin,f.repostFrom
    f.repostFrom=nil
    f.choosing=nil
    if previous then
        chooseTab("history")
        selectOrder(previous)
        return
    end
    chooseTab("active")
    if origin then GL.ShowLedger("guid:" .. origin) end
end
local function publish()
    if not f.target then return end
    local guild=GL.Safe(GetGuildInfo,"player")
    if not guild then return message(L("Rejoignez une guilde pour publier la prime.")) end
    if f.draftGuild and guild~=f.draftGuild then
        return message(L("Vous avez changé de guilde. Rouvrez la création pour la nouvelle guilde."))
    end
    -- A wanted notice carries no gold: the guild is told and alerted all the same.
    local reward = f.form.gold:GetText()
    local amount = f.draft.kind=="free" and 0 or copper(reward)
    local q = tonumber(f.form.quota:GetText():match("^%d+$"))
    if not amount or (f.draft.kind=="gold" and amount==0) then return message(L("La récompense doit être comprise entre 1 et 1 000 PO.")) end
    if not q or q < 1 or q > 99 then return message(L("Choisissez entre 1 et 99 victoires.")) end
    local note = f.form.note:GetText()
    local problem=noteError(note)
    if problem then return message(problem) end
    local options = {quota=q,group=f.draft.group,split=f.draft.split,souvenir=f.draft.souvenir,note=note}
    local id,err,why = B.Post(f.target.guid,f.target.fullName or f.target.name,amount,options)
    if actionResult(id,err,why) then
        chooseTab("active")
        selectOrder(id)
        message(amount==0 and L("Avis de recherche publié à la guilde, sans or.") or L("Prime publiée à la guilde."))
    end
end
-- The creation page: first what you publish (a free wanted notice or a bounty in gold), then the
-- target, then only the choices that kind needs.
local function makeForm(host)
    local form=CreateFrame("Frame",nil,host)
    f.form=form
    form:SetAllPoints(host)
    form.options={}
    form.heading=text(form,26,18,600,30,21,nil,L("Nouvelle prime"))
    UI.journalFont(form.heading,"GameFontNormalLarge",21)
    text(form,26,48,600,20,13,t.inkMuted,L("Choisissez ce que vous publiez à la guilde."))
    form.free=button(form,L("Avis de recherche · gratuit"),26,80,300,function()
        f.draft.kind="free"
        syncOptions()
    end,true)
    form.gift=button(form,L("Prime en or"),338,80,300,function()
        f.draft.kind="gold"
        syncOptions()
    end,true)
    text(form,26,132,110,22,14,nil,L("Cible"))
    form.target=text(form,140,128,360,26,17,t.ink)
    GL.Safe(form.target.SetWordWrap,form.target,false)
    form.change=button(form,"",510,126,128,function()
        f.choosing=true
        resetList()
        refresh()
    end,true)
    form.goldLabel=text(form,26,174,110,22,14,nil,L("Or (PO)"))
    form.gold=input(form,140,168,160,12,true)
    text(form,338,174,130,22,14,nil,L("Victoires"))
    form.quota=input(form,478,168,160,2,true)
    local function choice(key, value, label, x, y, w)
        local c=button(form,label,x,y,w,function()
            f.draft[key]=value
            syncOptions()
        end,true)
        form.options[#form.options+1]={key=key,value=value,control=c}
        return c
    end
    text(form,26,216,110,22,14,nil,L("Chasse"))
    choice("group","solo",L("Hors groupe"),140,210,244)
    choice("group","party",L("Groupe autorisé"),394,210,244)
    form.splitLabel=text(form,26,256,110,22,14,nil,L("Partage"))
    choice("split","winner",L("Au vainqueur"),140,250,244)
    form.equal=choice("split","equal",L("Parts égales"),394,250,244)
    tip(form.equal,L("Entre le vainqueur et les membres de guilde de son groupe présents à proximité de la dernière victoire."))
    text(form,26,296,110,22,14,nil,L("Souvenir"))
    choice("souvenir","none",souvenirs.none,140,290,160)
    choice("souvenir","screenshot",L("Capture"),310,290,160)
    choice("souvenir","video",L("Vidéo"),480,290,158)
    text(form,26,336,300,22,14,nil,L("Consigne · facultative"))
    form.budget=text(form,410,336,228,22,12,t.inkMuted)
    form.budget:SetJustifyH("RIGHT")
    form.note=input(form,26,360,612,100,true)
    form.note:SetScript("OnTextChanged",function(self) showNoteBudget(self,form.budget) end)
    form.rules=text(form,26,398,612,40,12,t.inkMuted)
    form.cancel=button(form,L("Annuler"),26,462,160,cancelForm,true)
    form.publish=button(form,L("Publier l’avis"),366,462,272,publish,true)
    UI.selectButton(form.publish,true)
    form:Hide()
end

-- The bounty itself: who and how much on top, the progress, the rules as four short lines, the
-- order and the note, then one bar of actions. The issuer's own actions have their line.
local function makeDetail(host)
    local p=CreateFrame("Frame",nil,host)
    f.detail=p
    p:SetAllPoints(host)
    p.back=button(p,"‹ "..L("Liste"),26,14,120,function()
        f.viewing=nil
        f.editing=nil
        refresh()
    end)
    local face=CreateFrame("Button",nil,p)
    p.face=face
    face:SetPoint("TOPLEFT",26,-50)
    face:SetSize(96,96)
    UI.surface(face,t.gold)
    face.raceIcon=face:CreateTexture(nil,"ARTWORK")
    face.raceIcon:SetPoint("TOPLEFT",3,-3)
    face.raceIcon:SetPoint("BOTTOMRIGHT",-3,3)
    local rim=face:CreateTexture(nil,"OVERLAY")
    rim:SetAllPoints(face)
    rim:SetTexture(media.."PortraitBezel")
    -- The 3D head is drawn in a child frame. Named like the Journal's, the frame and the level
    -- medallion are kept above it by the shared portrait overlay (owner report, 0.56.0).
    face.portraitRim=rim
    face.classIcon=face:CreateTexture(nil,"OVERLAY")
    face.classIcon:SetSize(19,19)
    face.classIcon:SetPoint("BOTTOMRIGHT",-3,3)
    p.level=CreateFrame("Frame",nil,face)
    p.level:SetPoint("BOTTOMLEFT",-3,-3)
    p.level:SetSize(28,28)
    face.levelBadge=p.level
    local medallion=p.level:CreateTexture(nil,"ARTWORK")
    medallion:SetAllPoints(p.level)
    medallion:SetTexture(media.."LevelMedallion")
    p.level.caption=text(p.level,0,0,28,28,14,t.paper)
    p.level.caption:SetJustifyH("CENTER")
    GL.Safe(p.level.caption.SetJustifyV,p.level.caption,"MIDDLE")
    face:SetScript("OnClick",function() if f.order then showDossier(f.order.target,f.order.name) end end)
    tip(face,L("Ouvrir la fiche du joueur"))
    p.name=text(p,136,50,300,30,21,t.ink)
    UI.journalFont(p.name,"GameFontNormalLarge",21)
    GL.Safe(p.name.SetWordWrap,p.name,false)
    p.nameLink=CreateFrame("Button",nil,p)
    p.nameLink:SetAllPoints(p.name)
    p.nameLink:SetScript("OnClick",face:GetScript("OnClick"))
    tip(p.nameLink,L("Ouvrir la fiche du joueur"))
    p.identity=text(p,136,82,300,20,13,t.inkMuted)
    p.kicker=text(p,136,104,300,22,14,t.red)
    p.price=text(p,438,48,200,34,26,t.red)
    p.price:SetJustifyH("RIGHT")
    p.stars=goldStars(p,436,54,16)
    p.rewardLabel=text(p,438,84,200,20,12,t.inkMuted)
    p.rewardLabel:SetJustifyH("RIGHT")
    for _,y in ipairs({156,300}) do
        local rule=p:CreateTexture(nil,"ARTWORK")
        rule:SetPoint("TOPLEFT",26,-y)
        rule:SetSize(612,1)
        rule:SetColorTexture(unpack(t.gold))
        rule:SetAlpha(.6)
    end
    p.progress=text(p,26,166,420,26,17,t.red)
    p.track=CreateFrame("Frame",nil,p)
    p.track:SetSize(160,6)
    p.track:SetPoint("TOPLEFT",p,"TOPLEFT",478,-176)
    UI.surface(p.track,t.gold)
    UI.surface(p.track,{.85,.75,.55},1,1)
    p.fill=p.track:CreateTexture(nil,"ARTWORK")
    p.fill:SetPoint("LEFT",p.track,"LEFT",1,0)
    p.fill:SetHeight(4)
    p.fill:SetColorTexture(.77,.52,.16,1)
    -- The rules, as four short lines in two columns.
    p.keys={}
    for i,entry in ipairs({{"group",L("Chasse")},{"split",L("Partage")},{"souvenir",L("Souvenir")},{"deadline",L("Échéance")}}) do
        local x,y=26+((i-1)%2)*312,200+math.floor((i-1)/2)*26
        text(p,x,y,96,22,13,t.inkMuted,entry[2])
        p.keys[entry[1]]=text(p,x+96,y,210,22,14,t.ink)
    end
    p.deadline=p.keys.deadline
    p.rules=text(p,26,254,612,40,12,t.inkMuted)
    p.owner=text(p,26,308,400,22,15,t.red)
    p.ownerLink=CreateFrame("Button",nil,p)
    p.ownerLink:SetAllPoints(p.owner)
    p.ownerLink:SetScript("OnClick",function() if f.order then showDossier(f.order.owner,who(f.order.owner)) end end)
    tip(p.ownerLink,L("Ouvrir la fiche du joueur"))
    p.note=text(p,26,334,612,36,14)
    p.payment=text(p,26,372,612,22,14)
    p.people={}
    for i=1,4 do
        local c=button(p,"",26+((i-1)%2)*310,396+math.floor((i-1)/2)*28,302,
            function(self) if self.guid then showDossier(self.guid,who(self.guid)) end end,true)
        p.people[i]=c
    end
    local bar=CreateFrame("Frame",nil,p)
    f.tools=bar
    bar:SetAllPoints(p)
    bar.manage=text(bar,26,412,150,22,13,t.inkMuted,L("Votre contrat"))
    bar.note=button(bar,L("Modifier la consigne"),140,406,200,function() showEditor("note") end,true)
    bar.renew=button(bar,L("Prolonger"),346,406,140,function()
        if f.order and actionResult(B.Update(f.order.id,nil,true)) then
            refresh()
            message(L("Contrat renouvelé."))
        end
    end,true)
    bar.withdraw=button(bar,L("Retirer"),492,406,146,function() showEditor("withdraw") end,true)
    bar.pledge=button(bar,L("Contribuer"),26,446,160,function() showEditor("pledge") end,true)
    bar.pin=button(bar,"",192,446,160,function()
        local o=f.order
        if o then
            local saved=pins(true)
            saved[o.id]=not saved[o.id] or nil
            refresh()
        end
    end,true)
    p.dossier=button(p,L("Fiche"),518,446,120,face:GetScript("OnClick"),true)
    p.retained=button(p,L("Voir la prime retenue"),26,446,260,function()
        local previous=f.order
        local current=B.OpenFor(previous.target)
        if current and current.id==previous.supersededBy and current.state=="open" then
            chooseTab("active")
            selectOrder(current.id)
        else
            message(L("La prime retenue est déjà terminée."))
        end
    end,true)
    p.repost=button(p,L("Republier la prime"),26,446,260,function()
        local o=f.order
        if not B.CanRepost(o) then return end
        startForm(contact(o.target) or {guid=o.target,fullName=o.name})
        f.repostFrom=o.id
        f.draft.group,f.draft.split,f.draft.souvenir=o.group or "party",o.split or "equal",o.souvenir or "none"
        local mise=(o.pot[o.owner] or 0)
        f.draft.kind=mise>0 and "gold" or "free"
        f.form.gold:SetText(mise>0 and tostring(mise/10000) or "")
        f.form.quota:SetText(tostring(o.quota or 1))
        f.form.note:SetText(o.note or "")
        syncOptions()
        message(L("Nouveau contrat : seule votre mise est reprise. Vérifiez puis publiez."))
    end,true)
    local edit=CreateFrame("Frame",nil,p)
    f.editor=edit
    edit:SetAllPoints(p)
    edit.title=text(edit,26,384,400,22,14)
    edit.budget=text(edit,410,384,228,22,12,t.inkMuted)
    edit.budget:SetJustifyH("RIGHT")
    edit.field=input(edit,26,408,612,100,true)
    edit.field:SetScript("OnTextChanged",function(self) showNoteBudget(self,edit.budget) end)
    edit.ok=button(edit,"",26,446,240,commitEdit,true)
    edit.cancel=button(edit,L("Annuler"),274,446,160,function()
        f.editing=nil
        refresh()
    end,true)
    edit:Hide()
end
local groupNames={solo=L("Hors groupe"),party=L("Groupe autorisé")}
local splitNames={winner=L("Au vainqueur"),equal=L("Parts égales")}
local function renderDetail(o)
    local p=f.detail
    visible(p,o~=nil and f.viewing==true)
    if not o then return end
    local record=contact(o.target) or {guid=o.target,fullName=o.name}
    GL.PaintBookPortrait(p.face,record)
    local race,class,faction,lvl=targetInfo(record)
    p.name:SetText(UI.plain(o.name))
    visible(p.level,lvl~=nil)
    if lvl then p.level.caption:SetText(tostring(lvl)) end
    p.identity:SetText(UI.plain(table.concat({race,class,faction}," · ")))
    local pot=total(o)
    p.price:SetText(pot>0 and money(pot) or L("Gratuit"))
    p.rewardLabel:SetText(pot>0 and L("Récompense totale") or L("Avis de recherche"))
    local final=o.winner or o.priorWinner
    local winner=final and final.actor
    local me=mine()
    local a=account(o,me)
    visible(p.stars,a.remaining>0)
    if a.remaining>0 then p.kicker:SetTextColor(.43,.23,.025) else p.kicker:SetTextColor(unpack(t.red)) end
    for _,c in ipairs(p.people) do
        c.guid=nil
        c:Hide()
    end
    if winner then
        p.kicker:SetText(o.supersededBy and states.superseded or L("Prime faite · ")..a.status)
        for i,h in ipairs(members(o)) do
            local c=p.people[i]
            if c then
                c.guid=h
                local share,waiting,toSend=0,0,0
                local _,retained=B.Share(o,h,h)
                for payer in pairs(o.pot) do
                    local send,unreceived,received=B.Payment(o,payer,h)
                    share,waiting,toSend=share+unreceived+received,waiting+unreceived,toSend+send
                end
                local status=share==0 and L("Sans courrier") or waiting==0 and L("Reçu")
                    or toSend==0 and L("En transit") or L("En attente")
                c:SetText(UI.plain(who(h)).." · "..status)
                local breakdown=UI.plain(who(h)).."\n"..status
                if share>0 then breakdown=breakdown.." · "..money(share-waiting).." / "..money(share) end
                if retained>0 then breakdown=breakdown.."\n"..L("Part conservée : ")..money(retained) end
                tip(c,breakdown)
                c:Show()
            end
        end
        local detail={a.role}
        if a.due>0 then detail[#detail+1]=L("À envoyer : ")..money(a.due) end
        if a.incoming>0 then detail[#detail+1]=L("À recevoir : ")..money(a.incoming) end
        if a.received>0 then detail[#detail+1]=L("Reçu : ")..money(a.received) end
        if a.due+a.incoming==0 and a.transit>0 then detail[#detail+1]=L("En transit : ")..money(a.transit) end
        p.payment:SetText(table.concat(detail,"  ·  "))
        p.progress:SetText(L("Victoires : ")..(o.quota or 1).."/"..(o.quota or 1))
    else
        p.kicker:SetText(states[o.state] or "")
        if o.state=="claimed" then
            p.progress:SetText(L("Victoires : ")..(o.quota or 1).."/"..(o.quota or 1))
        else
            p.progress:SetText(L("Vos victoires : ")..B.Progress(o).."/"..(o.quota or 1))
        end
        p.payment:SetText("")
    end
    local gauge=o.state=="open" and (o.quota or 1)>1
    visible(p.track,gauge)
    if gauge then
        local part=math.min(1,B.Progress(o)/(o.quota or 1))
        visible(p.fill,part>0)
        if part>0 then p.fill:SetWidth(158*part) end
    end
    p.keys.group:SetText(groupNames[o.group] or groupNames.party)
    p.keys.split:SetText(o.group=="solo" and "—" or splitNames[o.split] or splitNames.winner)
    p.keys.souvenir:SetText(souvenirs[o.souvenir] or souvenirs.none)
    p.deadline:SetText(winner and L("Terminée le ")..compactDate(final.time) or compactDate(o.expires))
    local rules=huntRules(o.group,o.split)
    if o.souvenir and o.souvenir~="none" then
        rules=rules.." "..L("Souvenir facultatif : %s."):format(souvenirs[o.souvenir] or souvenirs.none)
    end
    p.rules:SetText(rules)
    p.owner:SetText(L("Créée par %s"):format(UI.plain(who(o.owner))))
    p.note:SetText(o.note and o.note~="" and UI.plain(o.note) or L("Aucune consigne particulière."))
    visible(p.retained,o.state=="superseded")
    visible(p.repost,o.state~="superseded" and B.CanRepost(o))
    if o.state~="open" then f.editing=nil end
    visible(f.tools,isOpen(o) and not f.editing)
    visible(f.editor,f.editing~=nil)
    f.tools.pin:SetText(pins()[o.id] and L("Désépingler") or L("Épingler"))
    f.tools.pledge:SetEnabled(o.state=="open")
    local owner=o.state=="open" and o.owner==mine()
    visible(f.tools.manage,owner)
    visible(f.tools.note,owner)
    visible(f.tools.renew,owner)
    visible(f.tools.withdraw,owner)
end
selectOrder=function(id)
    f.selected, f.editing, f.reveal, f.viewing = id,nil,true,true
    f.filters:Hide()
    message()
    refresh()
end
local function filteredContacts(query)
    local list, seen={},{}
    local current=GL.Identity("target")
    if GL.BountyTargetEligible(current) and (current.fullName or ""):lower():find(query:lower(),1,true) then
        list[#list+1]=current
        seen[current.guid]=true
    end
    for _,record in ipairs(GL.SearchPlayers({query=query,sort="name"})) do
        if GL.BountyTargetEligible(record) and not seen[record.guid] then list[#list+1]=record end
    end
    return list
end
local function currentOrders()
    -- The engine replays the guild log. Scrolling or typing must only filter its current result.
    if f.cachedTab~=f.tab or not f.cachedOrders or (f.nextExpiry and GL.Now()>f.nextExpiry) then
        f.cachedTab=f.tab
        f.tallyLines=nil
        if f.tab=="history" then
            f.cachedOrders,f.nextExpiry=B.History()
        else
            f.cachedOrders,f.nextExpiry=B.List(),nil
            for _,o in pairs(f.cachedOrders) do
                if o.state=="open" and (not f.nextExpiry or o.expires<f.nextExpiry) then f.nextExpiry=o.expires end
            end
        end
    end
    return f.cachedOrders
end
-- The key figures of the left column, each with the list it opens.
local function tally()
    local me,openCount,inPlay,incoming,due=mine(),0,0,0,0
    for _,o in pairs(B.List()) do
        if isOpen(o) then
            openCount=openCount+1
            inPlay=inPlay+total(o)
        end
    end
    for _,o in pairs(B.History()) do
        local a=account(o,me)
        incoming=incoming+a.incoming
        due=due+a.due
    end
    return {{L("Primes ouvertes"),tostring(openCount),"active","all"},{L("Or en jeu"),inPlay>0 and money(inPlay) or "0","active","all"},
        {L("À recevoir"),incoming>0 and money(incoming) or "0","history","incoming"},{L("À envoyer"),due>0 and money(due) or "0","history","due"}}
end
local function paintTally()
    f.tallyLines=f.tallyLines or tally()
    local lines=f.tallyLines
    for i,cell in ipairs(f.tally) do
        local line=lines[i]
        cell.label:SetText(line[1])
        cell.value:SetText(line[2])
        cell.tab,cell.view=line[3],line[4]
        if (i==3 or i==4) and line[2]~="0" then cell.value:SetTextColor(.91,.77,.48) else cell.value:SetTextColor(unpack(t.paper)) end
    end
end
local function kindOf(o)
    return total(o)>0 and "gold" or "free"
end
refresh=function()
    if not f or not f:IsShown() then return end
    local creating=f.creating==true
    local choosing=creating and f.choosing
    local query=f.search:GetText():lower()
    local list,selected={},nil
    if choosing then
        list=filteredContacts(query)
    elseif not creating then
        local me,pinned=mine(),pins()
        for _,o in pairs(currentOrders()) do
            local a=f.tab=="history" and account(o,me)
            if (a or isOpen(o)) and (f.role=="all" or f.role=="hunted" and a and a.hunted or f.role=="issued" and o.owner==me)
                and passFilter(o,f.filterKey,me,pinned,a) and (f.kind=="all" or kindOf(o)==f.kind)
                and (f.group=="all" or o.group==f.group) and o.name:lower():find(query,1,true) then
                list[#list+1]=o
            end
        end
        table.sort(list,function(x,y)
            local xt,yt=(x.winner and x.winner.time) or x.at,(y.winner and y.winner.time) or y.at
            if xt~=yt then return xt>yt end
            return x.id>y.id
        end)
        for index,o in ipairs(list) do
            if o.id==f.selected then
                selected=o
                if f.reveal and (index<=f.offset or index>f.offset+pageSize) then f.offset=index-1 end
                break
            end
        end
        f.reveal=nil
        if f.viewing and f.selected and not selected then
            f.viewing=nil
            message(L("Le contrat que vous lisiez a changé : il n’est plus dans cette liste."))
        end
        selected=selected or list[1]
        if not selected or f.selected~=selected.id then f.editing=nil end
        f.selected=selected and selected.id
        if not selected then f.viewing=nil end
    end
    f.order=not creating and selected or nil
    f.offset=math.max(0,math.min(f.offset,#list-pageSize))
    f.count=#list
    local listing=choosing or not creating and not f.viewing
    visible(f.list,listing)
    visible(f.form,creating and not choosing)
    UI.selectButton(f.activeTab,not creating and f.tab=="active")
    UI.selectButton(f.historyTab,not creating and f.tab=="history")
    UI.selectButton(f.new,creating)
    f.heading:SetText(choosing and L("Choisir la cible") or f.tab=="history" and L("Historique") or L("Primes de la guilde"))
    f.lead:SetText(choosing and L("Les adversaires de votre carnet. Un clic choisit la cible.")
        or f.tab=="history" and L("Les primes terminées qui vous concernent, et leur règlement.")
        or L("Les cibles mises à prix par la guilde. Un clic ouvre le contrat."))
    visible(f.viewCycle,not choosing)
    visible(f.openFilters,not choosing)
    if not choosing then
        for _,entry in ipairs(filterLists[f.tab]) do
            if entry[1]==f.filterKey then f.viewCycle:SetText(L("%s · %d"):format(entry[2],#list)) end
        end
        UI.selectButton(f.viewCycle,f.filterKey~="all")
        local active=(f.role~="all" and 1 or 0)+(f.kind~="all" and 1 or 0)+(f.group~="all" and 1 or 0)
        f.openFilters:SetText(active>0 and (L("Filtres").." · "..active) or L("Filtres"))
        UI.selectButton(f.openFilters,active>0)
    end
    for i,row in ipairs(f.rows) do
        local e=listing and list[i+f.offset]
        row.entry=e or nil
        visible(row,e~=nil and e~=false)
        if e then
            local a=not choosing and f.tab=="history" and account(e,mine())
            local gold=a and a.remaining>0
            visible(row.stars,gold)
            visible(row.gold,gold)
            local id=choosing and e.guid or e.target
            local r=choosing and e or contact(id) or {guid=id,fullName=e.name}
            GL.PaintBookPortrait(row,r)
            row.title:SetText(UI.plain(e.fullName or e.name))
            local _,class,_,level=targetInfo(r)
            if choosing then
                row.meta:SetText((level and (L("Niv. ")..level.." · ") or "")..UI.plain(class))
                row.amount:SetText("")
            elseif a then
                row.meta:SetText(a.role.." · "..a.status)
                row.amount:SetText(total(e)>0 and money(total(e)) or L("Avis"))
            else
                local parts={L("%d/%d victoires"):format(B.Progress(e),e.quota or 1),groupNames[e.group] or groupNames.party,
                    L("échéance %s"):format(GL.Safe(date,"%d/%m",e.expires) or "—")}
                row.meta:SetText(table.concat(parts," · "))
                row.amount:SetText(total(e)>0 and money(total(e)) or L("Avis"))
            end
            visible(row.sheet,not choosing)
            visible(row.selected,choosing and f.target and f.target.guid==id)
        end
    end
    f.prev:SetEnabled(f.offset>0)
    f.next:SetEnabled(f.offset+pageSize<#list)
    visible(f.prev,listing and #list>pageSize)
    visible(f.next,listing and #list>pageSize)
    f.page:SetText(listing and #list>0 and ((f.offset+1).."–"..math.min(f.offset+pageSize,#list).." / "..#list) or "")
    f.empty:SetText(listing and #list==0 and (query~="" and L("Aucun résultat pour cette recherche.")
        or choosing and L("Aucun adversaire identifié. Ciblez un adversaire en jeu.")
        or f.tab=="active" and not GL.Safe(GetGuildInfo,"player") and L("Rejoignez une guilde pour utiliser les primes.")
        or L("Aucune prime dans cette sélection.")) or "")
    if f.filters:IsShown() then
        for _,group in ipairs(f.filterGroups) do
            local current=f[group.field]
            for _,choice in ipairs(group.choices) do UI.selectButton(choice,choice.value==current) end
            for _,entry in ipairs(group.entries) do
                if entry[1]==current then group.caption:SetText(group.title.." : "..entry[2]) end
            end
            for _,choice in ipairs(group.choices) do visible(choice,not group.history or f.tab=="history") end
            visible(group.caption,not group.history or f.tab=="history")
        end
    end
    paintTally()
    if not creating then renderDetail(selected) else f.detail:Hide() end
end

-- The book: the narrow format of Relations and Guilde. Left, the two lists, "Nouvelle prime" and
-- the key figures. Right, the page: the list, a bounty, or the creation.
local function build()
    f=UI.bookWindow("GrudgeLedgerBounties", "Grudge Ledger", true)
    f.tab,f.filterKey,f.role,f.kind,f.group,f.offset="active","all","all","all","all",0
    GL.SetupBookNavigation(f,"bounties")
    local function entry(title,y,fn)
        local b=UI.button(f,title,38,-y,168,fn,true)
        b:SetHeight(30)
        return b
    end
    f.activeTab=entry(L("À chasser"),158,function() chooseTab("active") end)
    f.historyTab=entry(L("Historique"),194,function() chooseTab("history") end)
    f.new=entry(L("Nouvelle prime"),244,function() startForm(nil) end)
    -- The key figures, drawn like those of the player sheet and of Relations.
    f.keyHeading=text(f,40,300,166,18,12,t.brass,L("Chiffres clés"))
    f.tally={}
    for i=1,4 do
        local cell=CreateFrame("Button",nil,f)
        cell:SetPoint("TOPLEFT",40,-320-(i-1)*22)
        cell:SetSize(166,20)
        cell.label=UI.label(cell,"",nil,0,-3,100)
        UI.journalFont(cell.label,"GameFontHighlight",11)
        cell.label:SetTextColor(unpack(t.brass))
        cell.value=UI.label(cell,"",nil,96,-1,70)
        UI.journalFont(cell.value,"GameFontNormalLarge",12)
        cell.value:SetJustifyH("RIGHT")
        local rule=cell:CreateTexture(nil,"BACKGROUND")
        rule:SetPoint("BOTTOMLEFT")
        rule:SetSize(166,1)
        rule:SetColorTexture(.55,.40,.20,.30)
        local hover=cell:CreateTexture(nil,"HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(.91,.77,.48,.10)
        cell:SetScript("OnClick",function(self)
            chooseTab(self.tab)
            f.filterKey=self.view
            refresh()
        end)
        f.tally[i]=cell
    end
    local host=CreateFrame("Frame",nil,f)
    host:SetPoint("TOPLEFT",240,-152)
    host:SetSize(664,510)
    f.host=host
    -- The list page, with the Journal's three controls: search, the list with its count, "Filtres".
    local list=CreateFrame("Frame",nil,host)
    f.list=list
    list:SetAllPoints(host)
    f.heading=text(list,26,18,600,30,21,t.ink)
    UI.journalFont(f.heading,"GameFontNormalLarge",21)
    f.lead=text(list,26,48,612,20,13,t.inkMuted)
    f.search=input(list,26,72,236,64,false)
    f.placeholder=text(f.search,9,5,220,19,12,t.muted,L("Rechercher…"))
    f.viewCycle=button(list,"",266,72,200,function()
        local views=filterLists[f.tab]
        for i,v in ipairs(views) do
            if v[1]==f.filterKey then
                f.filterKey=views[i%#views+1][1]
                break
            end
        end
        f.offset,f.selected,f.editing=0,nil,nil
        refresh()
    end)
    f.filter=f.viewCycle
    f.openFilters=button(list,L("Filtres"),470,72,168,function()
        if f.filters:IsShown() then
            f.filters:Hide()
        else
            f.filters:Show()
            f.filters:Raise()
            refresh()
        end
    end)
    f.rows={}
    for i=1,pageSize do
        local row=CreateFrame("Button",nil,list)
        row:SetPoint("TOPLEFT",26,-(108+(i-1)*56))
        row:SetSize(612,54)
        row.selected=row:CreateTexture(nil,"BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(.57,.39,.18,.22)
        row.gold=row:CreateTexture(nil,"BORDER")
        row.gold:SetAllPoints()
        row.gold:SetColorTexture(.91,.61,.08,.18)
        row.stars=goldStars(row,370,8,13)
        local line=row:CreateTexture(nil,"BORDER")
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(.49,.32,.13,.32)
        local hover=row:CreateTexture(nil,"HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(.57,.39,.18,.16)
        row:SetHighlightTexture(hover)
        row.raceIcon=row:CreateTexture(nil,"ARTWORK")
        row.raceIcon:SetPoint("TOPLEFT",2,-7)
        row.raceIcon:SetSize(40,40)
        row.classIcon=row:CreateTexture(nil,"OVERLAY")
        row.classIcon:SetPoint("TOPLEFT",28,-33)
        row.classIcon:SetSize(15,15)
        row.title=text(row,54,7,300,22,15,t.ink)
        GL.Safe(row.title.SetWordWrap,row.title,false)
        row.meta=text(row,54,29,320,18,12,t.inkMuted)
        GL.Safe(row.meta.SetWordWrap,row.meta,false)
        row.amount=text(row,380,14,126,24,17,t.red)
        row.amount:SetJustifyH("RIGHT")
        row.sheet=button(row,L("Fiche"),516,13,96,function()
            local e=row.entry
            if e then showDossier(e.target,e.name) end
        end,true)
        row:SetScript("OnClick",function(self)
            if not self.entry then return end
            if f.creating then
                setTarget(self.entry)
                f.choosing=nil
                syncOptions()
                message()
                refresh()
            else
                selectOrder(self.entry.id)
            end
        end)
        f.rows[i]=row
    end
    f.empty=text(list,26,124,612,60,14,t.inkMuted)
    local function shift(n)
        f.offset=math.max(0,f.offset+n)
        refresh()
    end
    f.prev=button(list,"‹",26,464,48,function() shift(-pageSize) end,true)
    f.next=button(list,"›",590,464,48,function() shift(pageSize) end,true)
    f.page=text(list,80,470,504,18,12,t.inkMuted)
    f.page:SetJustifyH("CENTER")
    -- The panel of filters, drawn like the Journal's: a caption per group, two columns, then Effacer
    -- and Fermer.
    f.filters=CreateFrame("Frame",nil,list)
    f.filters:SetPoint("TOPLEFT",355,-102)
    f.filters:SetSize(283,280)
    f.filters:EnableMouse(true)
    f.filters:SetFrameStrata("FULLSCREEN_DIALOG")
    GL.Safe(f.filters.SetFrameLevel,f.filters,(GL.Safe(list.GetFrameLevel,list) or 1)+20)
    UI.surface(f.filters,t.gold)
    UI.surface(f.filters,t.panel,1)
    f.filterGroups={}
    local function group(field,title,entries,y,history)
        local g={field=field,title=title,entries=entries,history=history,choices={}}
        g.caption=UI.label(f.filters,"",nil,8,-y,267)
        g.caption:SetTextColor(unpack(t.brass))
        for i,entry in ipairs(entries) do
            local value=entry[1]
            local c=UI.button(f.filters,entry[2],8+((i-1)%2)*135,-(y+18)-math.floor((i-1)/2)*28,133,function()
                f[field]=value
                f.offset,f.selected,f.editing=0,nil,nil
                refresh()
            end,true)
            c.value=value
            g.choices[i]=c
        end
        f.filterGroups[#f.filterGroups+1]=g
        return g
    end
    f.filterKinds=group("kind",L("Type"),{{"all",L("Tout")},{"gold",L("Prime en or")},{"free",L("Avis de recherche")}},8)
    f.filterHunts=group("group",L("Chasse"),{{"all",L("Toutes")},{"solo",L("Hors groupe")},{"party",L("Groupe autorisé")}},90)
    f.roles={}
    local roles=group("role",L("Mon rôle"),{{"all",L("Tous les rôles")},{"hunted",L("Chasseur")},{"issued",L("Commanditaire")}},172,true)
    f.roles.all,f.roles.hunted,f.roles.issued=roles.choices[1],roles.choices[2],roles.choices[3]
    f.filters.clear=UI.button(f.filters,L("Effacer"),143,-246,65,function()
        f.role,f.kind,f.group,f.filterKey,f.offset,f.selected=  "all","all","all","all",0,nil
        f.search:SetText("")
        refresh()
    end)
    f.filters.close=UI.button(f.filters,L("Fermer"),211,-246,65,function() f.filters:Hide() end)
    f.filters:Hide()
    makeForm(host)
    makeDetail(host)
    f.feedback=text(f,252,649,640,21,12,t.ink)
    f.search:SetScript("OnTextChanged",function(self)
        visible(f.placeholder,self:GetText()=="")
        f.offset=0
        f.viewing=nil
        -- Typing closes the panel of filters; "Effacer" empties the search and keeps it open.
        if self:GetText()~="" then f.filters:Hide() end
        refresh()
    end)
    f:HookScript("OnHide",function()
        f.filters:Hide()
        f.search:ClearFocus()
    end)
    f:RegisterEvent("PLAYER_GUILD_UPDATE")
    f:SetScript("OnEvent",function()
        f.cachedOrders=nil
        f.dirty=true
    end)
    local elapsed=0
    f:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+(dt or 0)
        if not f.dirty and elapsed<1 then return end
        elapsed=0
        if f.dirty or (f.nextExpiry and GL.Now()>f.nextExpiry) then
            f.dirty,f.cachedOrders,f.nextExpiry=nil,nil,nil
            refresh()
        end
    end)
end

function GL.OpenBounties(guid,mode)
    if not f then build() end
    GL.ShowBookPage(f)
    f.cachedOrders=nil
    chooseTab("active")
    if mode=="due" or mode=="incoming" then
        chooseTab("history")
        f.filterKey=mode
        refresh()
        return f
    end
    if mode=="create" then
        local r=contact(guid)
        if guid and not r then
            local live=GL.Identity("target")
            if live and live.guid==guid then r=live end
        end
        startForm(r,r and r.guid)
    elseif guid then
        for _,o in pairs(currentOrders()) do
            if o.target==guid and isOpen(o) then
                selectOrder(o.id)
                return f
            end
        end
        chooseTab("history")
        local recent
        for _,o in pairs(currentOrders()) do
            if o.target==guid and (not recent or o.at>recent.at or o.at==recent.at and o.id>recent.id) then recent=o end
        end
        if recent then
            selectOrder(recent.id)
            return f
        end
        chooseTab("active")
        message(L("Aucune prime pour ce joueur."))
    end
    return f
end

-- Payments (0.58.2): whoever owes gold for a bounty and whoever is owed it are told when it
-- happens, with a banner and the sound of coins, and reminded at login in the chat. A paid share
-- is told too. Worked out again a few seconds after the guild's bounties change.
local owedSeen, owingSeen
-- The gold not yet sent to you at your last check, kept per character in GL.db.bountyPaymentWatch:
-- a payer who sends it while you are offline is told at the next login (0.58.4). The mail itself is
-- only counted as received at your mailbox. Read once, before the first check of the session
-- writes over it.
local offlineBase
local function watched(me)
    if type(GL.db.bountyPaymentWatch)~="table" then GL.db.bountyPaymentWatch={} end
    local w=GL.db.bountyPaymentWatch
    if type(w[me])~="table" then w[me]={} end
    return w[me]
end
-- The form for one or for several; the caller fills it (review 0.58.5: "many" holds two values).
local function plural(n,one,many) return n==1 and one or many end
-- Between your login and its reminder, the guild's catch-up arrives in batches: it is not news.
-- After a /reload the reminder is told in the chat only, without banner or coins.
local loginPending,waitingLogin,reloaded=false,false,false
local function ledger()
    local me=mine()
    local dues,incomes={},{}
    -- No guild space for a moment (roster not arrived): nothing is known, not "nothing is due".
    if not me or not B.GuildScope() or not B.IsMember(me) then return nil end
    -- (B.History returns the orders and their next expiry: only the first counts here.)
    local active=B.List()
    local closed=B.History()
    -- A won bounty can be in both lists: each one counts once.
    local counted={}
    for _,list in ipairs({active,closed}) do
        for id,o in pairs(list) do
            if (o.winner or o.priorWinner) and not o.supersededBy and not counted[id] then
                counted[id]=true
                for _,h in ipairs(members(o)) do
                    -- A hunter gone from the guild cannot be paid by mail: no reminder for it.
                    local due=h~=me and B.IsMember(h) and B.Due(o,me,h) or 0
                    if due>0 then
                        local entry=dues[id] or {o=o,amount=0,hunters={}}
                        dues[id]=entry
                        entry.amount=entry.amount+due
                        entry.hunters[#entry.hunters+1]=h
                    end
                    if h==me then
                        for payer in pairs(o.pot) do
                            local unsent,waiting=B.Payment(o,payer,me)
                            if payer~=me and waiting>0 then
                                local entry=incomes[id] or {o=o,amount=0,unsent=0,payers=0}
                                incomes[id]=entry
                                entry.amount=entry.amount+waiting
                                entry.unsent=entry.unsent+unsent
                                entry.payers=entry.payers+1
                            end
                        end
                    end
                end
            end
        end
    end
    return dues,incomes,counted
end
local function coins()
    local sounds=SOUNDKIT or {}
    local sound=sounds.LOOT_WINDOW_COIN_SOUND or sounds.IG_BACKPACK_COIN_SELECT
    if sound and GL.Settings and GL.Settings().sounds then GL.Safe(PlaySound,sound,"Master") end
end
local function total(entries)
    local sum,count=0,0
    for _,entry in pairs(entries) do
        sum=sum+entry.amount
        count=count+1
    end
    return sum,count
end
function GL.BountyPaymentsCheck(first)
    if not GL.db then return end
    if first then loginPending=true end
    local dues,incomes,known=ledger()
    -- No guild yet: the login reminder waits for the next check that can read it.
    if not dues then return end
    first=loginPending
    local me=mine()
    if offlineBase==nil then
        offlineBase={}
        for id,amount in pairs(watched(me)) do
            if type(id)=="string" and type(amount)=="number" then offlineBase[id]=amount end
        end
    end
    local owe,count=total(dues)
    GL.bountyDue={amount=owe,count=count,text=money(owe)}
    if GL.PaintBountyReminder then GL.PaintBountyReminder() end
    if first or not owedSeen or waitingLogin then
        -- At login: one line in the chat for each side, nothing when nothing is due.
        if first then
            loginPending,waitingLogin=false,false
            local loud=not reloaded
            local owing=total(incomes)
            -- Sent while you were away: the gold not yet sent dropped on a contract still known.
            local received,paidCount=0,0
            if offlineBase then
                for id,amount in pairs(offlineBase) do
                    local now=incomes[id] and incomes[id].unsent or 0
                    if known[id] and now<amount then
                        received=received+amount-now
                        paidCount=paidCount+1
                    end
                end
                offlineBase=false
            end
            if received>0 then
                local note=plural(paidCount,
                    L("Pendant votre absence, %s vous ont été envoyés pour une prime. Le courrier vous attend à la boîte aux lettres."),
                    L("Pendant votre absence, %s vous ont été envoyés pour %d primes. Les courriers vous attendent à la boîte aux lettres."))
                    :format(money(received),paidCount)
                GL.Print(note)
                if loud and GL.ShowStoryBanner then
                    GL.ShowStoryBanner("bounty:received","friend",L("Paiement envoyé"),L("Primes"),note,
                        L("Clic : la prime  •  clic droit : fermer"),function() GL.OpenBounties(nil,"incoming") end,"wanted")
                end
                if loud then coins() end
            end
            if owe>0 then
                local line=L("Primes à régler : vous devez %s. À une boîte aux lettres, le bouton « Régler la prime » prépare chaque courrier.")
                GL.Print(line:format(money(owe)))
                local note=plural(count,L("Vous devez %s pour une prime. Une boîte aux lettres prépare le courrier."),
                    L("Vous devez %s pour %d primes. Une boîte aux lettres prépare les courriers.")):format(money(owe),count)
                local function show()
                    if not GL.ShowStoryBanner then return end
                    GL.ShowStoryBanner("bounty:due","warning",L("Prime à régler"),L("Primes"),note,
                        L("Clic : la prime  •  clic droit : fermer"),function() GL.OpenBounties(nil,"due") end,"wanted")
                end
                -- One banner at a time: the gold sent to you first, what you owe a few seconds later.
                if loud and received>0 and C_Timer and C_Timer.After then C_Timer.After(8,show) elseif loud then show() end
                if loud and received==0 then coins() end
            end
            if owing>0 then GL.Print(L("Primes à recevoir : %s vous sont dus."):format(money(owing))) end
        end
    else
        for id,entry in pairs(dues) do
            local before=owedSeen[id]
            if not before or entry.amount>before.amount then
                local hunter=UI.plain(who(entry.hunters[1]))
                local note=L("%s a remporté la prime. Vous lui devez %s : une boîte aux lettres prépare le courrier."):format(hunter,money(entry.amount))
                if #entry.hunters>1 then note=L("%d chasseurs ont remporté la prime. Vous leur devez %s : une boîte aux lettres prépare les courriers.")
                    :format(#entry.hunters,money(entry.amount)) end
                if GL.ShowStoryBanner then
                    GL.ShowStoryBanner(entry.o.target and ("guid:"..entry.o.target) or id,"warning",L("Prime à régler"),UI.plain(entry.o.name),note,
                        L("Clic : la prime  •  clic droit : fermer"),function() GL.OpenBounties(entry.o.target,"view") end,"wanted")
                end
                coins()
            end
        end
        for id,entry in pairs(incomes) do
            if not owingSeen[id] then
                if GL.ShowStoryBanner then
                    GL.ShowStoryBanner(entry.o.target and ("guid:"..entry.o.target) or id,"friend",L("Prime remportée"),UI.plain(entry.o.name),
                        L("La guilde vous doit %s. Le courrier arrivera dans votre boîte aux lettres."):format(money(entry.amount)),
                        L("Clic : la prime  •  clic droit : fermer"),function() GL.OpenBounties(entry.o.target,"view") end,"wanted")
                end
                coins()
            end
        end
        for id,entry in pairs(owingSeen) do
            -- Only a contract still known and still the same: a replaced one was not paid.
            local now=incomes[id]
            if known[id] and (not now or now.amount<entry.amount) then
                GL.Print(L("Paiement reçu pour la prime sur %s."):format(UI.plain(entry.o.name)))
                -- Told now: the login check does not tell it again.
                if offlineBase then offlineBase[id]=nil end
            elseif known[id] and now and offlineBase==false and now.unsent<(entry.unsent or 0) then
                -- Sent to you now (after the login check, which tells what was sent while you were away).
                local note=L("De l’or vous a été envoyé pour la prime sur %s. Le courrier vous attend à la boîte aux lettres.")
                    :format(UI.plain(entry.o.name))
                GL.Print(note)
                if GL.ShowStoryBanner then
                    GL.ShowStoryBanner(entry.o.target and ("guid:"..entry.o.target) or id,"friend",L("Paiement envoyé"),UI.plain(entry.o.name),note,
                        L("Clic : la prime  •  clic droit : fermer"),function() GL.OpenBounties(entry.o.target,"view") end,"wanted")
                end
                coins()
            end
        end
    end
    owedSeen,owingSeen=dues,incomes
    -- The snapshot the next login compares with.
    local w=watched(me)
    for id in pairs(w) do w[id]=nil end
    for id,entry in pairs(incomes) do if entry.unsent>0 then w[id]=entry.unsent end end
    return dues,incomes
end
local checking=false
GL.On("BOUNTIES_CHANGED",function()
    if checking then return end
    if C_Timer and C_Timer.After then
        checking=true
        C_Timer.After(2,function()
            checking=false
            GL.BountyPaymentsCheck(false)
        end)
    else
        GL.BountyPaymentsCheck(false)
    end
end)
local reminder=CreateFrame("Frame")
reminder:RegisterEvent("PLAYER_LOGIN")
reminder:RegisterEvent("PLAYER_ENTERING_WORLD")
reminder:SetScript("OnEvent",function(_,event,_,reloading)
    if event=="PLAYER_ENTERING_WORLD" then
        if reloading==true then reloaded=true end
        return
    end
    -- A new session: the next check reads what was saved at the end of the last one.
    offlineBase=nil
    -- After the guild's catch-up, so that the reminder counts what arrived while you were away.
    if C_Timer and C_Timer.After then
        waitingLogin=true
        C_Timer.After(20,function()
            GL.BountyPaymentsCheck(true)
            -- Guild not readable yet: once more, later.
            if loginPending then C_Timer.After(40,function() if loginPending then GL.BountyPaymentsCheck(true) end end) end
        end)
    end
end)

-- A burst of sync events repaints the visible panel only once on the next frame.
GL.On("BOUNTIES_CHANGED",function() if f then f.dirty=true end end)
GL.On("DOSSIER_UPDATED",function() if f then f.dirty=true end end)
