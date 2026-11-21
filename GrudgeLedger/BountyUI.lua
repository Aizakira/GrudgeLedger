-- Guild contracts share the book's navigation, portraits and character dossier.
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
local filterLists = {
    active={{"all",L("Toutes les primes")},{"pinned",L("Épinglées")},
        {"issued",L("Mes contrats publiés")},{"solo",L("Hors groupe")},{"party",L("Groupe autorisé")}},
    history={{"all",L("Tous les états")},{"incoming",L("Or à recevoir")},
        {"transit",L("Courrier en transit")},{"due",L("Or à envoyer")},{"paid",L("Payées")}}
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
    for _,h in ipairs(members(o)) do
        if h==me then a.hunted=true end
        for payer in pairs(o.pot) do
            local send,waiting,received=B.Payment(o,payer,h)
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
    f.form:Hide(); f.filters:Hide(); resetList(); message(); refresh()
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
    f.form.target:SetText(record and UI.plain(record.fullName or record.name) or L("Sélectionnez un joueur à gauche"))
    if record and record.faction~="Alliance" and record.faction~="Horde" then
        f.form.target:SetText(UI.plain(record.fullName or record.name).." · "..L("Faction inconnue"))
    end
    f.form.publish:SetEnabled(record ~= nil)
end
local function syncOptions()
    for _, pair in ipairs(f.form.options) do UI.selectButton(pair.control, f.draft[pair.key]==pair.value) end
    f.form.equal:SetEnabled(f.draft.group=="party")
    f.form.rules:SetText(huntRules(f.draft.group,f.draft.split).." "..L("Souvenir facultatif."))
end
startForm = function(record, origin)
    f.editing, f.origin, f.tab, f.repostFrom = nil, origin, "active", nil
    f.draftGuild=GL.Safe(GetGuildInfo,"player")
    f.filters:Hide(); f.form:Show(); f.detail:Hide()
    f.draft={group="solo",split="winner",souvenir="none"}
    f.form.gold:SetText(""); f.form.quota:SetText("1"); f.form.note:SetText("")
    setTarget(record); syncOptions(); resetList(); message(); refresh()
    if record and not f.target then actionResult(nil,"ally") end
end
local function cancelForm()
    local origin,previous=f.origin,f.repostFrom
    f.repostFrom=nil
    if previous then chooseTab("history"); selectOrder(previous); return end
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
    local amount, q = copper(f.form.gold:GetText()), f.form.quota:GetText():match("^%d+$")
    q = tonumber(q)
    if not amount then return message(L("La récompense doit être comprise entre 0 et 1 000 PO.")) end
    if not q or q < 1 or q > 99 then return message(L("Choisissez entre 1 et 99 victoires.")) end
    local note = f.form.note:GetText()
    local problem=noteError(note)
    if problem then return message(problem) end
    local options = {quota=q,group=f.draft.group,split=f.draft.split,souvenir=f.draft.souvenir,note=note}
    local id,err,why = B.Post(f.target.guid,f.target.fullName or f.target.name,amount,options)
    if actionResult(id,err,why) then chooseTab("active"); selectOrder(id); message(L("Prime publiée à la guilde.")) end
end
local function makeForm()
    local form=CreateFrame("Frame",nil,f); f.form=form; form:SetAllPoints(f); form.options={}
    text(form,358,163,525,26,20,nil,L("Créer une prime de guilde"))
    text(form,358,202,72,23,13,t.inkMuted,L("Cible"))
    form.target=text(form,430,197,457,44,18,t.ink)
    text(form,358,251,250,24,14,nil,L("Récompense totale (PO)"))
    text(form,642,251,250,24,14,nil,L("Victoires requises"))
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
    text(form,358,332,135,25,14,nil,L("Chasse"))
    choice("group","solo",L("Hors groupe"),489,324,180)
    choice("group","party",L("Groupe autorisé"),682,324,196)
    text(form,358,372,135,24,14,nil,L("Répartition"))
    choice("split","winner",L("Au vainqueur"),489,364,180)
    form.equal=choice("split","equal",L("Parts égales"),682,364,196)
    tip(form.equal,L("Entre le vainqueur et les membres de guilde de son groupe présents à proximité de la dernière victoire."))
    text(form,358,414,135,24,14,nil,L("Souvenir"))
    choice("souvenir","none",souvenirs.none,489,406,108)
    choice("souvenir","screenshot",L("Capture"),606,406,140)
    choice("souvenir","video",L("Vidéo"),755,406,123)
    text(form,358,455,291,22,14,nil,L("Consigne libre · facultative"))
    form.note=input(form,358,482,520,100,true)
    form.budget=text(form,655,455,223,22,12,t.inkMuted); form.budget:SetJustifyH("RIGHT")
    form.note:SetScript("OnTextChanged",function(self) showNoteBudget(self,form.budget) end)
    form.rules=text(form,358,514,535,79,13,t.inkMuted)
    form.cancel=button(form,L("Annuler"),358,597,148,cancelForm,true)
    form.publish=button(form,L("Créer la prime"),606,597,272,publish,true)
    UI.selectButton(form.publish,true); form:Hide()
end

local function makeDetail()
    local p=CreateFrame("Frame",nil,f); f.detail=p; p:SetAllPoints(f)
    p.kicker=text(p,358,161,493,31,21,t.red)
    p.stars=goldStars(p,855,169,16)
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
    tip(face,L("Ouvrir la fiche du joueur"))
    p.name=text(p,475,201,420,32,22,t.ink)
    p.nameLink=CreateFrame("Button",nil,p); p.nameLink:SetAllPoints(p.name)
    p.nameLink:SetScript("OnClick",face:GetScript("OnClick"))
    tip(p.nameLink,L("Ouvrir la fiche du joueur"))
    p.identity=text(p,476,236,418,24,13,t.inkMuted)
    local coin=p:CreateTexture(nil,"ARTWORK"); coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    coin:SetPoint("TOPLEFT",476,-271); coin:SetSize(20,20)
    p.price=text(p,503,261,256,38,26,t.red)
    p.rewardLabel=text(p,769,271,128,29,12,t.inkMuted,L("Récompense totale"))
    p.rewardLabel:SetJustifyH("RIGHT")
    for _,y in ipairs({305,397,481}) do
        local rule=p:CreateTexture(nil,"ARTWORK"); rule:SetPoint("TOPLEFT",358,-y)
        rule:SetSize(540,1); rule:SetColorTexture(unpack(t.gold)); rule:SetAlpha(.6)
    end
    p.progress=text(p,358,312,544,29,18,t.red)
    p.track=CreateFrame("Frame",nil,p); p.track:SetSize(129,6); p.track:SetPoint("TOPRIGHT",p,"TOPLEFT",895,-324)
    UI.surface(p.track,t.gold); UI.surface(p.track,t.panel,1,1)
    p.fill=p.track:CreateTexture(nil,"ARTWORK"); p.fill:SetPoint("LEFT",p.track,"LEFT",1,0)
    p.fill:SetHeight(4); p.fill:SetColorTexture(.77,.52,.16,1)
    p.rules=text(p,358,342,548,54,12,t.inkMuted)
    p.owner=text(p,358,398,540,26,16,t.red)
    p.ownerLink=CreateFrame("Button",nil,p); p.ownerLink:SetAllPoints(p.owner)
    p.ownerLink:SetScript("OnClick",function() if f.order then showDossier(f.order.owner,who(f.order.owner)) end end)
    tip(p.ownerLink,L("Ouvrir la fiche du joueur"))
    p.deadline=text(p,670,426,228,20,12,t.inkMuted)
    text(p,358,426,300,17,12,t.inkMuted,L("Consigne du contrat"))
    p.note=text(p,358,446,538,34,14)
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
    bar.pledge=button(bar,L("Contribuer"),512,522,160,function() showEditor("pledge") end,true)
    p.dossier=button(p,L("Fiche complète"),720,645,178,face:GetScript("OnClick"),true)
    bar.manage=text(bar,358,563,520,19,12,t.inkMuted,L("Gestion du contrat"))
    bar.note=button(bar,L("Modifier la consigne"),358,586,193,function() showEditor("note") end,true)
    bar.renew=button(bar,L("Prolonger"),557,586,138,function()
        if f.order and actionResult(B.Update(f.order.id,nil,true)) then refresh(); message(L("Contrat renouvelé.")) end
    end,true)
    bar.withdraw=button(bar,L("Retirer la prime"),701,586,194,function() showEditor("withdraw") end,true)
    p.retained=button(p,L("Voir la prime retenue"),358,610,282,function()
        local previous=f.order
        local current=B.OpenFor(previous.target)
        if current and current.id==previous.supersededBy and current.state=="open" then
            chooseTab("active"); selectOrder(current.id)
        else
            message(L("La prime retenue est déjà terminée."))
        end
    end,true)
    p.repost=button(p,L("Republier la prime"),358,565,234,function()
        local o=f.order
        if not B.CanRepost(o) then return end
        startForm(contact(o.target) or {guid=o.target,fullName=o.name})
        f.repostFrom=o.id
        f.draft.group,f.draft.split,f.draft.souvenir=o.group or "party",o.split or "equal",o.souvenir or "none"
        f.form.gold:SetText(tostring((o.pot[o.owner] or 0)/10000))
        f.form.quota:SetText(tostring(o.quota or 1)); f.form.note:SetText(o.note or ""); syncOptions()
        message(L("Nouveau contrat : seule votre mise est reprise. Vérifiez puis publiez."))
    end,true)
    local edit=CreateFrame("Frame",nil,p); f.editor=edit; edit:SetAllPoints(p)
    edit.budget=text(edit,665,497,227,22,12,t.inkMuted); edit.budget:SetJustifyH("RIGHT")
    edit.title=text(edit,358,495,303,23,14); edit.field=input(edit,358,520,532,100,true)
    edit.field:SetScript("OnTextChanged",function(self) showNoteBudget(self,edit.budget) end)
    edit.ok=button(edit,"",358,565,235,commitEdit,true)
    edit.cancel=button(edit,L("Annuler"),606,565,160,function() f.editing=nil; refresh() end,true)
    edit:Hide()
end
local function renderDetail(o)
    local p=f.detail
    visible(p,o~=nil)
    if not o then return end
    local record=contact(o.target) or {guid=o.target,fullName=o.name}
    GL.PaintBookPortrait(p.face,record)
    local race,class,faction,lvl=targetInfo(record)
    p.name:SetText(UI.plain(o.name))
    visible(p.level,lvl~=nil); if lvl then p.level.caption:SetText(tostring(lvl)) end
    p.identity:SetText(UI.plain(table.concat({race,class,faction}," · ")))
    p.price:SetText(money(total(o)))
    local final=o.winner or o.priorWinner
    local winner=final and final.actor
    local me=mine()
    local a=account(o,me)
    visible(p.stars,a.remaining>0)
    if a.remaining>0 then p.kicker:SetTextColor(.43,.23,.025) else p.kicker:SetTextColor(unpack(t.red)) end
    for i,c in ipairs(p.people) do c.guid=nil; c:Hide() end
    if winner then
        p.kicker:SetText(o.supersededBy and states.superseded or L("Prime faite · ")..a.status)
        local hunters=members(o)
        for i,h in ipairs(hunters) do
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
                tip(c,breakdown); c:Show()
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
        p.kicker:SetText(o.state=="open" and L("MISE À PRIX") or states[o.state])
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
        if part>0 then p.fill:SetWidth(127*part) end
    end
    local rules=huntRules(o.group,o.split)
    if o.souvenir and o.souvenir~="none" then
        rules=rules.." "..L("Souvenir facultatif : %s."):format(souvenirs[o.souvenir] or souvenirs.none)
    end
    p.rules:SetText(rules)
    p.owner:SetText(L("Créée par %s"):format(UI.plain(who(o.owner))))
    p.deadline:SetText(winner and L("Terminée : ")..compactDate(final.time)
        or L("Échéance : ")..compactDate(o.expires))
    p.note:SetText(o.note and o.note~="" and UI.plain(o.note) or L("Aucune consigne particulière."))
    visible(p.retained,o.state=="superseded"); visible(p.repost,o.state~="superseded" and B.CanRepost(o)); if o.state~="open" then f.editing=nil end
    visible(f.tools,isOpen(o) and not f.editing); visible(f.editor,f.editing~=nil)
    f.tools.pin:SetText(pins()[o.id] and L("Désépingler") or L("Épingler"))
    f.tools.pledge:SetEnabled(o.state=="open")
    local owner=o.state=="open" and o.owner==mine()
    visible(f.tools.manage,owner); visible(f.tools.note,owner); visible(f.tools.renew,owner); visible(f.tools.withdraw,owner)
end
selectOrder=function(id)
    f.selected, f.editing, f.reveal = id,nil,true
    f.filters:Hide(); message(); refresh()
end
local function filteredContacts(query)
    local list, seen={},{}
    local current=GL.Identity("target")
    if GL.BountyTargetEligible(current) and (current.fullName or ""):lower():find(query:lower(),1,true) then
        list[#list+1]=current; seen[current.guid]=true
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
        if f.tab=="history" then f.cachedOrders,f.nextExpiry=B.History()
        else
            f.cachedOrders,f.nextExpiry=B.List(),nil
            for _,o in pairs(f.cachedOrders) do
                if o.state=="open" and (not f.nextExpiry or o.expires<f.nextExpiry) then f.nextExpiry=o.expires end
            end
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
            local a=f.tab=="history" and account(o,me)
            if (a or isOpen(o)) and (not a or f.role=="all" or f.role=="hunted" and a.hunted or f.role=="issued" and o.owner==me)
                and passFilter(o,f.filterKey,me,pinned,a)
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
    f.heading:SetText(creating and L("Choisir la cible") or f.tab=="history" and L("Mon historique") or L("Primes en cours"))
    visible(f.heading,creating or f.tab~="history")
    for key,b in pairs(f.roles) do
        visible(b,not creating and f.tab=="history"); UI.selectButton(b,key==f.role)
    end
    UI.selectButton(f.activeTab,not creating and f.tab=="active"); UI.selectButton(f.historyTab,not creating and f.tab=="history")
    visible(f.filter,not creating); visible(f.new,not creating)
    if not creating then
        for _,entry in ipairs(filterLists[f.tab]) do if entry[1]==f.filterKey then f.filter:SetText(L("Filtre : ")..entry[2]) end end
    end
    for i,row in ipairs(f.rows) do
        local e=list[i+f.offset]; row.entry=e; visible(row,e~=nil)
        if e then
            local a=not creating and f.tab=="history" and account(e,mine())
            local gold=a and a.remaining>0
            visible(row.stars,gold); visible(row.gold,gold)
            local id=creating and e.guid or e.target
            local r=creating and e or contact(id) or {guid=id,fullName=e.name}
            GL.PaintBookPortrait(row,r)
            row.title:SetText(UI.plain(e.fullName or e.name))
            local _,class,_,level=targetInfo(r)
            row.meta:SetText(creating and ((level and (L("Niv. ")..level.." · ") or "")..UI.plain(class))
                or a and (a.role.." · "..a.status) or (money(total(e)).." · "..(states[e.state] or "")))
            visible(row.selected,creating and f.target and f.target.guid==id or not creating and f.selected==e.id)
        end
    end
    f.prev:SetEnabled(f.offset>0); f.next:SetEnabled(f.offset+pageSize<#list)
    f.page:SetText(#list==0 and "0" or (f.offset+1).."–"..math.min(f.offset+pageSize,#list).." / "..#list)
    f.empty:SetText(#list==0 and (query~="" and L("Aucun résultat pour cette recherche.")
        or creating and L("Aucun adversaire identifié. Ciblez un adversaire en jeu.")
        or f.tab=="active" and not GL.Safe(GetGuildInfo,"player") and L("Rejoignez une guilde pour utiliser les primes.")
        or L("Aucune prime dans cette sélection.")) or "")
    if not creating then renderDetail(selected) end
end

local function build()
    f=UI.bookWindow("GrudgeLedgerBounties", "Grudge Ledger")
    f.tab,f.filterKey,f.offset="active","all",0
    GL.SetupBookNavigation(f,"bounties")
    f.activeTab=button(f,L("À chasser"),35,162,122,function() chooseTab("active") end)
    f.historyTab=button(f,L("Mon historique"),160,162,145,function() chooseTab("history") end)
    f.heading=text(f,36,203,268,26,18,t.paper)
    f.roles={}
    local function role(key,title,x,width)
        f.roles[key]=button(f,title,x,202,width,function()
            f.role=key; f.offset=0; f.selected=nil; f.filters:Hide(); refresh()
        end)
    end
    role("all",L("Tout"),35,54)
    role("hunted",L("Remportées"),92,102)
    role("issued",L("Publiées"),197,110)
    f.search=input(f,36,236,269,64,false)
    f.placeholder=text(f.search,9,5,250,19,12,t.muted,L("Rechercher un joueur…"))
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
        row.selected=row:CreateTexture(nil,"BACKGROUND"); row.selected:SetAllPoints()
        row.selected:SetTexture(media.."JournalButtons"); row.selected:SetTexCoord(36/1254,1218/1254,514/1254,768/1254)
        row.gold=row:CreateTexture(nil,"BORDER"); row.gold:SetAllPoints(); row.gold:SetColorTexture(.91,.61,.08,.24)
        row.stars=goldStars(row,242,5,13)
        local line=row:CreateTexture(nil,"BORDER"); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1); line:SetColorTexture(unpack(t.gold))
        local hover=row:CreateTexture(nil,"HIGHLIGHT"); hover:SetAllPoints(); hover:SetColorTexture(.57,.39,.18,.20)
        row:SetHighlightTexture(hover)
        row.raceIcon=row:CreateTexture(nil,"ARTWORK"); row.raceIcon:SetPoint("TOPLEFT",3,-1); row.raceIcon:SetSize(36,36)
        row.classIcon=row:CreateTexture(nil,"OVERLAY"); row.classIcon:SetPoint("TOPLEFT",28,-25); row.classIcon:SetSize(13,13)
        row.title=text(row,47,1,192,20,15,t.paper); GL.Safe(row.title.SetWordWrap,row.title,false)
        row.meta=text(row,47,21,215,16,11,t.brass); GL.Safe(row.meta.SetWordWrap,row.meta,false)
        row:SetScript("OnClick",function(self)
            if not self.entry then return end
            if f.form:IsShown() then setTarget(self.entry); message(); refresh() else selectOrder(self.entry.id) end
        end)
        f.rows[i]=row
    end
    f.empty=text(f,36,313,267,82,15,t.brass)
    local function shift(n) f.offset=math.max(0,f.offset+n); refresh() end
    f.prev=button(f,"<",36,562,66,function() shift(-pageSize) end)
    f.next=button(f,">",239,562,66,function() shift(pageSize) end)
    f.page=text(f,101,568,137,18,12,t.paper); f.page:SetJustifyH("CENTER")
    f.new=button(f,L("Créer une prime"),36,609,269,function() startForm(nil) end)
    local listArea=CreateFrame("Frame",nil,f)
    listArea:SetPoint("TOPLEFT",33,-305); listArea:SetSize(275,pageSize*40+8)
    if listArea.EnableMouseWheel then
        listArea:EnableMouseWheel(true)
        listArea:SetScript("OnMouseWheel",function(_,delta) shift(delta>0 and -1 or 1) end)
        for _,r in ipairs(f.rows) do
            r:EnableMouseWheel(true); r:SetScript("OnMouseWheel",listArea:GetScript("OnMouseWheel"))
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
        local recent
        for _,o in pairs(currentOrders()) do
            if o.target==guid and (not recent or o.at>recent.at or o.at==recent.at and o.id>recent.id) then recent=o end
        end
        if recent then selectOrder(recent.id); return f end
        chooseTab("active"); message(L("Aucune prime pour ce joueur."))
    end
    return f
end

-- A burst of sync events repaints the visible panel only once on the next frame.
GL.On("BOUNTIES_CHANGED",function() if f then f.dirty=true end end)
GL.On("DOSSIER_UPDATED",function() if f then f.dirty=true end end)
