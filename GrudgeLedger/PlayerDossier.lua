-- Character dossiers are read-only views over the personal journal and private Armory archive.
local GL, UI = GrudgeLedger, GrudgeLedger.UITheme
local L = GL.L
local locale = GetLocale and GetLocale() or "frFR"
local decimalComma = locale == "frFR" or locale == "esES"
local unknown = L("Non renseigné")
local function object(value) return type(value) == "table" and value or {} end
local function text(value)
    if type(value) == "string" and value ~= "" then return UI.plain(value) end
    if type(value) == "number" then return tostring(value) end
end
local function valueOf(value)
    if type(value) == "table" then return text(value.display_string) or text(value.name) or text(value.value) end
    return text(value)
end
local function timestamp(value)
    value = tonumber(value)
    if not value or value <= 0 then return unknown end
    if value >= 100000000000 then value = value / 1000 end -- Armory uses milliseconds; game clocks use seconds.
    return GL.Safe(date, "%d/%m/%Y %H:%M", math.floor(value)) or unknown
end
local function field(label, value) return L("%s : %s"):format(label, value or unknown) end
local slots = {
    {"head","Tête"}, {"neck","Cou"}, {"shoulder","Épaules"},
    {"back","Dos"}, {"chest","Torse"}, {"shirt","Chemise"},
    {"tabard","Tabard"}, {"wrist","Poignets"}, {"hand","Mains"},
    {"waist","Taille"}, {"leg","Jambes"}, {"foot","Pieds"},
    {"leftfinger","Anneau 1"}, {"rightfinger","Anneau 2"},
    {"lefttrinket","Bijou 1"}, {"righttrinket","Bijou 2"},
    {"weapon","Main droite"}, {"offhand","Main gauche"}, {"ranged","À distance"},
}
local slotIndex = {}
for i, s in ipairs(slots) do slotIndex[s[1]] = i end
local aliases = { finger1="leftfinger",finger2="rightfinger",trinket1="lefttrinket",trinket2="righttrinket",
    mainhand="weapon",legs="leg",feet="foot",hands="hand",shoulders="shoulder",wrists="wrist",shield="offhand" }
local function slotOrder(k)
    local key = k:lower():gsub("[^%a%d]", "")
    return slotIndex[aliases[key] or key] or (#slots + 1)
end
local function sortedKeys(t)
    local keys = {}
    for k in pairs(object(t)) do if type(k) == "string" then keys[#keys+1] = k end end
    table.sort(keys)
    return keys
end
local function prettyKey(k)
    return (k:gsub("(%l)(%u)", "%1 %2"):gsub("_"," "):lower():gsub("^%l", string.upper))
end
local statNames = {
    ITEMLEVEL=L("Niveau d’objet"), MOVEMENTSPEED=L("Vitesse de déplacement"),
    HEALTH=L("Vie"), MANA=L("Mana"), ARMOR=L("Armure"),
    ATTACKPOWER=L("Puissance d’attaque"), SPELLPOWER=L("Puissance des sorts"),
    STRENGTH=L("Force"), AGILITY=L("Agilité"), STAMINA=L("Endurance"),
    INTELLECT=L("Intelligence"), CRITICALSTRIKE=L("Coup critique"),
    HASTE=L("Hâte"), MASTERY=L("Maîtrise"), BONUSARMOR=L("Armure supplémentaire"),
    VERSATILITY=L("Polyvalence"), AVOIDANCE=L("Évitement"),
    DAMAGE=L("Dégâts"), ATTACKSPEED=L("Vitesse d’attaque"),
    ATTACKDPS=L("Dégâts par seconde"), MANAREGEN=L("Régénération de mana"),
    ENERGY=L("Énergie"), RAGE=L("Rage"), FOCUS=L("Focalisation"),
    SPIRIT=L("Esprit"), RUNICPOWER=L("Puissance runique"),
    DODGE=L("Esquive"), PARRY=L("Parade"), BLOCK=L("Blocage"),
}
local function itemDetails(item)
    local lines = {}
    local function add(label, v)
        if v then lines[#lines+1] = field(label, v) end
    end
    add(L("Niveau d’objet"),valueOf(object(item.level).value) or valueOf(item.level))
    add(L("Qualité"),valueOf(item.quality))
    add(L("Armure"),valueOf(item.armor))
    for _,stat in ipairs(object(item.stats)) do
        local display = valueOf(object(stat).display)
        if display then lines[#lines+1] = display
        else
            local st=object(object(stat).type)
            add(statNames[st.type] or valueOf(st) or text(st.type) or L("Statistique"),valueOf(object(stat).value))
        end
    end
    local weapon=object(item.weapon)
    add(L("Dégâts"),valueOf(weapon.damage)); add(L("Vitesse"),valueOf(weapon.attack_speed))
    add("DPS",valueOf(weapon.dps))
    for _,e in ipairs(object(item.enchantments)) do
        add(L("Enchantement"),valueOf(e) or valueOf(object(e).source_item) or text(object(e).enchantment_id))
    end
    for _,s in ipairs(object(item.sockets)) do
        add(L("Châsse"),valueOf(object(s).item) or valueOf(object(s).socket_type) or valueOf(s))
    end
    for _,s in ipairs(object(item.spells)) do
        local name, desc = valueOf(object(s).spell), text(object(s).description) or valueOf(s)
        add(L("Effet"),name and desc and (name.." — "..desc) or desc or name)
    end
    local set=object(item.set)
    add(L("Ensemble"),valueOf(set.item_set) or valueOf(item.set))
    for _,effect in ipairs(object(set.effects)) do add(L("Effet d’ensemble"),valueOf(effect) or text(object(effect).description)) end
    for _,key in ipairs(sortedKeys(item.requirements)) do
        add(L("Requis"),valueOf(item.requirements[key]))
    end
    local bonus={}
    for _,id in ipairs(object(item.bonus_list)) do if text(id) then bonus[#bonus+1]=text(id) end end
    if #bonus>0 then add(L("Bonus de variante"),table.concat(bonus,", ")) end
    add(L("Identifiant d’objet"),text(item.id))
    return #lines>0 and table.concat(lines,"\n") or L("Détails de la pièce non publiés.")
end
local function latestCombat(record)
    local latest
    for _,e in ipairs(object(record.history)) do
        if type(e)=="table" and not e.voided and e.voidReason~="battleground"
            and (e.kind=="kill" or e.kind=="death" or e.kind=="aggression") and type(e.time)=="number"
            and (not latest or e.time>=latest.time) then latest=e end
    end
    return latest
end

local relationNames={friend=L("Ami"),warning=L("Méfiance"),enemy=L("Ennemi"),neutral=L("Neutre")}
local function relationsPage(f,record,row)
    local B,G,S=GL.Bounties,GL.GuildProfiles,GL.SharedDossiers
    local timeline={}
    local function add(at,description,source)
        timeline[#timeline+1]={at=tonumber(at) or 0,description=description,source=source,seq=#timeline+1}
    end
    row(L("Avis sur ce personnage"),nil,true)
    if record then
        row(L("Votre carnet"),string.format("%+d",record.reputation or 0).." · "..(relationNames[GL.Relation(record)] or unknown))
        if GL.TagText and GL.TagText(record) then row(GL.TagText(record)) end
        for _,item in ipairs(GL.JournalEvents()) do
            if item.record==record then
                local e=item.event
                local description=GL.HistoryTitle(e)
                if e.text then description=description.."\n"..UI.plain(e.text) end
                if e.zone and e.zone~="?" then description=description.." · "..UI.plain(e.zone) end
                if e.voided then description=description.." · "..L("Annulé · exclu") end
                add(e.time,description,L("Votre journal").." · "..UI.plain(e.actorName or L("Auteur inconnu")))
            end
        end
    else row(L("Aucune rencontre personnelle enregistrée.")) end
    local reports=S and S.SocialReports(f.guid) or {}
    for _,report in ipairs(reports) do
        local author=UI.plain(B.MemberName(report.actor) or report.authorName or L("Membre de guilde"))
        row(author,string.format("%+d",report.score).." · "..relationNames[report.relation])
        row(field(L("Relevé"),timestamp(report.at)))
        for _,e in ipairs(report.events) do
            add(e.time,GL.HistoryTitle(e,author,f.nameLabel:GetText())..(e.zone and (" · "..UI.plain(e.zone)) or ""),L("Témoignage de %s"):format(author))
        end
    end
    if #reports==0 then row(L("Aucun historique ni solde partagé par les autres membres.")) end
    row(L("Le partage des faits et avis se règle dans Réglages > Relations. Les notes restent privées."))
    local seen,tagNames={},{}
    for _,choice in ipairs(G and G.choices or {}) do tagNames[choice[1]]=L(choice[2]) end
    for _,card in ipairs(G and G.List() or {}) do
        if card.target==f.guid then
            local history=G.View(card)
            for _,e in ipairs(history) do
                local key=e.actor..":"..e.seq
                if not seen[key] then
                    seen[key]=true
                    add(e.time,(e.on and L("Étiquette ajoutée : ") or L("Étiquette retirée : "))..(tagNames[e.tag] or unknown),
                        L("Avis de %s"):format(UI.plain(e.authorName)))
                end
            end
        end
    end
    for _,order in pairs(B and B.List() or {}) do
        if order.target==f.guid then
            local author=UI.plain(B.MemberName(order.owner) or L("Membre de guilde"))
            add(order.at,L("Mise à prix créée"),L("Créée par %s"):format(author))
            if order.endedAt then add(order.endedAt,L("Fin de la mise à prix"),L("Créée par %s"):format(author)) end
        end
    end
    table.sort(timeline,function(a,b) if a.at~=b.at then return a.at>b.at end return a.seq>b.seq end)
    row(L("Interactions datées"),nil,true)
    row(L("Les témoignages restent attribués à leur auteur ; ils ne modifient pas votre avis."))
    local offset=math.min(f.historyOffset or 0,math.max(0,math.ceil(#timeline/40)-1)*40)
    f.historyOffset=offset
    f.historyPrev:SetEnabled(offset>0); f.historyNext:SetEnabled(offset+40<#timeline)
    f.historyCount:SetText(("%d–%d / %d"):format(#timeline>0 and offset+1 or 0,math.min(offset+40,#timeline),#timeline))
    if #timeline==0 then row(L("Aucune interaction datée disponible.")) end
    for i=offset+1,math.min(offset+40,#timeline) do
        local entry=timeline[i]
        row(timestamp(entry.at).." · "..entry.source.."\n"..entry.description)
    end
end

local frame
local function armoryURL(fullName)
    local region=GL.ArmoryRegion()
    if not region or type(fullName)~="string" or not fullName:find(" ",1,true) then return end
    local slug=(strlower or string.lower)(fullName):gsub(" +","-"):gsub("[^a-z0-9%-]",function(c)
        return ("%%%02X"):format(c:byte())
    end)
    local lang=locale=="frFR" and "fr-fr" or (locale=="esES" or locale=="esMX") and "es-es" or "en-us"
    return "https://worldofwarcraft.blizzard.com/"..lang.."/forever/"..region.."/armory/character/"..slug
end
local percentages={CRITICALSTRIKE=true,DODGE=true,PARRY=true,BLOCK=true,HASTE=true,VERSATILITY=true,AVOIDANCE=true}
local function statValue(key,v)
    local function number(n)
        local s=("%.1f"):format(n):gsub("[.,]0$","")
        return decimalComma and s:gsub("%.",",") or s
    end
    if type(v)=="number" then return number(v)..(percentages[key] and L(" %") or "") end
    if type(v)=="table" and tonumber(v[1]) and tonumber(v[2]) then return number(v[1]).." – "..number(v[2]) end
    return valueOf(v)
end
local function draw(f)
    local localRecord=GL.Get(f.key)
    local record=localRecord or {guid=f.guid}
    f.guid=record.guid
    local archive=object(GL.ArmoryProfile(record,localRecord~=nil))
    local profile=setmetatable({}, {__index=archive})
    local inspection,pending
    if GL.DossierInspection then inspection,pending=GL.DossierInspection(record) end
    inspection=object(inspection)
    local archivedAt=tonumber(archive.updated) or 0
    if archivedAt>=100000000000 then archivedAt=archivedAt/1000 end
    if inspection.gear and (not archive.gear or inspection.gearAt>=(archive.gearAt or archivedAt)) then
        profile.inspectedGear,profile.partialGear=inspection.gear,inspection.partialGear
    end
    if inspection.trees and (not archive.trees or inspection.talentsAt>=(archive.treesAt or archivedAt)) then profile.trees=inspection.trees end
    local public=object(profile.identity)
    local mode=GL.ContactBountyMode(record)
    if mode then
        f.bounty:SetText(mode=="view" and L("Voir la prime") or L("Créer une prime"))
        f.bounty:Show()
    else f.bounty:Hide() end
    local name=text(record.fullName) or text(public.name) or text(f.knownName)
    if not name and f.guid and GL.Bounties and GL.Bounties.MemberName then name=text(GL.Bounties.MemberName(f.guid)) end
    f.nameLabel:SetText(name or unknown)
    GL.PaintBookPortrait(f.portrait,record)
    local faction,race,class=GL.IdentityLabels(record)
    f.identity:SetText(table.concat({
        (record.race or record.raceName) and text(race) or text(public.race) or unknown,
        (record.class or record.className) and text(class) or text(public.class) or unknown,
        record.faction and text(faction) or text(public.faction) or unknown}," · "))
    local event=latestCombat(record)
    local combat=object(event and event.combat)
    local stats=object(profile.stats)
    local liveStats=inspection.stats and (not next(stats) or inspection.statsAt>=(archive.statsAt or archivedAt))
    if liveStats then
        local combined={}
        for key,v in pairs(stats) do combined[key]=v end
        for key,v in pairs(inspection.stats) do combined[key]=v end
        stats=combined
    end
    -- Reuse the two-column stat rows as the selected character changes.
    local used,seen,y=0,{},0
    local function addStat(key)
        local val=statValue(key,stats[key])
        if not val then return end
        local c=f.statCells[used+1]
        if not c then
            c=CreateFrame("Frame",nil,f.identityBody); c:SetSize(117,44)
            c.value=UI.label(c,"","large",0,0,116); c.value:SetTextColor(unpack(UI.theme.paper))
            c.label=UI.label(c,"",nil,0,-23,117); UI.journalFont(c.label,"GameFontHighlight",11)
            c.label:SetTextColor(unpack(UI.theme.brass)); f.statCells[used+1]=c
        end
        c:ClearAllPoints(); c:SetPoint("TOPLEFT",(used%2)*122,-math.floor(used/2)*47); used=used+1
        c.value:SetText(val); c.label:SetText(statNames[key] or text(prettyKey(key))); c:Show(); seen[key]=true
    end
    for _,key in ipairs({"HEALTH","MANA","ENERGY","RAGE","FOCUS","RUNICPOWER","STRENGTH","AGILITY","STAMINA","INTELLECT","SPIRIT","ARMOR","CRITICALSTRIKE"}) do addStat(key) end
    for _,key in ipairs(sortedKeys(stats)) do if not seen[key] and key~="ITEMLEVEL" then addStat(key) end end
    for i=used+1,#f.statCells do f.statCells[i]:Hide() end
    y=math.ceil(used/2)*47
    local info={}
    if used==0 then info[1]=L("Aucun relevé de caractéristiques.\n") end
    if not next(archive) then
        info[#info+1]=L("Le compagnon lit le Journal à la déconnexion ou au /reload. Après l’import, /reload affiche le relevé.")
    end
    if liveStats then
        info[#info+1]=field(L("Caractéristiques vues en jeu"),timestamp(inspection.statsAt))
    end
    info[#info+1]=field(L("Guilde"),text(record.guild) or text(public.guild))
    info[#info+1]=field(L("Niveau Armurerie"),valueOf(profile.level))
    info[#info+1]=field(L("Niveau vu en jeu"),text(GL.ValidLevel(record.level)))
    info[#info+1]=field(L("Dernière rencontre"),timestamp(record.lastEncounterAt or record.lastDirectEncounterAt))
    if event then
        info[#info+1]=field(L("Dernier combat"),timestamp(event.time))
        info[#info+1]=field(L("Niveau adverse au combat"),text(GL.ValidLevel(combat.opponentLevel)))
        info[#info+1]=field(L("Votre niveau au combat"),text(GL.ValidLevel(combat.playerLevel)))
    end
    f.observed:ClearAllPoints(); f.observed:SetPoint("TOPLEFT",0,-y-5); f.observed:SetText(table.concat(info,"\n"))
    f.identityBody:SetHeight(math.max(f.identityScroll:GetHeight(),y+f.observed:GetStringHeight()+12))
    local snap=f.page=="reputation" and profile.reputationsAt or profile.updated
    local observedAt=f.page=="gear" and profile.inspectedGear and inspection.gearAt
        or f.page=="talents" and inspection.trees and profile.trees==inspection.trees and inspection.talentsAt
    local source
    if profile.sharedSource and not observedAt then
        source=L("Relevé partagé par %s"):format(GL.Bounties.MemberName(profile.sharedSource) or profile.sharedName or L("Membre de guilde"))
    elseif observedAt then
        source=(f.page=="gear" and profile.partialGear and L("Inspection partielle · ")
            or L("Inspection en jeu · "))..timestamp(observedAt)
    elseif snap then source=L("Relevé Armurerie : ")..timestamp(snap)
    elseif pending and (f.page=="gear" or f.page=="talents") then
        source=L("Inspection en cours…")
    elseif f.page=="gear" or f.page=="talents" then
        local unit=GL.VisiblePortraitUnit(record)
        if not unit then source=L("Hors de vue · aucun relevé chargé")
        else source=L("Aucun relevé disponible en jeu") end
    else source=L("Aucun relevé Armurerie chargé") end
    f.source:SetText(source)
    if f.page=="relations" then f.source:SetText(L("Journal personnel et témoignages de guilde")) end
    f.armoryURL=armoryURL(record.fullName or public.name or f.knownName)
    if f.armoryURL then f.armoryButton:Show() else f.armoryButton:Hide(); f.armoryLink:Hide() end
    local itemLevel=profile.averageItemLevel
    if profile.inspectedGear then itemLevel=inspection.averageItemLevel or itemLevel end
    f.ilvl:SetText(f.page=="gear" and field(L("Niv. d’objet moyen"),valueOf(itemLevel)) or "")
    for key,b in pairs(f.tabs) do UI.selectButton(b,f.page==key) end
    local gear,talents=f.page=="gear",f.page=="talents"
    for _,control in ipairs({f.historyPrev,f.historyNext,f.historyCount}) do
        if f.page=="relations" then control:Show() else control:Hide() end
    end
    if gear then f.equipment:Show(); GL.DrawDossierEquipment(f.equipment,record,profile,slots,slotOrder,itemDetails) else f.equipment:Hide() end
    if talents then
        f.talentScroll:Show()
        local h=GL.DrawDossierTalents(f.talents,record,profile)
        f.talents:SetHeight(math.max(f.talentScroll:GetHeight(),h))
        f.talentScroll:SetVerticalScroll(0)
    else f.talentScroll:Hide() end
    if gear or talents then f.scroll:Hide(); return end
    f.scroll:Show()
    local count,height=0,0
    local function row(label,amount,heading)
        count=count+1
        local r=f.rows[count]
        if not r then
            r=CreateFrame("Frame",nil,f.body); f.rows[count]=r
            r.caption=UI.label(r,"",nil,7,-4,510)
            r.amount=UI.label(r,"",nil,308,-4,198); r.amount:SetJustifyH("RIGHT")
            r.rule=r:CreateTexture(nil,"BACKGROUND"); r.rule:SetPoint("BOTTOMLEFT"); r.rule:SetPoint("BOTTOMRIGHT")
            r.rule:SetHeight(1); r.rule:SetColorTexture(.45,.28,.11,.21)
        end
        r.caption:SetWidth(amount and 292 or 500)
        UI.journalFont(r.caption,heading and "GameFontNormalLarge" or "GameFontHighlight",heading and 17 or 13)
        r.caption:SetTextColor(unpack(heading and UI.theme.red or UI.theme.ink)); r.amount:SetTextColor(unpack(UI.theme.ink))
        r.caption:SetText(label); r.amount:SetText(amount or "")
        local h=math.max(heading and 35 or 26,r.caption:GetStringHeight()+10,r.amount:GetStringHeight()+10)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT",0,-height); r:SetSize(514,h); r:Show(); height=height+h
    end
    if f.page=="relations" then
        relationsPage(f,localRecord,row)
    elseif f.page=="reputation" then
        row(L("Réputations auprès des factions"),nil,true)
        local reps=object(profile.reputations)
        if #reps==0 then row(profile.reputations and L("Aucune faction publiée.") or L("Réputations non disponibles dans ce relevé.")) end
        local group
        for _,v in ipairs(reps) do
            if v.group and v.group~=group then group=v.group; row(text(group) or unknown,nil,true) end
            local points=valueOf(v.value)
            if points and valueOf(v.max) then points=points.." / "..valueOf(v.max) end
            row(text(v.name) or unknown,(valueOf(v.standing) or unknown)..(points and (" · "..points) or ""))
        end
    else
        row(L("Palmarès JcJ · Armurerie"),nil,true)
        row(L("Victoires honorables"),valueOf(profile.honorableKills) or unknown)
        row(L("Rang JcJ"),valueOf(profile.pvpRank) or unknown)
        row(L("Champs de bataille"),profile.battlegroundsAt and timestamp(profile.battlegroundsAt),true)
        if #object(profile.battlegrounds)==0 then row(profile.battlegrounds and L("Aucun champ de bataille publié.") or L("Champs de bataille non renseignés.")) end
        for _,v in ipairs(object(profile.battlegrounds)) do
            row(text(v.name) or unknown,(valueOf(v.games) or "—")..L(" parties").." · "..(valueOf(v.wins) or "—")..L(" V").." / "..(valueOf(v.losses) or "—")..L(" D"))
        end
        row(L("Votre face-à-face · Journal"),nil,true)
        if localRecord then
            local p=GL.ContactMatchup(record)
            row(L("Victoires / morts"),p.kills.." / "..p.deaths)
            row(L("Honneur attribué"),p.honorAwards>0 and text(p.honor) or unknown)
        else row(L("Aucune rencontre personnelle enregistrée.")) end
        row(L("Face-à-face de la guilde"),nil,true)
        if f.guid and GL.Bounties and GL.Safe(GetGuildInfo,"player") then
            local wins,losses=GL.Bounties.GuildFights(f.guid)
            if wins==0 and losses==0 then row(L("Aucun résultat partagé pour cette cible."))
            else row(L("Victoires / morts"),wins.." / "..losses) end
            local scope=GL.Bounties.GuildScope()
            local members=scope and scope.scores and scope.scores[f.guid] or {}
            for _,member in ipairs(sortedKeys(members)) do
                local score=members[member]
                row(GL.Bounties.MemberName(member) or L("Membre de guilde"),score[1]..L(" V").." / "..score[2]..L(" D"))
            end
        else row(unknown) end
        row(L("Hauts faits JcJ"),type(profile.achievements)=="table" and tostring(#profile.achievements) or unknown,true)
        if profile.achievementsAt then row(field(L("Relevé"),timestamp(profile.achievementsAt))) end
        for _,a in ipairs(object(profile.achievements)) do
            row((text(a.name) or unknown)..(a.accountWide and L(" (compte)") or ""))
        end
    end
    for i=count+1,#f.rows do f.rows[i]:Hide() end
    f.body:SetHeight(math.max(f.scroll:GetHeight(),height))
end

local function scrollArea(f,x,y,w,h)
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",x,y); scroll:SetSize(w,h)
    local body=CreateFrame("Frame",nil,scroll)
    body:SetSize(w,h); scroll:SetScrollChild(body)
    return scroll,body
end
local function build()
    local f=UI.bookWindow("GrudgeLedgerPlayerDossier","Grudge Ledger")
    GL.SetupBookNavigation(f,"ledger")
    f.back=UI.button(f,L("Retour"),39,-154,116,function()
        f:Hide()
        if f.onReturn then f.onReturn() else GL.ShowLedger(f.key) end
    end)
    f.portrait=CreateFrame("Frame",nil,f); f.portrait:SetPoint("TOPLEFT",40,-193); f.portrait:SetSize(64,64)
    f.portrait.raceIcon=f.portrait:CreateTexture(nil,"ARTWORK"); f.portrait.raceIcon:SetAllPoints()
    f.portrait.classIcon=f.portrait:CreateTexture(nil,"OVERLAY"); f.portrait.classIcon:SetSize(16,16)
    f.portrait.classIcon:SetPoint("BOTTOMRIGHT")
    f.nameLabel=UI.label(f,"","large",111,-192,193)
    GL.Safe(f.nameLabel.SetMaxLines,f.nameLabel,2)
    f.identity=UI.label(f,"",nil,111,-237,193)
    UI.journalFont(f.identity,"GameFontHighlight",11)
    f.statHeading=UI.label(f,L("Caractéristiques"),"large",40,-266,255); f.statHeading:SetTextColor(unpack(UI.theme.brass))
    f.identityScroll,f.identityBody=scrollArea(f,40,-297,243,296)
    f.observed=UI.label(f.identityBody,"",nil,0,0,239); f.observed:SetTextColor(unpack(UI.theme.muted))
    f.bounty=UI.button(f,"",40,-612,247,function() GL.OpenContactBounty(f.guid) end)
    f.armoryButton=UI.button(f,L("Lien vers l’Armurerie"),40,-643,247,function()
        f.armoryLink:SetText(f.armoryURL); f.armoryLink:Show(); f.armoryLink:SetFocus(); f.armoryLink:HighlightText()
    end)
    f.armoryLink=CreateFrame("EditBox",nil,f.armoryButton,"InputBoxTemplate")
    f.armoryLink:SetSize(245,24); f.armoryLink:SetPoint("CENTER")
    f.armoryLink:SetAutoFocus(false); f.armoryLink:Hide()
    f.armoryLink:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    f.armoryLink:SetScript("OnEditFocusLost",function(self) self:Hide() end)
    f.tabs={}; f.rows={}; f.statCells={}
    for i,s in ipairs({{"gear","Équipement"},{"talents","Talents"},{"pvp","JcJ"},{"reputation","Factions"},{"relations","Relations"}}) do
        local key=s[1]
        f.tabs[key]=UI.button(f,L(s[2]),352+(i-1)*110,-156,105,function()
            f.page=key; f.scroll:SetVerticalScroll(0); draw(f)
        end,true,true)
    end
    f.source=UI.label(f,"",nil,355,-196,312); f.source:SetTextColor(unpack(UI.theme.inkMuted))
    f.ilvl=UI.label(f,"",nil,669,-196,222); f.ilvl:SetJustifyH("RIGHT"); f.ilvl:SetTextColor(unpack(UI.theme.ink))
    f.scroll,f.body=scrollArea(f,352,-225,520,408)
    f.equipment=CreateFrame("Frame",nil,f); f.equipment:SetPoint("TOPLEFT",359,-229); f.equipment:SetSize(515,398)
    f.talentScroll,f.talents=scrollArea(f,352,-225,529,403)
    f.talentScroll.scrollBarHideable=true
    f.historyPrev=UI.button(f,L("Précédent"),352,-645,130,function()
        f.historyOffset=math.max(0,(f.historyOffset or 0)-40); f.scroll:SetVerticalScroll(0); draw(f)
    end,nil,true)
    f.historyNext=UI.button(f,L("Suivant"),758,-645,130,function()
        f.historyOffset=(f.historyOffset or 0)+40; f.scroll:SetVerticalScroll(0); draw(f)
    end,nil,true)
    f.historyCount=UI.label(f,"",nil,493,-652,252); f.historyCount:SetJustifyH("CENTER")
    f.historyCount:SetTextColor(unpack(UI.theme.inkMuted))
    return f
end
function GL.OpenPlayerDossier(id,onReturn,knownName)
    if type(id)~="string" then return false end
    local key,guid
    if #id<=32 and id:match("^Player%-%w+%-%w+$") then
        key,guid="guid:"..id,id
    elseif id:match("^name:") and GL.Get(id) then
        local contact=GL.Get(id)
        key,guid=contact.key,contact.guid
    else return false end
    local contact=GL.Get(key)
    GL.RequestArmory(key,(contact and contact.fullName) or knownName,guid)
    frame=frame or build()
    frame.armoryLink:Hide()
    frame.key,frame.guid,frame.onReturn,frame.knownName,frame.page=key,guid,onReturn,knownName,"gear"
    frame.historyOffset=0
    frame.scroll:SetVerticalScroll(0); frame.identityScroll:SetVerticalScroll(0)
    if GL.InspectDossierUnit then GL.InspectDossierUnit(GL.VisiblePortraitUnit({guid=guid}),guid) end
    GL.ShowBookPage(frame)
    draw(frame)
    if guid and GL.SharedDossiers then GL.SharedDossiers.Request(guid) end
    return true
end

GL.On("DOSSIER_UPDATED",function(guid)
    if frame and frame:IsShown() and (not guid or frame.guid==guid) then draw(frame) end
end)
for _,event in ipairs({"CHANGED","GUILD_PROFILES","BOUNTIES_CHANGED"}) do
    GL.On(event,function() if frame and frame:IsShown() then draw(frame) end end)
end
